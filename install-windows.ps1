# =============================================================================
# RobotStreamer — One-Click Windows Installer
# Run this in PowerShell as Administrator:
#   Right-click PowerShell → "Run as Administrator"
#   Then paste: irm https://raw.githubusercontent.com/robotstreamer/robotstreamer/master/install-windows.ps1 | iex
# =============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$APP_NAME      = "RobotStreamer"
$INSTALL_DIR   = "$env:LOCALAPPDATA\RobotStreamer"
$DESKTOP       = [Environment]::GetFolderPath("Desktop")
$PYTHON_VER    = "3.12.3"
$PYTHON_URL    = "https://www.python.org/ftp/python/$PYTHON_VER/python-$PYTHON_VER-amd64.exe"
$FFMPEG_URL    = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$REPO_URL      = "https://github.com/robotstreamer/robotstreamer/archive/refs/heads/master.zip"
$NODE_URL      = "https://nodejs.org/dist/v20.14.0/node-v20.14.0-x64.msi"

function Write-Header {
    param([string]$msg)
    Write-Host ""
    Write-Host "  >>> $msg" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$msg)
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn {
    param([string]$msg)
    Write-Host "  [!!] $msg" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$msg)
    Write-Host "  [XX] $msg" -ForegroundColor Red
    exit 1
}

Clear-Host
Write-Host ""
Write-Host "  ██████╗  ██████╗ ██████╗  ██████╗ ████████╗" -ForegroundColor Cyan
Write-Host "  ██╔══██╗██╔═══██╗██╔══██╗██╔═══██╗╚══██╔══╝" -ForegroundColor Cyan
Write-Host "  ██████╔╝██║   ██║██████╔╝██║   ██║   ██║   " -ForegroundColor Cyan
Write-Host "  ██╔══██╗██║   ██║██╔══██╗██║   ██║   ██║   " -ForegroundColor Cyan
Write-Host "  ██║  ██║╚██████╔╝██████╔╝╚██████╔╝   ██║   " -ForegroundColor Cyan
Write-Host "  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝   ╚═╝   " -ForegroundColor Cyan
Write-Host "  RobotStreamer — Windows Installer" -ForegroundColor White
Write-Host ""

# ── Helper: download a file with a progress bar ──────────────────────────────
function Download-File {
    param([string]$url, [string]$dest, [string]$label)
    Write-Host "  Downloading $label..." -NoNewline
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $dest)
    Write-Host " done." -ForegroundColor Green
}

# ── Create install directory ──────────────────────────────────────────────────
Write-Header "Setting up install directory"
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\tmp"  | Out-Null
Write-OK "Install directory: $INSTALL_DIR"

# ── 1. Python ─────────────────────────────────────────────────────────────────
Write-Header "Checking Python"
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $ver = & python --version 2>&1
    Write-OK "Python already installed: $ver"
} else {
    Write-Warn "Python not found. Installing Python $PYTHON_VER..."
    $pyInstaller = "$INSTALL_DIR\tmp\python-installer.exe"
    Download-File $PYTHON_URL $pyInstaller "Python $PYTHON_VER"
    Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1" -Wait
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-OK "Python installed"
}

# ── 2. FFmpeg ─────────────────────────────────────────────────────────────────
Write-Header "Checking FFmpeg"
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpeg) {
    Write-OK "FFmpeg already installed"
} else {
    Write-Warn "FFmpeg not found. Installing..."
    $ffmpegZip = "$INSTALL_DIR\tmp\ffmpeg.zip"
    $ffmpegDir = "$INSTALL_DIR\ffmpeg"
    Download-File $FFMPEG_URL $ffmpegZip "FFmpeg"

    Write-Host "  Extracting FFmpeg..." -NoNewline
    Expand-Archive -Path $ffmpegZip -DestinationPath "$INSTALL_DIR\tmp\ffmpeg_extract" -Force
    $ffmpegSource = Get-ChildItem "$INSTALL_DIR\tmp\ffmpeg_extract" -Directory | Select-Object -First 1
    Move-Item $ffmpegSource.FullName $ffmpegDir -Force
    Write-Host " done." -ForegroundColor Green

    # Add to user PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $ffmpegBin = "$ffmpegDir\bin"
    if ($userPath -notlike "*$ffmpegBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$ffmpegBin", "User")
        $env:Path += ";$ffmpegBin"
    }
    Write-OK "FFmpeg installed to $ffmpegBin"
}

# ── 3. Node.js (for the desktop streaming app) ───────────────────────────────
Write-Header "Checking Node.js"
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $nodeVer = & node --version 2>&1
    Write-OK "Node.js already installed: $nodeVer"
} else {
    Write-Warn "Node.js not found. Installing..."
    $nodeMsi = "$INSTALL_DIR\tmp\node-installer.msi"
    Download-File $NODE_URL $nodeMsi "Node.js LTS"
    Start-Process msiexec -ArgumentList "/i `"$nodeMsi`" /quiet /norestart" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-OK "Node.js installed"
}

# ── 4. Download RobotStreamer source ──────────────────────────────────────────
Write-Header "Downloading RobotStreamer"
$repoZip  = "$INSTALL_DIR\tmp\robotstreamer.zip"
$repoDir  = "$INSTALL_DIR\robotstreamer"
Download-File $REPO_URL $repoZip "RobotStreamer source"

Write-Host "  Extracting..." -NoNewline
Expand-Archive -Path $repoZip -DestinationPath "$INSTALL_DIR\tmp\repo_extract" -Force
$extractedDir = Get-ChildItem "$INSTALL_DIR\tmp\repo_extract" -Directory | Select-Object -First 1
if (Test-Path $repoDir) { Remove-Item $repoDir -Recurse -Force }
Move-Item $extractedDir.FullName $repoDir -Force
Write-Host " done." -ForegroundColor Green
Write-OK "Source at $repoDir"

# ── 5. Install Python dependencies ───────────────────────────────────────────
Write-Header "Installing Python packages"
$reqFile = "$repoDir\requirements.txt"
if (Test-Path $reqFile) {
    & python -m pip install --quiet --upgrade pip 2>&1 | Out-Null
    & python -m pip install --quiet -r $reqFile 2>&1 | Out-Null
    Write-OK "Python packages installed"
} else {
    Write-Warn "requirements.txt not found, skipping"
}

# ── 6. Create launcher batch file ────────────────────────────────────────────
Write-Header "Creating launcher"

$launcherBat = "$INSTALL_DIR\RobotStreamer.bat"
$launcherContent = @"
@echo off
title RobotStreamer
cd /d "$repoDir"
echo.
echo  ============================================
echo   RobotStreamer Windows Streamer
echo  ============================================
echo.
echo  Enter your Robot ID and Stream Key below.
echo  (Find these on your robot page at robotstreamer.com)
echo.
set /p CAMERA_ID="Robot Camera ID: "
set /p STREAM_KEY="Stream Key: "
echo.
echo  Starting stream... (close this window to stop)
echo.
python send_video_windows.py %CAMERA_ID% "RobotStreamer" 0 --stream-key %STREAM_KEY%
pause
"@
$launcherContent | Out-File -FilePath $launcherBat -Encoding ASCII
Write-OK "Launcher created: $launcherBat"

# ── 7. Desktop shortcut ───────────────────────────────────────────────────────
Write-Header "Creating desktop shortcut"
$shortcutPath = "$DESKTOP\RobotStreamer.lnk"
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath  = $launcherBat
$shortcut.WorkingDirectory = $repoDir
$shortcut.Description = "RobotStreamer — Start streaming your robot"
$iconPath = "$repoDir\images\icon.ico"
if (Test-Path $iconPath) { $shortcut.IconLocation = $iconPath }
$shortcut.Save()
Write-OK "Shortcut created on Desktop"

# ── 8. Add to Start Menu ──────────────────────────────────────────────────────
$startMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\RobotStreamer"
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$startShortcut = $wsh.CreateShortcut("$startMenu\RobotStreamer.lnk")
$startShortcut.TargetPath  = $launcherBat
$startShortcut.WorkingDirectory = $repoDir
$startShortcut.Description = "RobotStreamer"
if (Test-Path $iconPath) { $startShortcut.IconLocation = $iconPath }
$startShortcut.Save()
Write-OK "Added to Start Menu"

# ── 9. Cleanup temp files ─────────────────────────────────────────────────────
Write-Header "Cleaning up"
Remove-Item "$INSTALL_DIR\tmp" -Recurse -Force -ErrorAction SilentlyContinue
Write-OK "Temp files removed"

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   Installation Complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  A shortcut has been placed on your Desktop."
Write-Host "  Double-click 'RobotStreamer' to start streaming."
Write-Host ""
Write-Host "  What you'll need from robotstreamer.com:"
Write-Host "    - Your Camera ID"
Write-Host "    - Your Stream Key"
Write-Host ""
Write-Host "  Installed to: $INSTALL_DIR" -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to close"
