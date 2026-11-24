#!/bin/sh
# Launch the game without pulling focus. Godot makes itself the front app on
# macOS as its window opens (even via `open -g`), so this hands focus straight
# back to whatever was in front. Extra arguments go to Godot.
#   tools/launch_quiet.sh > log.txt 2>&1
cd "$(dirname "$0")/.." || exit 1
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
