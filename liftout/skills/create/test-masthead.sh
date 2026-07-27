#!/usr/bin/env bash
# Check for masthead()'s favicon-plate logic: does a real ImageMagick run classify a
# transparent dark glyph as needing a plate, an opaque tile as not, matching the
# 0.08 stddev threshold in compose.sh?
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

probe(){ # $1 logo  $2 surface-hex  -> stddev
  magick "$1" -resize 40x40 -background "$2" -alpha remove -colorspace Gray \
    -format "%[fx:standard_deviation]" info:
}
plates(){ [ "$(awk -v s="$1" 'BEGIN{print (s<0.08)?1:0}')" = 1 ]; }

# dark glyph on transparent (worst real case: black mark, no backing)
magick -size 40x40 xc:none -fill black -draw "circle 20,20 20,6" "$T/glyph.png"
# opaque tile (carries its own background, should never get plated)
magick -size 40x40 xc:"#3355aa" -fill white -draw "circle 20,20 20,6" "$T/tile.png"

fail=0
check(){ # $1 desc  $2 got-bool  $3 want-bool
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1 (got $2, want $3)"; fail=1; fi
}

sd=$(probe "$T/glyph.png" "#17130E"); plates "$sd" && got=1 || got=0
check "dark glyph on dark surface -> plates" "$got" 1

sd=$(probe "$T/glyph.png" "#F1ECE0"); plates "$sd" && got=1 || got=0
check "dark glyph on light surface -> bare" "$got" 0

sd=$(probe "$T/tile.png" "#17130E"); plates "$sd" && got=1 || got=0
check "opaque tile on dark surface -> bare" "$got" 0

sd=$(probe "$T/tile.png" "#F1ECE0"); plates "$sd" && got=1 || got=0
check "opaque tile on light surface -> bare" "$got" 0

[ "$fail" = 0 ] && echo "all checks passed" || { echo "checks failed"; exit 1; }
