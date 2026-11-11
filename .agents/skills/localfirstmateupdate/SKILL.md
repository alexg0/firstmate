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
- **More than 0** - merge programmatically in a temporary detached worktree, regardless of live crewmates.
  Never merge in the primary checkout; it stays unchanged until step 3.
  Substitute the checked carry remote and branch below, then run under Bash from the home repo root:

```bash
(
  set -euo pipefail
  remote=<remote>
  branch=<branch>
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-carry.XXXXXX")
  worktree="$scratch/merge"
  cleanup() {
    result=$?
    trap - EXIT
    if [ -e "$worktree/.git" ]; then
      if git -C "$worktree" rev-parse -q --verify MERGE_HEAD >/dev/null; then
        git -C "$worktree" merge --abort || result=1
      fi
      git worktree remove "$worktree" || result=1
    fi
    rmdir "$scratch" || result=1
    exit "$result"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  git worktree add --detach "$worktree" "$remote/$branch"
  before=$(git -C "$worktree" rev-parse HEAD)
  if ! git -C "$worktree" merge --no-edit origin/main; then
    git -C "$worktree" diff --name-only --diff-filter=U
    exit 1
  fi
  (
    cd "$worktree"
    while IFS= read -r -d '' script; do
      printf 'Syntax check: %s\n' "$script"
      bash -n "$script"
    done < <(git diff --name-only -z --diff-filter=ACMR "$before" HEAD -- 'bin/*.sh')
    if [ -f bin/fm-lint.sh ]; then
      bash bin/fm-lint.sh
    fi
  )
  git -C "$worktree" push "$remote" "HEAD:$branch"
)
```

On success, cleanup removes the worktree before step 3.
If a push is rejected or cleanup fails, stop and report the exact failure without forcing or deleting anything.
On a merge conflict or check failure, cleanup aborts any pending merge and removes the worktree, pushing nothing.
After successful cleanup, report the conflicting files or failed check and automatically file and dispatch a `local-only` worker with `yolo` off, without asking the captain to approve dispatch.
Use `bin/fm-tasks-axi.sh` for the backlog item, `bin/fm-brief.sh` for the brief, `bin/fm-dispatch-resolve.sh` for profile resolution, and `bin/fm-spawn.sh` for isolated dispatch; their headers and help own the mechanics, and `harness-adapters` owns harness selection and launch verification.
Model the brief on `data/fm-carry-sync-1110/brief.md` when available, with this scope:

- Load `firstmate-coding-guidelines` before editing.
- Branch from local `main` (carry), then merge `origin/main` with a normal merge commit, preserving every local carry commit and both local carry behavior and upstream changes when resolving conflicts.
  Spawn can base the worktree on `origin/main`, not carry: explicitly direct the worker to create its task branch from local `main`, not detached `HEAD`, and verify `git merge-base --is-ancestor main HEAD` before reporting ready.
- Audit each local carry change and its net effect for full or partial redundancy with upstream, citing upstream and file evidence in the task report without dropping or reverting any local change.
- Run quick checks: `bash -n` on changed `bin/` scripts, `bin/fm-lint.sh`, and relevant test scripts touched by the merged upstream changes or conflicted files; skip live-harness and opt-in container tests and report those omissions and any failures.
- Stop with a committed, clean ready branch and task report; no push or PR, and no behavior changes beyond conflict resolution.

Wait for the captain's approval before landing the ready branch through the guarded local-only path and pushing to the checked carry remote and branch without force.
Only after that push succeeds, continue to step 3.
If worker dispatch or validation fails, stop and report; never treat a failed check as a ready branch.

## 3. Run the normal update

Load and follow the `updatefirstmate` skill (`bin/fm-update.sh`, then its reread, restart, and nudge steps).

## 4. Report

Tell the captain in one or two plain lines how many upstream commits carry picked up (or that it was already current), whether it was pushed, and the `/updatefirstmate` outcome.
Name anything that stopped the flow and what decision it needs.

## Safety

- Never force-push, rebase, reset, stash, or delete refs on main or carry.
- Never push to `origin` (upstream); push only to the carry remote.
- Never touch `projects/`.
