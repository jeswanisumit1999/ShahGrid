#!/usr/bin/env bash
# Build ShahGrid frontend + backend on macOS/Linux and publish a GitHub Release
# that the server's update.ps1 / setup.ps1 will pull. Mirror of release.ps1.
#
# Produces the SAME zip layout the server expects:
#   frontend-<tag>.zip  ->  contains  web/...      (extracts to <dest>/web)
#   backend-<tag>.zip   ->  contains  dist/ prisma/ package.json package-lock.json
#                                     (node_modules NOT shipped; server runs npm ci)
#
# Requires: flutter, node/npm, zip, gh (logged in with push access).
#
# Usage:
#   ./deploy/windows/release.sh -t v1.2.0 -n "fix retailer export"
#   ./deploy/windows/release.sh -t v1.2.1 --skip-backend     # frontend-only
#   ./deploy/windows/release.sh -t v1.2.2 --skip-frontend    # backend-only
set -euo pipefail

TAG=""
API_BASE_URL="https://app.shahgrid.com/api/v1"
SKIP_FRONTEND=false
SKIP_BACKEND=false
NOTES=""

usage() {
  cat <<EOF
Usage: $0 -t <tag> [options]
  -t, --tag <tag>          Release tag, e.g. v1.2.0 (required)
  -a, --api-base-url <url> Baked into the Flutter build (default: $API_BASE_URL)
  -n, --notes <text>       Release notes
      --skip-frontend      Build/publish backend only
      --skip-backend       Build/publish frontend only
  -h, --help
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)            TAG="$2"; shift 2 ;;
    -a|--api-base-url)   API_BASE_URL="$2"; shift 2 ;;
    -n|--notes)          NOTES="$2"; shift 2 ;;
    --skip-frontend)     SKIP_FRONTEND=true; shift ;;
    --skip-backend)      SKIP_BACKEND=true; shift ;;
    -h|--help)           usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

[[ -z "$TAG" ]] && { echo "ERROR: -t/--tag is required" >&2; usage 1; }

step() { echo ""; echo "==> $*"; }

# Repo root = two levels up from this script (deploy/windows).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$REPO_ROOT/Frontend/shah_grid"
BACKEND_DIR="$REPO_ROOT/Backend"
OUT_DIR="$REPO_ROOT/.release"

rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
ASSETS=()

# ── Frontend ──────────────────────────────────────────────────────────────────
if ! $SKIP_FRONTEND; then
  step "Flutter web build (API_BASE_URL=$API_BASE_URL)"
  ( cd "$FRONTEND_DIR" && flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL" )

  FE_ZIP="$OUT_DIR/frontend-$TAG.zip"
  # Zip the 'web' folder itself so it extracts to <dest>/web/...
  ( cd "$FRONTEND_DIR/build" && zip -rq "$FE_ZIP" web )
  ASSETS+=("$FE_ZIP")
  echo "  built $FE_ZIP"
fi

# ── Backend ───────────────────────────────────────────────────────────────────
if ! $SKIP_BACKEND; then
  step "Backend build (tsc)"
  ( cd "$BACKEND_DIR" && npm ci && npm run build )

  STAGE="$OUT_DIR/backend-stage"
  mkdir -p "$STAGE"
  cp -R "$BACKEND_DIR/dist"              "$STAGE/"
  cp -R "$BACKEND_DIR/prisma"            "$STAGE/"
  cp    "$BACKEND_DIR/package.json"      "$STAGE/"
  cp    "$BACKEND_DIR/package-lock.json" "$STAGE/"

  BE_ZIP="$OUT_DIR/backend-$TAG.zip"
  # Zip stage contents at the archive root (dist/, prisma/, package.json, lock).
  ( cd "$STAGE" && zip -rq "$BE_ZIP" . )
  ASSETS+=("$BE_ZIP")
  echo "  built $BE_ZIP"
fi

[[ ${#ASSETS[@]} -eq 0 ]] && { echo "Nothing built (both sides skipped)." >&2; exit 1; }

# ── Publish GitHub Release ────────────────────────────────────────────────────
step "Publishing GitHub release $TAG"
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI 'gh' not found. Install + 'gh auth login'." >&2; exit 1; }
[[ -z "$NOTES" ]] && NOTES="ShahGrid release $TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "${ASSETS[@]}" --clobber
else
  gh release create "$TAG" "${ASSETS[@]}" --title "$TAG" --notes "$NOTES"
fi

echo ""
echo "Done. On the server run:  .\\update.ps1"
$SKIP_BACKEND  && echo "  (frontend-only -> server: .\\update.ps1 -FrontendOnly)"
$SKIP_FRONTEND && echo "  (backend-only  -> server: .\\update.ps1 -BackendOnly)"
exit 0
