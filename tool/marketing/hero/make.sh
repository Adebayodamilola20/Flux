#!/usr/bin/env bash
# Regenerate the DevNotch hero shot: wallpaper -> SVG -> PNGs.
# Edit the CONFIG block in build.py (tilt / scale / framing) or the `slots`
# list (tools, percentages, colours), then run this.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="../../../design-exports"
NAME="DevNotch — Hero Shot"

shot() {  # shot <html> <png> <w> <h>
  "$CHROME" --headless --disable-gpu --hide-scrollbars --no-sandbox \
    --force-device-scale-factor=2 --screenshot="$2" --window-size="$3,$4" \
    "file://$PWD/$1" >/dev/null 2>&1
}

# 1. wallpaper: blurred/grainy SVG -> flat JPEG (blur must be baked; Figma drops SVG filters)
printf '<style>html,body{margin:0;overflow:hidden}img{display:block;width:1240px;height:800px}</style><img src="wallpaper.svg" width="1240" height="800">' > .wp.html
shot .wp.html .wp.png 1240 800
sips -s format jpeg -s formatOptions 88 -Z 1860 .wp.png --out wallpaper.jpg >/dev/null

# 2. build the layered SVG (embeds the wallpaper as a base64 image fill)
python3 build.py

# 3. render it at 2x, then downsample for the 1x
printf '<style>html,body{margin:0;overflow:hidden}img{display:block;width:1600px;height:1000px}</style><img src="%s" width="1600" height="1000">' \
  "$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$NAME.svg")" > .hero.html
shot .hero.html .hero.png 1600 1000

mkdir -p "$OUT"
cp "$NAME.svg"          "$OUT/$NAME.svg"
cp .hero.png            "$OUT/$NAME@2x.png"
sips -Z 1600 .hero.png --out "$OUT/$NAME.png" >/dev/null
cp wallpaper.jpg        "$OUT/devnotch-wallpaper-purple.jpg"
rm -f .wp.html .wp.png .hero.html .hero.png

echo "-> $OUT"
ls -1 "$OUT"
