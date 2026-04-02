# Bundled Artwork

This directory contains public domain artwork used for ASCII art welcome tabs.

## Downloading Artwork

Run the download script from the repository root:

```bash
chmod +x scripts/download-artwork.sh
./scripts/download-artwork.sh
```

## Included Artwork

| Filename | Title | Artist | Year |
|----------|-------|--------|------|
| great-wave.jpg | The Great Wave off Kanagawa | Katsushika Hokusai | 1831 |
| starry-night.jpg | The Starry Night | Vincent van Gogh | 1889 |
| mona-lisa.jpg | Mona Lisa | Leonardo da Vinci | 1503 |
| persistence-memory.jpg | The Persistence of Memory | Salvador Dalí | 1931 |
| girl-pearl-earring.jpg | Girl with a Pearl Earring | Johannes Vermeer | 1665 |
| the-scream.jpg | The Scream | Edvard Munch | 1893 |
| creation-adam.jpg | The Creation of Adam | Michelangelo | 1512 |
| wanderer-fog.jpg | Wanderer Above the Sea of Fog | Caspar David Friedrich | 1818 |
| vitruvian-man.jpg | Vitruvian Man | Leonardo da Vinci | 1490 |
| birth-venus.jpg | The Birth of Venus | Sandro Botticelli | 1485 |

## License

All artwork is in the public domain (created before 1928 or explicitly released).
Images are sourced from Wikimedia Commons.

## Adding New Artwork

1. Ensure the artwork is in the public domain
2. Add the image to this directory
3. Update `BundledArtworkCatalog` in `WelcomeImage.swift`
4. Run the build
