#!/usr/bin/env bash
set -euo pipefail

VERSION="v30.0.0"
COMMIT="c0b3a8d258d52d16e5bc39a75168a99aab9d098e"
REGISTRY="https://ghcr.io"
REPOSITORY="cosmoscontracts/juno"
DESTINATION="${1:-./junod-v30.0.0}"

case "$(uname -m)" in
  x86_64|amd64)
    PLATFORM="linux/amd64"
    LAYER="7a4b3df8dcc64badab3b6c508e1231affdae45f4f339882263c3b13cf58b2817"
    BINARY_SHA="f782a5f984aa7880ea30e9d98aad71c99fa047aa894d06a16c1a81c658acdbb7"
    ;;
  aarch64|arm64)
    PLATFORM="linux/arm64"
    LAYER="f272d1591e1df19bba9b469768f1ef14a36fb9c8808b2fad08a7ee6d492e3270"
    BINARY_SHA="6db8320d0c338ed7adec72e3ca4fd654fd01f2bdbb665f4814b31c919f167b2d"
    ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

for command in curl jq tar sha256sum install grep; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  }
done

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

TOKEN="$(
  curl -fsSL \
    "$REGISTRY/token?service=ghcr.io&scope=repository:$REPOSITORY:pull" |
    jq -er '.token'
)"

LAYER_FILE="$TMP_DIR/layer.tar.gz"
curl -fsSL \
  -H "Authorization: Bearer $TOKEN" \
  "$REGISTRY/v2/$REPOSITORY/blobs/sha256:$LAYER" \
  -o "$LAYER_FILE"

printf '%s  %s\n' "$LAYER" "$LAYER_FILE" | sha256sum --check --status || {
  printf 'OCI layer checksum mismatch for %s\n' "$PLATFORM" >&2
  exit 1
}

tar -xzf "$LAYER_FILE" -C "$TMP_DIR" bin/junod
printf '%s  %s\n' "$BINARY_SHA" "$TMP_DIR/bin/junod" | sha256sum --check --status || {
  printf 'junod checksum mismatch for %s\n' "$PLATFORM" >&2
  exit 1
}

mkdir -p "$(dirname "$DESTINATION")"
install -m 0755 "$TMP_DIR/bin/junod" "$DESTINATION"

VERSION_OUTPUT="$($DESTINATION version --long)"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fxq "version: $VERSION"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fxq "commit: $COMMIT"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fxq "cosmos_sdk_version: v0.53.7"
printf '%s\n' "$VERSION_OUTPUT" | grep -Fq 'github.com/CosmWasm/wasmvm/v3@v3.0.4'
printf '%s\n' "$VERSION_OUTPUT" | grep -Fq 'github.com/cometbft/cometbft@v0.38.23'

printf 'Installed verified Juno %s binary for %s\n' "$VERSION" "$PLATFORM"
printf 'Commit: %s\n' "$COMMIT"
printf 'SHA-256: %s\n' "$BINARY_SHA"
printf 'Path: %s\n' "$DESTINATION"
