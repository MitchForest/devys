/** A sample business's small static website, as a repository in its folder (no remote). */
export const sampleSite = {
  name: "acme-site",
  files: {
    "index.html": `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Acme Roasters</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <main>
      <h1>Fresh coffee from Acme Roasters</h1>
      <p>Small-batch beans, roasted in town and sold online and to our neighbourhood cafes.</p>
      <a href="mailto:hello@acmeroasters-sample.com">Order beans</a>
    </main>
  </body>
</html>
`,
    "style.css": `body { font-family: system-ui, sans-serif; margin: 0; background: #f7f2ec; color: #2b1d14; }
main { max-width: 640px; margin: 15vh auto; padding: 0 16px; }
h1 { font-size: 2.5rem; }
a { color: #8a4b20; }
`,
    "README.md": `# Acme Roasters website

A static site: open index.html in a browser. No build step.
`,
  },
};
