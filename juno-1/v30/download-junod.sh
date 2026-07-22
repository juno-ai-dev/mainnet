#!/usr/bin/env bash
set -euo pipefail

REGISTRY="https://ghcr.io"
REPOSITORY="cosmoscontracts/juno"
DESTINATION="${1:-./junod-v30.0.0}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_MANIFEST="$SCRIPT_DIR/release-manifest.json"

if [[ "$(uname -s)" != "Linux" ]]; then
  printf 'Unsupported operating system: %s (Linux required)\n' "$(uname -s)" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac
PLATFORM="linux/$ARCH"

for command in curl jq tar sha256sum install grep mktemp mv; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  }
done

[[ -f "$RELEASE_MANIFEST" ]] || {
  printf 'Release manifest not found: %s\n' "$RELEASE_MANIFEST" >&2
  exit 1
}
[[ ! -e "$DESTINATION" ]] || {
  printf 'Refusing to overwrite existing destination: %s\n' "$DESTINATION" >&2
  exit 1
}

VERSION="$(jq -er '.release.version' "$RELEASE_MANIFEST")"
COMMIT="$(jq -er '.release.peeled_commit' "$RELEASE_MANIFEST")"
INDEX_DIGEST="$(jq -er '.oci.index_digest' "$RELEASE_MANIFEST")"
MANIFEST_DIGEST="$(jq -er --arg platform "$PLATFORM" '.oci.platforms[$platform].manifest_digest' "$RELEASE_MANIFEST")"
LAYER_DIGEST="$(jq -er --arg platform "$PLATFORM" '.oci.platforms[$platform].binary_layer_digest' "$RELEASE_MANIFEST")"
BINARY_SHA="$(jq -er --arg platform "$PLATFORM" '.oci.platforms[$platform].binary_sha256' "$RELEASE_MANIFEST")"

verify_digest() {
  local expected="$1"
  local file="$2"
  printf '%s  %s\n' "${expected#sha256:}" "$file" | sha256sum --check --status
}

TMP_DIR="$(mktemp -d)"
DEST_TMP=""
cleanup() {
  [[ -z "$DEST_TMP" ]] || rm -f "$DEST_TMP"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

TOKEN="$(
  curl -fsSL \
    "$REGISTRY/token?service=ghcr.io&scope=repository:$REPOSITORY:pull" |
    jq -er '.token'
)"
AUTH_HEADER="Authorization: Bearer $TOKEN"
INDEX_ACCEPT="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"
MANIFEST_ACCEPT="application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

INDEX_FILE="$TMP_DIR/index.json"
curl -fsSL -H "$AUTH_HEADER" -H "Accept: $INDEX_ACCEPT" \
  "$REGISTRY/v2/$REPOSITORY/manifests/$INDEX_DIGEST" -o "$INDEX_FILE"
verify_digest "$INDEX_DIGEST" "$INDEX_FILE" || {
  printf 'OCI index checksum mismatch\n' >&2
  exit 1
}

INDEX_MANIFEST="$(
  jq -er --arg arch "$ARCH" \
    '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch) | .digest] | if length == 1 then .[0] else error("platform manifest not unique") end' \
    "$INDEX_FILE"
)"
[[ "$INDEX_MANIFEST" == "$MANIFEST_DIGEST" ]] || {
  printf 'OCI index does not map %s to expected manifest\n' "$PLATFORM" >&2
  exit 1
}

PLATFORM_FILE="$TMP_DIR/platform.json"
curl -fsSL -H "$AUTH_HEADER" -H "Accept: $MANIFEST_ACCEPT" \
  "$REGISTRY/v2/$REPOSITORY/manifests/$MANIFEST_DIGEST" -o "$PLATFORM_FILE"
verify_digest "$MANIFEST_DIGEST" "$PLATFORM_FILE" || {
  printf 'OCI platform manifest checksum mismatch for %s\n' "$PLATFORM" >&2
  exit 1
}
jq -e --arg layer "$LAYER_DIGEST" 'any(.layers[]; .digest == $layer)' \
  "$PLATFORM_FILE" >/dev/null || {
  printf 'Expected binary layer is not referenced by %s manifest\n' "$PLATFORM" >&2
  exit 1
}

LAYER_FILE="$TMP_DIR/layer.tar.gz"
curl -fsSL -H "$AUTH_HEADER" \
  "$REGISTRY/v2/$REPOSITORY/blobs/$LAYER_DIGEST" -o "$LAYER_FILE"
verify_digest "$LAYER_DIGEST" "$LAYER_FILE" || {
  printf 'OCI layer checksum mismatch for %s\n' "$PLATFORM" >&2
  exit 1
}

tar -xzf "$LAYER_FILE" --no-same-owner --no-same-permissions \
  -C "$TMP_DIR" bin/junod
verify_digest "sha256:$BINARY_SHA" "$TMP_DIR/bin/junod" || {
  printf 'junod checksum mismatch for %s\n' "$PLATFORM" >&2
  exit 1
}

VERSION_OUTPUT="$("$TMP_DIR/bin/junod" version --long)"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fxq "version: $VERSION"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fxq "commit: $COMMIT"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fxq "cosmos_sdk_version: v0.53.7"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fq 'github.com/CosmWasm/wasmvm/v3@v3.0.4'
printf '%s\n' "$VERSION_OUTPUT" | grep -Fq 'github.com/cometbft/cometbft@v0.38.23'

DEST_DIR="$(dirname -- "$DESTINATION")"
mkdir -p "$DEST_DIR"
DEST_TMP="$(mktemp "$DEST_DIR/.junod-v30.0.0.XXXXXX")"
install -m 0755 "$TMP_DIR/bin/junod" "$DEST_TMP"
mv "$DEST_TMP" "$DESTINATION"
DEST_TMP=""

printf 'Installed verified Juno %s candidate binary for %s\n' "$VERSION" "$PLATFORM"
printf 'Commit field: %s\n' "$COMMIT"
printf 'SHA-256: %s\n' "$BINARY_SHA"
printf 'Path: %s\n' "$DESTINATION"
printf 'WARNING: published OCI metadata reports vcs.modified=true; see the runbook readiness gates.\n'
