# Powłoka na każdym hoście: bash zostaje powłoką logowania i interaktywnie
# przechodzi w fish (tryb ratunkowy systemd i skrypty dalej mają basha),
# aliasy eza/bat, powitanie fastfetch (customBot.enableFastfetch) i tmux.
{ lib, ... }:
{
  flake.modules.nixos.base-shell =
    { config, pkgs, ... }:
    let
      ezaAlias = flags: "eza ${flags} --color=always --group-directories-first --icons=always";
    in
    {
      programs = {
        bash = {
          enable = true;
          interactiveShellInit = ''
            if [[ $(${lib.getExe' pkgs.procps "ps"} --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
            then
              shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
              exec ${lib.getExe pkgs.fish} $LOGIN_OPTION
            fi
          '';
        };

        fish = {
          enable = true;
          shellAliases = {
            ls = ezaAlias "-al";
            la = ezaAlias "-a";
            ll = ezaAlias "-l";
            lt = ezaAlias "-aT";
            "l." = "eza -a | grep -e '^\\.'";
            ".." = "cd ..";
            "..." = "cd ../..";
            "...." = "cd ../../..";
            grep = "grep --color=auto";
            cat = "bat";
            hw = "hwinfo --short";
          };
          interactiveShellInit = ''
            # Ustawienia wtyczki 'done' (-g: bez zapisu fish_variables przy każdym starcie)
            set -g __done_min_cmd_duration 10000
            set -g __done_notification_urgency_level low

            # Powitanie fastfetch
            ${lib.optionalString config.customBot.enableFastfetch ''
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
        };

        tmux = {
          enable = true;
          keyMode = "vi";
          historyLimit = 100000;
          terminal = "tmux-256color";
          extraConfig = ''
            # Obsługa myszy (przewijanie, zmiana rozmiaru paneli, wybór)
            set -g mouse on

            # Obrazki Sixel (np. chafa) przez tmux: klient z TERM=xterm-256color
            # to Konsole, ttyd (enableSixel) albo Windows Terminal (WSL) — wszystkie
            # obsługują Sixel. Alacritty (bez grafiki) ma własny terminfo i
            # TERM=alacritty, więc tu nie pasuje.
            set -as terminal-features ',xterm-256color:sixel'
          '';
        };
      };

      environment.systemPackages = with pkgs; [
        fish
        fishPlugins.done
        eza
        bat
        fastfetch
        p7zip # wymagany m.in. przez reshadelinux
        chafa
      ];
    };
}
