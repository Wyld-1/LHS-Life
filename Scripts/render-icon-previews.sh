#!/bin/zsh
# Re-renders the app-icon pictures shown in the icon picker (the first-open
# card and Settings → App Icon) from the Icon Composer files.
#
# The app can't load its own icons as images at runtime, so the picker shows
# rendered copies kept in Assets.xcassets. Run this after editing either
# .icon file, or the picker keeps showing the old artwork.
#
#   ./Scripts/render-icon-previews.sh

set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
ASSETS="LHS Life/Assets.xcassets"

render() {   # render <.icon name> <imageset name>
  local out="$ASSETS/$2.imageset/$2.png"
  "$ICTOOL" "$1.icon" --export-image --output-file "$out" \
    --platform iOS --rendition Default --width 60 --height 60 --scale 3 >/dev/null
  echo "Rendered $1 → $out"
}

render "LHS Life Icon"      IconPreviewClassic
render "LHS Life Halloween"    IconPreviewHalloween
render "LHS Life Thanksgiving" IconPreviewThanksgiving
render "LHS Life Christmas"    IconPreviewChristmas
render "LHS Life Easter"       IconPreviewEaster
