#!/bin/sh
# Downloads Satoshi from Fontshare (free for commercial use) into the app resources.
set -eu
dest="$(dirname "$0")/../Musculation/Resources/Fonts"
mkdir -p "$dest"
tmp="$(mktemp -d)"
curl -fsSL "https://api.fontshare.com/v2/fonts/download/satoshi" -o "$tmp/satoshi.zip"
unzip -q "$tmp/satoshi.zip" -d "$tmp"
for weight in Medium Bold Black; do
  find "$tmp" -name "Satoshi-$weight.otf" -exec cp {} "$dest/" \;
done
rm -rf "$tmp"
ls "$dest"
