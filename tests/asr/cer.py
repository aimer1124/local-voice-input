#!/usr/bin/env python3
"""Character Error Rate between reference and hypothesis.

Pure stdlib (no jiwer dep) to keep the test suite zero-install. The metric is
the standard one: Levenshtein distance / len(reference). Whitespace and ASCII
punctuation are stripped on both sides before comparing — we care about
character recognition, not formatting (LLM cleaning runs downstream anyway).

Usage:
    cer.py REF_FILE HYP_FILE        # prints "0.0833"
    cer.py --ref-string REF "$HYP"  # inline strings
"""
import argparse
import sys
import unicodedata


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKC", s)
    out = []
    for ch in s:
        cat = unicodedata.category(ch)
        if cat.startswith("Z") or cat.startswith("C"):  # spaces/control
            continue
        if cat.startswith("P"):  # punctuation
            continue
        out.append(ch.lower())
    return "".join(out)


def levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, cb in enumerate(b, 1):
            cur[j] = min(
                prev[j] + 1,        # deletion
                cur[j - 1] + 1,     # insertion
                prev[j - 1] + (ca != cb),  # substitution
            )
        prev = cur
    return prev[-1]


def cer(ref: str, hyp: str) -> float:
    r = normalize(ref)
    h = normalize(hyp)
    if not r:
        return 0.0 if not h else 1.0
    return levenshtein(r, h) / len(r)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("ref")
    p.add_argument("hyp")
    p.add_argument("--ref-string", action="store_true",
                   help="treat REF/HYP as inline strings, not file paths")
    args = p.parse_args()

    if args.ref_string:
        ref_text, hyp_text = args.ref, args.hyp
    else:
        ref_text = open(args.ref, encoding="utf-8").read()
        hyp_text = open(args.hyp, encoding="utf-8").read()

    print(f"{cer(ref_text, hyp_text):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
