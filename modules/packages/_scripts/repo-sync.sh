cd "$(git rev-parse --show-toplevel)"
echo "Committing local changes..."
git add -A
# Commit tylko gdy są zmiany — błąd hooka (np. gitleaks) ma przerwać sync.
git diff --cached --quiet || git commit -m "chore: sync repository"
echo "Pulling latest changes..."
git pull --rebase --autostash
echo "Pushing to GitHub..."
git push
echo "Repository synced!"
