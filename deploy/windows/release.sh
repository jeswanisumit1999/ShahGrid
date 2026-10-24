#!/usr/bin/env bash
# Build ShahGrid frontend + backend and publish a GitHub Release.
# Usage: ./deploy/windows/release.sh -t v0.0.5 [-n "release notes"] [--skip-frontend] [--skip-backend]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$REPO_ROOT/Frontend/shah_grid"
BACKEND_DIR="$REPO_ROOT/Backend"
OUT_DIR="$REPO_ROOT/.release"
API_BASE_URL="https://app.shahgrid.com/api/v1"
TAG=""
NOTES=""
SKIP_FRONTEND=false
SKIP_BACKEND=false

usage() {
  echo "Usage: $0 -t <tag> [-u <api-base-url>] [-n <notes>] [--skip-frontend] [--skip-backend]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)       TAG="$2"; shift 2 ;;
    -u|--url)       API_BASE_URL="$2"; shift 2 ;;
    -n|--notes)     NOTES="$2"; shift 2 ;;
    --skip-frontend) SKIP_FRONTEND=true; shift ;;
    --skip-backend)  SKIP_BACKEND=true; shift ;;
    *) usage ;;
  esac
done

[[ -z "$TAG" ]] && { echo "ERROR: -t <tag> is required"; usage; }
[[ -z "$NOTES" ]] && NOTES="ShahGrid release $TAG"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
ASSETS=()

# -- Frontend ------------------------------------------------------------------
if [[ "$SKIP_FRONTEND" == false ]]; then
  echo ""
  echo "==> Flutter web build (API_BASE_URL=$API_BASE_URL)"
  pushd "$FRONTEND_DIR" > /dev/null
  flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
  popd > /dev/null

  FE_ZIP="$OUT_DIR/frontend-$TAG.zip"
  # Archive the 'web' folder so it extracts to web/... (matches update.ps1 expectation)
  pushd "$FRONTEND_DIR/build" > /dev/null
  zip -r "$FE_ZIP" web
  popd > /dev/null
  ASSETS+=("$FE_ZIP")
  echo "  built $FE_ZIP"
fi

# -- Backend -------------------------------------------------------------------
if [[ "$SKIP_BACKEND" == false ]]; then
  echo ""
  echo "==> Backend package (src + tsconfig shipped; server compiles)"
  STAGE="$OUT_DIR/backend-stage"
  mkdir -p "$STAGE"
  cp -r "$BACKEND_DIR/src"             "$STAGE/"
  cp -r "$BACKEND_DIR/prisma"          "$STAGE/"
  cp    "$BACKEND_DIR/tsconfig.json"   "$STAGE/"
  cp    "$BACKEND_DIR/package.json"    "$STAGE/"
  cp    "$BACKEND_DIR/package-lock.json" "$STAGE/"

  BE_ZIP="$OUT_DIR/backend-$TAG.zip"
  pushd "$STAGE" > /dev/null
  zip -r "$BE_ZIP" .
  popd > /dev/null
  ASSETS+=("$BE_ZIP")
  echo "  built $BE_ZIP"
fi

[[ ${#ASSETS[@]} -eq 0 ]] && { echo "ERROR: nothing built (both sides skipped)"; exit 1; }

# -- Publish GitHub Release ----------------------------------------------------
echo ""
echo "==> Publishing GitHub release $TAG"
command -v gh > /dev/null || { echo "ERROR: 'gh' CLI not found. Install: brew install gh && gh auth login"; exit 1; }

if gh release view "$TAG" > /dev/null 2>&1; then
  gh release upload "$TAG" "${ASSETS[@]}" --clobber
else
  gh release create "$TAG" "${ASSETS[@]}" --title "$TAG" --notes "$NOTES"
fi

echo ""
echo "Done. On the server run:  .\\update.ps1"
[[ "$SKIP_BACKEND"  == true ]] && echo "  (frontend-only -> server: .\\update.ps1 -FrontendOnly)"
[[ "$SKIP_FRONTEND" == true ]] && echo "  (backend-only  -> server: .\\update.ps1 -BackendOnly)"
