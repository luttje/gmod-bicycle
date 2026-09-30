#!/bin/bash

# This script packs the addon with gmad and publishes it to the workshop with gmpublish.
# This script is only intended to be run on Windows (Git Bash), by luttje (or someone else with contributor access to
# the workshop item).
#
# 1.    Optionally set the path to the garrysmod bin directory in tools/.env (see tools/.env.example). When not set, the
#       bin directory of the Garry's Mod install this addon lives in is used.
#
# 2.    Run this script with the update message as the first argument, e.g:
#       ./tools/update-workshop.sh "Fixed wheelies"
#
#       If WORKSHOP_ID below is still empty, a new workshop item is created instead (using tools/icon.jpg, a 512x512
#       JPG). Put the ID it prints into WORKSHOP_ID afterwards.
#
# Add --dry-run flag to only build the .gma and see what publish command would be executed:
#       ./tools/update-workshop.sh "Fixed wheelies" --dry-run

WORKSHOP_ID="3810718443"

SCRIPT_BASEDIR=$(cd "$(dirname "$0")" && pwd)
ADDON_DIR=$(cd "$SCRIPT_BASEDIR/.." && pwd)
CONFIG_FILE="$SCRIPT_BASEDIR/.env"
BUILD_DIR="$SCRIPT_BASEDIR/build"
GMA_FILE="$BUILD_DIR/bicycle.gma"
ICON_FILE="$SCRIPT_BASEDIR/icon.jpg"

DRY_RUN=false
UPDATE_MESSAGE=""
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [ -z "$UPDATE_MESSAGE" ]; then
        UPDATE_MESSAGE="$arg"
    fi
done

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN MODE - Publish command will not be executed"
    echo "==================================================="
fi

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Fall back to the bin directory of the Garry's Mod install this addon is in (garrysmod/addons/bicycle -> bin)
if [ -z "$GM_BIN_PATH" ]; then
    GM_BIN_PATH="$ADDON_DIR/../../../bin"
fi

if [ ! -f "$GM_BIN_PATH/gmad.exe" ] || [ ! -f "$GM_BIN_PATH/gmpublish.exe" ]; then
    echo "Error: gmad.exe and gmpublish.exe not found in $GM_BIN_PATH"
    echo "Set GM_BIN_PATH in $CONFIG_FILE (see .env.example)"
    exit 1
fi

if [ -z "$WORKSHOP_ID" ] && [ ! -f "$ICON_FILE" ]; then
    echo "Error: WORKSHOP_ID is empty, so a new workshop item would be created, but that requires an icon at $ICON_FILE"
    exit 1
fi

if [ -z "$UPDATE_MESSAGE" ] && [ -n "$WORKSHOP_ID" ]; then
    echo "Error: Update message required as first argument"
    exit 1
fi

# Create the GMA file
echo "Creating GMA file..."
mkdir -p "$BUILD_DIR"
rm -f "$GMA_FILE"

if ! "$GM_BIN_PATH/gmad.exe" create -folder "$ADDON_DIR" -out "$GMA_FILE"; then
    echo "Error: gmad failed. If it complained about files not on the allowlist, add them to \"ignore\" in addon.json"
    exit 1
fi

if [ -n "$WORKSHOP_ID" ]; then
    PUBLISH_CMD=("$GM_BIN_PATH/gmpublish.exe" update -id "$WORKSHOP_ID" -addon "$GMA_FILE" -changes "$UPDATE_MESSAGE")
else
    PUBLISH_CMD=("$GM_BIN_PATH/gmpublish.exe" create -addon "$GMA_FILE" -icon "$ICON_FILE")
fi

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN MODE - The following publish command would be executed:"
    echo "============================================================="
    printf '"%s" ' "${PUBLISH_CMD[@]}"
    echo ""
    echo ""
    echo "DRY RUN COMPLETE - GMA file created at $GMA_FILE but not published"
else
    echo "Publishing to workshop..."
    if ! "${PUBLISH_CMD[@]}"; then
        echo "Error: gmpublish failed (is Steam running and are you logged in?)"
        exit 1
    fi

    if [ -z "$WORKSHOP_ID" ]; then
        echo "Workshop item created! Put the ID printed above into WORKSHOP_ID in $0 and the README."
    else
        echo "Workshop update completed!"
    fi
fi
