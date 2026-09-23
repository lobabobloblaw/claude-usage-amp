#!/bin/bash
#
# Build Tokenamp and assemble build/Tokenamp.app.
#
# Command Line Tools only: no Xcode, no xcodebuild. The bundle is put together by hand and
# ad-hoc signed, which is all macOS needs to let a local app use notifications and the menu bar.
#
# Re-runnable: the app directory is rebuilt from scratch every time.
#
#   scripts/build_app.sh [--debug]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
SCRATCH=".build-app"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

APP="build/Tokenamp.app"
CONTENTS="$APP/Contents"

echo "==> swift build -c $CONFIG --scratch-path $SCRATCH --product Tokenamp"
swift build -c "$CONFIG" --scratch-path "$SCRATCH" --product Tokenamp

BIN="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --product Tokenamp --show-bin-path)/Tokenamp"
if [[ ! -x "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Skins"
cp "$BIN" "$CONTENTS/MacOS/Tokenamp"

ICON_LINE=""
if [[ -f "assets/Tokenamp.icns" ]]; then
    cp "assets/Tokenamp.icns" "$CONTENTS/Resources/Tokenamp.icns"
    ICON_LINE=$'\t<key>CFBundleIconFile</key>\n\t<string>Tokenamp</string>'
    echo "    icon: assets/Tokenamp.icns"
fi

# Document types: .wsz only, through an *imported* type declaration. Tokenamp does not define the
# classic Winamp skin format, so it imports the type (an app that exports one takes precedence)
# and names it in its own namespace, since the format has no registered identifier. It conforms to
# public.zip-archive, so Finder still knows it is a zip. Claiming com.pkware.zip-archive made
# LaunchServices ignore the extension list: Tokenamp was offered for every .zip, never for .wsz.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Tokenamp</string>
	<key>CFBundleDisplayName</key>
	<string>Tokenamp</string>
	<key>CFBundleExecutable</key>
	<string>Tokenamp</string>
	<key>CFBundleIdentifier</key>
	<string>local.tokenamp.app</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
${ICON_LINE}
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Winamp Classic Skin</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Default</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>local.tokenamp.wsz</string>
			</array>
		</dict>
	</array>
	<key>UTImportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>local.tokenamp.wsz</string>
			<key>UTTypeDescription</key>
			<string>Winamp Classic Skin</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.zip-archive</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>wsz</string>
				</array>
			</dict>
		</dict>
	</array>
</dict>
</plist>
PLIST

SKIN_COUNT=0
shopt -s nullglob
for skin in skins/dist/*.wsz; do
    cp "$skin" "$CONTENTS/Resources/Skins/"
    SKIN_COUNT=$((SKIN_COUNT + 1))
done
shopt -u nullglob
echo "    bundled skins: $SKIN_COUNT"
if [[ "$SKIN_COUNT" -eq 0 ]]; then
    echo "    warning: skins/dist/*.wsz is empty - the app will fall back to its built-in skin" >&2
fi

echo "==> ad-hoc signing"
codesign --force --deep -s - "$APP"
# Not `verify && echo`: a failing command on the left of && does not trip `set -e`.
if ! codesign --verify --deep --strict "$APP"; then
    echo "error: signature verification failed for $APP" >&2
    exit 1
fi
echo "    signature ok"

echo
echo "built $APP"
echo "run it with:  open $APP            (or: $CONTENTS/MacOS/Tokenamp --demo)"
