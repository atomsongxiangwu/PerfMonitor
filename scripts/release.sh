#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

# Auto-load project .env so callers don't need to run `source .env` manually.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# GITHUB_TOKEN set in the shell environment (e.g. a work token in ~/.zshrc) blocks
# gh from using its own stored credentials for the personal account. Unset it here
# so gh falls back to its keychain/config-file login.
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "==> Unsetting GITHUB_TOKEN (shell env) so gh uses stored personal credentials"
  unset GITHUB_TOKEN
fi

APP_NAME="${APP_NAME:-PerfMonitor}"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.yourcompany.perfmonitor}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-13.0}"
ICON_ICNS_PATH="${ICON_ICNS_PATH:-}"

APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE="${NOTARIZE:-0}"

# Sparkle / auto-update (optional – see scripts/setup-sparkle.sh)
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_REPO="${GITHUB_REPO:-PerfMonitor}"
APPCAST_URL="${APPCAST_URL:-}"

DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
PKG_ROOT="$DIST_DIR/pkgroot"
PKG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.pkg"
DEFAULT_ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --version <ver>              App version (default: ${VERSION})
  --bundle-id <id>             Bundle identifier (default: ${BUNDLE_ID})
  --icon-icns <path>           Path to app .icns icon (optional)
  --app-sign <identity>        Developer ID Application identity
  --installer-sign <identity>  Developer ID Installer identity
  --notary-profile <profile>   notarytool keychain profile name
  --notarize                   Submit pkg for notarization and staple
  -h, --help                   Show this help

Environment alternatives:
  VERSION, BUNDLE_ID, MIN_MACOS_VERSION, ICON_ICNS_PATH,
  APP_SIGN_IDENTITY, INSTALLER_SIGN_IDENTITY, NOTARY_PROFILE, NOTARIZE=1
  SPARKLE_PUBLIC_KEY, SPARKLE_PRIVATE_KEY_FILE, SPARKLE_TOOLS_DIR,
  GITHUB_USER, GITHUB_REPO, APPCAST_URL
  ENV_FILE (optional custom .env path)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"; shift 2 ;;
    --bundle-id)
      BUNDLE_ID="$2"; shift 2 ;;
    --icon-icns)
      ICON_ICNS_PATH="$2"; shift 2 ;;
    --app-sign)
      APP_SIGN_IDENTITY="$2"; shift 2 ;;
    --installer-sign)
      INSTALLER_SIGN_IDENTITY="$2"; shift 2 ;;
    --notary-profile)
      NOTARY_PROFILE="$2"; shift 2 ;;
    --notarize)
      NOTARIZE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

# Recompute pkg path in case --version overrides env/default.
PKG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.pkg"

# Derive APPCAST_URL from GitHub info if not explicitly set.
if [[ -z "$APPCAST_URL" && -n "$GITHUB_USER" ]]; then
  APPCAST_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/appcast.xml"
fi

if [[ -z "$ICON_ICNS_PATH" && -f "$DEFAULT_ICON_PATH" ]]; then
  ICON_ICNS_PATH="$DEFAULT_ICON_PATH"
fi

if [[ ! -f "$ROOT_DIR/Package.swift" ]]; then
  echo "Error: Package.swift not found at $ROOT_DIR" >&2
  exit 1
fi

echo "==> Building release binary"
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$BUILD_DIR/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: release binary missing at $BIN_PATH" >&2
  exit 1
fi

echo "==> Creating .app bundle"
rm -rf "$APP_DIR" "$PKG_ROOT" "$PKG_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

HAS_ICON=0
if [[ -n "$ICON_ICNS_PATH" ]]; then
  if [[ ! -f "$ICON_ICNS_PATH" ]]; then
    echo "Error: icon file not found at $ICON_ICNS_PATH" >&2
    exit 1
  fi
  cp "$ICON_ICNS_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
  HAS_ICON=1
  echo "==> Included app icon: $ICON_ICNS_PATH"
else
  echo "==> No icon provided; app bundle will use default system icon"
fi

# ---- Embed Sparkle.framework ----
SPARKLE_XCFW=""
for candidate in \
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework" \
    "$ROOT_DIR/.build/artifacts/Sparkle/Sparkle/Sparkle.xcframework"
do
  if [[ -d "$candidate" ]]; then
    SPARKLE_XCFW="$candidate"
    break
  fi
done

if [[ -n "$SPARKLE_XCFW" ]]; then
  echo "==> Embedding Sparkle.framework"
  SPARKLE_FW=""
  for arch_dir in "$SPARKLE_XCFW"/macos-*/; do
    if [[ -d "${arch_dir}Sparkle.framework" ]]; then
      SPARKLE_FW="${arch_dir}Sparkle.framework"
      break
    fi
  done

  if [[ -n "$SPARKLE_FW" ]]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"

    # Ensure the binary's rpath points to the embedded Frameworks dir.
    RPATH_TARGET="@executable_path/../Frameworks"
    EXISTING_RPATHS=$(otool -l "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null \
        | awk '/cmd LC_RPATH/{found=1} found && /path /{print $2; found=0}' || true)
    if ! echo "$EXISTING_RPATHS" | grep -qF "$RPATH_TARGET"; then
      install_name_tool -add_rpath "$RPATH_TARGET" \
          "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    fi
    # Remove any build-dir rpaths referencing Sparkle so the bundle is self-contained.
    for rp in $EXISTING_RPATHS; do
      if echo "$rp" | grep -qi sparkle; then
        install_name_tool -delete_rpath "$rp" \
            "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
      fi
    done
    echo "    Sparkle.framework embedded from: $SPARKLE_FW"
  else
    echo "    Warning: no macOS slice found in $SPARKLE_XCFW"
  fi
else
  echo "==> Sparkle.xcframework not found in build artifacts; skipping embed"
fi

INFO_PLIST="$APP_DIR/Contents/Info.plist"
cat > "$INFO_PLIST" <<PLIST_HEAD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
PLIST_HEAD

if [[ "$HAS_ICON" == "1" ]]; then
  cat >> "$INFO_PLIST" <<PLIST_ICON
  <key>CFBundleIconFile</key><string>AppIcon</string>
PLIST_ICON
fi

# Sparkle keys – written when the public key is configured.
# APPCAST_URL is already derived from GITHUB_USER/GITHUB_REPO at the top of this script.
if [[ -n "$SPARKLE_PUBLIC_KEY" && -n "$APPCAST_URL" ]]; then
  cat >> "$INFO_PLIST" <<PLIST_SPARKLE
  <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUFeedURL</key><string>${APPCAST_URL}</string>
PLIST_SPARKLE
  echo "==> Sparkle keys written to Info.plist (feed: $APPCAST_URL)"
elif [[ -n "$SPARKLE_PUBLIC_KEY" && -z "$APPCAST_URL" ]]; then
  echo "==> Warning: SPARKLE_PUBLIC_KEY is set but GITHUB_USER is not; SUFeedURL skipped"
  echo "    Set GITHUB_USER in .env to enable auto-update feed"
fi

cat >> "$INFO_PLIST" <<PLIST_TAIL
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS_VERSION}</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST_TAIL

if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  echo "==> Signing app with: $APP_SIGN_IDENTITY"
  codesign --force --deep --timestamp --options runtime --sign "$APP_SIGN_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
  echo "==> No app signing identity set; using ad-hoc signature"
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Creating installer root"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_DIR" "$PKG_ROOT/Applications/"

echo "==> Building pkg"
if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location / \
    --sign "$INSTALLER_SIGN_IDENTITY" \
    "$PKG_PATH"
else
  pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location / \
    "$PKG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Error: --notarize requires --notary-profile or NOTARY_PROFILE" >&2
    exit 1
  fi
  echo "==> Submitting pkg for notarization"
  xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling pkg"
  xcrun stapler staple "$PKG_PATH"
fi

# ---- Generate appcast.xml (requires Sparkle sign_update tool) ----
# Private key is stored in macOS Keychain by default; sign_update reads it automatically.
# If you stored the key as a file, set SPARKLE_PRIVATE_KEY_FILE in .env.
SIGN_UPDATE_TOOL=""
for candidate in \
    "${SPARKLE_TOOLS_DIR}/sign_update" \
    "/usr/local/bin/sign_update" \
    "/opt/homebrew/bin/sign_update"
do
  if [[ -x "$candidate" ]]; then
    SIGN_UPDATE_TOOL="$candidate"
    break
  fi
done

if [[ -n "$SIGN_UPDATE_TOOL" && -n "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "==> Signing update package"
  # Use -f only when a private key file is explicitly configured; otherwise rely on Keychain.
  if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    SIGN_OUTPUT=$("$SIGN_UPDATE_TOOL" "$PKG_PATH" -f "$SPARKLE_PRIVATE_KEY_FILE" 2>&1)
  else
    SIGN_OUTPUT=$("$SIGN_UPDATE_TOOL" "$PKG_PATH" 2>&1)
  fi
  # Parse output lines like: sparkle:edSignature="..." length=NNN
  EDDSA_SIG=$(echo "$SIGN_OUTPUT" | grep -oE 'edSignature="[^"]+"' | cut -d'"' -f2 || true)
  SIG_LENGTH=$(echo "$SIGN_OUTPUT" | grep -oE 'length=[0-9]+' | cut -d= -f2 || true)
  PKG_SIZE="${SIG_LENGTH:-$(stat -f%z "$PKG_PATH" 2>/dev/null || wc -c < "$PKG_PATH" | tr -d ' ')}"

  if [[ -z "$EDDSA_SIG" ]]; then
    echo "    Warning: could not parse EdDSA signature from sign_update output:"
    echo "    $SIGN_OUTPUT"
  else
    PUBDATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
    PKG_DOWNLOAD_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/v${VERSION}/${APP_NAME}-${VERSION}.pkg"

    cat > "$DIST_DIR/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>${APP_NAME} Changelog</title>
        <link>${APPCAST_URL}</link>
        <description>${APP_NAME} release history</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_MACOS_VERSION}</sparkle:minimumSystemVersion>
            <pubDate>${PUBDATE}</pubDate>
            <enclosure
                url="${PKG_DOWNLOAD_URL}"
                sparkle:edSignature="${EDDSA_SIG}"
                length="${PKG_SIZE}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
APPCAST
    echo "    appcast.xml generated: $DIST_DIR/appcast.xml"

    # ---- Auto-publish: GitHub Release + push appcast.xml ----
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
      if [[ -n "$GITHUB_USER" ]]; then
        RELEASE_TAG="v${VERSION}"
        REPO_SLUG="${GITHUB_USER}/${GITHUB_REPO}"

        echo ""
        echo "==> Creating GitHub Release ${RELEASE_TAG}"
        # Create release (--notes-from-tag uses tag annotation; falls back to empty notes).
        if gh release view "$RELEASE_TAG" --repo "$REPO_SLUG" &>/dev/null 2>&1; then
          echo "    Release ${RELEASE_TAG} already exists; uploading asset only"
          gh release upload "$RELEASE_TAG" "$PKG_PATH" --repo "$REPO_SLUG" --clobber
        else
          gh release create "$RELEASE_TAG" "$PKG_PATH" \
            --repo "$REPO_SLUG" \
            --title "PerfMonitor ${VERSION}" \
            --notes "Release ${VERSION}" \
            --latest
        fi
        echo "    Release asset uploaded: $(basename "$PKG_PATH")"

        echo ""
        echo "==> Committing and pushing appcast.xml"
        cd "$ROOT_DIR"
        cp "$DIST_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
        git add appcast.xml
        if git diff --cached --quiet; then
          echo "    appcast.xml unchanged; no commit needed"
        else
          git commit -m "chore: update appcast for ${RELEASE_TAG}"
          git push
          echo "    appcast.xml pushed to main branch"
        fi
      else
        echo ""
        echo "    Skipping auto-publish: set GITHUB_USER in .env to enable"
        echo "    Manual steps:"
        echo "      1. Create GitHub Release tagged v${VERSION}"
        echo "      2. Upload $PKG_PATH as a release asset"
        echo "      3. cp $DIST_DIR/appcast.xml appcast.xml && git add appcast.xml && git commit -m 'chore: appcast v${VERSION}' && git push"
      fi
    else
      echo ""
      echo "    GitHub CLI not configured; run: gh auth login"
      echo "    Manual steps:"
      echo "      1. Create GitHub Release tagged v${VERSION}"
      echo "      2. Upload $PKG_PATH as a release asset"
      echo "      3. cp $DIST_DIR/appcast.xml appcast.xml && git add appcast.xml && git commit -m 'chore: appcast v${VERSION}' && git push"
    fi
  fi
elif [[ -z "$SIGN_UPDATE_TOOL" && -n "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "==> sign_update tool not found; skipping appcast generation"
  echo "    Run scripts/setup-sparkle.sh to install the Sparkle tools"
else
  echo "==> Sparkle signing not configured; skipping appcast generation"
  echo "    Set SPARKLE_PUBLIC_KEY and GITHUB_USER in .env (then run scripts/setup-sparkle.sh if needed)"
fi

echo ""
echo "==> Done"
echo "App: $APP_DIR"
echo "Pkg: $PKG_PATH"
