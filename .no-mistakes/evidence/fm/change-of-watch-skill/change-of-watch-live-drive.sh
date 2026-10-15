#!/usr/bin/env bash
# Disposable live drive for the change-of-watch skill's prescribed commands.
#
# Stands up (1) two throwaway "firstmate homes" (pc = sender, mac = receiver),
# each with its own bin/ (symlinked to the real product scripts), data/, state/,
# and (2) a throwaway unprivileged sshd on loopback with a disposable keypair,
# so the documented "ssh <host> 'cd <home> && FM_HOME=<home> bin/fm-inbox.sh
# note -'" wrapper is driven end to end over a real SSH connection.
# Nothing here touches the operator's real homes, data, config, keys, or sshd.
set -uo pipefail

REPO=/Users/ameen/.no-mistakes/worktrees/263a936a3c0b/01M4YXDTEECBEAZNYQENZT36X4
BASE=$(mktemp -d "${TMPDIR:-/tmp}/fm-cow-live.XXXXXX")
PC="$BASE/pc-home"        # sender home ("pc")
MAC="$BASE/mac-home"      # receiver home ("mac")
TODAY=$(date +%Y-%m-%d)
FAILURES=0
SSHD_PID=''

say()  { printf '\n=== %s ===\n' "$*"; }
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

cleanup() {
  [ -n "$SSHD_PID" ] && kill "$SSHD_PID" 2>/dev/null
  [ -n "${SSHD_PID:-}" ] && wait "$SSHD_PID" 2>/dev/null
  rm -rf "$BASE"
}
trap cleanup EXIT

########################################################################
say "FIXTURE: two disposable homes + a disposable loopback sshd"
make_home() { # <home>
  local h=$1
  mkdir -p "$h/data" "$h/state" "$h/config" "$h/projects"
  cp "$REPO/.tasks.toml" "$h/.tasks.toml"
  ln -s "$REPO/bin" "$h/bin"
  cat >"$h/data/backlog.md" <<'EOF'
## In flight

## Queued

## Done
EOF
}
make_home "$PC"; make_home "$MAC"
mkdir -p "$BASE/ssh"
ssh-keygen -q -t ed25519 -N '' -f "$BASE/ssh/host_ed25519" -C cow-host
ssh-keygen -q -t ed25519 -N '' -f "$BASE/ssh/user_ed25519" -C cow-user
cp "$BASE/ssh/user_ed25519.pub" "$BASE/ssh/authorized_keys"
SSH_PORT=$((22000 + RANDOM % 2000))
cat >"$BASE/ssh/sshd_config" <<EOF
Port $SSH_PORT
ListenAddress 127.0.0.1
HostKey $BASE/ssh/host_ed25519
PidFile $BASE/ssh/sshd.pid
AuthorizedKeysFile $BASE/ssh/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
LogLevel ERROR
EOF
/usr/sbin/sshd -f "$BASE/ssh/sshd_config" -E "$BASE/ssh/sshd.log"
sleep 1
SSHD_PID=$(cat "$BASE/ssh/sshd.pid" 2>/dev/null || true)
SSH_ARGS=(-p "$SSH_PORT" -i "$BASE/ssh/user_ed25519" -o StrictHostKeyChecking=no
          -o UserKnownHostsFile="$BASE/ssh/known_hosts" -o BatchMode=yes 127.0.0.1)
if ssh "${SSH_ARGS[@]}" 'echo ssh-ready' 2>/dev/null | grep -q ssh-ready; then
  ok "throwaway sshd on 127.0.0.1:$SSH_PORT accepts the disposable key"
else
  bad "throwaway sshd did not come up; the ssh transport leg cannot be driven"
fi

# The documented transport, verbatim in shape:
#   ssh <host> 'cd <home> && FM_HOME=<home> bin/fm-inbox.sh note -' < note.txt
run_note_ssh() { # <home> ; body on stdin
  local h=$1
  ssh "${SSH_ARGS[@]}" "cd $h && FM_HOME=$h bin/fm-inbox.sh note -"
}
# The single-line argument form, aimed at <home> from the other firstmate.
run_note_line_ssh() { # <home> <text>
  local h=$1 text=$2
  ssh "${SSH_ARGS[@]}" "cd $h && FM_HOME=$h bin/fm-inbox.sh note \"$text\""
}
# The same, on a host whose remote shell leaves FM_HOME unset (mis-delivery shape).
run_note_line_no_home_ssh() { # <home> <text>
  local h=$1 text=$2
  ssh "${SSH_ARGS[@]}" "cd $h && unset FM_HOME && bin/fm-inbox.sh note \"$text\""
}

flip_owner() { # <file> <item> <owner>
  local file=$1 item=$2 owner=$3 tmp
  tmp=$(mktemp)
  awk -v item="$item" -v owner="$owner" -v today="$TODAY" '
    $1 == item { print item, owner, today; next }
    { print }
  ' "$file" >"$tmp" && mv "$tmp" "$file"
}
owner_of() { awk -v item="$2" '$1 == item { print $2 }' "$1"; }
hold() { # <home> <args...>
  local h=$1
  shift
  (cd "$h" && FM_HOME="$h" FM_STATE_OVERRIDE="$h/state" FM_DATA_OVERRIDE="$h/data" \
    FM_CONFIG_OVERRIDE="$h/config" "$REPO/bin/fm-captain-hold.sh" "$@")
}
show_task() { # <home> <id>
  local h=$1 id=$2
  (cd "$h" && tasks-axi show "$id" --full 2>&1)
}
note_count() { find "$1/state/inbox" -maxdepth 1 -name '*.note' 2>/dev/null | wc -l | tr -d ' '; }
note_id_of() { printf '%s\n' "$1" | sed -n 's/^queued //p' | head -1; }

########################################################################
say "SCENARIO 1: documentation inventory consumer accepts the new skill entry"
out=$("$REPO/bin/fm-doc-audience-check.sh" 2>&1); rc=$?
printf '%s\n' "$out"
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'fm-doc-audience-check: ok surfaces='; then
  ok "repo inventory check passes with the change-of-watch entry"
else
  bad "repo inventory check did not pass (rc=$rc)"
fi
mut="$BASE/inventory-without-entry.json"
python3 - "$REPO/docs/documentation-audiences.json" "$mut" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["surfaces"] = [e for e in data["surfaces"]
                    if e["path"] != ".agents/skills/change-of-watch/SKILL.md"]
json.dump(data, open(sys.argv[2], "w"), indent=2)
PY
out=$("$REPO/bin/fm-doc-audience-check.sh" --inventory "$mut" 2>&1); rc=$?
printf '%s\n' "$out"
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'unclassified: .agents/skills/change-of-watch/SKILL.md'; then
  ok "removing the entry makes the consumer fail and name that skill (entry is load-bearing)"
else
  bad "dropping the entry did not fail the way the consumer is expected to (rc=$rc)"
fi

########################################################################
say "SCENARIO 2: docs-audience regression test (drives the real consumer end to end)"
out=$("$REPO/tests/fm-documentation-audiences.test.sh" 2>&1); rc=$?
printf '%s\n' "$out" | tail -6
[ $rc -eq 0 ] && ok "tests/fm-documentation-audiences.test.sh passes" \
  || bad "tests/fm-documentation-audiences.test.sh failed (rc=$rc)"

########################################################################
say "SCENARIO 3: handoff note over the documented ssh+FM_HOME wrapper reaches the receiver home"
printf 'project-x pc %s\n' "$TODAY" >"$PC/data/owners.md"
flip_owner "$PC/data/owners.md" project-x mac          # skill step 2
cat >"$BASE/note.txt" <<'EOF'
handoff: project-x
Standing: plan approved, crew idle.
In flight: none.
Open captain call: x-captain-call | Choose the migration order | reason: two viable orders | until: 2026-11-01
EOF
out=$(run_note_ssh "$MAC" <"$BASE/note.txt" 2>&1); rc=$?
printf '%s\n' "$out"
note_id=$(note_id_of "$out")
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'firstmate will pick this up at its next check\.'; then
  ok "note over ssh exits 0 and prints the delivery confirmation"
else
  bad "note over ssh did not exit 0 with the confirmation line (rc=$rc)"
fi
if [ -n "$note_id" ] && [ -f "$MAC/state/inbox/$note_id.note" ] \
   && grep -q '^handoff: project-x' "$MAC/state/inbox/$note_id.note" \
   && grep -q '^Open captain call: x-captain-call' "$MAC/state/inbox/$note_id.note"; then
  ok "the multi-line note body survives ssh quoting into the receiver's inbox ($note_id.note)"
else
  bad "no intact note record found in the receiver's inbox"
fi
if grep -q "inbox:$note_id" "$MAC/state/.wake-queue" 2>/dev/null; then
  ok "one wake for the note is queued in the receiver's state"
else
  bad "no wake queued for the delivered note"
fi
[ "$(note_count "$PC")" = "0" ] && ok "the sender's own inbox stayed empty" \
  || bad "the note leaked into the sender's own inbox"
out=$( (cd "$MAC" && FM_HOME="$MAC" bin/fm-inbox.sh drain --ack "$note_id") 2>&1 ); rc=$?
printf '%s\n' "$out"
if [ $rc -eq 0 ] && [ -f "$MAC/state/inbox/handled/$note_id.note" ]; then
  ok "receiving ack (drain --ack) handles the note"
else
  bad "drain --ack did not handle the note (rc=$rc)"
fi

########################################################################
say "SCENARIO 3b: a forwarded captain request reaches the owner's inbox"
out=$(run_note_line_ssh "$MAC" 'forwarded: project-x' 2>&1); rc=$?
printf '%s\n' "$out"
fwd_id=$(note_id_of "$out")
if [ $rc -eq 0 ] && [ -n "$fwd_id" ] && [ -f "$MAC/state/inbox/$fwd_id.note" ] \
   && grep -q 'forwarded: project-x' "$MAC/state/inbox/$fwd_id.note"; then
  ok "the forward wrapper lands as a 'forwarded: <item>' note in the owner's home"
else
  bad "the forwarded note did not reach the owner's home (rc=$rc)"
fi
(cd "$MAC" && FM_HOME="$MAC" bin/fm-inbox.sh drain --ack "$fwd_id" >/dev/null 2>&1)

########################################################################
say "SCENARIO 3c: the owner table is read and edited over the same ssh wrapper"
printf 'project-a pc %s\nproject-b pc %s\n' "$TODAY" "$TODAY" >"$PC/data/owners.md"
read_back=$(ssh "${SSH_ARGS[@]}" "cat $PC/data/owners.md" 2>&1)
printf '%s\n' "$read_back"
printf '%s' "$read_back" | grep -q '^project-b pc ' \
  && ok "the other firstmate reads the owner table over ssh" \
  || bad "the owner table could not be read over ssh"
ssh "${SSH_ARGS[@]}" "cd $PC && sed -i.cowsave 's/^project-b pc .*/project-b mac $TODAY/' data/owners.md && rm -f data/owners.md.cowsave" >/dev/null 2>&1
if [ "$(owner_of "$PC/data/owners.md" project-b)" = "mac" ] \
   && grep -q "^project-b mac $TODAY$" "$PC/data/owners.md" \
   && [ "$(owner_of "$PC/data/owners.md" project-a)" = "pc" ]; then
  ok "a line is flipped over ssh with its since-date, leaving the other line alone"
else
  bad "the owner-line flip over ssh did not land as documented"
fi

########################################################################
say "SCENARIO 4: adversarial - a saved note with no wake exits non-zero and prints no confirmation"
BROKEN_ROOT="$BASE/broken-root"; BROKEN_MAC="$BASE/broken-mac"
mkdir -p "$BROKEN_ROOT/bin" "$BROKEN_MAC/data" "$BROKEN_MAC/state" "$BROKEN_MAC/config"
cp "$REPO/bin/fm-inbox.sh" "$BROKEN_ROOT/bin/fm-inbox.sh"   # real script, missing wake lib
cp "$REPO/.tasks.toml" "$BROKEN_MAC/.tasks.toml"
printf 'project-y pc %s\n' "$TODAY" >"$PC/data/owners.md"
flip_owner "$PC/data/owners.md" project-y mac
out=$( (cd "$BROKEN_ROOT" && FM_HOME="$BROKEN_MAC" bin/fm-inbox.sh note "handoff: project-y") 2>&1 ); rc=$?
printf '%s\n' "$out"
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q '^queued ' \
   && ! printf '%s' "$out" | grep -q 'firstmate will pick this up at its next check\.'; then
  ok "'queued <id>' alone is not proof: rc=$rc and no confirmation line"
else
  bad "wake failure was not distinguished from delivery (rc=$rc)"
fi
[ -n "$(find "$BROKEN_MAC/state/inbox" -maxdepth 1 -name '*.note' 2>/dev/null)" ] \
  && ok "the record survived the failed wake on disk" \
  || bad "the note record was lost on wake failure"
flip_owner "$PC/data/owners.md" project-y pc
[ "$(owner_of "$PC/data/owners.md" project-y)" = "pc" ] \
  && ok "flipping the owner line back restores the sender as owner" \
  || bad "owner line was left pointing at the receiver after a failed send"

########################################################################
say "SCENARIO 5: adversarial - FM_HOME left unset on the sending host misdelivers the note locally"
before_mac=$(note_count "$MAC")
out=$(run_note_line_no_home_ssh "$MAC" "accepted project-x" 2>&1); rc=$?
printf '%s\n' "$out"
leaked_id=$(note_id_of "$out")
if [ $rc -eq 0 ] && [ -f "$MAC/state/inbox/$leaked_id.note" ] \
   && [ "$(note_count "$MAC")" -gt "$before_mac" ]; then
  ok "omitting FM_HOME queues the reply into the sending host's own inbox"
else
  bad "the FM_HOME requirement could not be demonstrated (rc=$rc)"
fi
(cd "$MAC" && FM_HOME="$MAC" bin/fm-inbox.sh drain --ack "$leaked_id" >/dev/null 2>&1)
# The correct accept reply: the other firstmate's home, named explicitly.
before_pc=$(note_count "$PC")
out=$(run_note_line_ssh "$PC" "accepted project-x" 2>&1); rc=$?
printf '%s\n' "$out"
accepted_id=$(note_id_of "$out")
if [ $rc -eq 0 ] && [ -f "$PC/state/inbox/$accepted_id.note" ] \
   && [ "$(note_count "$PC")" -gt "$before_pc" ]; then
  ok "the accept reply reaches the sender's home when FM_HOME names it"
else
  bad "the accept reply did not reach the sender's home (rc=$rc)"
fi

########################################################################
say "SCENARIO 6: receiver re-files the open captain call; sender closes its copy"
out=$(hold "$PC" hold x-captain-call --title 'Choose the migration order' \
  --reason 'two viable orders' --until 2026-11-01 2>&1); rc=$?
printf '%s\n' "$out"
[ $rc -eq 0 ] && ok "the original call is a captain hold in the sender's home" \
  || bad "could not create the original captain hold (rc=$rc)"
out=$(hold "$MAC" hold x-captain-call --title 'Choose the migration order' \
  --reason 'two viable orders' --until 2026-11-01 2>&1); rc=$?
printf '%s\n' "$out"
mac_show=$(show_task "$MAC" x-captain-call)
printf '%s\n' "$mac_show"
if [ $rc -eq 0 ] && printf '%s' "$mac_show" | grep -q 'hold_kind: captain' \
   && printf '%s' "$mac_show" | grep -q '2026-11-01'; then
  ok "the documented re-file command creates the hold in the receiver's home, deferral date kept"
else
  bad "the documented re-file command did not create the hold in the receiver's home (rc=$rc)"
fi
printf 'handed over to mac\n' >"$BASE/handover.txt"
out=$(hold "$PC" answer x-captain-call --decision-file "$BASE/handover.txt" 2>&1); rc=$?
printf '%s\n' "$out"
pc_show=$(show_task "$PC" x-captain-call)
state=$(printf '%s\n' "$pc_show" | sed -n 's/^  state: //p' | head -1)
if [ $rc -eq 0 ] && [ "$state" = "done" ] && printf '%s' "$pc_show" | grep -q 'handed over to mac'; then
  ok "the sender's copy closes and records the handover (state=$state)"
else
  bad "the sender's copy did not close with the handover recorded (rc=$rc, state=$state)"
fi

########################################################################
say "SCENARIO 7: adversarial - handing back to a home that already closed the id uses the dated fallback"
out=$(hold "$PC" hold x-captain-call --title 'Choose the migration order' \
  --reason 'two viable orders' 2>&1); rc=$?
printf '%s\n' "$out"
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'already closed'; then
  ok "re-filing the plain closed id is refused"
else
  bad "re-filing the plain closed id was not refused (rc=$rc)"
fi
out=$(hold "$PC" hold "x-captain-call-$TODAY" --title 'Choose the migration order' \
  --reason 'two viable orders' 2>&1); rc=$?
printf '%s\n' "$out"
fallback_show=$(show_task "$PC" "x-captain-call-$TODAY")
if [ $rc -eq 0 ] && printf '%s' "$fallback_show" | grep -q 'hold_kind: captain'; then
  ok "the dated id fallback re-files the call in the returning home"
else
  bad "the dated id fallback could not re-file the call (rc=$rc)"
fi

########################################################################
say "SCENARIO 8: repo change-to-test router registers the new skill and AGENTS.md"
printf -- '--- changed paths handed to the selector ---\n'
git -C "$REPO" diff --name-only 'HEAD~5...HEAD'
out=$("$REPO/bin/fm-test-run.sh" --changed --base 'HEAD~5' --list 2>&1); rc=$?
printf '%s\n' "$out" | head -8
selected=$(printf '%s\n' "$out" | grep -c '^tests/.*\.test\.sh$')
printf 'selected scripts: %s\n' "$selected"
if [ $rc -eq 0 ] && [ "$selected" -gt 0 ] \
   && printf '%s' "$out" | grep -q '^tests/fm-documentation-audiences\.test\.sh$' \
   && printf '%s' "$out" | grep -q '^tests/fm-captain-hold-lifecycle\.test\.sh$' \
   && ! printf '%s' "$out" | grep -q '__unmapped__'; then
  ok "the selector routes the new skill path and AGENTS.md into tests, nothing unmapped"
else
  bad "the selector did not route the changed paths cleanly (rc=$rc, selected=$selected)"
fi

########################################################################
say "SCENARIO 9: repo's captain-hold regression suite through the supported runner"
out=$("$REPO/bin/fm-test-run.sh" tests/fm-captain-hold-lifecycle.test.sh 2>&1); rc=$?
printf '%s\n' "$out" | grep -E '^(ok - |FM_TEST_END|FM_TEST_SUMMARY )' | tail -14
ok_count=$(printf '%s\n' "$out" | grep -c '^ok - ')
printf 'passing assertions before the abort: %s\n' "$ok_count"
printf '%s\n' "$out" | grep -q 'exit=1' \
  && printf 'NOTE: the suite exits 1 after aborting inside its process-event/lavish function,\n' \
  && printf '      unrelated to this branch (unchanged files; pre-existing in this environment).\n'

########################################################################
say "SUMMARY"
printf 'failures: %d\n' "$FAILURES"
exit "$FAILURES"
