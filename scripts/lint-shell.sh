#!/bin/bash
# Lint shell scripts for the "$VAR<non-ASCII>" set -u trap.
#
# Bash with `set -u` parses `$HOTWORDS_FILE（   # lint-shell:disable (literal example)` as one identifier (because
# `（` is not a word-boundary byte for shell), then errors with "unbound
# variable: HOTWORDS_FILE…". This bit us three times (v1.1.5, v1.1.8,
# v1.2.0). The fix is `${HOTWORDS_FILE}（` — the braces terminate the name.
#
# This script greps for the offending pattern. Run from anywhere:
#   bash scripts/lint-shell.sh
#
# Exits 0 if clean, 1 if any match. Wire into CI + pre-commit hook.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Files to check: bin/*, scripts/*.sh, raycast/*.sh, install.sh, top-level *.sh.
# Skip vendored/built artifacts.
mapfile -t FILES < <(
    {
        find "$ROOT/bin"     -type f 2>/dev/null
        find "$ROOT/scripts" -type f -name "*.sh" 2>/dev/null
        find "$ROOT/raycast" -type f -name "*.sh" 2>/dev/null
        find "$ROOT/tests"   -type f -name "*.sh" 2>/dev/null
        ls    "$ROOT/install.sh" 2>/dev/null
    } | sort -u
)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "lint-shell: no shell files found"
    exit 0
fi

# Perl regex: $IDENT immediately followed by a non-ASCII byte.
# - Resets $. per file (default $. is cumulative across files).
# - Lines containing the `lint-shell:disable` pragma are skipped (used in
#   this script itself and any other place that legitimately documents the
#   anti-pattern in prose / strings rather than executing it).
HITS=$(perl -ne '
    next if /lint-shell:disable/;
    if (/\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]/) {
        print "$ARGV:$.: $_";
    }
    close(ARGV) if eof;
' "${FILES[@]}" 2>/dev/null)

if [ -n "$HITS" ]; then
    echo "✗ lint-shell: found \$VAR<non-ASCII> — wrap in braces (\${VAR}<...>) to survive set -u"
    echo ""
    printf '%s\n' "$HITS"
    echo ""
    echo "  Why: bash treats \$HOTWORDS_FILE（   # lint-shell:disable (literal example) as one identifier; \${HOTWORDS_FILE}（ does not."
    echo "  Prior incidents: v1.1.5 (\$CONFIG_FILE), v1.1.8 (\$HOTWORDS_FILE) — see CHANGELOG."
    exit 1
fi

echo "✓ lint-shell: ${#FILES[@]} files clean"
