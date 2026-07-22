# Liftout: Spec

## What it is

A Claude Code skill that turns an **article URL** into a polished, editorial
**share card**: a social image built around the single sharpest quote from the
piece, set over (or beside) the article's own hero image. The inspiration was
tools like ShareSparrow ("paste a link, get an Instagram-ready graphic"). The
difference is that Liftout is *article-aware*: it uses the piece's real key image
and pulls a real quote, instead of filling a generic template with a placeholder
avatar.

Prior-art check across Claude skills and plugin marketplaces (December 2026): no
existing skill does URL to scraped article image to pulled quote to designed,
image-adaptive card. The nearest neighbors are a text-only pull-quote formatter
(`pm-claude-skills/quote-card`), a generic HTML quote-card template with an avatar
placeholder (`nexu-io/open-design`, `card-twitter`), and assorted `seo-image-gen`
and og:image validators. "Pullquote" as a name was already taken by
`seattletimes/pullquote`, a 2017 "quick social media image generator", which is
why this is **Liftout**, the newsroom term for a lift-out quote.

## Design principles

1. **The quote has the most visual weight.** Everything else (title, byline,
   outlet, favicon, date) supports it.
2. **Live composition, not template substitution.** A 6-word pull-quote and a
   60-word one need different type sizes and layouts. ImageMagick's `caption:`
   auto-fits type to a box, so the quote sizes itself to the space.
3. **Look at the render and fix it.** The skill's final step is to open the PNG,
   read it back, and correct it. A rigid script that renders blind cannot catch a
   clipped byline or text lost against a busy image. An agent looking at the
   output can. This is the core of why it is a skill and not a one-shot program.
4. **Colors come from the image and contrast it.** Surfaces and accents are tinted
   from the hero's own dominant hue (grayscale photos fall back to neutral ink/gold),
   and the script measures the hero's mean luminance to flip surface and text so they
   always read: light image gets a dark surface with light text, dark image gets
   the reverse.

## Pipeline

1. **Scrape** the page's OpenGraph metadata and favicon (curl plus grep).
2. **Pick the quote** by LLM judgment: the strongest self-contained line in the body.
3. **Download** the hero image and favicon locally (local files never race the render).
4. **Compose** with `compose.sh` (ImageMagick), choosing a style and format.
5. **Verify**: read `card.png`, tweak, re-render until right.

## Styles

- **floating**: an opaque, rounded card with a soft drop shadow, centered over the
  full-brightness image, with the quote inside it. Immersive, you are *in* the
  image. The date rides on top as a small accent kicker; the title sits under the quote.
- **matted**: a gallery mat whose tone matches the image. The hero is inset as a
  small framed print with a hairline keyline, and the quote sits below it in the
  mat, sized to fill the gap between photo and metadata. Reverent, the image
  becomes an artifact on a page. The date joins the byline.

## Formats

| FORMAT | Size | Notes |
|--------|------|-------|
| `portrait` (default) | 1080x1350 | 4:5, the Instagram size |
| `square` | 1080x1080 | 1:1 feed tile |
| `landscape` | 1200x630 | OG / Twitter card. Floating only, really: matted gets cramped |

## Adaptive color

`INK`/`PAPER`/`ACCENT`/`CRIMSON` aren't fixed anymore — they're derived per-image.
`compose.sh` quantizes the hero to a handful of swatches (`-colors 8 +dither
histogram:info:`), throws out near-gray/black/white ones, and picks whichever
remaining swatch is most saturated *and* populous (`score = count * saturation`).
That swatch's hue gets re-lit into a dark surface, a pale surface, and two accent
weights (`hsl2hex`), overwriting the neutrals. A grayscale/monochrome photo has no
qualifying swatch, so it falls straight back to the original ink/paper/gold/crimson.

```bash
MEAN=$(magick hero.jpg -colorspace Gray -format "%[fx:mean]" info:)
DARKIMG=$(awk -v m="$MEAN" 'BEGIN{print (m<0.5)?1:0}')
# dark surface: light text + gold-role accent. light surface: ink text + crimson-role accent.
palette(){ if [ "$1" = 1 ]; then TX="$PAPER"; ACC="$ACCENT"; else TX="$INK"; ACC="$CRIMSON"; fi; }
```

- **matted**: the mat tone *matches* the image tone (light image gets a pale mat and ink text).
- **floating**: the card is the *opposite* tone of the image so it pops (light image gets a
  dark card and light text).
- Style guide (`~/.config/liftout/style.conf`) and per-call env vars still override the
  derived colors, same precedence as before — derivation only fills in when neither is set.

## Type

No brand fonts ship with the skill. Type falls back to clean system faces (Georgia
and Helvetica/Arial on macOS, DejaVu/Liberation on Linux). Users point at their own
serif and sans in a style guide at `~/.config/liftout/style.conf` (or `$LIFTOUT_STYLE`):

```bash
SERIF="/path/to/your-serif-bold.otf"      # the quote, the hero face
SANS="/path/to/your-sans-bold.otf"        # outlet + title
SIT="/path/to/your-serif-italic.otf"      # byline
```

Fonts resolve as: per-call env var, then the style guide, then the first installed
system default. The same file sets the accent colors (`ACCENT`, `CRIMSON`, `INK`,
`PAPER`). The skill offers to create it on first run; it works without it.

## Key recipe fragments (from the spike)

**Background, floating.** Fill the frame, keep it at full brightness (the card
carries the contrast):

```bash
magick hero.jpg -resize 1080x1350^ -gravity center -extent 1080x1350 base.png
```

**The quote, auto-fit.** This is the mechanism that adapts to any quote length:

```bash
magick -background none -fill "$TX" -font "$SERIF" -size 700x520 -gravity center \
  caption:"$QUOTE" quote.png
```

**Opaque card plus soft drop shadow,** so it separates from a busy image:

```bash
magick -size ${PW}x${PH} xc:none -fill 'rgba(20,16,11,0.86)' \
  -draw "roundrectangle 0,0,$((PW-1)),$((PH-1)),26,26" pn.png
magick pn.png \( +clone -background black -shadow 70x24+0+12 \) +swap \
  -background none -layers merge +repage pns.png
```

**Matted: quote fills the leftover height.** Measure the metadata block, give the
rest to the quote:

```bash
AVAIL=$(( H - PHOTO_TOP - PHOTO_DISP - GAP_PHOTO - PAD_BOTTOM ))
QH=$(( AVAIL - META ))
magick -background none -fill "$TX" -font "$SERIF" -size 900x${QH} -gravity west \
  caption:"$QUOTE" q.png
```

**Left-aligned stack via one append.** Spacing self-adjusts to any article. This
is what fixed the disappearing-byline bug an earlier blind version had:

```bash
magick -background none -gravity west \
  q.png \( -size 1x24 xc:none \) bar.png \( -size 1x22 xc:none \) title.png \
  -append stack.png
```

## Reference example (built and tested against this article)

- **Article**: David Brooks, "Democrats Became Great by Fighting the Left,"
  *The Atlantic*, July 8, 2026:
  <https://www.theatlantic.com/ideas/2026/07/democrats-fight-left-dsa/687839/>
- **OG metadata** extracted:
  - `og:title`: "Democrats Became Great by Fighting the Left"
  - `og:site_name`: "The Atlantic"
  - `name="author"`: "David Brooks"
  - `article:published_time`: `2026-07-08T14:33:49Z`, rendered as "July 8, 2026"
  - `og:image`: the red-rose and bucking-donkey linocut (a light, busy image)
  - favicon: the largest `apple-touch-icon` (the red "A" chip)
- **Quotes tried** (author's own words, lightly trimmed):
  1. "Liberals need to remember their history, and fight for their values." (short)
  2. "Every Democrat is going to have to ask themselves: Do I support the moral realism
     of the mainstream Democrats, with their pragmatic reformist temper, or do I support
     the progressives, with their utopian belief in human perfectibility and their
     willingness to concentrate power in order to take aggressive action on behalf of
     social justice?" (very long, which proved the auto-fit)
  3. "Progressives are showing once again that so long as your followers are fervently
     committed, it doesn't take many people to commandeer a movement… The sauvignon-blanc
     liberals in the affluent coastal suburbs hardly seem capable of pushing back
     effectively." (the keeper)

## Known limitations

- **Built and tested on macOS.** Requires ImageMagick 7 (`magick`) and `awk`. The
  Linux font fallbacks (DejaVu, Liberation) are included in the resolution order but
  have not been tested on Linux.
- **Landscape matted is tight.** 630px of height cannot hold a framed photo and a
  large quote, so the quote shrinks. Use floating for landscape.
- **Two styles.** Curated down from a 10-treatment exploration. Floating and matted
  were the two that gave the quote a clean reading surface while keeping the image
  intact. More styles and aspect ratios are the obvious next step, but the
  article-aware angle is the point, not a big template gallery.
