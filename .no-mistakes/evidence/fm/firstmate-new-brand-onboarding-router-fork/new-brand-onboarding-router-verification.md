# new-brand-onboarding shared router skill — test evidence

Branch: fm/firstmate-new-brand-onboarding-router-fork (46cf74ac, base 55ec4756)

## 1. Real consumer check (documentation classification)

The shared skill's minimal validation surface is `bin/fm-doc-audience-check.sh`, which parses
`docs/documentation-audiences.json` (typed semantic check of the new classification entry)
and verifies every skill file is classified:

```
$ bash bin/fm-doc-audience-check.sh
fm-doc-audience-check: ok surfaces=92 local_links=299
exit=0
```

`docs/documentation-audiences.json` also passes `json.load` (valid JSON).

## 2. Skill discovery (pi native skill loader)

The worktree is a live pi home surface: after the change, the pi skill loader discovers
`.agents/skills/new-brand-onboarding/SKILL.md` and lists it as an invocable skill
(`new-brand-onboarding`, `user-invocable: true`), matching the frontmatter format used by
sibling skills (e.g. `afk`, `ahoy`). This confirms both natural-language triggering
(description exposes "onboard / add / set up / resume a Brand in Studio v2") and the
explicit `/skill:new-brand-onboarding` path are available.

## 3. Boundary / no-duplication checks

- `projects/studio-v2/.agents/skills/new-brand-onboarding/SKILL.md` does NOT exist in this
  repo: the project-local execution skill is not duplicated, as required. The shared skill
  references it by path and defers execution to it.
- Referenced transport/lifecycle scripts exist in the repo: `bin/fm-send.sh`, `bin/fm-brief.sh`,
  `bin/fm-spawn.sh` — the routing branches use only existing machinery, no new router script
  was added (`git diff --stat` shows exactly 3 files: the SKILL.md, one AGENTS.md section 7
  trigger line, one JSON classification entry).

## 4. Non-deterministic paths (not CI-testable)

The primary-home routing to `studio-v2-mate`, the per-Brand worker commissioning, the
approval-gate conversational UX, and the stop-and-report-blocker branches are natural-language
agent behavior (they require the running Firstmate home with `data/secondmates.md` and the
Studio v2 clone, neither of which exists in a source worktree). Per the test-quality rule these
belong to development/agent evaluation, not deterministic CI; the skill text is the contract.

Result: all deterministic validation surface passes; no product code defects found.
