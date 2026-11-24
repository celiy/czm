#!/usr/bin/env bash
# Install czm mods into the Project Zomboid mods folder.
#
#   ./install.sh <mod> [<mod> ...]   install the given mods
#   ./install.sh --list              list available mods
#   ./install.sh --dest <dir> ...    use a specific mods folder
#   ./install.sh --workshop <mod>    stage for Workshop upload instead
#                                    (~/Zomboid/Workshop/<folder>/)
#
# A <mod> is either a repo folder name (Gasoline_Degradation) or a mod id
# (GasolineDegradation). If the mod already exists in the game's mods folder
# (folder or symlink) it is deleted and replaced by the repo version.
# Files are copied, not moved, so the repo stays intact.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${PZ_MODS_DIR:-}"
WORKSHOP=0

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Prints "<repo folder>|<mod id>|<path>" for every mod in the repo.
list_mods() {
    local src
    for src in "$REPO"/*/Contents/mods/*/; do
        [ -d "$src" ] || continue
        src="${src%/}"
        printf '%s|%s|%s\n' "$(basename "$(dirname "$(dirname "$(dirname "$src")")")")" "$(basename "$src")" "$src"
    done
}

find_mods_dir() {
    local c
    if [ -n "$DEST" ]; then echo "$DEST"; return; fi
    for c in "${ZOMBOID_USER_DIR:-}" "$HOME/Zomboid" "${USERPROFILE:-}/Zomboid" "$HOME/.local/share/Zomboid"; do
        [ -n "$c" ] && [ -d "$c/mods" ] && { echo "$c/mods"; return; }
    done
    return 1
}

MODS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list) list_mods | awk -F'|' '{printf "%s  (mod id: %s)\n", $1, $2}'; exit 0 ;;
        --workshop) WORKSHOP=1 ;;
        --dest) [ $# -ge 2 ] || { echo "--dest needs a folder" >&2; exit 1; }; DEST="$2"; shift ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *) MODS+=("$1") ;;
    esac
    shift
done

if [ ${#MODS[@]} -eq 0 ]; then usage >&2; echo >&2; echo "Available mods:" >&2; list_mods | awk -F'|' '{print "  " $1}' >&2; exit 1; fi

MODS_DIR="$(find_mods_dir)" || { echo "Could not find the Zomboid mods folder. Use --dest <dir> or set PZ_MODS_DIR." >&2; exit 1; }
if [ "$WORKSHOP" -eq 1 ]; then
    # Workshop items live next to the mods folder, unless --dest was given.
    [ -n "$DEST" ] || MODS_DIR="$(dirname "$MODS_DIR")/Workshop"
    echo "Workshop folder: $MODS_DIR"
else
    echo "Mods folder: $MODS_DIR"
fi
mkdir -p "$MODS_DIR"

for name in "${MODS[@]}"; do
    line="$(list_mods | awk -F'|' -v n="$name" '$1==n || $2==n {print; exit}')"
    if [ -z "$line" ]; then echo "Unknown mod: $name (see --list)" >&2; exit 1; fi
    folder="$(echo "$line" | cut -d'|' -f1)"
    id="$(echo "$line" | cut -d'|' -f2)"
    src="$(echo "$line" | cut -d'|' -f3)"

    [ -n "$id" ] && [ -n "$folder" ] || { echo "Empty mod name, aborting" >&2; exit 1; }

    if [ "$WORKSHOP" -eq 1 ]; then
        # Whole item: workshop.txt, preview.png and Contents/.
        target="$MODS_DIR/$folder"
        src="$REPO/$folder"
        [ -f "$src/workshop.txt" ] && [ -f "$src/preview.png" ] || { echo "$folder is missing workshop.txt or preview.png" >&2; exit 1; }
        # The game writes id=<number> into workshop.txt on the first upload;
        # keep it when replacing, or the next upload would create a new item.
        old_id=""
        [ -f "$target/workshop.txt" ] && old_id="$(grep -m1 '^id=' "$target/workshop.txt" || true)"
    else
        target="$MODS_DIR/$id"
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf -- "$target" # no trailing slash: a symlink is removed, not followed
        echo "Removed existing $target"
    fi
    if [ "$WORKSHOP" -eq 1 ]; then
        mkdir -p "$target"
        cp -r -- "$src/workshop.txt" "$src/preview.png" "$src/Contents" "$target/"
    else
        cp -r -- "$src" "$target"
    fi
    if [ "$WORKSHOP" -eq 1 ] && [ -n "$old_id" ] && ! grep -q '^id=' "$target/workshop.txt"; then
        echo "$old_id" >> "$target/workshop.txt"
        echo "Kept $old_id from the previous workshop.txt"
    fi
    echo "Installed $folder -> $target"
done
