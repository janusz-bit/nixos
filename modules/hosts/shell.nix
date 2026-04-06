{ lib, ... }:
let
  sharedBashInit = pkgs: ''
    if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
    then
      shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
    fi
  '';

  sharedFishAliases = {
    # Eza zamiast ls
    ls = "eza -al --color=always --group-directories-first --icons=always";
    la = "eza -a --color=always --group-directories-first --icons=always";
    ll = "eza -l --color=always --group-directories-first --icons=always";
    lt = "eza -aT --color=always --group-directories-first --icons=always";
    "l." = "eza -a | grep -e '^\\.'";

    # Nawigacja
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";

    # Inne narzędzia
    grep = "grep --color=auto";
    cat = "bat";
    hw = "hwinfo --short";
  };

  sharedFishInit = config: ''
    # Ustawienia wtyczki 'done'
    set -U __done_min_cmd_duration 10000
    set -U __done_notification_urgency_level low

    # Powitanie fastfetch
    ${lib.optionalString config.custom.enableFastfetch ''
      function fish_greeting
        fastfetch
      end
    ''}

    # Kolorowe man pages przy użyciu bat
    set -x MANROFFOPT "-c"
    set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

    # Fix dla Javy (jeśli używasz)
    set -x _JAVA_AWT_WM_NONREPARENTING 1
  '';

  sharedPackages =
    pkgs: with pkgs; [
      fish
      fishPlugins.done
      eza
      bat
      hw-probe
      fastfetch
    ];
in
{
  flake.nixosModules.shell =
    { pkgs, config, ... }:
    {
      programs.bash = {
        enable = true;
        # Using fish as the the login shell can cause compatibility issues. For example, certain recovery environments such as systemd's emergency mode to be completely broken when fish was set as the login shell. This limitation is noted on the Gentoo wiki. There they present an alternative, keeping bash as the system shell but having it exec fish when run interactively.
        interactiveShellInit = sharedBashInit pkgs;
      };
      programs.fish.enable = true;
      programs.fish.shellAliases = sharedFishAliases;
      programs.fish.interactiveShellInit = sharedFishInit config;

      environment.systemPackages = sharedPackages pkgs;
    };

  flake.homeModules.shell =
    { pkgs, config, ... }:
    {
      programs.bash = {
        enable = true;
        initExtra = sharedBashInit pkgs;
      };
      programs.fish.enable = true;
      programs.fish.shellAliases = sharedFishAliases;
      programs.fish.interactiveShellInit = sharedFishInit config;

      home.packages = sharedPackages pkgs;
    };
}
