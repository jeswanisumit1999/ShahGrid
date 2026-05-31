#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
DOCKER_USER="sumitjeswani"
BACKEND_IMAGE="$DOCKER_USER/shahgrid-backend:latest"
FRONTEND_IMAGE="$DOCKER_USER/shahgrid-frontend:latest"
API_BASE_URL="https://shahgrid.publicvm.com/api/v1"
FRONTEND_DIR="Frontend/shah_grid"

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo ""; echo "▶ $*"; }

# ── Parse flags ───────────────────────────────────────────────────────────────
PUSH_GIT=true
PUSH_BACKEND=true
PUSH_FRONTEND=true
COMMIT_MSG=""

usage() {
  echo "Usage: $0 [options] [\"commit message\"]"
  echo ""
  echo "Options:"
  echo "  --no-git        Skip GitHub push"
  echo "  --no-backend    Skip backend Docker build/push"
  echo "  --no-frontend   Skip frontend Docker build/push"
  echo "  -h, --help      Show this help"
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --no-git)       PUSH_GIT=false ;;
    --no-backend)   PUSH_BACKEND=false ;;
    --no-frontend)  PUSH_FRONTEND=false ;;
    -h|--help)      usage ;;
    *)              COMMIT_MSG="$arg" ;;
  esac
done

# ── 1. Git push ───────────────────────────────────────────────────────────────
if $PUSH_GIT; then
  log "Pushing to GitHub..."
  git add -A

  if [ -z "$COMMIT_MSG" ]; then
    read -rp "Commit message: " COMMIT_MSG
  fi

  if git diff --cached --quiet; then
    echo "  Nothing to commit, skipping."
  else
    git commit -m "$COMMIT_MSG"
  fi

  git push origin "$(git rev-parse --abbrev-ref HEAD)"
  echo "  GitHub ✓"
fi

# ── 2. Backend Docker image ───────────────────────────────────────────────────
if $PUSH_BACKEND; then
  log "Building & pushing backend image ($BACKEND_IMAGE)..."
  docker buildx build \
    --platform linux/amd64 \
    -t "$BACKEND_IMAGE" \
    --push \
    ./Backend
  echo "  Backend Docker ✓"
fi

# ── 3. Frontend: Flutter build → Docker image ─────────────────────────────────
if $PUSH_FRONTEND; then
  log "Building Flutter web (API_BASE_URL=$API_BASE_URL)..."
  (cd "$FRONTEND_DIR" && flutter build web --release \
    --dart-define=API_BASE_URL="$API_BASE_URL")

  log "Building & pushing frontend image ($FRONTEND_IMAGE)..."
  docker buildx build \
    --platform linux/amd64 \
    -t "$FRONTEND_IMAGE" \
    --push \
    "./$FRONTEND_DIR"
  echo "  Frontend Docker ✓"
fi

echo ""
echo "✓ All done."
