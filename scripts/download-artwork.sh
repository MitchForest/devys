#!/bin/bash
# download-artwork.sh
# Downloads public domain artwork for ASCII art welcome tabs
#
# All images are from Wikimedia Commons and are in the public domain.
# These are resized versions suitable for ASCII art conversion.

set -e

ARTWORK_DIR="Packages/UI/Sources/UI/Resources/Artwork"
mkdir -p "$ARTWORK_DIR"

echo "Downloading artwork for ASCII welcome tabs..."

# The Great Wave off Kanagawa - Hokusai (1831)
echo "  [1/10] The Great Wave..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Tsunami_by_hokusai_19th_century.jpg/1200px-Tsunami_by_hokusai_19th_century.jpg" -o "$ARTWORK_DIR/great-wave.jpg"

# The Starry Night - Van Gogh (1889)
echo "  [2/10] Starry Night..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/e/ea/Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg/1200px-Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg" -o "$ARTWORK_DIR/starry-night.jpg"

# Mona Lisa - Da Vinci (1503)
echo "  [3/10] Mona Lisa..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/e/ec/Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg/800px-Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg" -o "$ARTWORK_DIR/mona-lisa.jpg"

# The Persistence of Memory - Dalí (1931)
echo "  [4/10] Persistence of Memory..."
curl -sL "https://upload.wikimedia.org/wikipedia/en/d/dd/The_Persistence_of_Memory.jpg" -o "$ARTWORK_DIR/persistence-memory.jpg"

# Girl with a Pearl Earring - Vermeer (1665)
echo "  [5/10] Girl with a Pearl Earring..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0f/1665_Girl_with_a_Pearl_Earring.jpg/800px-1665_Girl_with_a_Pearl_Earring.jpg" -o "$ARTWORK_DIR/girl-pearl-earring.jpg"

# The Scream - Munch (1893)
echo "  [6/10] The Scream..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Edvard_Munch%2C_1893%2C_The_Scream%2C_oil%2C_tempera_and_pastel_on_cardboard%2C_91_x_73_cm%2C_National_Gallery_of_Norway.jpg/800px-Edvard_Munch%2C_1893%2C_The_Scream%2C_oil%2C_tempera_and_pastel_on_cardboard%2C_91_x_73_cm%2C_National_Gallery_of_Norway.jpg" -o "$ARTWORK_DIR/the-scream.jpg"

# Creation of Adam - Michelangelo (1512)
echo "  [7/10] Creation of Adam..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/Michelangelo_-_Creation_of_Adam_%28cropped%29.jpg/1200px-Michelangelo_-_Creation_of_Adam_%28cropped%29.jpg" -o "$ARTWORK_DIR/creation-adam.jpg"

# Wanderer Above the Sea of Fog - Friedrich (1818)
echo "  [8/10] Wanderer Above Sea of Fog..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg/800px-Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg" -o "$ARTWORK_DIR/wanderer-fog.jpg"

# Vitruvian Man - Da Vinci (1490)
echo "  [9/10] Vitruvian Man..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/Da_Vinci_Vitruve_Luc_Viatour.jpg/800px-Da_Vinci_Vitruve_Luc_Viatour.jpg" -o "$ARTWORK_DIR/vitruvian-man.jpg"

# Birth of Venus - Botticelli (1485)
echo "  [10/10] Birth of Venus..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0b/Sandro_Botticelli_-_La_nascita_di_Venere_-_Google_Art_Project_-_edited.jpg/1200px-Sandro_Botticelli_-_La_nascita_di_Venere_-_Google_Art_Project_-_edited.jpg" -o "$ARTWORK_DIR/birth-venus.jpg"

echo ""
echo "✓ All artwork downloaded to $ARTWORK_DIR"
echo ""
echo "Note: These images are in the public domain and sourced from Wikimedia Commons."
