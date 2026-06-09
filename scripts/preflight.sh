#!/bin/bash
# Run deterministic release/pre-merge checks.
#
# By default this avoids network, microphone, and local LLM dependencies. Use
# RUN_LLM=1 and/or RUN_ASR=1 when the local Ollama model and Whisper fixtures
# should be included in the gate.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FAIL=0

run_step() {
    local name="$1"
    shift
    echo ""
    echo "==> $name"
    if "$@"; then
        echo "✓ $name"
    else
        echo "✗ $name"
        FAIL=1
    fi
}

run_step "shell lint" bash "$ROOT/scripts/lint-shell.sh"
run_step "doc coverage (config vars <-> docs)" bash "$ROOT/scripts/check-docs.sh"
run_step "CLI integration" bash "$ROOT/tests/integration/run.sh"

if [ "${RUN_LLM:-0}" = "1" ]; then
    run_step "LLM cleanup regression" bash "$ROOT/tests/llm/run.sh"
else
    echo ""
    echo "==> LLM cleanup regression"
    echo "skip: set RUN_LLM=1 to run tests/llm/run.sh"
fi

if [ "${RUN_ASR:-0}" = "1" ]; then
    run_step "ASR regression" bash "$ROOT/tests/asr/run.sh"
else
    echo ""
    echo "==> ASR regression"
    echo "skip: set RUN_ASR=1 to run tests/asr/run.sh"
fi

if [ "$FAIL" = "0" ]; then
    echo ""
    echo "✓ preflight passed"
    exit 0
fi

echo ""
echo "✗ preflight failed"
exit 1
