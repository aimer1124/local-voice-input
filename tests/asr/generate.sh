#!/bin/bash
# Regenerate WAV samples from the .txt scripts using macOS `say` TTS.
# Result: tests/asr/samples/*.wav (gitignored, regenerable on any Mac).
#
# Sample shape: 16kHz mono 16-bit PCM — same as what whisper-cli expects after
# our SoX preprocessing. We use `say -o foo.aiff` then sox-convert to wav, so
# the test signal mirrors a clean mic capture (no rec/SoX in the loop).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLES="$DIR/samples"
MANIFEST="$SAMPLES/manifest.tsv"

[ -f "$MANIFEST" ] || { echo "missing manifest: $MANIFEST" >&2; exit 1; }

while IFS=$'\t' read -r id voice rate post_fx _cer _note; do
    [[ "$id" =~ ^# ]] && continue
    [ -z "$id" ] && continue
    txt="$SAMPLES/$id.txt"
    wav="$SAMPLES/$id.wav"
    aiff="$SAMPLES/.$id.tmp.aiff"

    if [ "$post_fx" = "silence" ]; then
        sox -n -r 16000 -c 1 -b 16 "$wav" trim 0 1.0
        echo "✓ $id  (silence 1s)"
        continue
    fi

    [ ! -f "$txt" ] && { echo "✗ $id  (no .txt)" >&2; continue; }

    say -v "$voice" -r "$rate" -o "$aiff" -f "$txt"
    sox "$aiff" -r 16000 -c 1 -b 16 "$wav.tmp.wav"

    case "$post_fx" in
        none) mv "$wav.tmp.wav" "$wav" ;;
        *)    sox "$wav.tmp.wav" "$wav" $post_fx
              rm -f "$wav.tmp.wav" ;;
    esac
    rm -f "$aiff"
    echo "✓ $id  (voice=$voice rate=$rate fx=$post_fx)"
done < "$MANIFEST"

echo ""
echo "Done. ${SAMPLES}/*.wav regenerated."
