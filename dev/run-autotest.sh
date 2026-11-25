#!/usr/bin/env bash
# Run the in-game auto test (CZMAutoTest) in an isolated Zomboid profile.
#
#   dev/run-autotest.sh            run and print the results
#   PZ_DIR=<install dir> ...       if the game is not found automatically
#   CZM_TEST_TIMEOUT=900 ...       seconds before giving up (default 600)
#
# It never touches your saves or settings: the game is started with its own
# cache folder (default ~/.cache/czm-pz-test) holding copies of the czm mods
# and the test harness. A game window opens on your screen and closes by
# itself when the tests finish. Exit code 0 only if every check passed.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${CZM_TEST_CACHE:-$HOME/.cache/czm-pz-test}"
TIMEOUT="${CZM_TEST_TIMEOUT:-600}"

find_game() {
    local c
    for c in "${PZ_DIR:-}" \
             "$HOME/.local/share/Steam/steamapps/common/ProjectZomboid" \
             "$HOME/.steam/steam/steamapps/common/ProjectZomboid" \
             /mnt/*/SteamLibrary/steamapps/common/ProjectZomboid; do
        [ -n "$c" ] && [ -x "$c/projectzomboid.sh" ] && { echo "$c"; return; }
    done
    return 1
}

# Never touch a game the player has open: only test instances are stopped here.
if pgrep -fa "[P]rojectZomboid64" | grep -v "cachedir=" | grep -q .; then
    echo "Your own Project Zomboid is open. Close it first; this test cannot run alongside it." >&2
    exit 3
fi
pgrep -f "[c]achedir=$HOME/.cache/czm-pz-test" | xargs -r kill 2>/dev/null || true
# Wait for every leftover process of an earlier test run (game, launcher, helpers).
for _ in $(seq 1 90); do pgrep -f "cachedir=$CACHE" >/dev/null || break; sleep 1; done
pgrep -f "cachedir=$CACHE" | xargs -r kill 2>/dev/null || true

GAME="$(find_game)" || { echo "Game not found. Set PZ_DIR to the ProjectZomboid install folder." >&2; exit 2; }

# Fresh isolated profile with the mods under test.
# Keep the profile between runs (it stores the Terms of Service acceptance);
# only the mods and the trigger file are refreshed.
rm -rf -- "$CACHE/mods" "$CACHE/Lua/czm_autotest.txt"
mkdir -p "$CACHE/mods" "$CACHE/Lua"
for src in "$REPO"/*/Contents/mods/*/ "$REPO"/dev/*/Contents/mods/*/; do
    [ -d "$src" ] || continue
    cp -r -- "${src%/}" "$CACHE/mods/"
done

cat > "$CACHE/mods/default.txt" <<'EOF'
VERSION = 1,

mods
{
    mod = GasolineDegradation,
    mod = PerishableFoods,
    mod = CZMAutoTest,
}

maps
{
}
EOF
# Without this file the game resets default.txt to "no mods" on startup.
printf '%s\n' 'If this file does not exist, default.txt will be reset to empty (no mods active).' > "$CACHE/mods/reset-mods-42_00.txt"
# Tutorial windows pause the game and stop the world from updating in tests.
OPTS="$CACHE/options.ini"
if [ -f "$OPTS" ]; then
    sed -i -e 's/^showSurvivalGuide=.*/showSurvivalGuide=false/' \
           -e 's/^showFirstTimeSearchTutorial=.*/showFirstTimeSearchTutorial=false/' \
           -e 's/^showFirstTimeSneakTutorial=.*/showFirstTimeSneakTutorial=false/' "$OPTS"
fi
printf 'world=%s\nmode=%s\napo=%s\n' "${CZM_TEST_WORLD:-czm-autotest}" "${CZM_TEST_MODE:-gasoline}" "${CZM_TEST_APO:-1}" > "$CACHE/Lua/czm_autotest.txt"

echo "Game:    $GAME"
echo "Profile: $CACHE"
echo "Starting the game (timeout ${TIMEOUT}s)..."

# A stale console from an earlier run must never be mistaken for this run's result.
rm -f "$CACHE/console.txt" "$CACHE/launcher.out"

"$GAME/projectzomboid.sh" -cachedir="$CACHE" >"$CACHE/launcher.out" 2>&1 &
PID=$!

LOG="$CACHE/console.txt"
elapsed=0
while kill -0 "$PID" 2>/dev/null; do
    if [ -f "$LOG" ] && grep -q '^\[CZM-TEST\] DONE\|CZM-TEST\] DONE' "$LOG" 2>/dev/null; then
        sleep 5 # let the game finish quitting
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        echo "Timed out after ${TIMEOUT}s; stopping the game." >&2
        pkill -P "$PID" 2>/dev/null || true
        kill "$PID" 2>/dev/null || true
        break
    fi
done
# The launcher script may exit before the game; make sure nothing is left running.
# Let the game and its launcher finish quitting, so the next run starts clean.
for _ in $(seq 1 60); do pgrep -f "cachedir=$CACHE" >/dev/null || break; sleep 1; done
pgrep -f "cachedir=$CACHE" | xargs -r kill 2>/dev/null || true

echo
if grep -q "Steam must be running" "$CACHE/launcher.out" 2>/dev/null; then
    echo "The game did not start: Steam is not running. Start Steam and run this again." >&2
    exit 4
fi
echo "---- results ----"
if [ ! -f "$LOG" ]; then echo "No console.txt was written; the game did not start." >&2; exit 2; fi
grep -h 'CZM-TEST\]' "$LOG" | sed 's/^.*\(\[CZM-TEST\]\)/\1/' || true
echo
echo "---- mod errors ----"
grep -hE "GasolineDegradation.*(attempt to|stack traceback|LuaError)|GD_(Core|World|Client|Access)\.lua" "$LOG" | head -20 || true

if grep -q 'CZM-TEST\] DONE pass=[0-9]* fail=0' "$LOG"; then
    echo "ALL PASSED"; exit 0
fi
echo "FAILED or incomplete" >&2
exit 1
