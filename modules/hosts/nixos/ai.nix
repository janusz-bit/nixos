# Skille i modele agentów AI na laptopie: skille własne (w tym obscura z jej
# programem, nixos-system z faktami o hoście, brulion z brulion-cli,
# claude-usage z limitami subskrypcji Claude), ub-mode, paczki tstack
# i frontend-design oraz lokalne modele na GPU — Qwen3.8 Flash-Next (Coder
# IQ1_M i Gyro-M) i Inkling-2-Mini z serwera Strata (Gyro-M jako domyślny
# model opencode2) i Ternary Bonsai 2.5 27B PTQ1_0 z forka llama.cpp (llama-prism).
# Tylko wybór; definicje są w modules/ai/. Port Strata jest otwarty
# w tailnecie (np. dla Brulionu na telefonie: http://nixos.<tailnet>:8080/v1).
#
# Sprawdzenie: `sudo iptables -S nixos-fw | grep 8080`, z telefonu (Tailscale
# włączony) w Brulionie Ustawienia -> Rozszerzenia -> Sprawdź.
_: {
  flake.modules.nixos.nixos-ai =
    { config, ... }:
    {
      # Strata (--no-api-key) na domyślnym porcie 8080 z ai.providers.strata:
      # tylko tailscale0, nie LAN. Z RPi połączenia przez tailscale0 otwiera
      # i tak tylko konto t3code (hosts/t3code-laptop.nix).
      networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [
        8080
      ];

      ai = {
        skills = {
          brulion.enable = true;
          claude-usage.enable = true;
          nixos-system.enable = true;
          obscura.enable = true;
          ub-mode.enable = true;
        };
        skillPacks = {
          frontend-design.enable = true;
          tstack.enable = true;
        };
        models = {
          inkling-2-mini-sq-20.enable = true;
          ternary-bonsai-2-5-27b.enable = true;
          qwen3-8-flash-next-coder-iq1_m.enable = true;
          qwen3-8-flash-next-gyro-gyro-m.enable = true;
        };
        # Odpowiednik v2 tego, co `strata connect opencode` zapisuje w formacie
        # v1 (opencode2 sam tłumaczy v1 tak samo: small_model -> agents.title,
        # autoupdate -> update).
        opencode.settings =
          let
            gyroM = "strata/qwen3-8-flash-next-gyro-gyro-m";
          in
          {
            model = gyroM;
            agents.title.model = gyroM;
            update = "disable";
            share = "disabled";
            # Strata liczy bufor 60548 tokenów dla okna 128K (kompakcja przy 52%
            # limitu wejścia). Bufor jest wspólny dla wszystkich modeli, więc
            # jako ułamek okna: 46% z 131072 to prawie ten sam próg.
            compaction = {
              auto = true;
              buffer = "46%";
            };
          };
      };
    };
}
