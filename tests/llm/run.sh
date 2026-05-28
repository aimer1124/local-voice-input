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

for input_file in "$CASES"/*.input.txt; do
    [ -f "$input_file" ] || continue
    id="$(basename "$input_file" .input.txt)"
    must_yes="$CASES/$id.must_contain.txt"
    must_no="$CASES/$id.must_not_contain.txt"

    input=$(cat "$input_file")
    output=$(bash "$BG" --test-llm-clean "$input" 2>/dev/null)

    case_fails=()

    if [ -f "$must_yes" ]; then
        while IFS= read -r needle || [ -n "$needle" ]; do
            [ -z "$needle" ] && continue
            if ! contains_ci "$output" "$needle"; then
                case_fails+=("missing:\"$needle\"")
            fi
        done < "$must_yes"
    fi
    if [ -f "$must_no" ]; then
        while IFS= read -r needle || [ -n "$needle" ]; do
            [ -z "$needle" ] && continue
            if contains_ci "$output" "$needle"; then
                case_fails+=("forbidden:\"$needle\"")
            fi
        done < "$must_no"
    fi

    if [ ${#case_fails[@]} -eq 0 ]; then
        PER_CASE+=("$id|PASS|$output")
    else
        FAIL=1
        PER_CASE+=("$id|FAIL ${case_fails[*]}|$output")
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
