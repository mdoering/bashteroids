#!/usr/bin/env bash
# Renders the tvOS Brand Assets app icon.
#
# Back layer: graphics/landscape.png letterboxed into the 5:3 icon
# canvas (1280x768 large, 400x240 small). Front layer is a fully
# transparent PNG so the landscape shows unobstructed; tvOS still
# gets its required 2-layer parallax stack.
#
# Run whenever graphics/landscape.png changes.
#
# Requires: magick (brew install imagemagick)

set -euo pipefail

cd "$(dirname "$0")/.."

LANDSCAPE_SRC="graphics/landscape.png"
ASSET_ROOT="Bashteroids/Assets.xcassets/AppIcon.brandassets"

write_back() {
    local out="$1"
    local w="$2"
    local h="$3"
    # Fit landscape inside w×h preserving aspect, pad with #030508.
    # Background must be fully opaque (actool requirement for back layer).
    magick "$LANDSCAPE_SRC" -resize "${w}x${h}" \
        -background "#030508" -gravity center -extent "${w}x${h}" \
        -alpha off "$out"
}

write_transparent() {
    local out="$1"
    local w="$2"
    local h="$3"
    magick -size "${w}x${h}" xc:none -alpha set "$out"
}

write_back        "$ASSET_ROOT/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back.png"               400  240
write_back        "$ASSET_ROOT/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/back.png"  1280 768
write_transparent "$ASSET_ROOT/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front.png"            400  240
write_transparent "$ASSET_ROOT/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/front.png" 1280 768

echo "Rendered Brand Assets PNGs from $LANDSCAPE_SRC."
