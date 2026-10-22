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
