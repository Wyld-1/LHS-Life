#!/bin/zsh
# Renders the app-icon pictures shown in the icon picker (the holiday card
# and Settings → App Icon) from the Icon Composer files.
#
# The app can't load its own icons as images: Xcode compiles .icon files
# into a format UIImage(named:) can't read. So the picker shows rendered
# copies kept in IconPreviews.xcassets: a catalog of
# their own, because Assets.xcassets is shared with the widget extension and
# writing to it from the app's build would make the two targets depend on
# each other.
#
# Runs automatically as the "Render Icon Previews" build phase, before the
# asset catalog compiles, and only re-renders an icon whose .icon file
# changed since its preview was made. Run it by hand to force all of them:
#
#   ./Scripts/render-icon-previews.sh --all
#
# ADDING A HOLIDAY: add a line to ICONS below, and add the .icon folder and
# its preview PNG to the build phase's input and output files.

set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=(
  "LHS Life Icon:IconPreviewClassic"
  "LHS Life Halloween:IconPreviewHalloween"
  "LHS Life Thanksgiving:IconPreviewThanksgiving"
  "LHS Life Christmas:IconPreviewChristmas"
  "LHS Life Easter:IconPreviewEaster"
)

# Xcode's own copy of Icon Composer: the one building the app.
DEV="${DEVELOPER_DIR:-$(xcode-select -p)}"
ICTOOL="$DEV/../Applications/Icon Composer.app/Contents/Executables/ictool"
ASSETS="LHS Life/IconPreviews.xcassets"

for pair in "${ICONS[@]}"; do
  icon="${pair%%:*}"; set="${pair#*:}"
  out="$ASSETS/$set.imageset/$set.png"
  # Up to date: a preview exists and nothing in the .icon is newer.
  if [[ "${1:-}" != "--all" && -f "$out" && -z "$(find "$icon.icon" -newer "$out" -print -quit)" ]]; then
    continue
  fi
  "$ICTOOL" "$icon.icon" --export-image --output-file "$out" \
    --platform iOS --rendition Default --width 60 --height 60 --scale 3 >/dev/null
  echo "Rendered $icon → $out"
done
