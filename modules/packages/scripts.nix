{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        flake-update = pkgs.writeShellScriptBin "flake-update" ''
          set -euo pipefail

          cd "$(git rev-parse --show-toplevel)"
          if [[ ! -f flake.nix || ! -f modules/packages/_helium/default.nix ]]; then
            echo "Run flake-update from the NixOS configuration repository." >&2
            exit 1
          fi
          if [[ -n "$(git status --porcelain)" ]]; then
            echo "Commit or stash existing changes before running flake-update." >&2
            exit 1
          fi

          echo "Updating flake inputs..."
          nix flake update
          echo "Updating helium..."
          ${pkgs.lib.getExe pkgs.nix-update} --system x86_64-linux -F helium
          ${pkgs.lib.getExe pkgs.nix-update} --system aarch64-linux -F helium --version skip
          echo "Updating bootdev-cli..."
          ${pkgs.lib.getExe pkgs.nix-update} -F bootdev-cli
          echo "Updating waywallen..."
          # Dwa pasy jak przy helium: x86_64 (wersja + hash), potem
          # aarch64 (hash bez zmiany wersji). OweVersion (plugin
          # open-wallpaper-engine) bumpuje się RĘCZNIE w
          # modules/packages/_waywallen/default.nix + `nix hash file`.
          ${pkgs.lib.getExe pkgs.nix-update} --system x86_64-linux -F waywallen
          ${pkgs.lib.getExe pkgs.nix-update} --system aarch64-linux -F waywallen --version skip

          echo "Syncing GitHub Actions workflows from the updated flake..."
          nix run .#sync-github-actions

          git add -A -- flake.lock .github/workflows \
            modules/packages/_helium/default.nix \
            modules/packages/_bootdev-cli/default.nix \
            modules/packages/_waywallen/default.nix
          if git diff --cached --quiet; then
            echo "Everything is already up to date."
          else
            # The dev shell's workflow hook may still point at the old lock.
            # The fresh generator has already run above.
            SKIP=sync-github-actions git commit -m "flake-update: update inputs and packages"
          fi
          echo "All packages updated!"
        '';

        repo-sync = pkgs.writeShellScriptBin "repo-sync" ''
          set -e
          cd "$(git rev-parse --show-toplevel)"
          echo "Committing local changes..."
          git add -A
          git commit -m "chore: sync repository" || true
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
      };
    };
}
