# Skrypty utrzymania repo (packages.<system>, `nix run .#<nazwa>`):
# flake-update (wejścia flake'a, pakiety lokalne, workflowy, commit),
# repo-sync (commit wszystkiego, rebase, push), flake-release (tag vN, push),
# package-import (kopia pakietu z przypiętego nixpkgs do modules/packages/).
#
# `package-import <atrybut>` kopiuje katalog pakietu (z meta.position) do
# modules/packages/_<atrybut>/ (package.nix -> default.nix), dopisuje go do
# localPackages i sprawdza, że kopia daje tę samą derywację co nixpkgs: od
# tej chwili overlay local-packages podmienia nim pakiet z nixpkgs na hostach,
# a aktualizuje się go lokalnie (`nix-update -F <atrybut>` albo ręcznie).
# Pliki zostają w indeksie gita bez commita.
#
# Każdy działa na repo bieżącego katalogu (alias fish `update-my-pkgs` =
# flake-update). flake-update startuje tylko z czystego drzewa, więc jego
# commit zawiera wyłącznie aktualizację. repo-sync robi `git add -A`: zabiera
# każdy plik z drzewa, także roboczy (notatki i skrypty trzymać w $TMPDIR).
# flake-release wydaje tylko z master, który nie jest za origin/master, i
# wypycha gałąź z tagiem atomowo; tag v* uruchamia w CI workflowy poza
# ciężkimi (hosty z buildOnTags = false, ISO; github-actions.nix). Push to
# wdrożenie: `update` na hostach bierze konfigurację prosto z GitHuba.
#
# Sprawdzenie: `nix build --no-link .#flake-update .#repo-sync .#flake-release
# .#package-import`
# (flake-update przechodzi przy tym shellcheck).
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        flake-update = pkgs.writeShellApplication {
          name = "flake-update";
          runtimeInputs = [ pkgs.nix-update ];
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            if [[ ! -f flake.nix || ! -f modules/packages/_waywallen/default.nix ]]; then
              echo "Run flake-update from the NixOS configuration repository." >&2
              exit 1
            fi
            if [[ -n "$(git status --porcelain)" ]]; then
              echo "Commit or stash existing changes before running flake-update." >&2
              exit 1
            fi

            echo "Updating flake inputs..."
            nix flake update
            echo "Updating bootdev-cli..."
            nix-update -F bootdev-cli
            # helium i waywallen: dwa pasy — x86_64 (wersja + hash), potem
            # aarch64 (hash bez zmiany wersji).
            echo "Updating helium..."
            nix-update --system x86_64-linux -F helium
            nix-update --system aarch64-linux -F helium --version skip
            echo "Updating waywallen..."
            # OweVersion (plugin open-wallpaper-engine) bumpuje się RĘCZNIE w
            # modules/packages/_waywallen/default.nix + `nix hash file`.
            nix-update --system x86_64-linux -F waywallen
            nix-update --system x86_64-linux -F waywallen-kde-plugin
            nix-update --system aarch64-linux -F waywallen --version skip

            echo "Syncing GitHub Actions workflows and docs from the updated flake..."
            nix run .#sync-github-actions
            nix run .#sync-docs

            git add -A -- flake.lock .github/workflows docs/reference \
              modules/packages/_bootdev-cli/default.nix \
              modules/packages/_helium/default.nix \
              modules/packages/_waywallen/default.nix \
              modules/packages/_waywallen-kde-plugin/default.nix
            if git diff --cached --quiet; then
              echo "Everything is already up to date."
            else
              git commit -m "flake-update: update inputs and packages"
            fi
            echo "All packages updated!"
          '';
        };

        repo-sync = pkgs.writeShellScriptBin "repo-sync" ''
          set -euo pipefail
          cd "$(git rev-parse --show-toplevel)"
          echo "Committing local changes..."
          git add -A
          # Commit tylko gdy są zmiany — błąd hooka (np. gitleaks) ma przerwać sync.
          if ! git diff --cached --quiet; then
            git commit -m "chore: sync repository"
          fi
          echo "Pulling latest changes..."
          git pull --rebase --autostash
          echo "Pushing to GitHub..."
          git push
          echo "Repository synced!"
        '';

        flake-release = pkgs.writeShellScriptBin "flake-release" ''
          set -euo pipefail

          fail() {
            echo "flake-release: $*" >&2
            exit 1
          }

          cd "$(git rev-parse --show-toplevel)"
          [[ -f flake.nix ]] || fail "Run this from the NixOS configuration repository."
          branch=$(git symbolic-ref --quiet --short HEAD) || fail "Detached HEAD; switch to master."
          [[ "$branch" == "master" ]] || fail "Release only from master (current branch: $branch)."
          upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}') || fail "Set master upstream to origin/master."
          [[ "$upstream" == "origin/master" ]] || fail "Expected origin/master as upstream, got $upstream."
          [[ -z "$(git ls-files --others --exclude-standard)" ]] || fail "Commit or remove untracked files before releasing."

          git fetch --tags origin
          git merge-base --is-ancestor origin/master HEAD || fail "Local master is behind or diverged from origin/master."

          # Najwyższy osiągalny tag wydania; ignoruj tagi innych projektów.
          latest_tag=""
          while IFS= read -r tag; do
            if [[ "$tag" =~ ^v[0-9]+(\.[0-9]+){0,2}$ ]]; then
              latest_tag="$tag"
              break
            fi
          done < <(git tag --merged HEAD --list 'v[0-9]*' --sort=-version:refname)

          if [[ -z "$latest_tag" ]]; then
            new_tag="v1"
          else
            latest_num="''${latest_tag#v}"
            if [[ "$latest_num" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
              IFS='.' read -r major minor patch <<< "$latest_num"
              new_tag="v$major.$minor.$((10#$patch + 1))"
            elif [[ "$latest_num" =~ ^[0-9]+\.[0-9]+$ ]]; then
              IFS='.' read -r major minor <<< "$latest_num"
              new_tag="v$major.$((10#$minor + 1))"
            else
              new_tag="v$((10#$latest_num + 1))"
            fi
          fi

          git show-ref --verify --quiet "refs/tags/$new_tag" && fail "Tag $new_tag already exists."
          echo "Releasing $new_tag..."

          # git commit -a samo zwraca błąd również przy pustym drzewie.
          # Commituj tylko gdy są zmiany; błędów hooków nie wolno ukrywać.
          if ! git diff --quiet || ! git diff --cached --quiet; then
            git add -u
            git commit -m "Release $new_tag"
          fi
          [[ -z "$(git status --porcelain)" ]] || fail "Worktree changed during release; resolve it before tagging."
          [[ -z "$(git tag --points-at HEAD --list 'v[0-9]*')" ]] || fail "HEAD already has a release tag."

          git tag "$new_tag"
          if ! git push --atomic origin "HEAD:refs/heads/$branch" "refs/tags/$new_tag:refs/tags/$new_tag"; then
            fail "Push failed; $new_tag remains local for inspection and retry."
          fi
          echo "Release $new_tag pushed successfully!"
        '';

        package-import = pkgs.writeShellApplication {
          name = "package-import";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
          ];
          text = ''
            if [[ $# -ne 1 || ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
              echo "Usage: package-import <top-level nixpkgs attribute>" >&2
              exit 1
            fi
            name=$1
            cd "$(git rev-parse --show-toplevel)"
            registry=modules/packages/packages.nix
            dest=modules/packages/_$name
            if [[ ! -f flake.nix || ! -f "$registry" ]]; then
              echo "Run package-import from the NixOS configuration repository." >&2
              exit 1
            fi
            if [[ -e "$dest" ]]; then
              echo "$dest already exists." >&2
              exit 1
            fi

            # --inputs-from: nixpkgs przypięty w flake.lock (ten sam, którego
            # używają hosty), nie wpis z rejestru.
            position=$(nix eval --inputs-from . --raw "nixpkgs#$name.meta.position")
            upstream_drv=$(nix eval --inputs-from . --raw "nixpkgs#$name.drvPath")
            file=''${position%:*}
            dir=$(dirname "$file")
            entry=$(basename "$file")
            relative_dir=''${dir#"$(cut -d/ -f1-4 <<<"$file")"/}
            if [[ "$relative_dir" == pkgs/top-level ]]; then
              echo "$name is defined inline in pkgs/top-level; there is no directory to copy." >&2
              exit 1
            fi
            if [[ "$entry" != default.nix && -e "$dir/default.nix" ]]; then
              echo "$relative_dir has both $entry and default.nix; copy it by hand." >&2
              exit 1
            fi

            # Wpis alfabetycznie w bloku localPackages; awk opiera się na jego
            # wcięciach w packages.nix.
            registered=$(awk -v name="$name" '
              /^  localPackages = pkgs: \{$/ { inside = 1; print; next }
              inside && !done && (/^  \};$/ || $1 > name) {
                printf "    %s = pkgs.callPackage ./_%s { };\n", name, name
                done = 1
              }
              /^  \};$/ { inside = 0 }
              { print }
              END { exit !done }
            ' "$registry") || {
              echo "No localPackages block found in $registry." >&2
              exit 1
            }

            cp -r "$dir" "$dest"
            # Kopia ze store jest tylko do odczytu.
            chmod -R u+w "$dest"
            if [[ "$entry" != default.nix ]]; then
              mv "$dest/$entry" "$dest/default.nix"
            fi
            printf '%s\n' "$registered" >"$registry"
            # Flake widzi tylko pliki śledzone przez git.
            git add -- "$dest"
            echo "Copied $relative_dir to $dest and registered $name in $registry."

            if ! local_drv=$(nix eval --raw ".#$name.drvPath"); then
              echo "$dest does not evaluate. Fix it, or undo: git rm -rf -- $dest and remove $name from $registry." >&2
              exit 1
            fi
            if [[ "$local_drv" == "$upstream_drv" ]]; then
              echo "Same derivation as nixpkgs: $local_drv"
            else
              echo "Warning: $local_drv differs from nixpkgs ($upstream_drv);" \
                "nixpkgs probably passes extra arguments to callPackage (pkgs/top-level/all-packages.nix)." >&2
            fi
          '';
        };
      };
    };
}
