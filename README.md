# liftout

A Claude Code plugin that turns an **article URL** into a polished, editorial **share card**: the piece's own hero image, the single sharpest quote pulled from the body set as the dominant element, and colors that adapt to the image. It renders live with ImageMagick and looks at the result before handing it over, instead of stamping content into a fixed template.

## Installation

```
claude plugin marketplace add benjaminjackson/liftout
claude plugin install liftout@liftout
```

Requires **ImageMagick 7** (`magick`) and **awk**. No fonts are bundled: type falls back to clean system faces (Georgia and Helvetica on macOS, DejaVu and Liberation on Linux). To use your own brand fonts and accent colors, set them in a style guide the skill offers to create on first run (`~/.config/liftout/style.conf`).

## liftout

Paste a link. The skill scrapes the article, pulls the quote most worth sharing, and composes a card built around it, in one of two styles, at the aspect ratio you want.

The reason this is a skill and not a one-shot script: every article is different. A six-word pull-quote and a sixty-word one need different type sizes; a busy light image and a moody dark one need opposite color treatments. So liftout composes each card live and then reads the render back to fix what a blind script would miss.

### How it works

Five steps, and the last one is the point.

1. **Scrape.** `curl` the page and lift the OpenGraph tags: `og:title`, `og:image` (the hero), `og:site_name` (the outlet), `name="author"` (the byline), and `article:published_time` (the date), plus the largest `apple-touch-icon` for the favicon, falling back to Google's favicon service.

2. **Pull the quote.** This is why a person or an LLM does this instead of a script. It reads the body and picks the one line that is punchy, self-contained, and makes someone want to click. Not `og:description`, the genuinely best *sentence in the piece*. It keeps the author's words and trims only lightly. Hand it a quote and it uses yours verbatim.

3. **Download** the hero image and favicon locally, so the render never races a network fetch.

4. **Compose** with ImageMagick. The quote is set with `caption:`, which auto-fits the type to its box: a short quote comes out big, a long one shrinks to fit. In the matted style the quote grows to fill the gap between the photo and the byline.

5. **Look at it and fix it.** It opens `card.png`, reads it back, and checks that the quote is the loudest thing and fully on-frame, the text contrasts the image, the favicon is crisp, and the byline is present. Then it edits the recipe and re-renders until it is right. A rigid renderer cannot see a clipped byline or text lost against a light background. An agent looking at its own output can.

### Two styles

- **floating**: an opaque, rounded card with a soft drop shadow, centered over the full-brightness image, with the quote inside it. Immersive, you are *in* the image. The date rides on top as a small accent kicker, the title sits under the quote.
- **matted**: a gallery mat whose tone matches the image, with the hero inset as a small framed print and the quote below it, sized to fill the space. Reverent, the image becomes an artifact on a page. The date joins the byline.

They were curated down from a ten-treatment exploration (magazine cover, duotone, split-screen, newsprint halftone, and others). These two won because they give the quote a clean surface to read against while keeping the image intact. The others either fought the artwork or threw it away.

### Colors adapt to the image

The script measures the hero's brightness and flips the surface and text so they always contrast. A light image gets a dark surface with light text; a dark image gets the reverse. The accent goes gold on a dark surface, crimson on a light one. The favicon always leads the outlet name, in both styles.

### Formats

Portrait `1080x1350` (default, the Instagram 4:5 size), square `1080x1080`, or landscape `1200x630` for OG and Twitter cards. Floating handles all three. Matted is happiest in portrait and square: landscape leaves too little height for a framed photo and a large quote, so reach for floating there.

### Usage

- **Explicitly:** `/liftout:create <article-url> [portrait|square|landscape]`
- **Automatically:** on phrases like "make a share card from this," "turn this article into a quote card," or "social graphic for this link."

It asks which style if you don't say, defaults to portrait, and pulls the quote itself unless you hand it one.

See [`docs/SPEC.md`](docs/SPEC.md) for the full design, the ImageMagick recipe, and the reference example the skill was built against.

## Author

Benjamin Jackson ([@benjaminjackson](https://github.com/benjaminjackson))
