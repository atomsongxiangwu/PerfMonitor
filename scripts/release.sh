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

APP_NAME="${APP_NAME:-PerfMonitor}"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.yourcompany.perfmonitor}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-13.0}"
ICON_ICNS_PATH="${ICON_ICNS_PATH:-}"

APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE="${NOTARIZE:-0}"

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

echo "==> Done"
echo "App: $APP_DIR"
echo "Pkg: $PKG_PATH"
