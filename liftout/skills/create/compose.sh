#!/usr/bin/env bash
# Liftout — compose a share card from a hero image + text, live with ImageMagick.
# Two styles, user's pick:
#   STYLE=floating  → card centered over the full image, quote inside (default)
#   STYLE=matted    → gallery mat, image inset as a framed print, quote below
# Colors adapt to the hero image: surfaces and accents are tinted from the image's own
# dominant hue, and light/dark placement still follows brightness (a light image gets a
# dark surface with light text and vice versa), so the card always contrasts and always
# feels like it belongs to the photo.
#
# Inputs (env vars):
#   QUOTE   the pulled quote (include curly “ ” yourself)   [required]
#   OUTLET  e.g. "The Atlantic"                              [required]
#   TITLE   article title                                    (empty to omit)
#   BYLINE  e.g. "By David Brooks"                           (empty to omit)
#   DATE    e.g. "July 8, 2026"                              (empty to omit)
#   ACCENT  hex accent for a DARK surface (default gold); a light surface uses crimson
#   STYLE   floating (default) | matted | both (writes card-floating.png + card-matted.png)
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

# derive surface + accent colors from the hero image's own dominant hue, so the card's
# palette is tied to the photo instead of always landing on flat ink/paper. Quantizes
# the image to a few swatches, picks the most saturated populous one (skipping
# near-gray/black/white swatches), then re-lights that hue into a dark surface, a pale
# surface, and two accent weights. Falls back to the neutrals above for grayscale/
# monochrome photos where there's no real hue to pull from.
hsl2hex(){ awk -v h="$1" -v s="$2" -v l="$3" 'function hue2rgb(p,q,t){if(t<0)t+=1;if(t>1)t-=1;if(t<1/6)return p+(q-p)*6*t;if(t<1/2)return q;if(t<2/3)return p+(q-p)*(2/3-t)*6;return p}
  BEGIN{H=h/360; if(s==0){r=g=b=l}else{q=(l<0.5)?l*(1+s):l+s-l*s; p=2*l-q; r=hue2rgb(p,q,H+1/3); g=hue2rgb(p,q,H); b=hue2rgb(p,q,H-1/3)}
  printf "#%02X%02X%02X", r*255, g*255, b*255}'; }
HIST=$(magick hero.jpg -resize 100x100 -colors 8 +dither -format '%c' histogram:info: 2>/dev/null || true)
HUE=""; SAT=""
if [ -n "$HIST" ]; then
  read -r HUE SAT < <(echo "$HIST" | awk -F'[:()]' '
    {
      cnt=$1+0; n=split($3,rgb,","); if (n<3) next
      r=rgb[1]/255; g=rgb[2]/255; b=rgb[3]/255
      mx=(r>g?(r>b?r:b):(g>b?g:b)); mn=(r<g?(r<b?r:b):(g<b?g:b)); d=mx-mn
      l=(mx+mn)/2
      s=(d==0)?0:d/(1-((2*l-1)<0?-(2*l-1):(2*l-1)))
      if (s<0.15 || l<0.12 || l>0.88) next          # skip near-gray/black/white swatches
      if (mx==r) h=60*(((g-b)/d)%6); else if (mx==g) h=60*((b-r)/d+2); else h=60*((r-g)/d+4)
      if (h<0) h+=360
      score=cnt*s                                    # favor populous AND saturated
      if (score>best){best=score; bh=h; bs=s}
    }
    END{ if (best>0) printf "%.1f %.3f", bh, bs }') || true
fi
if [ -n "$HUE" ]; then
  CSAT=$(awk -v s="$SAT" 'BEGIN{v=s; if(v<0.35)v=0.35; if(v>0.7)v=0.7; print v}')
  INK=$(hsl2hex "$HUE" "$(awk -v s="$CSAT" 'BEGIN{print s*0.7}')" 0.13)
  PAPER=$(hsl2hex "$HUE" "$(awk -v s="$CSAT" 'BEGIN{print s*0.35}')" 0.95)
  ACCENT=$(hsl2hex "$HUE" "$(awk -v s="$CSAT" 'BEGIN{v=s*1.3; print (v>0.9)?0.9:v}')" 0.62)
  CRIMSON=$(hsl2hex "$HUE" "$(awk -v s="$CSAT" 'BEGIN{v=s*1.3; print (v>0.9)?0.9:v}')" 0.38)
fi
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

if [ "$STYLE" = "both" ]; then STYLES=(floating matted); else STYLES=("$STYLE"); fi
for S in "${STYLES[@]}"; do
OUTFILE="card.png"; [ "${#STYLES[@]}" -gt 1 ] && OUTFILE="card-${S}.png"

if [ "$S" = "matted" ]; then
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
    "$T/stk.png"   -gravity southwest -geometry +${MARGIN}+${PAD_BOTTOM} -composite "$OUTFILE"

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
  magick "$T/base.png" "$T/pnf.png" -gravity center -composite "$OUTFILE"
fi
echo "wrote $OUTFILE ($S, $FORMAT, $([ "$DARKIMG" = 1 ] && echo dark || echo light) image)"
done
