#!/bin/bash
# Run the ASR regression suite.
#
# For each entry in samples/manifest.tsv:
#   1. Ensure samples/<id>.wav exists (regenerate via generate.sh if missing).
#   2. Feed it to vinput_bg.sh --test-transcribe (raw Whisper output).
#   3. Compute CER against samples/<id>.txt (the reference text).
#   4. Compare CER against the cer_max budget from the manifest.
#
# Exit non-zero if any sample exceeds budget. Prints a table at the end.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
SAMPLES="$DIR/samples"
BG="$ROOT/bin/vinput_bg.sh"
CER="$DIR/cer.py"
MANIFEST="$SAMPLES/manifest.tsv"

[ -x "$BG" ] || { echo "missing $BG"; exit 1; }
[ -f "$MANIFEST" ] || { echo "missing $MANIFEST"; exit 1; }

NEED_GENERATE=0
while IFS=$'\t' read -r id _v _r _fx _c _n; do
    [[ "$id" =~ ^# ]] && continue
    [ -z "$id" ] && continue
    [ ! -f "$SAMPLES/$id.wav" ] && NEED_GENERATE=1
done < "$MANIFEST"

if [ "$NEED_GENERATE" = "1" ]; then
    echo "▶ Some WAVs missing — regenerating via generate.sh..."
    bash "$DIR/generate.sh"
    echo ""
fi

# Sandbox: don't pollute the user's vinput recent-context cache during testing.
export RECENT_PROMPT_FILE="$(mktemp -t vinput-test-recent.XXXXXX)"
trap 'rm -f "$RECENT_PROMPT_FILE"' EXIT

FAIL=0
RESULTS=()
RESULTS+=("ID|CER|BUDGET|VERDICT|HYP")

while IFS=$'\t' read -r id voice rate fx cer_max note; do
    [[ "$id" =~ ^# ]] && continue
    [ -z "$id" ] && continue
    wav="$SAMPLES/$id.wav"
    ref="$SAMPLES/$id.txt"

    if [ ! -f "$wav" ]; then
        RESULTS+=("$id|-|$cer_max|MISSING_WAV|-")
        FAIL=1
        continue
    fi

    hyp=$(bash "$BG" --test-transcribe "$wav" 2>/dev/null)
    cer_val=$(python3 "$CER" --ref-string "$(cat "$ref")" "$hyp" 2>/dev/null || echo "ERR")

    if [ "$cer_val" = "ERR" ]; then
        RESULTS+=("$id|ERR|$cer_max|ERR|$hyp")
        FAIL=1
        continue
    fi

    verdict=$(awk -v c="$cer_val" -v m="$cer_max" 'BEGIN{print (c+0 <= m+0) ? "PASS" : "FAIL"}')
    [ "$verdict" = "FAIL" ] && FAIL=1
    # Truncate hyp to one line for the table.
    hyp_short=$(printf '%s' "$hyp" | tr '\n' ' ' | cut -c1-40)
    RESULTS+=("$id|$cer_val|$cer_max|$verdict|$hyp_short")
done < "$MANIFEST"

echo ""
printf '%s\n' "${RESULTS[@]}" | column -t -s '|'
echo ""

if [ "$FAIL" = "0" ]; then
    echo "✓ All samples within budget."
    exit 0
else
    echo "✗ Regression failed — see table above."
    exit 1
fi
