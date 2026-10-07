# nix/nixosModules.nix — the NixOS module for hermes-agent
#
# This module shares its options, its renderers for config.yaml, .env and
# documents, and its state setup with the Home Manager module
# (nix/homeManagerModules.nix). The shared code is in nix/moduleCommon.nix.
# This file holds only the parts that need root: the service user, a system
# state directory, the system PATH, and container mode.
#
# Two modes:
#   container.enable = false (default) → native systemd service
#   container.enable = true            → OCI container (persistent writable layer)
#
# Container mode: hermes runs from /nix/store bind-mounted read-only into a
# plain Ubuntu container. The writable layer (apt/pip/npm installs) persists
# across restarts and agent updates. Only image/volume/options changes trigger
# container recreation. Environment variables are written to $HERMES_HOME/.env
# and read by hermes at startup — no container recreation needed for env changes.
#
# Tool resolution: the hermes wrapper uses --suffix PATH for nix store tools,
# so apt/uv-installed versions take priority. The container entrypoint provisions
# extensible tools on first boot: nodejs/npm via apt, uv via curl, and a Python
# 3.11 venv (bootstrapped entirely by uv) at ~/.venv with pip seeded. Agents get
# writable tool prefixes for npm i -g, pip install, uv tool install, etc.
#
# Usage:
#   services.hermes-agent = {
#     enable = true;
#     settings.model.default = "anthropic/claude-sonnet-4";
#     environmentFiles = [ config.sops.secrets."hermes/env".path ];
#   };
#
# ── Kopia w tym repo (janusz-bit/nixos) ─────────────────────────────────────
# Plik = nix/nixosModules.nix z NousResearch/hermes-agent @ 0a374d16 (MIT,
# ./LICENSE), importowany przez modules/hosts/raspberry-pi-4/hermes.nix zamiast
# inputs.hermes-agent.nixosModules.default. moduleCommon.nix i pakiet nadal
# pochodzą z inputu. Zmiany względem upstreamu (oznaczone „janusz-bit:”):
#   1. aktywacja „hermes-agent-setup” nie pisze jako root w katalogach
#      należących do konta hermes. Upstream robi tam mkdir/chown/chmod/install
#      i merge config.yaml jako root; agent podmienia wpis na symlink
#      (np. stateDir/home -> /etc) i przy najbliższym switch/boot dostaje
#      roota. Tu root zakłada tylko stateDir (rodzic /var/lib należy do roota),
#      resztę wykonuje proces z uid/gid usługi (setpriv), więc symlink agenta
#      daje mu co najwyżej jego własne uprawnienia,
#   2. tryb kontenerowy jest wyłączony asercją — jego aktywacji (dowiązania
#      w katalogach domowych hostUsers jako root) nikt tu nie przeglądał,
#   3. moduleCommon.nix z inputu (ścieżka absolutna zamiast ./).
# Synchronizacja po `nix flake update hermes-agent`: diff upstreamowego
# nix/nixosModules.nix między starym a nowym commitem nałożyć na ten plik,
# zachowując zmiany 1–3 (porównywać z upstreamem przepuszczonym przez nixfmt
# z devShella — inna wersja nixfmt zmienia wcięcia), potem podbić commit
# w pierwszym zdaniu powyżej. Test: checks.<system>.hermes-activation.
# Usunąć kopię, gdy upstream przestanie pisać jako root w stateDir
# (temporary-fixes.md).
{ inputs, ... }:
{
  flake.nixosModules.default =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:

    let
      cfg = config.services.hermes-agent;
      # janusz-bit: (3) ścieżka do inputu zamiast ./moduleCommon.nix
      common = import "${inputs.self}/nix/moduleCommon.nix" { inherit lib; };

      effectivePackage = common.effectivePackage cfg;
      hermes-agent = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.default;

      hermesHome = "${cfg.stateDir}/.hermes";

      # In container mode, the agent uses the mount path in the container.
      effectiveWorkDir = if cfg.container.enable then containerWorkDir else cfg.workingDirectory;

      # config.yaml mode: group-writable (0660) when interactive users share this
      # HERMES_HOME via addToSystemPackages, so they can save settings through the
      # CLI/TUI without hitting EACCES; otherwise group-read-only (0640). Secrets
      # (.env) stay 0640 regardless.
      configYamlMode = if cfg.addToSystemPackages then "0660" else "0640";

      containerName = "hermes-agent";
      containerDataDir = "/data"; # stateDir mount point inside container
      containerHomeDir = "/home/hermes";

      # ── Container mode helpers ──────────────────────────────────────────
      containerBin =
        if cfg.container.backend == "docker" then
          "${pkgs.docker}/bin/docker"
        else
          "${pkgs.podman}/bin/podman";

      # Runs as root inside the container on every start. Provisions the
      # hermes user + sudo on first boot (writable layer persists), then
      # drops privileges. Supports arbitrary base images (Debian, Alpine, etc).
      containerEntrypoint = pkgs.writeShellScript "hermes-container-entrypoint" ''
        set -eu

        HERMES_UID="''${HERMES_UID:?HERMES_UID must be set}"
        HERMES_GID="''${HERMES_GID:?HERMES_GID must be set}"

        # ── Group: ensure a group with GID=$HERMES_GID exists ──
        # Check by GID (not name) to avoid collisions with pre-existing groups
        # (e.g. GID 100 = "users" on Ubuntu)
        EXISTING_GROUP=$(getent group "$HERMES_GID" 2>/dev/null | cut -d: -f1 || true)
        if [ -n "$EXISTING_GROUP" ]; then
          GROUP_NAME="$EXISTING_GROUP"
        else
          GROUP_NAME="hermes"
          if command -v groupadd >/dev/null 2>&1; then
            groupadd -g "$HERMES_GID" "$GROUP_NAME"
          elif command -v addgroup >/dev/null 2>&1; then
            addgroup -g "$HERMES_GID" "$GROUP_NAME" 2>/dev/null || true
          fi
        fi

        # ── User: ensure a user with UID=$HERMES_UID exists ──
        PASSWD_ENTRY=$(getent passwd "$HERMES_UID" 2>/dev/null || true)
        if [ -n "$PASSWD_ENTRY" ]; then
          TARGET_USER=$(echo "$PASSWD_ENTRY" | cut -d: -f1)
          TARGET_HOME=$(echo "$PASSWD_ENTRY" | cut -d: -f6)
        else
          TARGET_USER="hermes"
          TARGET_HOME="/home/hermes"
          if command -v useradd >/dev/null 2>&1; then
            useradd -u "$HERMES_UID" -g "$HERMES_GID" -m -d "$TARGET_HOME" -s /bin/bash "$TARGET_USER"
          elif command -v adduser >/dev/null 2>&1; then
            adduser -u "$HERMES_UID" -D -h "$TARGET_HOME" -s /bin/sh -G "$GROUP_NAME" "$TARGET_USER" 2>/dev/null || true
          fi
        fi
        mkdir -p "$TARGET_HOME"
        chown "$HERMES_UID:$HERMES_GID" "$TARGET_HOME"
        chmod 0750 "$TARGET_HOME"

        # Ensure HERMES_HOME is owned by the target user.
        # Use find instead of chown -R: chown strips the setgid bit (kernel
        # behavior), destroying the 2770 permissions the NixOS activation
        # script sets for group access by hostUsers.  Only touch files with
        # wrong ownership so correctly-owned dirs keep their permission bits.
        if [ -n "''${HERMES_HOME:-}" ] && [ -d "$HERMES_HOME" ]; then
          find "$HERMES_HOME" \! -user "$HERMES_UID" -exec chown "$HERMES_UID:$HERMES_GID" {} +
        fi

        # ── Provision apt packages (first boot only, cached in writable layer) ──
        # sudo: agent self-modification
        # nodejs/npm: writable node so npm i -g works (nix store copies are read-only)
        #   Node 22 via NodeSource — Ubuntu 24.04 ships Node 18 which is EOL.
        # curl: needed for uv installer + NodeSource setup
        if [ ! -f /var/lib/hermes-tools-provisioned ] && command -v apt-get >/dev/null 2>&1; then
          echo "First boot: provisioning agent tools..."
          apt-get update -qq
          apt-get install -y -qq sudo curl ca-certificates gnupg
          mkdir -p /etc/apt/keyrings
          curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
            | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
          echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
            > /etc/apt/sources.list.d/nodesource.list
          apt-get update -qq
          apt-get install -y -qq nodejs
          touch /var/lib/hermes-tools-provisioned
        fi

        if command -v sudo >/dev/null 2>&1 && [ ! -f /etc/sudoers.d/hermes ]; then
          mkdir -p /etc/sudoers.d
          echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hermes
          chmod 0440 /etc/sudoers.d/hermes
        fi

        # uv (Python manager) — not in Ubuntu repos, retry-safe outside the sentinel
        if ! command -v uv >/dev/null 2>&1 && [ ! -x "$TARGET_HOME/.local/bin/uv" ] && command -v curl >/dev/null 2>&1; then
          su -s /bin/sh "$TARGET_USER" -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || true
        fi

        # Python 3.12 venv — gives the agent a writable Python with pip.
        # --seed includes pip/setuptools so bare `pip install` works.
        _UV_BIN="$TARGET_HOME/.local/bin/uv"
        if [ ! -d "$TARGET_HOME/.venv" ] && [ -x "$_UV_BIN" ]; then
          su -s /bin/sh "$TARGET_USER" -c "
            export PATH=\"\$HOME/.local/bin:\$PATH\"
            uv python install 3.12
            uv venv --python 3.12 --seed \"\$HOME/.venv\"
          " || true
        fi

        # Put the agent venv first on PATH so python/pip resolve to writable copies
        if [ -d "$TARGET_HOME/.venv/bin" ]; then
          export PATH="$TARGET_HOME/.venv/bin:$PATH"
        fi

        if command -v setpriv >/dev/null 2>&1; then
          exec setpriv --reuid="$HERMES_UID" --regid="$HERMES_GID" --init-groups "$@"
        elif command -v su >/dev/null 2>&1; then
          exec su -s /bin/sh "$TARGET_USER" -c 'exec "$0" "$@"' -- "$@"
        else
          echo "WARNING: no privilege-drop tool (setpriv/su), running as root" >&2
          exec "$@"
        fi
      '';

      # Identity hash — only recreate container when structural config changes.
      # Package and entrypoint use stable symlinks (current-package, current-entrypoint)
      # so they can update without recreation. Env vars go through $HERMES_HOME/.env.
      containerIdentity = builtins.hashString "sha256" (
        builtins.toJSON {
          schema = 4; # bump when identity inputs change (4: Node 18→22 via NodeSource)
          image = cfg.container.image;
          extraVolumes = cfg.container.extraVolumes;
          extraOptions = cfg.container.extraOptions;
        }
      );

      identityFile = "${cfg.stateDir}/.container-identity";

      # janusz-bit: (2) containerModeFile (.container-mode dla CLI) usunięty
      # razem z aktywacją trybu kontenerowego.

      # Default: /var/lib/hermes/workspace → /data/workspace.
      # Custom paths outside stateDir pass through unchanged (user must add extraVolumes).
      containerWorkDir =
        if lib.hasPrefix "${cfg.stateDir}/" cfg.workingDirectory then
          "${containerDataDir}/${lib.removePrefix "${cfg.stateDir}/" cfg.workingDirectory}"
        else
          cfg.workingDirectory;

      # The hardening and the environment that the gateway unit and the
      # backend unit share.
      commonServiceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workingDirectory;

        Restart = cfg.restart;
        RestartSec = cfg.restartSec;

        # Shared-state: files created by the service should be group-writable
        # so interactive users in the hermes group can read/write them.
        UMask = "0007";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [
          cfg.stateDir
          cfg.workingDirectory
        ];
        PrivateTmp = true;
      };

      commonUnitEnvironment = {
        HOME = cfg.stateDir;
      }
      // common.processEnvironment { inherit hermesHome; };

      unitPath = common.processPath { inherit pkgs cfg; };

      # Whether the service uid gets a systemd user manager, and with it the
      # user bus that restart-safe cron workers need (see the `linger` attribute
      # under createUser). Read back off `config` rather than assumed, so an
      # operator who declares the user themselves — or who turns the default off
      # — does not pay for a bus that will never arrive.
      lingerEnabled = ((config.users.users.${cfg.user} or { }).linger or false) == true;

    in
    {
      options.services.hermes-agent =
        common.sharedOptions {
          defaultPackage = hermes-agent;
          defaultPackageText = lib.literalExpression "hermes-agent.packages.\${system}.default";
          defaultWorkingDirectory = "${cfg.stateDir}/workspace";
          defaultWorkingDirectoryText = lib.literalExpression ''"''${cfg.stateDir}/workspace"'';
        }
        // (with lib; {
          # ── Service identity ───────────────────────────────────────────
          user = mkOption {
            type = types.str;
            default = "hermes";
            description = "System user running the gateway.";
          };

          group = mkOption {
            type = types.str;
            default = "hermes";
            description = "System group running the gateway.";
          };

          createUser = mkOption {
            type = types.bool;
            default = true;
            description = "Create the user/group automatically.";
          };

          # ── Directories ────────────────────────────────────────────────
          stateDir = mkOption {
            type = types.str;
            default = "/var/lib/hermes";
            description = "State directory. Contains .hermes/ subdir (HERMES_HOME).";
          };

          addToSystemPackages = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Add the hermes CLI to environment.systemPackages and export
              HERMES_HOME system-wide (via environment.variables) so interactive
              shells share state with the gateway service.
            '';
          };

          # ── OCI Container (opt-in) ────────────────────────────────────
          container = {
            enable = mkEnableOption "OCI container mode (Ubuntu base, full self-modification support)";

            backend = mkOption {
              type = types.enum [
                "docker"
                "podman"
              ];
              default = "docker";
              description = "Container runtime.";
            };

            extraVolumes = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Extra volume mounts (host:container:mode format).";
              example = [ "/home/user/projects:/projects:rw" ];
            };

            extraOptions = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Extra arguments passed to docker/podman run.";
            };

            image = mkOption {
              type = types.str;
              default = "ubuntu:24.04";
              description = "OCI container image. The container pulls this at runtime via Docker/Podman.";
            };

            hostUsers = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = ''
                Interactive users who get a ~/.hermes symlink to the service
                stateDir. These users are automatically added to the hermes group.
              '';
              example = [ "sidbin" ];
            };
          };
        });

      config = lib.mkIf cfg.enable (
        lib.mkMerge [

          # ── Merge MCP servers into settings ────────────────────────────────
          (lib.mkIf (cfg.mcpServers != { }) {
            services.hermes-agent.settings.mcp_servers = common.mcpServersToConfig cfg.mcpServers;
          })

          # ── User / group ──────────────────────────────────────────────────
          (lib.mkIf cfg.createUser {
            users.groups.${cfg.group} = { };
            users.users.${cfg.user} = {
              isSystemUser = true;
              inherit (cfg) group;
              home = cfg.stateDir;
              createHome = true;
              shell = pkgs.bashInteractive;

              # The cron scheduler launches every job in a transient `systemd-run
              # --user --scope` so a gateway restart cannot kill a running job,
              # and that needs a systemd user manager for this uid. A system
              # service has no /run/user/<uid> unless the uid lingers, and the
              # dispatch fails closed — without this, no cron job runs at all.
              #
              # Needs nixpkgs >= 25.05 (users.manageLingering). In container mode cron
              # runs inside the container, so the host uid needs no user manager.
              linger = lib.mkDefault (!cfg.container.enable);
            };
          })

          # ── Host CLI ──────────────────────────────────────────────────────
          # Add the hermes CLI to system PATH and export HERMES_HOME system-wide
          # so interactive shells share state (sessions, skills, cron) with the
          # gateway service instead of creating a separate ~/.hermes/.
          (lib.mkIf cfg.addToSystemPackages {
            environment.systemPackages = [ effectivePackage ];
            environment.variables.HERMES_HOME = hermesHome;
          })

          # ── Host user group membership ─────────────────────────────────────
          (lib.mkIf (cfg.container.enable && cfg.container.hostUsers != [ ]) {
            users.users = lib.genAttrs cfg.container.hostUsers (_user: {
              extraGroups = [ cfg.group ];
            });
          })

          # ── Assertions ─────────────────────────────────────────────────────
          {
            assertions =
              common.pluginNameAssertions {
                inherit cfg;
                optionPath = "services.hermes-agent";
              }
              ++ common.workspaceFilesAssertions {
                inherit cfg;
                opt = options.services.hermes-agent.workingDirectory;
                optionPath = "services.hermes-agent";
              }
              ++ common.backendBindAssertions {
                inherit cfg;
                optionPath = "services.hermes-agent";
              }
              ++ [
                {
                  # janusz-bit: (2) tylko tryb natywny został przejrzany pod
                  # kątem zapisów roota w katalogach agenta.
                  assertion = !cfg.container.enable;
                  message = "services.hermes-agent: container mode is not supported by the vendored module in modules/hosts/raspberry-pi-4/_hermes-agent (its activation was not reviewed).";
                }
                {
                  # Container mode runs one command in one container. A second
                  # process needs its own container and its own ports. This
                  # module does not do that.
                  assertion = !(cfg.container.enable && cfg.backend.mode != "none");
                  message = "services.hermes-agent: backend.mode is not supported together with container.enable — the container runs the gateway only.";
                }
              ];
          }

          # ── Per-user profile for extraPackages ───────────────────────────
          # Wire extraPackages into the hermes user's per-user profile so the
          # login-shell snapshot (which rebuilds PATH from NixOS profiles) sees
          # them.  The systemd service PATH also includes them for direct access.
          (lib.mkIf (cfg.extraPackages != [ ]) {
            # listOf options are merged by the NixOS module system — this appends to
            # any packages the operator assigned to this user externally (e.g. when
            # createUser = false and the user definition lives elsewhere in the config).
            users.users.${cfg.user}.packages = cfg.extraPackages;
          })

          # ── Warnings ──────────────────────────────────────────────────────
          (lib.mkIf (cfg.container.enable && !cfg.addToSystemPackages && cfg.container.hostUsers != [ ]) {
            warnings = [
              ''
                services.hermes-agent: container.enable is true and container.hostUsers
                is set, but addToSystemPackages is false. Without a host-installed hermes
                binary, container routing will not work for interactive users.
                Set addToSystemPackages = true or ensure hermes is on PATH.
              ''
            ];
          })

          # ── Directories ───────────────────────────────────────────────────
          {
            systemd.tmpfiles.rules = [
              "d ${cfg.stateDir}                2770 ${cfg.user} ${cfg.group} - -"
              "d ${hermesHome}                  2770 ${cfg.user} ${cfg.group} - -"
              "d ${cfg.stateDir}/home           0750 ${cfg.user} ${cfg.group} - -"
              "d ${cfg.workingDirectory}        2770 ${cfg.user} ${cfg.group} - -"
            ]
            ++ map (d: "d ${hermesHome}/${d} 2770 ${cfg.user} ${cfg.group} - -") common.stateSubdirs;
          }

          # ── Activation: link config + auth + documents ────────────────────
          # janusz-bit: (1) zmiana względem upstreamu. Root zakłada wyłącznie
          # stateDir: jego rodzic (/var/lib) należy do roota, więc agent nie
          # podmieni tej ścieżki. Wszystko wewnątrz stateDir należy do agenta
          # (2770) i każdy wpis może być jego symlinkiem, dlatego katalogi,
          # config.yaml, .env, dokumenty i pluginy zakłada proces z uid/gid
          # usługi (setpriv), który przez symlink sięgnie tylko tam, gdzie agent
          # i tak sięga. Pliki environmentFiles muszą być czytelne dla
          # cfg.user (u nas sekrety agenix z owner = "hermes"); nieczytelny
          # plik kończy się ostrzeżeniem jak w upstreamie.
          {
            system.activationScripts."hermes-agent-setup" =
              let
                stateSetup = pkgs.writeShellScript "hermes-agent-state-setup" ''
                  set -eu
                  PATH=${
                    lib.makeBinPath [
                      pkgs.coreutils
                      pkgs.findutils
                    ]
                  }

                  # Katalogu innego właściciela (założonego kiedyś jako root/nixos)
                  # nie da się bezpiecznie naprawić automatycznie — głośny błąd
                  # zamiast cichego EPERM z chmod.
                  own_dir() {
                    if [ ! -O "$1" ]; then
                      echo "hermes-agent: $1 nie należy do ${cfg.user}; napraw raz: chown -h ${cfg.user}:${cfg.group} $1" >&2
                      return 1
                    fi
                  }

                  # Ensure directories exist (activation runs before tmpfiles)
                  mkdir -p ${hermesHome} ${cfg.stateDir}/home ${cfg.workingDirectory}
                  for _dir in ${hermesHome} ${cfg.stateDir}/home ${cfg.workingDirectory}; do
                    own_dir "$_dir"
                  done
                  chmod 2770 ${hermesHome} ${cfg.workingDirectory}
                  chmod 0750 ${cfg.stateDir}/home

                  # Create subdirs, set setgid + group-writable, migrate existing files.
                  # Nix-managed .env/.managed stay 0640/0644; config.yaml uses
                  # configYamlMode (0660 under addToSystemPackages, else 0640).
                  find ${hermesHome} -maxdepth 1 \
                    \( -name "*.db" -o -name "*.db-wal" -o -name "*.db-shm" -o -name "SOUL.md" \) \
                    -exec chmod g+rw {} + 2>/dev/null || true
                  for _subdir in ${lib.concatStringsSep " " common.stateSubdirs}; do
                    mkdir -p "${hermesHome}/$_subdir"
                    own_dir "${hermesHome}/$_subdir"
                    chmod 2770 "${hermesHome}/$_subdir"
                    find "${hermesHome}/$_subdir" -type f \
                      -exec chmod g+rw {} + 2>/dev/null || true
                  done

                  # config.yaml zapisany kiedyś przez innego użytkownika (CLI jako
                  # nixos/root) nie da się chmodować jako cfg.user; kopia przez
                  # plik tymczasowy w tym samym katalogu daje plik usługi z tą
                  # samą treścią, zanim merge ją zaktualizuje.
                  if [ -e ${hermesHome}/config.yaml ] && [ ! -O ${hermesHome}/config.yaml ]; then
                    cp ${hermesHome}/config.yaml ${hermesHome}/.config.yaml.own
                    mv -f ${hermesHome}/.config.yaml.own ${hermesHome}/config.yaml
                  fi

                  ${common.mkStateScript {
                    inherit pkgs cfg hermesHome;
                    inherit (cfg) workingDirectory;
                    configWorkingDirectory = effectiveWorkDir;
                    # null: pliki należą do procesu, który je tworzy (cfg.user)
                    owner = null;
                    stateDirs = common.stateSubdirs;
                    modes = {
                      config = configYamlMode;
                      env = "0640";
                      managed = "0644";
                      auth = "0600";
                      document = "0640";
                    };
                  }}

                  # Container mode metadata — the host CLI would exec into the
                  # container. Container mode is disabled (assertion above).
                  rm -f ${hermesHome}/.container-mode
                '';
              in
              lib.stringAfter
                ([ "users" ] ++ lib.optional (config.system.activationScripts ? setupSecrets) "setupSecrets")
                ''
                  install -d -m 2770 -o ${cfg.user} -g ${cfg.group} ${cfg.stateDir}
                  ${pkgs.util-linux}/bin/setpriv \
                    --reuid=${cfg.user} --regid=${cfg.group} --init-groups \
                    --inh-caps=-all --bounding-set=-all --no-new-privs --reset-env \
                    -- ${stateSetup}
                '';
          }

          # ══════════════════════════════════════════════════════════════════
          # MODE A: Native systemd service (default)
          # ══════════════════════════════════════════════════════════════════
          (lib.mkIf (!cfg.container.enable) {
            systemd.services.hermes-agent = {
              description = "Hermes Agent Gateway";
              wantedBy = [ "multi-user.target" ];
              # linger-users.service is the unit that runs `loginctl
              # enable-linger` for a declared `users.users.<name>.linger`.
              after = [
                "network-online.target"
              ]
              ++ lib.optional lingerEnabled "linger-users.service";
              wants = [
                "network-online.target"
              ]
              ++ lib.optional lingerEnabled "linger-users.service";

              # cfg.environment and cfg.environmentFiles are written to
              # $HERMES_HOME/.env by the activation script. load_hermes_dotenv()
              # reads them at Python startup — no systemd EnvironmentFile needed.
              environment = commonUnitEnvironment;

              # Wait for the user bus that `systemd-run --user --scope` connects
              # to. Ordering after linger-users.service is not enough on its own:
              # `loginctl enable-linger` returns before logind has finished
              # starting user@<uid>.service, and run_gateway() resolves
              # XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS exactly once at
              # startup — so a bus that appears after ExecStart is a bus this
              # process never sees, for its whole lifetime.
              #
              # Bounded and non-fatal: a gateway without cron beats no gateway.
              preStart = lib.mkIf lingerEnabled ''
                for _ in $(seq 1 50); do
                  [ -S "/run/user/$(id -u)/bus" ] && break
                  sleep 0.2
                done
                if [ ! -S "/run/user/$(id -u)/bus" ]; then
                  echo "hermes-agent: no user bus at /run/user/$(id -u)/bus after 10s;" \
                       "restart-safe cron dispatch will fail for the life of this process" >&2
                fi
              '';

              serviceConfig = commonServiceConfig // {
                ExecStart = lib.escapeShellArgs (common.gatewayArgv cfg);
              };

              path = unitPath;
            };
          })

          # ── The backend: hermes serve or hermes dashboard ─────────────────
          # This is a different process from the gateway. Both use one
          # HERMES_HOME.
          (lib.mkIf (!cfg.container.enable && cfg.backend.mode != "none") {
            systemd.services.hermes-backend = {
              description = common.backendDescription cfg;
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];

              environment = commonUnitEnvironment;

              serviceConfig = commonServiceConfig // {
                ExecStart = lib.escapeShellArgs (common.backendArgv { inherit pkgs cfg; });
              };

              path = unitPath;
            };
          })

          # ══════════════════════════════════════════════════════════════════
          # MODE B: OCI container (persistent writable layer)
          # ══════════════════════════════════════════════════════════════════
          (lib.mkIf cfg.container.enable {
            # Ensure the container runtime is available
            virtualisation.docker.enable = lib.mkDefault (cfg.container.backend == "docker");

            systemd.services.hermes-agent = {
              description = "Hermes Agent Gateway (container)";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network-online.target"
              ]
              ++ lib.optional (cfg.container.backend == "docker") "docker.service";
              wants = [ "network-online.target" ];
              requires = lib.optional (cfg.container.backend == "docker") "docker.service";

              preStart = ''
                # Stable symlinks — container references these, not store paths directly
                ln -sfn ${effectivePackage} ${cfg.stateDir}/current-package
                ln -sfn ${containerEntrypoint} ${cfg.stateDir}/current-entrypoint

                # GC roots so nix-collect-garbage doesn't remove store paths in use
                ${pkgs.nix}/bin/nix-store --add-root ${cfg.stateDir}/.gc-root --indirect -r ${effectivePackage} 2>/dev/null || true
                ${pkgs.nix}/bin/nix-store --add-root ${cfg.stateDir}/.gc-root-entrypoint --indirect -r ${containerEntrypoint} 2>/dev/null || true

                # Check if container needs (re)creation
                NEED_CREATE=false
                if ! ${containerBin} inspect ${containerName} &>/dev/null; then
                  NEED_CREATE=true
                elif [ ! -f ${identityFile} ] || [ "$(cat ${identityFile})" != "${containerIdentity}" ]; then
                  echo "Container config changed, recreating..."
                  ${containerBin} rm -f ${containerName} || true
                  NEED_CREATE=true
                fi

                if [ "$NEED_CREATE" = "true" ]; then
                  # Resolve numeric UID/GID — passed to entrypoint for in-container user setup
                  HERMES_UID=$(${pkgs.coreutils}/bin/id -u ${cfg.user})
                  HERMES_GID=$(${pkgs.coreutils}/bin/id -g ${cfg.user})

                  echo "Creating container..."
                  ${containerBin} create \
                    --name ${containerName} \
                    --network=host \
                    --entrypoint ${containerDataDir}/current-entrypoint \
                    --volume /nix/store:/nix/store:ro \
                    --volume ${cfg.stateDir}:${containerDataDir} \
                    --volume ${cfg.stateDir}/home:${containerHomeDir} \
                    ${lib.concatStringsSep " " (map (v: "--volume ${v}") cfg.container.extraVolumes)} \
                    --env HERMES_UID="$HERMES_UID" \
                    --env HERMES_GID="$HERMES_GID" \
                    --env HERMES_HOME=${containerDataDir}/.hermes \
                    --env HERMES_MANAGED=true \
                    --env HOME=${containerHomeDir} \
                    ${lib.concatStringsSep " " cfg.container.extraOptions} \
                    ${cfg.container.image} \
                    ${containerDataDir}/current-package/bin/hermes gateway run --replace ${lib.concatStringsSep " " cfg.extraArgs}

                  echo "${containerIdentity}" > ${identityFile}
                fi
              '';

              script = ''
                exec ${containerBin} start -a ${containerName}
              '';

              preStop = ''
                ${containerBin} stop -t 10 ${containerName} || true
              '';

              serviceConfig = {
                Type = "simple";
                Restart = cfg.restart;
                RestartSec = cfg.restartSec;
                TimeoutStopSec = 30;
              };
            };
          })
        ]
      );
    };
}
