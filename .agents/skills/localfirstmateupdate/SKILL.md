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
On a merge conflict or check failure, cleanup aborts any pending merge and removes the worktree, pushes nothing, and stops the flow.
Report the conflicting files or failed check to the captain; offer an agent task only as an option for their approval.
If a push is rejected or cleanup fails, stop and report the exact failure without forcing or deleting anything.

## 3. Run the normal update

Load and follow the `updatefirstmate` skill (`bin/fm-update.sh`, then its reread, restart, and nudge steps).

## 4. Report

Tell the captain in one or two plain lines how many upstream commits carry picked up (or that it was already current), whether it was pushed, and the `/updatefirstmate` outcome.
Name anything that stopped the flow and what decision it needs.

## Safety

- Never force-push, rebase, reset, stash, or delete refs on main or carry.
- Never push to `origin` (upstream); push only to the carry remote.
- Never touch `projects/`.
