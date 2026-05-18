#!/usr/bin/env bash

set -euo pipefail

PAYLOADS_JSON="payloads/payloads.json"
TEMP_DIR="$(mktemp -d)"

UPDATE=false

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

require_file() {
  local file="$1"

  if [ ! -s "$file" ]; then
    echo "Required file is missing or empty: $file" >&2
    exit 1
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "Download URL was empty/null for output: $output" >&2
    exit 1
  fi

  echo "Downloading: $url"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$output" "$url"
  require_file "$output"
}

json_get_version() {
  local index="$1"
  jq -r ".payloads[$index].version" "$PAYLOADS_JSON"
}

json_set_payload() {
  local index="$1"
  local version="$2"
  local path="$3"

  local tmp
  tmp="$(mktemp)"

  jq \
    --arg version "$version" \
    --arg path "$path" \
    ".payloads[$index].version = \$version | .payloads[$index].path = \$path" \
    "$PAYLOADS_JSON" > "$tmp"

  mv "$tmp" "$PAYLOADS_JSON"
}

github_latest_tag() {
  local repo="$1"

  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | jq -r ".tag_name"
}

github_latest_asset_url_matching() {
  local repo="$1"
  local jq_filter="$2"

  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | jq -r "$jq_filter"
}

echo "Reading current payload versions."

AMS_VERSION="$(json_get_version 0)"
HKT_VERSION="$(json_get_version 1)"
TEX_VERSION="$(json_get_version 2)"

echo "Current Atmosphere version: $AMS_VERSION"
echo "Current Hekate version: $HKT_VERSION"
echo "Current TegraExplorer version: $TEX_VERSION"

echo "Fetching latest release versions."

AMS_LATEST="$(github_latest_tag "Atmosphere-NX/Atmosphere")"
HKT_LATEST="$(github_latest_tag "CTCaer/hekate")"
TEX_LATEST="$(github_latest_tag "suchmememanyskill/TegraExplorer")"

echo "Latest Atmosphere version: $AMS_LATEST"
echo "Latest Hekate version: $HKT_LATEST"
echo "Latest TegraExplorer version: $TEX_LATEST"

if [ "$AMS_VERSION" != "$AMS_LATEST" ]; then
  echo "Newest Atmosphere version detected: $AMS_LATEST"
  UPDATE=true

  AMS_URL="$(github_latest_asset_url_matching \
    "Atmosphere-NX/Atmosphere" \
    '.assets[] | select(.name == "fusee.bin") | .browser_download_url' \
  )"

  download_file "$AMS_URL" "$TEMP_DIR/fusee.bin"

  rm -f payloads/ams-*.bin
  mv "$TEMP_DIR/fusee.bin" "payloads/ams-$AMS_LATEST.bin"

  json_set_payload 0 "$AMS_LATEST" "payloads/ams-$AMS_LATEST.bin"

  echo "Atmosphere successfully updated."
else
  echo "Atmosphere is already current."
fi

if [ "$HKT_VERSION" != "$HKT_LATEST" ]; then
  echo "Newest Hekate version detected: $HKT_LATEST"
  UPDATE=true

  HKT_URL="$(github_latest_asset_url_matching \
    "CTCaer/hekate" \
    '.assets[] | select(.name | test("^hekate_ctcaer_.*\\.zip$")) | .browser_download_url' \
  )"

  download_file "$HKT_URL" "$TEMP_DIR/hekate.zip"

  unzip -o "$TEMP_DIR/hekate.zip" -d "$TEMP_DIR/hekate"

  HKT_BIN="$(find "$TEMP_DIR/hekate" -maxdepth 1 -type f -name 'hekate_ctcaer_*.bin' | head -n 1)"

  if [ -z "$HKT_BIN" ]; then
    echo "Could not find hekate_ctcaer_*.bin inside downloaded Hekate zip." >&2
    exit 1
  fi

  require_file "$HKT_BIN"

  rm -f payloads/hekate-*.bin
  mv "$HKT_BIN" "payloads/hekate-$HKT_LATEST.bin"

  json_set_payload 1 "$HKT_LATEST" "payloads/hekate-$HKT_LATEST.bin"

  echo "Hekate successfully updated."
else
  echo "Hekate is already current."
fi

if [ "$TEX_VERSION" != "$TEX_LATEST" ]; then
  echo "Newest TegraExplorer version detected: $TEX_LATEST"
  UPDATE=true

  TEX_URL="$(github_latest_asset_url_matching \
    "suchmememanyskill/TegraExplorer" \
    '.assets[] | select(.name == "TegraExplorer.bin") | .browser_download_url' \
  )"

  download_file "$TEX_URL" "$TEMP_DIR/TegraExplorer.bin"

  rm -f payloads/tegraexplorer-*.bin
  mv "$TEMP_DIR/TegraExplorer.bin" "payloads/tegraexplorer-$TEX_LATEST.bin"

  json_set_payload 2 "$TEX_LATEST" "payloads/tegraexplorer-$TEX_LATEST.bin"

  echo "TegraExplorer successfully updated."
else
  echo "TegraExplorer is already current."
fi

if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "UPDATE=$UPDATE" >> "$GITHUB_ENV"
fi

echo "Update complete. UPDATE=$UPDATE"
