# Live validation evidence - fm/one-brain-phase-a (ce8c8c9 -> 2ef18a4)

Product: firstmate (shared tracked shell tooling). No GUI/browser surface; the
end-user surface is the CLI lifecycle of a remote secondmate.

## Why bash 5 is used to drive the e2e

`tests/fm-remote-secondmate-lifecycle-e2e.test.sh` stops on macOS's stock bash
3.2 at an unrelated, pre-existing step (`bin/fm-remote-home-seed.sh:160`
`PROJECT_NAMES[@]: unbound variable` under `set -u`, an empty-array expansion
bash 3.2 rejects). This is the "Mac fails at an unrelated earlier step" the
author's intent already names. A GNU bash 5.2 was built from source into
`/tmp/fm-tools/bash-5.2` for this run and prepended to `PATH`, so every product
script (`#!/usr/bin/env bash`) is driven by bash 5.2 exactly as CI does.

## Files

- `e2e-remote-secondmate-lifecycle-target.log` - full e2e on the change commit
  (2ef18a4): `ALL TESTS PASSED`, including the new retirement assertions.
- `e2e-remote-secondmate-lifecycle-base.log` - the SAME updated e2e test run
  against the base product code (ce8c8c9 bin/), showing the regression is
  reproduced: `error: remote pending-reply cleanup failed; preserving the local
  route for retry` / `not ok - safe remote retirement failed after handoff
  serialization`.
- `control-absent-home-scenarios.sh` - disposable driver for the retired-home
  control-script scenarios (absolute `FM_HOME` under a throwaway temp root).
- `control-absent-home-target.log` / `control-absent-home-base.log` - its
  transcripts before/after the fix.
