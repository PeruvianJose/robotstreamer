#!/usr/bin/env bash
# =============================================================================
# RobotStreamer — One-Click macOS Installer
# Installs Node.js, builds the desktop app, and places it in /Applications
# =============================================================================

set -e

APP_NAME="RobotStreamer"
INSTALL_DIR="$HOME/.robotstreamer-app"
RSAPP_REPO="https://github.com/robotstreamer/rsapp.git"
NODE_VERSION="20"   # LTS

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GRN}[RobotStreamer]${NC} $*"; }
warn() { echo -e "${YLW}[RobotStreamer]${NC} $*"; }
err()  { echo -e "${RED}[RobotStreamer]${NC} $*"; exit 1; }

echo ""
echo "  ██████╗  ██████╗ ██████╗  ██████╗ ████████╗"
echo "  ██╔══██╗██╔═══██╗██╔══██╗██╔═══██╗╚══██╔══╝"
echo "  ██████╔╝██║   ██║██████╔╝██║   ██║   ██║   "
echo "  ██╔══██╗██║   ██║██╔══██╗██║   ██║   ██║   "
echo "  ██║  ██║╚██████╔╝██████╔╝╚██████╔╝   ██║   "
echo "  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝   ╚═╝   "
echo "  RobotStreamer macOS Installer"
echo ""

# ── 1. Check macOS ──────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    err "This installer is for macOS only."
fi

log "macOS detected: $(sw_vers -productVersion)"

# ── 2. Install Homebrew if missing ──────────────────────────────────────────
# Add known Homebrew paths first
[[ -f "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -f "/usr/local/bin/brew"    ]] && export PATH="/usr/local/bin:$PATH"

if ! command -v brew &>/dev/null; then
    log "Installing Homebrew (you may be prompted for your Mac password)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Reload for Apple Silicon
    [[ -f "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -f "/usr/local/bin/brew"    ]] && export PATH="/usr/local/bin:$PATH"
else
    log "Homebrew already installed: $(brew --version | head -1)"
fi

# ── 3. Install Node.js LTS ──────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
    log "Installing Node.js $NODE_VERSION LTS..."
    brew install node@$NODE_VERSION
    brew link --overwrite node@$NODE_VERSION 2>/dev/null || true
    export PATH="/opt/homebrew/opt/node@$NODE_VERSION/bin:$PATH"
    export PATH="/usr/local/opt/node@$NODE_VERSION/bin:$PATH"
else
    log "Node.js already installed: $(node --version)"
fi

# Ensure keg-only Node is on PATH
export PATH="/opt/homebrew/opt/node@$NODE_VERSION/bin:$PATH"
export PATH="/usr/local/opt/node@$NODE_VERSION/bin:$PATH"

if ! command -v node &>/dev/null; then
    err "Node.js installation failed. Please install manually from https://nodejs.org"
fi

# ── 4. Install git if missing ────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    log "Installing git..."
    brew install git
fi

# ── 5. Install FFmpeg ────────────────────────────────────────────────────────
if ! command -v ffmpeg &>/dev/null; then
    log "Installing FFmpeg (required for video streaming)..."
    brew install ffmpeg
else
    log "FFmpeg already installed: $(ffmpeg -version 2>&1 | head -1)"
fi

# ── 6. Download/update rsapp source ─────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

if [[ -d "$INSTALL_DIR/rsapp/.git" ]]; then
    log "Updating existing rsapp installation..."
    git -C "$INSTALL_DIR/rsapp" pull --ff-only || warn "Could not update; using existing version."
else
    log "Downloading RobotStreamer desktop app..."
    rm -rf "$INSTALL_DIR/rsapp"
    git clone "$RSAPP_REPO" "$INSTALL_DIR/rsapp"
fi

cd "$INSTALL_DIR/rsapp"

# ── 7. Update package.json to modern Electron ───────────────────────────────
log "Updating dependencies to modern versions..."
cat > package.json << 'PKGJSON'
{
  "name": "rsapp",
  "version": "1.1.0",
  "description": "RobotStreamer desktop app for macOS, Windows, and Linux",
  "main": "main.js",
  "dependencies": {
    "colors": "^1.4.0",
    "electron-context-menu": "^3.6.1",
    "electron-store": "^8.1.0",
    "executive": "^1.6.3",
    "node-media-server": "2.6.2",
    "say": "^0.16.0",
    "tree-kill": "^1.2.2"
  },
  "devDependencies": {
    "electron": "^30.0.0",
    "electron-packager": "^17.1.2"
  },
  "scripts": {
    "start": "electron .",
    "package-mac": "electron-packager . --overwrite --platform=darwin --arch=arm64,x64 --icon=assets/icons/mac/icon.icns --prune=true --out=release-builds --asar=true",
    "package-win": "electron-packager . --overwrite --asar=false --platform=win32 --arch=x64 --icon=assets/icons/win/icon.ico --prune=true --out=release-builds",
    "package-linux": "electron-packager . --overwrite --platform=linux --arch=x64 --icon=assets/icons/png/icon.png --prune=true --out=release-builds"
  },
  "author": "RobotStreamer",
  "license": "ISC"
}
PKGJSON

# ── 8. Patch main.js for Electron 30 compatibility ───────────────────────────
log "Patching main.js for modern Electron..."
# Electron 30+ requires contextIsolation and disallows nodeIntegration by default
# Patch to add explicit nodeIntegration where needed
python3 - << 'PYEOF'
import re, sys

with open('main.js', 'r') as f:
    content = f.read()

# Fix deprecated remote module usage
content = content.replace(
    "const {app,",
    "const {app,"
)

# Add webPreferences if BrowserWindow is created without them
def add_web_prefs(match):
    existing = match.group(0)
    if 'nodeIntegration' in existing:
        return existing
    return existing.replace(
        'webPreferences:',
        'webPreferences:\n      nodeIntegration: true,\n      contextIsolation: false,'
    )

content = re.sub(r'webPreferences:\s*\{[^}]+\}', add_web_prefs, content, flags=re.DOTALL)

# If no webPreferences block found, add one to new BrowserWindow calls
if 'nodeIntegration: true' not in content:
    content = content.replace(
        'new BrowserWindow({',
        'new BrowserWindow({\n      webPreferences: { nodeIntegration: true, contextIsolation: false },'
    )

with open('main.js', 'w') as f:
    f.write(content)

print('main.js patched successfully')
PYEOF

# ── 9. Install npm dependencies ──────────────────────────────────────────────
log "Installing npm packages (this may take a minute)..."
npm install --legacy-peer-deps 2>&1 | grep -E "(error|warn|added)" || true
npm install --save-dev electron@30 electron-packager@17 --legacy-peer-deps 2>&1 | grep -E "(error|warn|added)" || true

# ── 10. Build the macOS .app bundle ─────────────────────────────────────────
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    ELECTRON_ARCH="arm64"
else
    ELECTRON_ARCH="x64"
fi

log "Building macOS app for $ARCH..."
npx electron-packager . \
    --overwrite \
    --platform=darwin \
    --arch=$ELECTRON_ARCH \
    --icon=assets/icons/mac/icon.icns \
    --prune=true \
    --out=release-builds \
    --app-bundle-id=com.robotstreamer.app \
    --app-version=1.1.0 2>&1 | tail -5

# ── 11. Move to /Applications ───────────────────────────────────────────────
BUILD_APP=$(find release-builds -name "*.app" | head -1)
if [[ -z "$BUILD_APP" ]]; then
    err "Build failed — .app not found. Check errors above."
fi

log "Installing to /Applications..."
if [[ -d "/Applications/RobotStreamer.app" ]]; then
    warn "Removing previous installation..."
    rm -rf "/Applications/RobotStreamer.app"
fi
cp -R "$BUILD_APP" "/Applications/RobotStreamer.app"

# ── 12. Done ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}✓ Installation complete!${NC}"
echo ""
echo "  RobotStreamer.app is now in your /Applications folder."
echo "  Open it from Finder, Spotlight (Cmd+Space), or run:"
echo "  open /Applications/RobotStreamer.app"
echo ""
echo "  First-time setup:"
echo "  1. Open the app"
echo "  2. Enter your Robot ID and Stream Key"
echo "  3. Toggle LIVE to start streaming"
echo ""
