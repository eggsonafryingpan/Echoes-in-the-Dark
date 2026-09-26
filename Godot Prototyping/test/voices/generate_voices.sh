#!/usr/bin/env bash
#
# Re-render the bat companion's voice from lines.txt.
#
# Safe to run any time. Every run fully re-syncs the clip folder to
# lines.txt: lines that changed are re-rendered, new lines appear, and
# clips whose id is no longer in lines.txt are deleted. Nothing is left
# orphaned, so you never hand-delete a file after renaming a line.
#
# The game addresses clips by id alone, so editing wording here needs zero
# code and zero scene changes -- edit the text, re-run this, done.
#
#   ./generate_voices.sh              render with the Superstar voice
#   VOICE=Samantha ./generate_voices.sh   use a different macOS voice
#
# Output format depends on what is installed: mp3 if ffmpeg or lame is
# present, otherwise 16-bit wav via afconvert, which ships with macOS. The
# game accepts any of them and looks the clip up by id either way, so the
# fallback needs no action from you -- install ffmpeg only if you want the
# smaller files.

set -euo pipefail

VOICE="${VOICE:-Superstar}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINES_FILE="$HERE/lines.txt"
OUT_DIR="$HERE/../assets/sfx/voice"

if [[ ! -f "$LINES_FILE" ]]; then
	echo "ERROR: no lines.txt beside this script ($LINES_FILE)" >&2
	exit 1
fi

if ! command -v say >/dev/null 2>&1; then
	echo "ERROR: 'say' not found -- this renderer is macOS-only." >&2
	exit 1
fi

if ! say -v '?' | grep -q "^${VOICE}[[:space:]]"; then
	echo "ERROR: voice '$VOICE' is not installed." >&2
	echo "       Install it in System Settings > Accessibility > Spoken Content," >&2
	echo "       or pick another: say -v '?'" >&2
	exit 1
fi

# Pick the best encoder available rather than hard-failing on a missing one.
if command -v ffmpeg >/dev/null 2>&1; then
	ENCODER=ffmpeg
	EXT=mp3
elif command -v lame >/dev/null 2>&1; then
	ENCODER=lame
	EXT=mp3
else
	ENCODER=afconvert
	EXT=wav
fi

encode() {  # $1 = source .aiff, $2 = destination
	case "$ENCODER" in
		ffmpeg)    ffmpeg -loglevel error -y -i "$1" -codec:a libmp3lame -q:a 4 "$2" ;;
		lame)      lame --quiet -V 4 "$1" "$2" ;;
		afconvert) afconvert -f WAVE -d LEI16 "$1" "$2" ;;
	esac
}

trim() {  # strip leading and trailing whitespace
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

mkdir -p "$OUT_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "voice:   $VOICE"
echo "encoder: $ENCODER -> .$EXT"
echo "output:  $OUT_DIR"
echo

declare -a IDS=()
LINE_NO=0

while IFS= read -r raw || [[ -n "$raw" ]]; do
	LINE_NO=$((LINE_NO + 1))
	line="${raw%$'\r'}"                       # tolerate CRLF
	[[ -z "$(trim "$line")" ]] && continue
	[[ "$(trim "$line")" == \#* ]] && continue

	if [[ "$line" != *"|"* ]]; then
		echo "ERROR: line $LINE_NO has no '|' separator: $line" >&2
		exit 1
	fi

	id="$(trim "${line%%|*}")"
	text="$(trim "${line#*|}")"

	if ! [[ "$id" =~ ^[a-z0-9_]+$ ]]; then
		echo "ERROR: line $LINE_NO: invalid id '$id' (lowercase, digits, underscore)" >&2
		exit 1
	fi
	if [[ -z "$text" ]]; then
		echo "ERROR: line $LINE_NO: id '$id' has no text" >&2
		exit 1
	fi
	for existing in ${IDS[@]+"${IDS[@]}"}; do
		if [[ "$existing" == "$id" ]]; then
			echo "ERROR: line $LINE_NO: duplicate id '$id'" >&2
			exit 1
		fi
	done

	# </dev/null so `say` can never consume the lines.txt we are reading.
	say -v "$VOICE" "$text" -o "$TMP_DIR/$id.aiff" </dev/null
	encode "$TMP_DIR/$id.aiff" "$OUT_DIR/$id.$EXT"
	IDS+=("$id")
	echo "  rendered $id.$EXT"
done < "$LINES_FILE"

# Prune: anything in the folder that lines.txt no longer claims. This also
# clears a stale clip in the other format when the encoder changes, so one
# id can never end up with two files racing to be found first.
shopt -s nullglob
for path in "$OUT_DIR"/*.mp3 "$OUT_DIR"/*.wav "$OUT_DIR"/*.ogg "$OUT_DIR"/*.aiff; do
	base="$(basename "$path")"
	file_id="${base%.*}"
	file_ext="${base##*.}"
	keep=0
	for id in ${IDS[@]+"${IDS[@]}"}; do
		if [[ "$id" == "$file_id" && "$file_ext" == "$EXT" ]]; then
			keep=1
			break
		fi
	done
	if (( keep == 0 )); then
		rm -f "$path" "$path.import"
		echo "  pruned   $base"
	fi
done

echo
echo "${#IDS[@]} line(s) in sync."
