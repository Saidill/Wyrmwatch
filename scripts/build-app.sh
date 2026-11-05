#!/bin/zsh
# Builds Wyrmwatch.app (the notch app) from the Swift package.
# With --install it also replaces /Applications/Wyrmwatch.app and relaunches it.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/Wyrmwatch.app"
ICON="$ROOT/.build/AppIcon.icns"
INSTALLED="/Applications/Wyrmwatch.app"

cd "$ROOT"
swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN/Wyrmwatch" "$APP/Contents/MacOS/Wyrmwatch"
# The Rive runtime (for the mascot) is a framework the binary loads from Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$BIN/RiveRuntime.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Wyrmwatch" 2>/dev/null || true
# Now playing from any app (Spotify, browsers, ...): mediaremote-adapter (BSD 3-Clause, vendored at v0.7.7).
# Built with CMake once and again only when its sources change; without CMake the app falls back to Music only.
MRA_SRC="$ROOT/Vendor/mediaremote-adapter"
MRA_OUT="$ROOT/.build/mediaremote-adapter"
CMAKE="$(command -v cmake || true)"
[[ -z "$CMAKE" && -x /opt/homebrew/bin/cmake ]] && CMAKE=/opt/homebrew/bin/cmake
[[ -z "$CMAKE" ]] && CMAKE="$(ls /Library/Frameworks/Python.framework/Versions/*/bin/cmake 2>/dev/null | tail -1 || true)"
if [[ -n "$CMAKE" ]]; then
    if [[ ! -d "$MRA_OUT/MediaRemoteAdapter.framework" || -n "$(find "$MRA_SRC" -newer "$MRA_OUT/MediaRemoteAdapter.framework" -type f | head -1)" ]]; then
        "$CMAKE" -S "$MRA_SRC" -B "$MRA_OUT" -DCMAKE_BUILD_TYPE=Release >/dev/null
        "$CMAKE" --build "$MRA_OUT" --target MediaRemoteAdapter >/dev/null
        touch "$MRA_OUT/MediaRemoteAdapter.framework"
    fi
    cp -R "$MRA_OUT/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
    cp "$MRA_SRC/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
    cp "$MRA_SRC/LICENSE" "$APP/Contents/Resources/mediaremote-adapter-LICENSE"
else
    echo "warning: cmake not found, building without mediaremote-adapter (now playing from Music only)" >&2
fi
# The mascot itself, when there is one.
if [[ -f "$ROOT/Resources/wyrm.riv" ]]; then cp "$ROOT/Resources/wyrm.riv" "$APP/Contents/Resources/"; fi

# The icon is the app's own dragon, drawn by the binary; only redraw it when the drawing changes.
if [[ ! -f "$ICON" || "$ROOT/Sources/Wyrmwatch/App/IconRenderer.swift" -nt "$ICON" ]]; then
    SET="$ROOT/.build/AppIcon.iconset"
    rm -rf "$SET" && mkdir -p "$SET"
    "$APP/Contents/MacOS/Wyrmwatch" --render-icon "$ROOT/.build/AppIcon-1024.png"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ROOT/.build/AppIcon-1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ROOT/.build/AppIcon-1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$ICON"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Wyrmwatch</string>
    <key>CFBundleDisplayName</key><string>Wyrmwatch</string>
    <key>CFBundleIdentifier</key><string>com.saidilhalim.wyrmwatch</string>
    <key>CFBundleExecutable</key><string>Wyrmwatch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Used to show your next calendar event in the notch.</string>
    <key>NSAppleEventsUsageDescription</key><string>Used to bring the terminal tab running a Claude session to the front, and to show and control what is playing in Music.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/Frameworks/RiveRuntime.framework"
[[ -d "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" ]] && codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Quit the running copy, swap in the new build, and start it again.
    pkill -x Wyrmwatch 2>/dev/null || true
    # The app used to be called ClaudeUsage: quit that copy and move it to the Trash (recoverable), so only one
    # notch app runs.
    pkill -x ClaudeUsage 2>/dev/null || true
    if [[ -d "/Applications/ClaudeUsage.app" ]]; then
        osascript -e 'tell application "Finder" to delete POSIX file "/Applications/ClaudeUsage.app"' >/dev/null 2>&1 || true
        echo "Moved the old /Applications/ClaudeUsage.app to the Trash"
    fi
    for _ in {1..50}; do pgrep -x Wyrmwatch >/dev/null || break; sleep 0.1; done
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    touch "$INSTALLED" # so Finder picks up the icon
    open "$INSTALLED"
    echo "Installed and relaunched $INSTALLED"
else
    echo "Install and relaunch:  ./scripts/build-app.sh --install"
fi
