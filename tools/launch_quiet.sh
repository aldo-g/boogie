#!/bin/sh
# Launch the game without pulling focus. Godot makes itself the front app on
# macOS as its window opens (even via `open -g`), so this hands focus straight
# back to whatever was in front. Extra arguments go to Godot.
#   tools/launch_quiet.sh > log.txt 2>&1
cd "$(dirname "$0")/.." || exit 1
# Switched off for now (2026-11-25). Godot 4.7 makes itself the front app
# whenever its main window is shown, and no setting, flag or window mode
# stops it; handing focus back afterwards still takes the person at this
# Mac off their work for a moment, every launch. While tools/NO_WINDOWS
# exists nothing is launched here. Delete that file to turn windows back
# on, or set WINDOW=1 for a single run. Headless runs (--headless: every
# test script and BotSim) never take focus and don't come through here.
if [ -e tools/NO_WINDOWS ] && [ "$WINDOW" != "1" ]; then
	echo "launch_quiet: windowed Godot is switched off (tools/NO_WINDOWS). Nothing launched." >&2
	echo "launch_quiet: delete tools/NO_WINDOWS, or run with WINDOW=1, to open a window." >&2
	exit 3
fi
front=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true')
/Applications/Godot.app/Contents/MacOS/Godot --path . "$@" &
pid=$!
# Godot can take focus more than once while it starts up, so watch for a few seconds.
i=0
while [ $i -lt 40 ]; do
	sleep 0.25
	now=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true')
	if [ "$now" = "$pid" ] && [ "$front" != "$pid" ]; then
		osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $front) to true"
	fi
	i=$((i + 1))
done
echo "Godot running, pid $pid"
