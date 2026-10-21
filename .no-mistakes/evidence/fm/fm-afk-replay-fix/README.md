# Live validation evidence: away-mode daemon fresh-start status history

Change under test: `seed_status_seen_markers` in `bin/fm-supervise-daemon.sh`, called once at
`fm_super_main` startup, so a fresh away-mode daemon bounds every status log that has no usable
classified position instead of replaying its whole history in the first digest.

Every scenario below was driven against the real product, not a stub: the real
`bin/fm-afk-start.sh` away-mode entry point starts the real `bin/fm-supervise-daemon.sh` over a
disposable `FM_HOME`/state directory with a fake tmux pane (bordered, empty composer), and the
observed surface is the escalation digest the daemon actually typed into that pane. No real
home, state directory, project, notification channel, or shared service was touched
(`FM_WEDGE_ALARM_CHANNEL=off`, disposable `FM_HOME`/`FM_STATE_OVERRIDE`, `FM_FAKE_SENT` capture).

Files:

- `live-fixed-daemon-scenarios.txt` - scenarios A, B, D, E, F, G4, H driven live against this change.
- `live-fixed-injected-digests.txt` - the digests actually injected by the fixed daemon.
- `live-prefix-replay-baseline.txt` - the same fixture and entry point against a copy of the daemon
  with the `seed_status_seen_markers "$STATE"` startup call removed: reproduces the reported symptom
  (one digest carrying the complete history of finished tasks as `(catch-all scan)` items).
- `live-adversarial-guard-differential.txt` - the two guard fixes, each with the guard present and
  with exactly that guard removed from a disposable copy, showing the silent-loss behavior the
  guard prevents.
- `daemon-colocated-tests.txt` - the colocated suite and the seven tests this change adds.
