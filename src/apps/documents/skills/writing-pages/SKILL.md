---
name: writing-pages
description: Write a page with artifactPage (a report, dashboard, comparison or plan) that renders offline on any screen, and change it with artifactEdit.
---

# Writing pages

A page is one self-contained HTML document the owner opens beside the conversation, on a
Mac, an iPad or a phone. It renders in a sandbox with no network, so everything it shows is
inside the HTML you pass to `artifactPage`.

## Rules the viewer enforces

- Inline only: CSS in `<style>`, JavaScript in `<script>`, images and fonts as `data:` URIs.
  Nothing is fetched: no CDNs, web fonts, remote images, `fetch` or links that load data.
- No forms, frames, `<object>`/`<embed>`, `<base>` or meta refresh. The page is refused.
- At most 512 KB. Keep data small: summarize, then show the rows that matter.

## Make it readable

- Start with the answer: a title, one or two sentences of conclusion, then the detail.
- Phone first: a centered column of at most 720px, 16px padding, 16px system-ui text,
  no fixed widths; a wide table sits in a container with `overflow-x: auto`.
- Support dark mode with `@media (prefers-color-scheme: dark)` and CSS variables.
- Draw charts with inline SVG or a few lines of script; label axes and values.
- Say where numbers came from and when; mark estimates as estimates.

## Versions

Change a page with `artifactEdit`: give the page's ref, an exact `find` string that appears
once in its HTML, and its `replace`. Each edit publishes the next version under the same
name, and the owner sees it update. Use `artifactPage` again only for a different page.
