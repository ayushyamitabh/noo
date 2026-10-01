# Noo website

The product site for Noo, meant to be deployed at `noo.ayushya.dev`.

Static HTML/CSS/vanilla JS, no build step and no dependencies beyond the
two Google Fonts already used by the app (Schibsted Grotesk, Instrument
Sans). Colors, radii, type scale and motion timing are copied from
`lib/theme/design_tokens.dart` so the site and the app read as the same
product.

## Files

- `index.html` — the whole page (hero, features, customize, privacy, CTA).
- `styles.css` — all styling, incl. the design tokens as CSS custom
  properties and a dark-mode variant (`prefers-color-scheme` and an
  explicit `data-theme` override for a future toggle).
- `script.js` — mobile nav, the hero's exploded-layer parallax
  (scroll + pointer), the two interactive Customize demos (accent color,
  bottom bar style), and scroll-reveal.
- `favicon.svg`.

## Local preview

Any static file server works, e.g.:

```bash
cd website
python3 -m http.server 8000
```

Then open `http://localhost:8000`.

## Deploying

Point any static host (Cloudflare Pages, Netlify, GitHub Pages, or a
plain nginx `root`) at this folder - there's nothing to build. Update the
`https://github.com` placeholder links and the two "Download for..."
buttons in `index.html` once real release links exist.
