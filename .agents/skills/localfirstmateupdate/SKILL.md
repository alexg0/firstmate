---
name: localfirstmateupdate
description: >-
  Update a firstmate home that follows a personal fork branch through config/self-update-source (for example "fork carry"): first bring that branch up to date with upstream origin/main and push it, then run the normal /updatefirstmate flow.
  Use when the captain invokes /localfirstmateupdate or asks to sync carry and update firstmate.
user-invocable: true
metadata:
  internal: true
---

# localfirstmateupdate

A firstmate home whose `config/self-update-source` names a fork branch (for example `fork carry`) only receives upstream changes after that branch absorbs `origin/main`.
This skill does that sync, then hands off to `/updatefirstmate`.
Run it from the firstmate home, the repo root that holds `config/self-update-source`.

## 1. Check preconditions

```sh
cat config/self-update-source          # expect "<remote> <branch>", e.g. "fork carry"
git status --porcelain                 # must be empty
git branch --show-current              # must be main
git fetch origin && git fetch <remote>
```

- If `config/self-update-source` is absent, there is no carry branch: run `/updatefirstmate` and stop.
- If the tree is dirty or not on `main`, stop and report.
  Never stash, reset, or force.
- `HEAD` must equal `<remote>/<branch>`.
  If local main has commits not on carry, or carry has commits not on main, stop and report the difference rather than guessing which side wins.

## 2. Sync carry with upstream

```sh
git rev-list --count HEAD..origin/main   # upstream commits carry is missing
```

- **0** - carry already contains upstream; go to step 3.
- **More than 0** - merge upstream into carry:
  1. Check the merge is clean: `git merge-tree --write-tree HEAD origin/main`.
  2. Respect the shared-material rule in `AGENTS.md` section 1: when any crewmate is live, or the merge conflicts, do not merge in the primary checkout.
     Dispatch a `local-only` ship task on the firstmate repo whose job is "merge origin/main into carry, keep every local carry commit, resolve conflicts, run the repo's checks", land it with `bin/fm-merge-local.sh`, then continue at step 2.4.
  3. When the fleet is empty and the merge is clean, merge directly: `git merge --no-edit origin/main`.
     A merge commit is expected on carry; never rebase or rewrite carry history.
  4. Run the repo's own quick checks from `CONTRIBUTING.md` (at minimum `bash -n` on changed `bin/` scripts) and stop on failure.
  5. Push with `git push <remote> main:<branch>`, fast-forward only and never `--force`.
     If the push is rejected, stop and report.

## 3. Run the normal update

Load and follow the `updatefirstmate` skill (`bin/fm-update.sh`, then its reread, restart, and nudge steps).

## 4. Report

Tell the captain in one or two plain lines how many upstream commits carry picked up (or that it was already current), whether it was pushed, and the `/updatefirstmate` outcome.
Name anything that stopped the flow and what decision it needs.

## Safety

- Never force-push, rebase, reset, stash, or delete refs on main or carry.
- Never push to `origin` (upstream); push only to the carry remote.
- Never touch `projects/`.
