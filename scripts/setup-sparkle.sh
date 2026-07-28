#!/usr/bin/env bash
# setup-sparkle.sh — One-time setup for Sparkle auto-update signing.
#
# Run this once before your first signed release:
#   bash scripts/setup-sparkle.sh
#
# What it does:
#   1. Downloads the specified Sparkle release tools (sign_update, generate_keys)
#   2. Generates an EdDSA key pair (private key stored at ~/Library/Preferences/Sparkle/)
#   3. Prints the .env lines you need to copy

set -euo pipefail

SPARKLE_VERSION="${1:-2.7.1}"
TOOLS_DIR="${HOME}/.sparkle-tools"
ARCHIVE="Sparkle-${SPARKLE_VERSION}.tar.xz"
DOWNLOAD_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${ARCHIVE}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Setting up Sparkle ${SPARKLE_VERSION} tools"
mkdir -p "$TOOLS_DIR"

# ---- Download tools if not already present ----
if [[ ! -x "$TOOLS_DIR/bin/sign_update" ]]; then
  echo "==> Downloading ${ARCHIVE}..."
  curl -fsSL -o "$TOOLS_DIR/${ARCHIVE}" "$DOWNLOAD_URL"
  echo "==> Extracting tools..."
  # Extract only the bin/ directory from the archive.
  tar -xJf "$TOOLS_DIR/${ARCHIVE}" -C "$TOOLS_DIR" --strip-components=0 ./bin 2>/dev/null \
    || tar -xJf "$TOOLS_DIR/${ARCHIVE}" -C "$TOOLS_DIR" 2>/dev/null
  rm -f "$TOOLS_DIR/${ARCHIVE}"
  echo "    Tools installed to $TOOLS_DIR/bin/"
else
  echo "==> Tools already present at $TOOLS_DIR/bin/"
fi

# ---- Generate keys (idempotent: Sparkle skips if key already exists) ----
echo ""
echo "==> Generating EdDSA key pair..."
echo "    (If a key already exists in the Keychain, this is a no-op.)"
echo ""
KEY_OUTPUT=$("$TOOLS_DIR/bin/generate_keys" 2>&1 || true)
echo "$KEY_OUTPUT"

# Extract the public key: look for a <string> tag or a bare base64 value after "SUPublicEDKey".
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -A1 "SUPublicEDKey" | grep "<string>" \
    | sed 's/.*<string>\(.*\)<\/string>.*/\1/' | tr -d '[:space:]' || true)

# Fallback: Sparkle 2.x prints the key on its own line preceded by spaces.
if [[ -z "$PUBLIC_KEY" ]]; then
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -E '^\s+[A-Za-z0-9+/]{40,}={0,2}\s*$' \
      | tr -d '[:space:]' || true)
fi

# Last resort: ask generate_keys to print only the public key.
if [[ -z "$PUBLIC_KEY" ]]; then
  PUBLIC_KEY=$("$TOOLS_DIR/bin/generate_keys" --print-public-key 2>/dev/null \
      | tr -d '[:space:]' || true)
fi

echo ""
echo "============================================================"
echo "  Sparkle setup complete"
echo "============================================================"
echo ""
echo "  Private key: stored in macOS Keychain (Sparkle reads it automatically)"
echo "  DO NOT export or share the private key."
echo ""
echo "  Add the following lines to your .env file:"
echo ""
echo "  SPARKLE_TOOLS_DIR=\"$TOOLS_DIR/bin\""
if [[ -n "$PUBLIC_KEY" ]]; then
  echo "  SPARKLE_PUBLIC_KEY=\"$PUBLIC_KEY\""
else
  echo "  SPARKLE_PUBLIC_KEY=\"<see SUPublicEDKey above>\""
fi
echo "  GITHUB_USER=\"your_github_username\""
echo "  GITHUB_REPO=\"PerfMonitor\""
echo "  # SPARKLE_PRIVATE_KEY_FILE is NOT needed — key lives in Keychain"
echo "  # APPCAST_URL is NOT needed — auto-derived from GITHUB_USER/GITHUB_REPO"
echo ""
echo "  After editing .env, run ./scripts/release.sh to build a signed release"
echo "  and generate appcast.xml ready to push to your GitHub repo."
echo ""
echo "  Release workflow:"
echo "    1. ./scripts/release.sh           # builds pkg + appcast.xml"
echo "    2. Create GitHub Release tagged v\$VERSION"
echo "    3. Upload dist/PerfMonitor-\$VERSION.pkg as a release asset"
echo "    4. git add appcast.xml && git commit -m 'chore: update appcast for v\$VERSION'"
echo "    5. git push  (Sparkle fetches appcast from the raw GitHub URL)"
echo "============================================================"
