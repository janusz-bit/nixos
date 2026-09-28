_: {
  flake.overlays.opencode-config = _final: prev: {
    opencode =
      let
        # Pluginy przypięte do konkretnych wersji: opencode instaluje je przy
        # starcie i wykonuje w procesie z kluczami API w env, więc „HEAD”
        # czy „latest” oznaczałoby niekontrolowane aktualizacje cudzego kodu.
        # Bump: nowy commit z `git ls-remote https://github.com/obra/superpowers.git HEAD`
        # i wersja z `npm view caveman-opencode-plugin version`.
        plugins = [
          "superpowers@git+https://github.com/obra/superpowers.git#d884ae04edebef577e82ff7c4e143debd0bbec99" # v6.1.1
          "caveman-opencode-plugin@0.1.5"
        ];

        # Zależności z nixpkgs zamiast `uv run` z niepinowanymi pakietami z PyPI.
        webSearchPython = prev.python3.withPackages (ps: [
          ps.mcp
          ps.ollama
        ]);

        webSearchMcp = prev.writeText "web-search-mcp.py" ''
          """
          MCP stdio server exposing Ollama web_search and web_fetch as tools.

          Environment:
          - OLLAMA_API_KEY (required): used by the ollama client for the hosted API.
          """

          from __future__ import annotations

          from typing import Any, Dict

          from mcp.server.fastmcp import FastMCP
          from ollama import Client

          client = Client()
          app = FastMCP("ollama-search-fetch")


          @app.tool()
          def web_search(query: str, max_results: int = 3) -> Dict[str, Any]:
              """
              Perform a web search using Ollama's hosted search API.

              Args:
                query: The search query to run.
                max_results: Maximum results to return (default: 3).

              Returns:
                JSON-serializable dict matching ollama.WebSearchResponse.model_dump()
              """
              return client.web_search(query=query, max_results=max_results).model_dump()


          @app.tool()
          def web_fetch(url: str) -> Dict[str, Any]:
              """
              Fetch the content of a web page for the provided URL.

              Args:
                url: The absolute URL to fetch.

              Returns:
                JSON-serializable dict matching ollama.WebFetchResponse.model_dump()
              """
              return client.web_fetch(url=url).model_dump()


          if __name__ == "__main__":
              app.run()
        '';

        # Modele z modalnościami: bez jawnego "text" w modalities.input opencode
        # podmienia media na komunikat błędu (domyślnie wszystko false).
        textImage = {
          attachment = true;
          tool_call = true;
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
        };

        openaiCompatible = name: options: models: {
          npm = "@ai-sdk/openai-compatible";
          inherit name options models;
        };

        opencodeJson = prev.writeText "opencode.json" (
          builtins.toJSON {
            "$schema" = "https://opencode.ai/config.json";
            model = "ollama-cloud/glm-5.3-flash:cloud";
            plugin = plugins;
            provider = {
              llmgateway =
                openaiCompatible "LLM Gateway"
                  {
                    baseURL = "https://api.llmgateway.io/v1";
                    apiKey = "{env:LLMGATEWAY_API_KEY}";
                  }
                  {
                    "claude-sonnet-4-6".name = "Claude Sonnet 4.6";
                    "gpt-5.5".name = "GPT-5.5";
                    "gemini-3.1-pro".name = "Gemini 3.1 Pro";
                    "qwen3.8-max".name = "Qwen3.8 Max";
                    "kimi-k3".name = "Kimi K3";
                    "glm-5.2".name = "GLM 5.2";
                  };
              ollama = openaiCompatible "Ollama" { baseURL = "http://localhost:11434/v1"; } {
                "ornith:35b".name = "ornith:35b";
              };
              ollama-cloud =
                openaiCompatible "Ollama Cloud"
                  {
                    baseURL = "https://ollama.com/v1";
                    apiKey = "{env:OLLAMA_API_KEY}";
                  }
                  {
                    "deepseek-v4.1-flash:cloud" = textImage // {
                      name = "DeepSeek V4.1 Flash";
                    };
                    "glm-5.3-flash:cloud" = textImage // {
                      name = "glm-5.3-flash:cloud";
                      modalities = {
                        input = [
                          "text"
                          "image"
                          "video"
                        ];
                        output = [ "text" ];
                      };
                    };
                  };
              opencode =
                openaiCompatible "OpenCode Cloud"
                  {
                    baseURL = "https://api.opencode.ai/v1";
                    apiKey = "{env:OPENCODE_GO_API_KEY}";
                  }
                  {
                    "glm-5.2".name = "glm-5.2";
                    "kimi-k3".name = "kimi-k3";
                  };
              llamacpp = openaiCompatible "llama.cpp (local)" { baseURL = "http://localhost:8080/v1"; } {
                "qwen3.8-27b" = {
                  name = "Qwen3.8 27B UD-Q8_K_XL (local)";
                  limit = {
                    context = 32768;
                    output = 4096;
                  };
                };
              };
            };
            permission = {
              websearch = "allow";
              external_directory."/nix/store/**" = "allow";
            };
            mcp = {
              web_search_and_fetch = {
                type = "local";
                command = [
                  "${webSearchPython}/bin/python"
                  "${webSearchMcp}"
                ];
                enabled = true;
              };
              nixos = {
                type = "local";
                command = [ (prev.lib.getExe prev.mcp-nixos) ];
                enabled = true;
              };
            };
          }
        );
      in
      prev.opencode.overrideAttrs (oldAttrs: {
        postInstall = (oldAttrs.postInstall or "") + ''
          mkdir -p $out/share/opencode
          install -Dm644 ${opencodeJson} $out/share/opencode/opencode.json
          wrapProgram $out/bin/opencode \
            --prefix PATH : ${prev.ripgrep}/bin \
            --set OPENCODE_DISABLE_AUTOUPDATE true \
            --set OPENCODE_CONFIG $out/share/opencode/opencode.json
        '';
      });
  };
}
