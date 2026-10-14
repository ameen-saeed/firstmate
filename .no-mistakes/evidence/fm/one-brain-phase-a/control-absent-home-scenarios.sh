#!/usr/bin/env bash
# Evidence driver for the two retired-remote-home defects on branch fm/one-brain-phase-a.
#
# Usage: control-absent-home-scenarios.sh <repo-checkout>
#
# Drives the REAL product script <repo>/bin/fm-remote-secondmate-control.sh
# (and the base-commit copy when given one) against disposable absent /
# non-seeded / seeded home directories under a throwaway temp root.
set -u

REPO=${1:?usage: control-absent-home-scenarios.sh <repo-checkout>}
CTL="$REPO/bin/fm-remote-secondmate-control.sh"
[ -x "$CTL" ] || { echo "not executable: $CTL"; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/fm-absent-home.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"' INT TERM

home_state() { # <path>
  if [ -e "$1" ] || [ -L "$1" ]; then
    printf 'STUB-PRESENT(%s)' "$(cd "$(dirname "$1")" && find "$(basename "$1")" -mindepth 0 | sort | tr '\n' ',')"
  else
    printf 'absent'
  fi
}

echo "### checkout: $REPO"
echo "### control script absence marker present: $(grep -c TARGET_HOME_ABSENT "$CTL")"
echo

echo "## Scenario A - a parent-side probe against a retired (absent) remote home must not recreate a stub"
H="$T/a/home"; rm -rf "$H"
probe_out=$(FM_HOME="$H" "$CTL" state ios 2>&1); probe_rc=$?
echo "  fm-remote-secondmate-control.sh state ios   -> rc=$probe_rc out=[$probe_out]"
echo "  home after probe: $(home_state "$H")"
echo

echo "## Scenario B - retiring that already-retired home must report already-retired and leave no stub"
retire_out=$(FM_HOME="$H" "$CTL" retire ios 2>&1); retire_rc=$?
echo "  fm-remote-secondmate-control.sh retire ios  -> rc=$retire_rc out=[$retire_out]"
echo "  home after retire: $(home_state "$H")"
case "$retire_out" in
  *already-retired*) echo "  VERDICT: reported already-retired" ;;
  *) echo "  VERDICT: did NOT report already-retired" ;;
esac
echo

echo "## Scenario C - every other control command against a retired home leaves it absent (fail-closed)"
for cmd in "state ios" "route ios" "send ios hello" "key ios Escape" "capture ios 10" \
           "observe ios" "sync ios" "update ios" "launch ios pi - - herdr"; do
  Hc="$T/c/$(printf '%s' "$cmd" | tr ' /' '__')"
  rm -rf "$Hc"
  # shellcheck disable=SC2086
  out=$(FM_HOME="$Hc" "$CTL" $cmd 2>&1); rc=$?
  printf '  %-26s rc=%-3s %-10s out=%s\n' "$cmd" "$rc" "$(home_state "$Hc")" "$out"
done
echo

echo "## Scenario D - adversarial: a non-seeded existing directory is still refused and never removed"
Hd="$T/d/home"; mkdir -p "$Hd/state"; printf 'user data\n' > "$Hd/user-file.txt"
out=$(FM_HOME="$Hd" "$CTL" retire ios 2>&1); rc=$?
echo "  retire ios -> rc=$rc out=[$out]"
echo "  tree after: $( (cd "$T/d" && find . | sort | tr '\n' ' ') )"
[ -f "$Hd/user-file.txt" ] && echo "  VERDICT: operator data preserved" || echo "  VERDICT: operator data DESTROYED"
echo

echo "## Scenario E - adversarial: a genuinely seeded home is not short-circuited as already-retired"
He="$T/e/home"; mkdir -p "$He/bin" "$He/state"
printf 'ios\n' > "$He/.fm-secondmate-home"; printf 'agents\n' > "$He/AGENTS.md"
printf 'other task record\n' > "$He/state/other.meta"
out=$(FM_HOME="$He" "$CTL" state ios 2>&1); rc=$?
echo "  state ios -> rc=$rc out=[$out]"
echo "  tree after: $( (cd "$T/e" && find . | sort | tr '\n' ' ') )"

echo
echo "## Scenario F - adversarial: a symlinked home is never removed through the link"
Hf="$T/f/home"; mkdir -p "$T/f"; ln -s "$T/f/missing-target" "$Hf"
out=$(FM_HOME="$Hf" "$CTL" retire ios 2>&1); rc=$?
echo "  dangling symlink home retire ios -> rc=$rc out=[$out]"
[ -L "$Hf" ] && echo "  VERDICT: symlink preserved" || echo "  VERDICT: symlink REMOVED"
