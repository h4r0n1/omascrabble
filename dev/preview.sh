#!/bin/bash
# Renders the game offscreen with the real Omarchy theme tokens and saves a PNG.
#
#   dev/preview.sh [scenario] [width] [height] [output.png]
#   scenarios: home setup start midgame pending narrow practice hvh challenge end settings stats joker exchange
#   env: PREVIEW_THEME=<omarchy theme name>  PREVIEW_APPEARANCE=omarchy|light|dark
#
# It runs a separate, short-lived Quickshell process on the offscreen platform:
# nothing is shown, the running omarchy-shell is not involved, and saves go to
# a temporary XDG_STATE_HOME. Needs the Omarchy shell sources (for qs.Commons).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
scenario="${1:-midgame}"
width="${2:-1180}"
height="${3:-860}"
output="${4:-${TMPDIR:-/tmp}/scrabble-preview-$scenario.png}"
shell_src="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

work="$(mktemp -d "${TMPDIR:-/tmp}/scrabble-preview.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config" "$work/state" "$work/data"
ln -s "$shell_src/Commons" "$work/config/Commons"
ln -s "$shell_src/Ui" "$work/config/Ui"
ln -s "$repo" "$work/config/plugin"
cp "$repo/dev/preview/shell.qml" "$work/config/shell.qml"
if [[ -n ${PREVIEW_DEFS:-} ]]; then
  mkdir -p "$work/data/omascrabble" && cp -r "$PREVIEW_DEFS" "$work/data/omascrabble/definitions"
fi
if [[ $scenario == corrupt ]]; then
  mkdir -p "$work/state/omascrabble"
  printf '{"format":"omascrabble-save","version":1,"gameId":"broken","bag":[1,1' > "$work/state/omascrabble/game.json"
fi

PREVIEW_SCENARIO="$scenario" PREVIEW_OUTPUT="$output" PREVIEW_WIDTH="$width" PREVIEW_HEIGHT="$height" \
PREVIEW_PLUGIN="$repo" PREVIEW_HC="${PREVIEW_HC:-}" PREVIEW_LANG="${PREVIEW_LANG:-}" PREVIEW_GAMELANG="${PREVIEW_GAMELANG:-}" XDG_STATE_HOME="$work/state" XDG_DATA_HOME="$work/data" \
QT_QPA_PLATFORM=offscreen timeout 60 quickshell -p "$work/config" 2>&1 \
  | grep -v -e "WAYLAND_DISPLAY" -e "QT_QPA_PLATFORM" -e "actually running" -e "--- WARNING" -e "window masks" || true

[[ $scenario == corrupt ]] && ls "$work/state/omascrabble/quarantine" 2>/dev/null | sed 's/^/quarantined: /'
[[ -f $output ]] && echo "$output"
