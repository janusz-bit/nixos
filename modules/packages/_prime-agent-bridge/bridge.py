#!/usr/bin/env python3
"""OpenAI-compatible HTTP bridge for the Prime Agent CLI.

Prime Agent is a terminal coding agent with no built-in HTTP server, so
this small stdlib-only service translates OpenAI /v1/chat/completions
requests into one-shot `prime-agent --print --mode json` runs. It is
registered as the third open-webui backend on the raspberry-pi-4 host
(modules/hosts/raspberry-pi-4/open-webui.nix).

Endpoints:
  GET  /v1/models            -> model list (seeded models.json + default)
  POST /v1/chat/completions  -> buffered or SSE-streamed completion
  GET  /healthz              -> liveness probe

Environment:
  PRIME_AGENT_BIN            path to the prime-agent binary (required)
  PRIME_BRIDGE_HOST          listen address (default 127.0.0.1)
  PRIME_BRIDGE_PORT          listen port (default 8643)
  PRIME_BRIDGE_TIMEOUT       per-request wall-clock timeout, seconds (600)
  PRIME_BRIDGE_MAX_CONCURRENT  max parallel agent runs (1; RPi4 RAM)
"""

import json
import os
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PRIME_AGENT_BIN = os.environ.get("PRIME_AGENT_BIN", "prime-agent")
LISTEN_HOST = os.environ.get("PRIME_BRIDGE_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("PRIME_BRIDGE_PORT", "8643"))
REQUEST_TIMEOUT = int(os.environ.get("PRIME_BRIDGE_TIMEOUT", "600"))
MAX_CONCURRENT = max(1, int(os.environ.get("PRIME_BRIDGE_MAX_CONCURRENT", "1")))
MODEL_PREFIX = "prime-agent/"
DEFAULT_MODEL_ID = "prime-agent"
SERVER_START = int(time.time())

# Serialize agent runs: each one spawns Node.js + an IPython kernel,
# which is more than enough for a 4 GB RPi4.
RUN_SEMAPHORE = threading.BoundedSemaphore(MAX_CONCURRENT)


def log(msg):
    print(f"[prime-agent-bridge] {msg}", file=sys.stderr, flush=True)


def load_seeded_models():
    """model_id -> provider_name map from the seeded models.json."""
    models_path = os.path.expanduser("~/.prime/agent/models.json")
    mapping = {}
    try:
        with open(models_path, encoding="utf-8") as fh:
            data = json.load(fh)
        for provider_name, provider in (data.get("providers") or {}).items():
            for model in provider.get("models") or []:
                mid = model.get("id")
                if mid:
                    mapping[mid] = provider_name
    except Exception as exc:
        log(f"models.json unavailable ({exc})")
    return mapping


def list_model_ids():
    """Default model plus every model from the seeded models.json."""
    return [DEFAULT_MODEL_ID] + [
        MODEL_PREFIX + mid for mid in load_seeded_models()
    ]


def message_text(message):
    content = message.get("content")
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for part in content:
            if not isinstance(part, dict):
                continue
            if part.get("type") == "text":
                parts.append(part.get("text", ""))
            elif part.get("type") == "image_url":
                parts.append("[image omitted]")
        return "\n".join(parts)
    return str(content)


def build_prompt(messages):
    """Flatten an OpenAI messages array into a single agent prompt."""
    blocks = []
    for message in messages:
        role = message.get("role") or "user"
        text = message_text(message).strip()
        if not text:
            continue
        if role == "system":
            blocks.append(f"SYSTEM INSTRUCTIONS:\n{text}")
        elif role == "assistant":
            blocks.append(f"ASSISTANT (previous reply):\n{text}")
        elif role == "tool":
            blocks.append(f"TOOL RESULT:\n{text}")
        else:
            blocks.append(f"USER:\n{text}")
    if not blocks:
        return ""
    if len(blocks) == 1:
        return blocks[0]
    return "\n\n".join(blocks) + "\n\nRespond to the last USER message."


def build_command(prompt, model):
    cmd = [PRIME_AGENT_BIN, "--print", "--mode", "json", "--no-session"]
    if model and model != DEFAULT_MODEL_ID:
        model_id = model[len(MODEL_PREFIX):] if model.startswith(MODEL_PREFIX) else model
        # Sam --model nie wystarczy: prime-agent rozpatruje wtedy modele
        # wbudowanych providerów (wymagających /login OAuth), a nie
        # custom providerów z models.json. Trzeba podać też --provider.
        provider = load_seeded_models().get(model_id)
        if provider:
            cmd += ["--provider", provider]
        cmd += ["--model", model_id]
    cmd += ["--", prompt]
    return cmd


def run_agent(cmd):
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    watchdog = threading.Timer(REQUEST_TIMEOUT, proc.kill)
    watchdog.daemon = True
    watchdog.start()
    return proc, watchdog


def iter_events(lines):
    """Parse Prime Agent JSONL events, skipping noise."""
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except ValueError:
            continue


def extract_delta(event):
    """Text delta from a message_update event, else None."""
    if event.get("type") != "message_update":
        return None
    ame = event.get("assistantMessageEvent") or {}
    if ame.get("type") != "text_delta":
        return None
    return ame.get("delta") or ""


def final_assistant(event):
    """(text, error) from an assistant message_end event, else None."""
    if event.get("type") != "message_end":
        return None
    msg = event.get("message") or {}
    if msg.get("role") != "assistant":
        return None
    if msg.get("stopReason") == "error":
        return "", msg.get("errorMessage") or "Prime Agent returned an error"
    parts = msg.get("content") or []
    texts = [
        part.get("text", "")
        for part in parts
        if isinstance(part, dict) and part.get("type") == "text"
    ]
    return "".join(texts), None


class BridgeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "PrimeAgentBridge/1.0"

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} {fmt % args}")

    # -- helpers ---------------------------------------------------------
    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status, message, etype="bridge_error"):
        self.send_json(
            status,
            {"error": {"message": message, "type": etype, "code": str(status)}},
        )

    def read_json_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length > 0 else b""
        if not raw:
            return {}
        return json.loads(raw)

    # -- routes ----------------------------------------------------------
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/v1/models", "/models"):
            self.send_json(
                200,
                {
                    "object": "list",
                    "data": [
                        {
                            "id": mid,
                            "object": "model",
                            "created": SERVER_START,
                            "owned_by": "prime-agent",
                        }
                        for mid in list_model_ids()
                    ],
                },
            )
        elif path in ("/healthz", "/health", "/"):
            self.send_json(200, {"status": "ok", "backend": PRIME_AGENT_BIN})
        else:
            self.send_error_json(404, f"Unknown endpoint {path}", "invalid_request_error")

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path not in ("/v1/chat/completions", "/chat/completions"):
            self.send_error_json(404, f"Unknown endpoint {path}", "invalid_request_error")
            return
        try:
            body = self.read_json_body()
        except ValueError:
            self.send_error_json(400, "Invalid JSON body", "invalid_request_error")
            return
        messages = body.get("messages") or []
        model = body.get("model") or DEFAULT_MODEL_ID
        stream = bool(body.get("stream"))
        prompt = build_prompt(messages)
        if not prompt:
            self.send_error_json(400, "No message content", "invalid_request_error")
            return
        if not RUN_SEMAPHORE.acquire(timeout=REQUEST_TIMEOUT):
            self.send_error_json(503, "Prime Agent busy", "overloaded_error")
            return
        try:
            if stream:
                self.handle_stream(prompt, model)
            else:
                self.handle_buffered(prompt, model)
        except (BrokenPipeError, ConnectionResetError):
            log("client disconnected mid-request")
        except Exception as exc:
            log(f"handler error: {exc!r}")
            try:
                self.send_error_json(500, str(exc))
            except Exception:
                pass
        finally:
            RUN_SEMAPHORE.release()

    # -- completion modes --------------------------------------------------
    def handle_buffered(self, prompt, model):
        cmd = build_command(prompt, model)
        log(f"run (buffered) model={model} prompt_chars={len(prompt)}")
        proc, watchdog = run_agent(cmd)
        try:
            stdout, stderr = proc.communicate(timeout=REQUEST_TIMEOUT + 30)
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout, stderr = proc.communicate()
        finally:
            watchdog.cancel()
        text_parts = []
        final_text = None
        agent_error = None
        for event in iter_events(stdout.splitlines()):
            delta = extract_delta(event)
            if delta:
                text_parts.append(delta)
                continue
            result = final_assistant(event)
            if result is not None:
                chunk_text, err = result
                if err:
                    agent_error = err
                elif chunk_text:
                    final_text = chunk_text
        text = "".join(text_parts) or final_text or ""
        if not text:
            detail = (
                agent_error
                or (stderr or "").strip()[-2000:]
                or f"Prime Agent exited with code {proc.returncode} without output"
            )
            self.send_error_json(502, detail)
            return
        self.send_json(
            200,
            {
                "id": f"chatcmpl-{uuid.uuid4().hex[:24]}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": text},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
            },
        )

    def handle_stream(self, prompt, model):
        cmd = build_command(prompt, model)
        log(f"run (stream) model={model} prompt_chars={len(prompt)}")
        proc, watchdog = run_agent(cmd)
        stderr_tail = []

        def drain_stderr():
            for line in proc.stderr:
                stderr_tail.append(line)
                if len(stderr_tail) > 200:
                    stderr_tail.pop(0)

        stderr_thread = threading.Thread(target=drain_stderr, daemon=True)
        stderr_thread.start()

        chat_id = f"chatcmpl-{uuid.uuid4().hex[:24]}"
        created = int(time.time())
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        def send_chunk(delta, finish_reason=None):
            payload = {
                "id": chat_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [
                    {"index": 0, "delta": delta, "finish_reason": finish_reason}
                ],
            }
            self.wfile.write(f"data: {json.dumps(payload)}\n\n".encode("utf-8"))
            self.wfile.flush()

        send_chunk({"role": "assistant", "content": ""})
        got_text = False
        agent_error = None
        try:
            for event in iter_events(proc.stdout):
                delta = extract_delta(event)
                if delta:
                    got_text = True
                    send_chunk({"content": delta})
                    continue
                result = final_assistant(event)
                if result is not None and result[1]:
                    agent_error = result[1]
            proc.wait(timeout=REQUEST_TIMEOUT)
        finally:
            watchdog.cancel()
            if proc.poll() is None:
                proc.kill()
        if agent_error:
            send_chunk({"content": f"\n\n[Prime Agent error: {agent_error}]"})
        elif not got_text:
            tail = "".join(stderr_tail).strip()[-2000:]
            send_chunk(
                {
                    "content": (
                        f"[Prime Agent produced no output; exit code "
                        f"{proc.returncode}] {tail}"
                    )
                }
            )
        send_chunk({}, finish_reason="stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


def main():
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), BridgeHandler)
    server.daemon_threads = True
    log(f"listening on http://{LISTEN_HOST}:{LISTEN_PORT} (backend: {PRIME_AGENT_BIN})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
