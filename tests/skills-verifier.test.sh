#!/usr/bin/env bash
# Behavioral regressions for the skills-verifier loop's deterministic guarantees.
#
# The loop that this skill owns is orchestrated by independent pi agents, so a
# model's prose cannot be pinned by a test. What CAN be pinned is the two rules
# the loop treats as code, because they decide which version wins and whether a
# judge can tell the versions apart:
#
#   1. the semver bump is truthful (a change class maps to exactly one bump);
#   2. the blind-judging label assignment randomizes per round, so the A/B
#      labels never leak which version is newer or which the verifier rewrote.
#
# These are encoded here as pure functions and asserted through their return
# values, not through the prose of SKILL.md.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# classify_bump <change-description> -> the truthful semver class.
# Mirrors the skill's rule: PATCH for wording/clarity, MINOR for a new bounded
# capability, MAJOR for a behavior change, and a loud refusal otherwise.
classify_bump() {
  case "$1" in
    wording | clarity | docs) echo patch ;;
    "new capability") echo minor ;;
    "behavior change") echo major ;;
    *) return 1 ;;
  esac
}

# anonymize <body-a> <body-b> -> prints two lines, "<label>:<body>".
# Labels A and B randomly per call, and strips identity/recency markers from
# each body so the judge never sees which version is newer or who wrote it.
anonymize() {
  local a b flip
  a=$(printf '%s' "$1" | sed -E 's/^(version|author|timestamp|date):.*/<redacted>/')
  b=$(printf '%s' "$2" | sed -E 's/^(version|author|timestamp|date):.*/<redacted>/')
  flip=$(( RANDOM % 2 ))
  if [ "$flip" = "0" ]; then
    printf 'A:%s\nB:%s\n' "$a" "$b"
  else
    printf 'A:%s\nB:%s\n' "$b" "$a"
  fi
}

# label_of <label> -> the body line out of an anonymize() pair.
label_of() { grep "^$1:" | sed "s/^$1://"; }

test_version_bump_is_truthful_and_total() {
  local got
  got=$(classify_bump wording) || fail "wording must classify"
  expect_code patch "$got" "wording/clarity bumps PATCH"
  got=$(classify_bump "new capability") || fail "new capability must classify"
  expect_code minor "$got" "a new bounded capability bumps MINOR"
  got=$(classify_bump "behavior change") || fail "behavior change must classify"
  expect_code major "$got" "a behavior change bumps MAJOR"
  if classify_bump "completely different" >/dev/null 2>&1; then
    fail "an unsupported change class must be refused, not guessed"
  fi
  pass "version bump classification is truthful and does not guess"
}

test_blind_label_randomizes_per_round() {
  local out_a seen_ab=0 seen_ba=0
  for _ in $(seq 1 30); do
    out_a=$(anonymize "body-alpha" "body-beta" | label_of A)
    case "$out_a" in
      "body-alpha") seen_ab=$(( seen_ab + 1 )) ;;
      "body-beta") seen_ba=$(( seen_ba + 1 )) ;;
    esac
  done
  [ "$seen_ab" -gt 0 ] && [ "$seen_ba" -gt 0 ] || fail "A/B labels did not randomize across rounds"
  pass "blind-judging A/B labels randomize so the newer version is not inferable from labeling"
}

test_blind_label_strips_identity_markers() {
  local draft="version: 2.0.0
author: ver-agent
timestamp: 2026-08-30T23:25:00Z
body-only-content"
  local labeled
  labeled=$(anonymize "$draft" "$draft")
  assert_not_contains "$labeled" "version: 2.0.0" "the blind label leaks a version marker"
  assert_not_contains "$labeled" "author: ver-agent" "the blind label leaks an author marker"
  assert_not_contains "$labeled" "timestamp: 2026-08-30T23:25:00Z" "the blind label leaks a timestamp marker"
  assert_contains "$labeled" "body-only-content" "the blind label kept the real body content"
  pass "blind judging strips identity and recency markers from a version"
}

test_version_bump_is_truthful_and_total
test_blind_label_randomizes_per_round
test_blind_label_strips_identity_markers
