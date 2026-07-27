#!/usr/bin/env bash
# Check that per-call INK/PAPER/CRIMSON/ACCENT env vars override both the
# hue-derived palette and the style guide -- regression guard for the bug where
# only ACCENT actually made it through (see git log).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp "$HERE/compose.sh" "$T/compose.sh"
cd "$T"

# grayscale heroes: zero saturation everywhere, so the hue derivation always
# bails and falls back to defaults -- any garish color below can only be the pin
magick -size 40x40 xc:gray20 hero_dark.jpg
magick -size 40x40 xc:gray85 hero_light.jpg

# capture first, then match in bash -- piping straight into `grep -q` races
# under pipefail: grep exits on its first match and SIGPIPEs magick mid-write.
# magick's %c hex is always uppercase, so a plain glob match needs no case-folding
# (macOS ships bash 3.2, no ${var,,}).
has(){ local h; h=$(magick card.png -format '%c' histogram:info:); [[ "$h" == *"$1"* ]]; }

fail=0
check(){ if [ "$2" = 1 ]; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

cp hero_dark.jpg hero.jpg
LIFTOUT_STYLE=/nonexistent INK="#FF00FF" QUOTE="“x”" OUTLET="Test" STYLE=matted FORMAT=square bash compose.sh >/dev/null
has "#FF00FF" && got=1 || got=0
check "INK override -> dark mat is magenta" "$got"

cp hero_light.jpg hero.jpg
LIFTOUT_STYLE=/nonexistent PAPER="#00FF00" QUOTE="“x”" OUTLET="Test" STYLE=matted FORMAT=square bash compose.sh >/dev/null
has "#00FF00" && got=1 || got=0
check "PAPER override -> light mat is green" "$got"

cp hero_light.jpg hero.jpg
LIFTOUT_STYLE=/nonexistent CRIMSON="#0000FF" QUOTE="“x”" OUTLET="Test" STYLE=matted FORMAT=square bash compose.sh >/dev/null
has "#0000FF" && got=1 || got=0
check "CRIMSON override -> light-surface accent bar is blue" "$got"

cp hero_dark.jpg hero.jpg
LIFTOUT_STYLE=/nonexistent ACCENT="#FFFF00" QUOTE="“x”" OUTLET="Test" STYLE=matted FORMAT=square bash compose.sh >/dev/null
has "#FFFF00" && got=1 || got=0
check "ACCENT override -> dark-surface accent bar is yellow (regression guard)" "$got"

cp hero_dark.jpg hero.jpg
echo 'INK="#111111"' > style.conf
LIFTOUT_STYLE="$T/style.conf" INK="#FF00FF" QUOTE="“x”" OUTLET="Test" STYLE=matted FORMAT=square bash compose.sh >/dev/null
has "#FF00FF" && win=1 || win=0
has "#111111" && lost=1 || lost=0
[ "$win" = 1 ] && [ "$lost" = 0 ] && got=1 || got=0
check "per-call INK beats style guide" "$got"

[ "$fail" = 0 ] && echo "all checks passed" || { echo "checks failed"; exit 1; }
