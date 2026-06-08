#!/bin/bash
# Run the LLM cleanup regression suite.
#
# For each tests/llm/cases/<id>.input.txt:
#   1. POST to Ollama via vinput_bg.sh --test-llm-clean
#   2. Assert must_contain.txt lines are substrings of output (case-insensitive)
#   3. Assert must_not_contain.txt lines are NOT substrings
#   4. Print PASS/FAIL table
#
# Exit non-zero if any case fails any assertion.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
CASES="$DIR/cases"
BG="$ROOT/bin/vinput_bg.sh"

[ -x "$BG" ] || { echo "missing $BG"; exit 1; }
[ -d "$CASES" ] || { echo "missing $CASES"; exit 1; }

# Sandbox: don't pollute the user's recent-context cache.
export RECENT_PROMPT_FILE="$(mktemp -t vinput-llm-test-recent.XXXXXX)"
trap 'rm -f "$RECENT_PROMPT_FILE"' EXIT

FAIL=0
PER_CASE=()

contains_ci() {
    # Case-insensitive substring check (ASCII portion only).
    local haystack="$1" needle="$2"
    [ -z "$needle" ] && return 0
    case "$(printf '%s' "$haystack" | tr '[:upper:]' '[:lower:]')" in
        *"$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"*) return 0 ;;
    esac
    return 1
}

check_case() {
    local input="$1" must_yes="$2" must_no="$3"
    local out fails=()
    out=$(bash "$BG" --test-llm-clean "$input" 2>/dev/null)
    if [ -f "$must_yes" ]; then
        while IFS= read -r needle || [ -n "$needle" ]; do
            [ -z "$needle" ] && continue
            contains_ci "$out" "$needle" || fails+=("missing:\"$needle\"")
        done < "$must_yes"
    fi
    if [ -f "$must_no" ]; then
        while IFS= read -r needle || [ -n "$needle" ]; do
            [ -z "$needle" ] && continue
            contains_ci "$out" "$needle" && fails+=("forbidden:\"$needle\"")
        done < "$must_no"
    fi
    # Side channel: emit output via env-like global
    LAST_OUTPUT="$out"
    LAST_FAILS="${fails[*]-}"
}

# LLMs are stochastic. Retry up to MAX_TRIES before declaring fail —
# the suite's value is catching systematic regressions, not single-run
# flakes. Override with VINPUT_LLM_MAX_TRIES=1 for strict mode.
MAX_TRIES="${VINPUT_LLM_MAX_TRIES:-3}"

for input_file in "$CASES"/*.input.txt; do
    [ -f "$input_file" ] || continue
    id="$(basename "$input_file" .input.txt)"
    must_yes="$CASES/$id.must_contain.txt"
    must_no="$CASES/$id.must_not_contain.txt"
    input=$(cat "$input_file")

    tries=0
    while [ "$tries" -lt "$MAX_TRIES" ]; do
        tries=$((tries + 1))
        check_case "$input" "$must_yes" "$must_no"
        [ -z "$LAST_FAILS" ] && break
    done

    if [ -z "$LAST_FAILS" ]; then
        marker="PASS"
        [ "$tries" -gt 1 ] && marker="PASS (try $tries/$MAX_TRIES)"
        PER_CASE+=("$id|$marker|$LAST_OUTPUT")
    else
        FAIL=1
        PER_CASE+=("$id|FAIL after $MAX_TRIES tries: $LAST_FAILS|$LAST_OUTPUT")
    fi
done

echo ""
echo "ID|VERDICT|OUTPUT"
printf '%s\n' "${PER_CASE[@]}"
echo ""

if [ "$FAIL" = "0" ]; then
    echo "✓ All LLM cleanup cases pass."
    exit 0
else
    echo "✗ Some LLM cleanup cases failed — see above."
    exit 1
fi
