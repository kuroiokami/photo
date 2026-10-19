#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product Photo
bin_path="$(swift build --show-bin-path)"
app_dir="$PWD/.build/Photo.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_path/Photo" "$app_dir/Contents/MacOS/Photo"
for resource in "$bin_path"/*.bundle; do
  [ -d "$resource" ] || continue
  ditto "$resource" "$app_dir/Contents/Resources/$(basename "$resource")"
done
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.kuroiokami.photo.development</string>
<key>CFBundleName</key><string>Photo</string>
<key>CFBundleExecutable</key><string>Photo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf 'Development app: %s\n' "$app_dir"
