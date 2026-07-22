---
name: create
description: >-
  Turn an article URL into a polished, editorial share card: the article's own
  hero image, a pulled quote as the dominant element, plus title, byline, outlet
  name and favicon. Use when the user pastes an article link and wants a share
  graphic, quote card, or social card. Invoke explicitly as
  `/liftout:create <url> [aspect-ratio]`, where aspect-ratio is portrait
  (default), square, or landscape. Trigger on "share card", "quote card",
  "liftout", "make a card from this article", "social graphic for this link".
argument-hint: "<url> [portrait|square|landscape]"
arguments: [url, aspect_ratio]
---

# Liftout

Compose a share card from an article URL, **live, per article**. Every piece
differs (a 6-word pull-quote and a 60-word one need completely different type
sizes), so this is not template substitution: you scrape the article, pick the
quote, run the ImageMagick recipe, **look at the result, and tweak until it's
right.** Looking at the render and fixing it is the job, not an optional step.

`compose.sh` (next to this file) is a proven starting recipe. Run it from the
skill directory; it reads `hero.jpg`/`logo.png` and writes `card.png` there.

## Arguments

When invoked explicitly (`/liftout:create <url> [aspect-ratio]`), the article URL
is `$url` and the optional aspect ratio is `$aspect_ratio`. Map the aspect ratio to
`FORMAT`: `portrait` (default, also 4:5), `square` (1:1), or `landscape` (1.91:1,
16:9, OG/Twitter). If `$aspect_ratio` is empty, default to portrait. When triggered
from conversation instead of an explicit call, read the URL and any aspect-ratio
preference from what the user said.

## First run: offer a style guide

Before composing the first card, check whether a style guide exists at
`~/.config/liftout/style.conf` (or `$LIFTOUT_STYLE`). If it doesn't, ask the user
once (AskUserQuestion) whether they'd like to set their own brand fonts and accent
colors, or use the defaults. Write the file either way, so this isn't asked again:

- **Customize:** ask for the font *names* (or a link to the brand's website/style
  guide) and hex colors — not file paths. Then find the actual `.otf`/`.ttf` files
  on their machine (e.g. `find ~/Library/Fonts /Library/Fonts -iname "*<name>*"`,
  or check a project's asset folder if they point you at one) and write those
  resolved absolute paths into the config, using `style.conf.example` (next to
  this file) as the template. If a named font can't be found locally, say so and
  fall back to defaults for that slot rather than guessing a path.
- **Use defaults:** copy `style.conf.example` to the config path (everything
  commented out), so it exists and they can edit it later.

`compose.sh` sources this file automatically. No brand fonts ship with the skill:
without a style guide, type falls back to clean system faces.

## Steps

1. **Scrape metadata.** Curl the page and pull the OpenGraph tags:
   ```bash
   curl -sL -A "Mozilla/5.0" "<URL>" > /tmp/article.html
   grep -ioE '<meta[^>]+(og:(title|image|site_name)|name="author")[^>]*>' /tmp/article.html
   grep -ioE '<meta[^>]+article:published_time[^>]*>' /tmp/article.html
   grep -ioE '<link[^>]+apple-touch-icon[^>]*>' /tmp/article.html
   ```
   Take: `og:title` (title), `og:image` (hero), `og:site_name` (outlet),
   `name="author"` (byline), `article:published_time` (format it like "July 8, 2026").
   Logo = the largest `apple-touch-icon` href, else
   `https://www.google.com/s2/favicons?domain=<domain>&sz=256`.

2. **Pick THE quote.** Read the article body and choose one line that's punchy,
   self-contained, and makes someone want to click. This is the whole reason a
   human/LLM does this. Don't default to `og:description` — find the best *sentence
   in the piece*. Keep the author's words; trim only lightly. If the user hands you
   a quote, use theirs verbatim.

3. **Download the images** (local files render reliably). `hero.jpg`/`logo.png` are
   reused from the *previous* article if you skip this — always clear them first:
   ```bash
   rm -f hero.jpg logo.png card.png card-floating.png card-matted.png
   curl -sL -A "Mozilla/5.0" "<og:image>" -o hero.jpg
   curl -sL -A "Mozilla/5.0" "<logo url>" -o logo.png   # skip if none — leave it deleted
   ```

4. **Compose.** Run the recipe with your values, generating both styles at once
   so the user can pick (default), and a format (default `portrait`):
   ```bash
   QUOTE="“…”" OUTLET="…" TITLE="…" BYLINE="By …" DATE="July 8, 2026" \
   ACCENT="#e3b23c" STYLE=both FORMAT=portrait bash compose.sh
   ```
   This writes `card-floating.png` and `card-matted.png`. Show both and ask which
   one to keep. If the user already said which style they want, pass `STYLE=floating`
   or `STYLE=matted` instead and it writes a single `card.png`.
   - `STYLE=floating` — card centered over the full-brightness image, quote inside it
     (immersive). Date rides up top as a kicker; title sits under the quote.
   - `STYLE=matted` — gallery mat, the image inset as a framed print, quote below
     (reverent; feels like a page). Date joins the byline.
   - `FORMAT=portrait` (1080×1350, default) · `square` (1080×1080) · `landscape`
     (1200×630). Floating handles all three; matted is best in portrait/square —
     landscape gets tight, so prefer floating there.
   - **Colors adapt to the image**: the script reads the hero's brightness and flips the
     surface + text so they always contrast — a light image gets a dark surface with
     light text, a dark image the reverse. `ACCENT` is the accent for a dark surface
     (gold); light surfaces use crimson automatically.
   - The favicon (`logo.png`) always leads the outlet name in both styles — so download it.
   - `TITLE`, `BYLINE`, `DATE` are all optional — omit any and the layout closes up.
   - Wrap the quote in curly quotes `“ ”` yourself.

5. **Look at the output(s) and fix them.** Open `card-floating.png`/`card-matted.png`
   (or `card.png` if only one style was requested), read them back. Check:
   - Quote is the loudest thing and fully on-frame (not clipped).
   - Every line legible: for `floating`, if a busy image bleeds through, raise the panel
     opacity (`rgba(20,16,11,0.86)` → higher); for `matted`, check the quote fills the
     space between photo and byline without crowding.
   - Favicon crisp, byline present, colors contrast the image.
   Then edit `compose.sh` (panel opacity, box size, accent) and re-run until it looks
   right. *Only then* show the user.

## Requirements
- **ImageMagick 7** (`magick`) and **awk**.
- **Fonts**: none required. Type falls back to clean system faces (Georgia and
  Helvetica/Arial on macOS, DejaVu/Liberation on Linux). To use your own brand
  fonts, set them in the style guide (see First run).

## Notes
- The quote auto-fits its box via ImageMagick's `caption:` — a short quote comes out big,
  a long one shrinks to fit. In matted, the quote grows to fill the gap between the photo
  and the metadata.
- Sites that block scraping (login wall / JS shell): ask the user for the
  title/quote/author, but still grab `og:image` for the background.
- Bad hero (404 or tiny): check `file hero.jpg`; fall back to `twitter:image` or ask.
