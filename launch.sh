#!/usr/bin/env bash
#
# One command to play Echoes in the Dark.
#
#   ./launch.sh             live: EmotiBit head + heart rate (starts the bridge, then the game)
#   ./launch.sh mouse       mouse only: no bridge, no headband
#   ./launch.sh calibrate   after moving the headband: its axis, then your gestures in game
#   ./launch.sh check       just check the setup, launch nothing
#
# Before live: EmotiBit on, EmotiBit Oscilloscope open and connected to it,
# and in the Oscilloscope's output list, OSC turned on (it sends to port 12345).
#
# Live play needs all of these at once, and if any one is off the game quietly
# falls back to the mouse:
#   1. the EmotiBit is streaming          2. the Oscilloscope's OSC output is on
#   3. the bridge listens on 12345        4. the bridge forwards to 8687
#   5. the game runs with --sensor=live, and nothing else holds port 8687
# This script does 3-5 and checks 1-2 by waiting for data before the game starts.
#
# Quitting the game also stops the bridge.

set -uo pipefail

ROOT="$HOME/Echoes-in-the-Dark"
GAME_DIR="$ROOT/Godot Prototyping/test"
BRIDGE_DIR="$ROOT/sensor_bridge"
GODOT="${GODOT:-/Applications/Godot 2.app/Contents/MacOS/Godot}"
PYTHON="$BRIDGE_DIR/.venv/bin/python"
EMOTIBIT_PORT=12345
GODOT_PORT=8687
LOG="$BRIDGE_DIR/bridge.log"
# Seconds to wait for EmotiBit data before starting the game anyway.
DATA_WAIT=20

MODE="${1:-live}"
BRIDGE_PID=""
MONITOR_PID=""

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }

cleanup() {
	[[ -n "$MONITOR_PID" ]] && kill "$MONITOR_PID" 2>/dev/null
	if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
		say "Stopping the bridge."
		kill "$BRIDGE_PID" 2>/dev/null
	fi
}
trap cleanup EXIT INT TERM

# Who is listening on a UDP port, as "command(pid)", or nothing. Sockets that
# only send to that port (the Oscilloscope sending to 12345) show as
# "local->remote" and don't count.
port_owner() {
	lsof -nP -iUDP:"$1" 2>/dev/null | awk 'NR > 1 && $NF !~ /->/ { print $1 "(" $2 ")" }' | sort -u | tr '\n' ' '
}

# A game instance (not the editor) already running would hold 8687.
running_games() {
	pgrep -f "Godot.*--path.*Prototyping/test" | while read -r pid; do
		ps -o command= -p "$pid" | grep -q -- "--editor" || echo "$pid"
	done
}

preflight() {
	local failed=0
	say "Checking the setup ($1)"
	if [[ -x "$GODOT" ]]; then ok "Godot: $GODOT"; else bad "Godot not found at $GODOT"; failed=1; fi
	if [[ -f "$GAME_DIR/project.godot" ]]; then ok "Game: $GAME_DIR"; else bad "No project.godot in $GAME_DIR"; failed=1; fi

	local games
	games="$(running_games)"
	if [[ -n "$games" ]]; then
		bad "A game is already running (pid $games). Quit it first: two games can't share port $GODOT_PORT."
		failed=1
	else
		ok "No other game running"
	fi

	if [[ "$1" != "mouse" ]]; then
		if [[ -x "$PYTHON" ]]; then
			ok "Bridge Python: $PYTHON ($("$PYTHON" --version 2>&1))"
		else
			bad "No venv at $BRIDGE_DIR/.venv. Create it once:"
			echo "         cd \"$BRIDGE_DIR\" && /opt/homebrew/bin/python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt"
			failed=1
		fi
		if [[ -f "$BRIDGE_DIR/nod_calibration.json" ]]; then
			ok "Nod calibration: $BRIDGE_DIR/nod_calibration.json"
		else
			warn "No nod calibration: head pitch and the river jump will guess. Run: ./launch.sh calibrate"
		fi
		local old_bridges
		old_bridges="$(pgrep -f "bridge.py" | tr '\n' ' ')"
		if [[ -n "$old_bridges" ]]; then
			warn "An old bridge is running (pid $old_bridges). It would hold port $EMOTIBIT_PORT; stopping it."
			[[ "$1" != "check" ]] && kill $old_bridges 2>/dev/null && sleep 0.5
		fi
		local owner
		owner="$(port_owner "$EMOTIBIT_PORT")"
		if [[ -n "$owner" && -z "$old_bridges" ]]; then
			bad "Port $EMOTIBIT_PORT is taken by $owner. Quit that, or the bridge can't hear the EmotiBit."
			failed=1
		fi
	fi

	local godot_owner
	godot_owner="$(port_owner "$GODOT_PORT")"
	if [[ -n "$godot_owner" ]]; then
		bad "Port $GODOT_PORT is taken by $godot_owner. The game won't get live data."
		failed=1
	else
		ok "Port $GODOT_PORT is free for the game"
	fi
	return $failed
}

# The bridge prints a status line every 2 s once EmotiBit packets arrive.
latest_status() { grep '^packets' "$LOG" 2>/dev/null | tail -1; }

start_bridge() {
	# Keep the last session's log, so a relaunch never wipes it.
	[[ -s "$LOG" ]] && mv "$LOG" "${LOG%.log}.prev.log"
	say "Starting the bridge: EmotiBit :$EMOTIBIT_PORT -> game :$GODOT_PORT (log: $LOG)"
	( cd "$BRIDGE_DIR" && exec "$PYTHON" -u bridge.py --listen-port "$EMOTIBIT_PORT" --godot-port "$GODOT_PORT" ) > "$LOG" 2>&1 &
	BRIDGE_PID=$!
	sleep 1
	if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
		bad "The bridge stopped straight away. Its output:"
		sed 's/^/         /' "$LOG"
		exit 1
	fi
	ok "Bridge running (pid $BRIDGE_PID)"

	say "Waiting up to ${DATA_WAIT}s for EmotiBit data..."
	local waited=0
	while (( waited < DATA_WAIT )); do
		local line
		line="$(latest_status)"
		if [[ -n "$line" ]]; then
			local imu
			imu="$(sed -E 's/.*imu ([0-9.]+) Hz.*/\1/' <<< "$line")"
			if awk -v r="$imu" 'BEGIN { exit !(r > 5) }'; then
				ok "EmotiBit data arriving: $line"
				return 0
			fi
		fi
		if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
			bad "The bridge stopped. Its output:"
			sed 's/^/         /' "$LOG"
			exit 1
		fi
		sleep 1
		waited=$((waited + 1))
	done
	bad "No EmotiBit data reached the bridge on port $EMOTIBIT_PORT. Check:"
	echo "         - the EmotiBit is on and the Oscilloscope shows live graphs"
	echo "         - Oscilloscope > output list: OSC is ticked"
	echo "         - the Oscilloscope's OSC port is $EMOTIBIT_PORT (oscOutputSettings.xml)"
	warn "Starting the game anyway: the mouse steers until data arrives, and the game prints when it does."
	return 1
}

# A one-line bridge status every 15 s while the game runs.
monitor_bridge() {
	while sleep 15; do
		kill -0 "$BRIDGE_PID" 2>/dev/null || { bad "bridge stopped (see $LOG)"; return; }
		local line
		line="$(latest_status)"
		printf '\033[36m[bridge]\033[0m %s\n' "${line:-no EmotiBit packets yet}"
	done
}

case "$MODE" in
	check)
		if preflight check; then say "All good."; else say "Fix the FAIL lines above."; exit 1; fi
		;;
	calibrate)
		preflight calibrate || exit 1
		say "Step 1 of 2, the headband: look straight ahead, then up, holding each still."
		( cd "$BRIDGE_DIR" && "$PYTHON" -u bridge.py --listen-port "$EMOTIBIT_PORT" --calibrate ) || exit 1
		say "Step 2 of 2, your gestures: the bat will ask for a nod, a jolt up, a headbutt and a shake."
		start_bridge
		"$GODOT" --path "$GAME_DIR" calibration.tscn -- --sensor=live
		;;
	mouse)
		preflight mouse || exit 1
		say "Starting the game with the mouse (no bridge)."
		"$GODOT" --path "$GAME_DIR" -- --sensor=mouse
		;;
	live)
		preflight live || exit 1
		start_bridge
		monitor_bridge &
		MONITOR_PID=$!
		say "Starting the game with --sensor=live. Watch for: 'SensorBridge: LIVE head data arriving from the bridge'."
		say "In game: C recenters the head, F10 shows which source is driving."
		"$GODOT" --path "$GAME_DIR" -- --sensor=live
		;;
	*)
		echo "Usage: ./launch.sh [live|mouse|calibrate|check]"
		exit 2
		;;
esac
