{
  inputs,
  self,
  customTop,
  lib,
  ...
}:
let
  editor = "micro";

  sharedPackages =
    pkgs: with pkgs; [
      micro-full
      nil
      nixd
      nixfmt-tree
      uv
      statix
      cachix
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent # self-improving agent AI (RLM)
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.dsh # DeepSeek agent harness
      nix-update
      tlrc
      fzf
      hw-probe
      htop
      cloudflared
      vulnix
    ];

  sharedSessionVariables = {
    NIXOS_OZONE_WL = "1";
    VISUAL = editor;
    EDITOR = editor;
  };

  environmentShellAliases =
    config:
    let
      rebuild =
        mode: remote:
        let
          flakeRef = if remote then customTop.repository.linkFlake else customTop.repository.place;
        in
        "nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${config.customBot.flakeTarget}${lib.optionalString remote " --refresh"}";
      update_alias = mode: remote: "sudo ${rebuild mode remote}";
    in
    {
      # Update systemu
      update = update_alias "switch" true;
      update-boot = update_alias "boot" true;
      # Jedno sudo na całość: po długim buildzie osobne `sudo systemctl reboot`
      # pytałoby znowu o hasło (wygasły timestamp) i reboot by nie nastąpił.
      update-reboot = "sudo sh -c '${rebuild "boot" true} && systemctl reboot'";
      update-local = update_alias "switch" false;
      update-local-boot = update_alias "boot" false;
    };

  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      customTop.cache.cachix.url
    ]
    ++ map (c: c.url) customTop.cache.inputs;
    extra-trusted-public-keys = [
      customTop.cache.cachix.pubKey
    ]
    ++ map (c: c.pubKey) customTop.cache.inputs;
  };
in
{
  flake.modules.nixos.base-configuration =
    {
      pkgs,
      config,
      lib,
      ...
    }:

    {

      imports = [ inputs.nix-index-database.nixosModules.default ];

      nixpkgs = {
        config.allowUnfree = true;
        overlays = [
          self.overlays.opencode-config
          self.overlays.local-packages
        ];
      };

      networking = {
        # mkDefault: na WSL resolv.conf generuje Windows (wsl-settings.nix).
        nameservers = lib.mkDefault [
          "9.9.9.9"
          "149.112.112.112"
          "2620:fe::fe"
          "2620:fe::9"
        ];
      };

      environment = {
        systemPackages = sharedPackages pkgs;
        sessionVariables = sharedSessionVariables;
        shellAliases = environmentShellAliases config;

        # Setting environment.localBinInPath = true; is highly recommended, because uv will install binaries in ~/.local/bin.
        localBinInPath = true;
      };

      nix.settings = sharedNixSettings;

      programs = {
        # Fix uv
        nix-ld.enable = true;

        nix-index-database.comma.enable = true;

        direnv.enable = true;

        # Tylko w fish: token cachix wstrzykuje funkcja `cachix-push`
        # (base/agenix.nix), niewidoczna dla innych procesów.
        fish.shellAliases.push = "nix build ${customTop.repository.linkFlake}#nixosConfigurations.${config.customBot.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | cachix-push ${customTop.cache.cachix.name}";
      };

      # The ZFS module is pulled in by default by nixpkgs even when ZFS
      # is not in use. Explicitly disable forceImportRoot to silence the
      # 26.11 evaluation warning and reduce the risk of data loss.
      boot.zfs.forceImportRoot = false;
    };
}
