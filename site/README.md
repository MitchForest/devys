# Devys marketing site

A static site: `index.html`, `styles.css` and three ES modules in `js/`. No build step.

- `js/face.js` is a generated copy of the Face renderer, which the web app owns at
  `src/web/design/face-renderer.js`. Edit the original, then run `bun run site:sync`;
  `tests/site.test.ts` fails while the copy is stale. Add further shared files to
  `tests/site-copies.ts`.
- `js/ascii.js` draws the ASCII shader backgrounds: the chaos-to-calm journey, the
  sunrise over the sea and the manifesto's water. All three are pinned scroll sections.
- `styles.css` mirrors the native tokens in `DevysDesignSystem`; `tests/design-tokens.test.ts`
  fails if its `:root` or `.scope-dark` colors drift from `DevysColors.swift`.

Preview locally:

```sh
cd site && python3 -m http.server 4321
```

The site uses no photography: backgrounds are aurora glows and ASCII fields.
`scripts/generate-images.ts` can generate Higgsfield imagery if a section ever needs it
(copy `.env.example` to `.env.local` and add `HIGGSFIELD_API_KEY`).
