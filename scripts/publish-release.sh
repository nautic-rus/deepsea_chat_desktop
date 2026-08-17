#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-release.sh <version> [tag] [release_name]

Examples:
  scripts/publish-release.sh 0.2.7
  scripts/publish-release.sh 0.2.7 v0.2.7 "DeepSea Chat 0.2.7"

Environment:
  DEEPSEA_RELEASE_DIST  Source folder with release artifacts.
                        Default: /Users/spiridovich/Documents/GitHub/deepsea_chat/dist
  GITHUB_TOKEN or GH_TOKEN  GitHub token with release access.
EOF
}

if [[ ${1:-} == "" || ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

version="$1"
tag="${2:-v${version}}"
release_name="${3:-DeepSea Chat ${version}}"
dist_dir="${DEEPSEA_RELEASE_DIST:-/Users/spiridovich/Documents/GitHub/deepsea_chat/dist}"

token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$token" ]]; then
  echo "Set GITHUB_TOKEN or GH_TOKEN before running this script." >&2
  exit 1
fi

if [[ ! -d "$dist_dir" ]]; then
  echo "Release source directory not found: $dist_dir" >&2
  exit 1
fi

repo_url="$(git remote get-url origin 2>/dev/null || true)"
case "$repo_url" in
  git@github.com:*)
    repo_path="${repo_url#git@github.com:}"
    ;;
  https://github.com/*)
    repo_path="${repo_url#https://github.com/}"
    ;;
  http://github.com/*)
    repo_path="${repo_url#http://github.com/}"
    ;;
  *)
    repo_path=""
    ;;
esac

repo_path="${repo_path%.git}"
if [[ -z "$repo_path" || "$repo_path" != */* ]]; then
  echo "Could not determine GitHub repository from origin remote." >&2
  exit 1
fi
owner="${repo_path%%/*}"
repo="${repo_path#*/}"

api_base="https://api.github.com/repos/${owner}/${repo}"
upload_base="https://uploads.github.com/repos/${owner}/${repo}"
auth_header="Authorization: Bearer ${token}"
accept_header="Accept: application/vnd.github+json"

assets=()
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  assets+=("$file")
done < <(
  find "$dist_dir" -maxdepth 1 -type f \( \
    -name "*.exe" -o \
    -name "*.dmg" \
  \) | sort
)

if (( ${#assets[@]} == 0 )); then
  echo "No release assets found in: $dist_dir" >&2
  exit 1
fi

echo "Using source directory: $dist_dir"
echo "Release tag: $tag"
echo "Release name: $release_name"
echo "Assets to upload:"
for asset in "${assets[@]}"; do
  echo "  - $(basename "$asset")"
done

release_json="$(curl -fsSL -H "$auth_header" -H "$accept_header" "${api_base}/releases/tags/${tag}" 2>/dev/null || true)"

if [[ -n "$release_json" ]]; then
  release_id="$(python3 - "$release_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["id"])
PY
)"

  assets_json="$(curl -fsSL -H "$auth_header" -H "$accept_header" "${api_base}/releases/${release_id}/assets")"
  asset_ids="$(python3 - "$assets_json" <<'PY'
import json
import sys
for asset in json.loads(sys.argv[1]):
    print(asset["id"])
PY
)"

  for asset_id in $asset_ids; do
    curl -fsSL -X DELETE -H "$auth_header" -H "$accept_header" "${api_base}/releases/assets/${asset_id}" >/dev/null
  done
else
  payload="$(python3 - "$tag" "$release_name" <<'PY'
import json
import sys

tag, release_name = sys.argv[1:3]
print(json.dumps({
    "tag_name": tag,
    "name": release_name,
    "draft": False,
    "prerelease": False,
    "generate_release_notes": True,
}))
PY
)"

  release_json="$(curl -fsSL -X POST -H "$auth_header" -H "$accept_header" -d "$payload" "${api_base}/releases")"
  release_id="$(python3 - "$release_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["id"])
PY
)"
fi

for asset in "${assets[@]}"; do
  asset_name="$(basename "$asset")"
  upload_url="${upload_base}/releases/${release_id}/assets?name=$(python3 - "$asset_name" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1]))
PY
)"

  curl -fsSL \
    -X POST \
    -H "$auth_header" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$asset" \
    "$upload_url" >/dev/null
done

echo "Release published successfully."
