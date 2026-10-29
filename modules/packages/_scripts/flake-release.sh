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
latest_tag=$(git tag --merged HEAD --list 'v[0-9]*' --sort=-version:refname |
  grep -m1 -E '^v[0-9]+(\.[0-9]+){0,2}$' || true)

if [[ -z "$latest_tag" ]]; then
  new_tag="v1"
else
  # Podbija ostatni człon numeru: v7 -> v8, v1.2 -> v1.3, v1.2.3 -> v1.2.4.
  last=${latest_tag##*[v.]}
  new_tag="${latest_tag%"$last"}$((10#$last + 1))"
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
git push --atomic origin "HEAD:refs/heads/$branch" "refs/tags/$new_tag:refs/tags/$new_tag" ||
  fail "Push failed; $new_tag remains local for inspection and retry."
echo "Release $new_tag pushed successfully!"
