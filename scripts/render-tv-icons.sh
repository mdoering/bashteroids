#!/usr/bin/env bash
# Renders the tvOS Brand Assets icon set from icon.svg.
# Splits the source SVG into back / middle / front layers and
# generates the eight PNGs the asset catalog needs. Run once
# whenever icon.svg changes; the output PNGs are committed.
#
# Requires: rsvg-convert (brew install librsvg)
#           magick      (brew install imagemagick)

set -euo pipefail

cd "$(dirname "$0")/.."

ASSET_ROOT="Bashteroids/Assets.xcassets/AppIcon.brandassets"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Source layer SVGs share viewBox 0 0 200 200 (matches icon.svg).
# We render each at icon height then pad to wide canvas.

cat > "$TMP/back.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="200" height="200" style="fill:#030508;"/>
  <g opacity="0.55">
    <circle cx="24" cy="22" r="1" fill="#fff"/>
    <circle cx="30" cy="168" r="0.8" fill="#fff"/>
    <circle cx="12" cy="95" r="0.8" fill="#fff"/>
    <circle cx="180" cy="170" r="1" fill="#fff"/>
    <circle cx="186" cy="115" r="0.7" fill="#fff"/>
    <circle cx="95" cy="186" r="0.8" fill="#fff"/>
    <circle cx="85" cy="99" r="0.7" fill="#fff"/>
    <circle cx="22" cy="140" r="0.6" fill="#fff"/>
  </g>
</svg>
EOF

cat > "$TMP/middle.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <g>
    <path d="M37,43l10,-20l20,-2l18,12l2,22l-14,16l-26,-4l-10,-24Z"
          fill="none" stroke="#fff" stroke-width="2.5"/>
    <circle cx="65" cy="43" r="8" fill="none" stroke="#fff" stroke-opacity="0.45" stroke-width="1.5"/>
  </g>
</svg>
EOF

cat > "$TMP/front.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <g>
    <path d="M88.493,130.731l-30.07,29.543l2.705,-11.903l-4.532,-11.111l-10.258,-6.616l42.154,0.087Z"
          fill="none" stroke="#f33" stroke-width="2.8" stroke-linecap="round"/>
  </g>
  <g>
    <path d="M125.818,97.634l42.144,0.921l-10.413,6.369l-4.796,11l2.42,11.964l-29.355,-30.254Z"
          fill="none" stroke="#4af" stroke-width="2.8" stroke-linecap="round"/>
    <path d="M110.47,90.797l3.544,1.577"
          fill="none" stroke="#4af" stroke-width="2.8" stroke-linecap="round"/>
  </g>
</svg>
EOF

render_layer() {
    local layer="$1"   # back|middle|front
    local cap_layer
    cap_layer="$(tr '[:lower:]' '[:upper:]' <<< "${layer:0:1}")${layer:1}"
    local large_w="$2"
    local large_h="$3"
    local small_w="$4"
    local small_h="$5"
    local bg="$6"       # background fill for padding (none|color)

    local large_imgset="$ASSET_ROOT/App Icon - App Store.imagestack/${cap_layer}.imagestacklayer/Content.imageset"
    local small_imgset="$ASSET_ROOT/App Icon.imagestack/${cap_layer}.imagestacklayer/Content.imageset"

    rsvg-convert -h "$large_h" "$TMP/$layer.svg" -o "$TMP/${layer}-large.png"
    magick "$TMP/${layer}-large.png" -background "$bg" -gravity center \
        -extent "${large_w}x${large_h}" "$large_imgset/${layer}.png"

    rsvg-convert -h "$small_h" "$TMP/$layer.svg" -o "$TMP/${layer}-small.png"
    magick "$TMP/${layer}-small.png" -background "$bg" -gravity center \
        -extent "${small_w}x${small_h}" "$small_imgset/${layer}.png"
}

# Back layer must be fully opaque (bottom of parallax stack).
# Middle/front are transparent so layers below show through.
render_layer back   1280 768 400 240 "#030508"
render_layer middle 1280 768 400 240 none
render_layer front  1280 768 400 240 none

# Top-shelf flat composite: icon (square) on the left, wordmark on the right.
render_topshelf() {
    local out="$1"
    local w="$2"
    local h="$3"

    rsvg-convert -h "$h" "$TMP/back.svg"   -o "$TMP/ts-back.png"
    rsvg-convert -h "$h" "$TMP/middle.svg" -o "$TMP/ts-middle.png"
    rsvg-convert -h "$h" "$TMP/front.svg"  -o "$TMP/ts-front.png"

    local font="/System/Library/Fonts/HelveticaNeue.ttc"

    magick -size "${w}x${h}" xc:"#030508" \
        \( "$TMP/ts-back.png"   \) -gravity West -geometry +60+0 -composite \
        \( "$TMP/ts-middle.png" \) -gravity West -geometry +60+0 -composite \
        \( "$TMP/ts-front.png"  \) -gravity West -geometry +60+0 -composite \
        -font "$font" -pointsize 110 -fill white \
        -gravity West -annotate +800+0 "BASHTEROIDS" \
        "$out"
}

render_topshelf "$ASSET_ROOT/Top Shelf Image.imageset/topshelf.png"      1920 720
render_topshelf "$ASSET_ROOT/Top Shelf Image Wide.imageset/topshelf.png" 2320 720

echo "Rendered Brand Assets PNGs."
