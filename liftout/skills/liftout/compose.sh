#!/usr/bin/env bash
# Liftout — compose a share card from a hero image + text, live with ImageMagick.
# Two styles, user's pick:
#   STYLE=floating  → card centered over the full image, quote inside (default)
#   STYLE=matted    → gallery mat, image inset as a framed print, quote below
# Colors adapt to the hero image's brightness: a light image gets a dark surface with
# light text (and vice versa), so the text and overlay always contrast the background.
#
# Inputs (env vars):
#   QUOTE   the pulled quote (include curly “ ” yourself)   [required]
#   OUTLET  e.g. "The Atlantic"                              [required]
#   TITLE   article title                                    (empty to omit)
#   BYLINE  e.g. "By David Brooks"                           (empty to omit)
#   DATE    e.g. "July 8, 2026"                              (empty to omit)
#   ACCENT  hex accent for a DARK surface (default gold); a light surface uses crimson
#   STYLE   floating (default) | matted
#   FORMAT  portrait 1080x1350 (default) | square 1080x1080 | landscape 1200x630
#   SERIF/SANS/SIT  font-file paths (override the auto-detected defaults)
# Files in cwd: hero.jpg (required), logo.png (the favicon, always shown if present)
# Style guide: sourced from $LIFTOUT_STYLE or ~/.config/liftout/style.conf if present.
#   It may set SERIF, SANS, SIT, ACCENT, CRIMSON, INK, PAPER. Per-call env vars win.
# Output: card.png
set -euo pipefail
cd "$(dirname "$0")"

QUOTE="${QUOTE:?set QUOTE}"; OUTLET="${OUTLET:?set OUTLET}"
TITLE="${TITLE:-}"; BYLINE="${BYLINE:-}"; DATE="${DATE:-}"
STYLE="${STYLE:-floating}"; FORMAT="${FORMAT:-portrait}"
# capture per-call style overrides so they beat the style guide + defaults
_ACCENT="${ACCENT:-}"; _SERIF="${SERIF:-}"; _SANS="${SANS:-}"; _SIT="${SIT:-}"
STYLE_CONF="${LIFTOUT_STYLE:-$HOME/.config/liftout/style.conf}"
case "$FORMAT" in
  square)    W=1080; H=1080 ;;
  landscape) W=1200; H=630  ;;
  *)         FORMAT=portrait; W=1080; H=1350 ;;
esac
UP(){ echo "$1" | tr '[:lower:]' '[:upper:]'; }
mn(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%d",(a<b)?a:b}'; }   # min of two ints
frac(){ awk -v x="$1" -v f="$2" 'BEGIN{printf "%d",x*f}'; }        # int(x*f)

# Fonts resolve as: per-call env > style guide > first installed system default below.
# No brand fonts ship here — set your own in the style guide. Defaults are clean system
# faces: Georgia/Helvetica on macOS, DejaVu/Liberation on Linux.
pickfont(){ local f; for f in "$@"; do [ -f "$f" ] && { printf '%s' "$f"; return; }; done; printf '%s' "${@: -1}"; }
SERIF=$(pickfont \
  "/System/Library/Fonts/Supplemental/Georgia Bold.ttf" \
  "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf" \
  "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf" "Georgia")
SANS=$(pickfont \
  "/System/Library/Fonts/Supplemental/Arial Bold.ttf" \
  "/System/Library/Fonts/Helvetica.ttc" \
  "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
  "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" "Helvetica")
SIT=$(pickfont \
  "/System/Library/Fonts/Supplemental/Georgia Italic.ttf" \
  "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf" \
  "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf" "Georgia-Italic")
ACCENT="#e3b23c"; INK="#17130E"; PAPER="#F1ECE0"; CRIMSON="#A62B1F"
[ -f "$STYLE_CONF" ] && . "$STYLE_CONF"                  # durable style guide overrides
[ -n "$_ACCENT" ] && ACCENT="$_ACCENT"                   # then per-call env wins
[ -n "$_SERIF" ] && SERIF="$_SERIF"; [ -n "$_SANS" ] && SANS="$_SANS"; [ -n "$_SIT" ] && SIT="$_SIT"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
gap(){ echo \( -size 1x${1} xc:none \); }

# is the hero image dark? (mean luminance < 0.5)
MEAN=$(magick hero.jpg -colorspace Gray -format "%[fx:mean]" info:)
DARKIMG=$(awk -v m="$MEAN" 'BEGIN{print (m<0.5)?1:0}')
# pick text (TX) + accent (ACC) for a surface: dark surface → light text + gold; light → ink + crimson
palette(){ if [ "$1" = 1 ]; then TX="$PAPER"; ACC="$ACCENT"; else TX="$INK"; ACC="$CRIMSON"; fi; }
# masthead = favicon chip + outlet name, always together, centered
masthead(){ # $1 name-color  $2 out-file
  magick -background none -fill "$1" -font "$SANS" -pointsize 25 label:"$OUTLET" "$T/_o.png"
  if [ -f logo.png ]; then
    magick logo.png -resize 40x40 "$T/_lg.png"
    magick -background none -gravity center "$T/_lg.png" \( -size 14x1 xc:none \) "$T/_o.png" +append "$2"
  else cp "$T/_o.png" "$2"; fi
}

if [ "$STYLE" = "matted" ]; then
  # mat tone follows the image tone so the framed print sits on a matching field
  palette "$DARKIMG"
  MAT=$([ "$DARKIMG" = 1 ] && echo "$INK" || echo "$PAPER")
  MARGIN=90; GAP_PHOTO=44; PAD_BOTTOM=70
  PHOTO_W=$((W - 2*MARGIN))
  PHOTO_TOP=$(mn $(( $(frac "$H" 0.10) > 72 ? $(frac "$H" 0.10) : 72 )) 9999)
  # ponytail: matted wants vertical room — landscape (630 tall) comes out compact but valid
  PHOTO_IN=$(mn $(frac "$H" 0.37) $((H - PHOTO_TOP - GAP_PHOTO - PAD_BOTTOM - 130)))
  PHOTO_DISP=$((PHOTO_IN + 4))   # +4 for the 2px keyline top+bottom
  MAST_TOP=$((PHOTO_TOP - 54))

  magick -size ${W}x${H} xc:"$MAT" "$T/base.png"
  magick hero.jpg -resize ${PHOTO_W}x${PHOTO_IN}^ -gravity center -extent ${PHOTO_W}x${PHOTO_IN} -bordercolor "$TX" -border 2 "$T/photo.png"
  masthead "$ACC" "$T/out.png"

  # metadata block first, so we know how much height the quote can claim
  magick -size 84x6 xc:"$ACC" "$T/bar.png"
  META=$(( 24 + 6 )); METAPARTS=( $(gap 24) "$T/bar.png" )
  if [ -n "$TITLE" ]; then
    magick -background none -fill "$TX" -font "$SANS" -size ${PHOTO_W}x -pointsize 30 caption:"$TITLE" "$T/ti.png"
    META=$(( META + 22 + $(magick identify -format "%h" "$T/ti.png") )); METAPARTS+=( $(gap 22) "$T/ti.png" )
  fi
  ATTR="$BYLINE"; [ -n "$DATE" ] && ATTR="${BYLINE:+$BYLINE  ·  }$DATE"
  if [ -n "$ATTR" ]; then
    magick -background none -fill "$TX" -font "$SIT" -pointsize 26 label:"$ATTR" "$T/at.png"
    META=$(( META + 12 + $(magick identify -format "%h" "$T/at.png") )); METAPARTS+=( $(gap 12) "$T/at.png" )
  fi

  # quote fills the gap between photo and metadata; caption auto-fits type to the box
  AVAIL=$(( H - PHOTO_TOP - PHOTO_DISP - GAP_PHOTO - PAD_BOTTOM ))
  QH=$(( AVAIL - META )); [ "$QH" -lt 60 ] && QH=60
  magick -background none -fill "$TX" -font "$SERIF" -size ${PHOTO_W}x${QH} -gravity west caption:"$QUOTE" "$T/q.png"
  magick -background none -gravity west "$T/q.png" "${METAPARTS[@]}" -append "$T/stk.png"

  magick "$T/base.png" \
    "$T/out.png"   -gravity north     -geometry +0+${MAST_TOP} -composite \
    "$T/photo.png" -gravity north     -geometry +0+${PHOTO_TOP} -composite \
    "$T/stk.png"   -gravity southwest -geometry +${MARGIN}+${PAD_BOTTOM} -composite card.png

else
  # floating: card over the full image. Surface is the OPPOSITE tone of the image so it
  # pops: light image → dark card + light text; dark image → light card + ink text.
  FSD=$([ "$DARKIMG" = 1 ] && echo 0 || echo 1)
  palette "$FSD"
  PANEL=$([ "$FSD" = 1 ] && echo 'rgba(20,16,11,0.86)' || echo 'rgba(242,238,228,0.93)')
  FLQW=$(mn 700 $((W - 360)))                    # quote box shrinks to fit narrow formats
  FLQH=$(mn 520 $(frac "$H" 0.42))               # and short ones
  magick hero.jpg -resize ${W}x${H}^ -gravity center -extent ${W}x${H} "$T/base.png"

  masthead "$TX" "$T/hdr.png"
  TOP=()
  [ -n "$DATE" ] && { magick -background none -fill "$ACC" -font "$SANS" -kerning 3 -pointsize 19 label:"$(UP "$DATE")" "$T/dt.png"; TOP+=( "$T/dt.png" $(gap 14) ); }
  TOP+=( "$T/hdr.png" )

  magick -background none -fill "$TX" -font "$SERIF" -size ${FLQW}x${FLQH} -gravity center caption:"$QUOTE" "$T/q.png"
  magick -size 64x5 xc:"$ACC" "$T/bar.png"
  STACK=( "${TOP[@]}" $(gap 32) "$T/q.png" $(gap 22) "$T/bar.png" )
  [ -n "$TITLE" ] && { magick -background none -fill "$TX" -font "$SANS" -size $((FLQW-60))x -pointsize 29 -gravity center caption:"$TITLE" "$T/ti.png"; STACK+=( $(gap 22) "$T/ti.png" ); }
  [ -n "$BYLINE" ] && { magick -background none -fill "$TX" -font "$SIT" -pointsize 25 label:"$BYLINE" "$T/byl.png"; STACK+=( $(gap 14) "$T/byl.png" ); }
  magick -background none -gravity center "${STACK[@]}" -append "$T/ct.png"

  CW=$(magick identify -format "%w" "$T/ct.png"); CH=$(magick identify -format "%h" "$T/ct.png")
  PW=$((CW+120)); PH=$((CH+92))
  magick -size ${PW}x${PH} xc:none -fill "$PANEL" \
    -draw "roundrectangle 0,0,$((PW-1)),$((PH-1)),26,26" "$T/pn.png"
  magick "$T/pn.png" \( +clone -background black -shadow 70x24+0+12 \) +swap \
    -background none -layers merge +repage "$T/pns.png"
  magick "$T/pns.png" "$T/ct.png" -gravity center -composite "$T/pnf.png"
  magick "$T/base.png" "$T/pnf.png" -gravity center -composite card.png
fi
echo "wrote card.png ($STYLE, $FORMAT, $([ "$DARKIMG" = 1 ] && echo dark || echo light) image)"
