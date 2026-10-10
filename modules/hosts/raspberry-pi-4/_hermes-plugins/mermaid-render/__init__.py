"""Mermaid diagrams as images on Matrix.

Element shows a ```mermaid block as raw code. The ``transform_llm_output`` hook
renders every such block of the final reply with mermaid-cli (headless
Chromium) into the Hermes image cache and replaces it with a ``MEDIA:<png>``
tag, which the gateway uploads as an inline image. The transform runs before
the reply is persisted, so history keeps the tag; the ``.mmd`` source stays
next to the PNG (same name) for later edits. A block that fails to render
(syntax error, timeout) is left as code.
"""

import hashlib
import logging
import re
import subprocess

from hermes_constants import get_hermes_dir

MMDC = "@mmdc@"
# Surfaces that render Mermaid themselves (CLI/TUI/desktop, Open WebUI over
# api_server) keep the code block.
PLATFORMS = {"matrix"}
TIMEOUT_S = 120

_BLOCK = re.compile(r"^[ \t]*```mermaid[ \t]*\n(.*?)^[ \t]*```[ \t]*$", re.M | re.S)
logger = logging.getLogger(__name__)


def _render(source: str):
    out_dir = get_hermes_dir("cache/images", "image_cache") / "mermaid"
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = out_dir / hashlib.sha256(source.encode()).hexdigest()[:16]
    png = stem.with_suffix(".png")
    if png.is_file():
        return png
    mmd = stem.with_suffix(".mmd")
    mmd.write_text(source)
    try:
        subprocess.run(
            [MMDC, "-q", "-i", str(mmd), "-o", str(png), "-s", "2", "-b", "white"],
            check=True,
            capture_output=True,
            timeout=TIMEOUT_S,
        )
    except Exception:
        png.unlink(missing_ok=True)
        raise
    return png


def _replace(match: re.Match) -> str:
    try:
        return f"MEDIA:{_render(match.group(1))}"
    except subprocess.CalledProcessError as exc:
        # The parse error is at the top; the rest is a puppeteer stack trace.
        logger.warning("mermaid-render: mmdc failed, keeping the code block: %s", exc.stderr.decode(errors="replace")[:300])
    except Exception as exc:
        logger.warning("mermaid-render: keeping the code block: %s", exc)
    return match.group(0)


def _on_llm_output(response_text: str = "", platform: str = "", **_):
    if platform not in PLATFORMS or "```mermaid" not in response_text:
        return None
    rendered = _BLOCK.sub(_replace, response_text)
    return rendered if rendered != response_text else None


def register(ctx) -> None:
    ctx.register_hook("transform_llm_output", _on_llm_output)
