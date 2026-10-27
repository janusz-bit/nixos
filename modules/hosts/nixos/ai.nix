# Skille i modele agentów AI na laptopie: skille własne (w tym obscura z jej
# programem i nixos-system z faktami o hoście), paczki Qt Development Skills
# i tstack, lokalny Trilium dla Prime Agenta oraz lokalne modele na GPU —
# Ternary Bonsai 2 27B (aliasy bonsai-serve i bonsai-serve-mtp) i Qwen3.8
# Flash-Next Coder z serwera Strata. Tylko wybór; definicje są w modules/ai/.
_: {
  flake.modules.nixos.nixos-ai = _: {
    ai = {
      skills = {
        ai-tutor.enable = true;
        nixos-system.enable = true;
        obscura.enable = true;
        trilium-notes.enable = true;
      };
      skillPacks = {
        qt-agent-skills.enable = true;
        tstack.enable = true;
      };
      models = {
        ternary-bonsai-2-27b.enable = true;
        ternary-bonsai-2-27b-mtp.enable = true;
        qwen3-8-flash-next-coder-iq1_m.enable = true;
      };
    };
  };
}
