#!/usr/bin/env bash
# live.sh <spawn-script> <label>: real tmux lab server; pane settles during the 59th 1s wait.
set -u
SPAWN=$1; LABEL=$2; TRIG=${3:-59}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LAB=$(cd "$LAB" && pwd -P)
home=$LAB/home; proj=$LAB/project; wt=$LAB/wt; bin=$LAB/bin; id=live-late-$LABEL
"$(dirname "$SPAWN")/fm-lab-home.sh" create "$home" >/dev/null || exit 1
mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config" "$bin" "$LAB/tmux"
touch "$home/state/.last-watcher-beat"; printf 'codex\n' > "$home/config/crew-harness"
printf '# Task\n## Captain'"'"'s intent\nlive late settle\n\n## Firstmate spec\nx\n' > "$home/data/$id/brief.md"
git init -q -b main "$proj"; git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$proj" worktree add -q -b "slot-$LABEL" "$wt"
cat > "$bin/sleep" <<SH
#!/bin/bash
if [ "\${1:-}" = 1 ]; then n=0; [ ! -f $LAB/sleeps ] || n=\$(cat $LAB/sleeps); n=\$((n+1)); echo \$n > $LAB/sleeps
  [ \$n -ne $TRIG ] || touch $LAB/go; fi
exec /bin/sleep "\$@"
SH
cat > "$bin/treehouse" <<SH
#!/bin/bash
# stub treehouse get: slot preparation finishes only when told, then a subshell in the slot
while [ ! -e $LAB/go ]; do /bin/sleep 0.1; done
cd "$wt" && exec /bin/bash --norc --noprofile
SH
printf '#!/bin/bash\necho fake-codex "$@"; exec /bin/sleep 600\n' > "$bin/codex"
chmod +x "$bin"/*
export TMUX_TMPDIR=$LAB/tmux
env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin:/opt/homebrew/bin" TERM=xterm TMUX_TMPDIR="$LAB/tmux" \
  tmux -L fm-lab new-session -d -s firstmate -x 200 -y 50 -c "$proj" /bin/bash --norc --noprofile
sock=$(tmux -L fm-lab display-message -p '#{socket_path}'); pid=$(tmux -L fm-lab display-message -p '#{pid}')
start=$(date +%s)
out=$(env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE \
  -u FM_PROJECTS_OVERRIDE -u FM_CONFIG_OVERRIDE FM_HOME="$home" FM_SPAWN_NO_GUARD=1 TMUX="$sock,$pid,0" PATH="$bin:$PATH" \
  "$SPAWN" "$id" "$proj" --mode no-mistakes --yolo off 2>&1); rc=$?
echo "== $LABEL: fm-spawn exit=$rc after $(( $(date +%s) - start ))s, discovery sleeps=$(cat $LAB/sleeps 2>/dev/null)"
echo "$out" | grep -v '^warning:' | sed "s#$LAB#\$LAB#g"
echo "-- state meta:"; { grep -E '^(worktree|window)=' "$home/state/$id.meta" 2>/dev/null || echo "(no meta)"; } | sed "s#$LAB#\$LAB#g"
echo "-- lab tmux windows / pane paths:"; tmux -L fm-lab list-windows -a -F '#{window_name} #{pane_current_path}' | sed "s#$LAB#\$LAB#g"
tmux -L fm-lab kill-server 2>/dev/null; chmod -R u+w "$LAB"; rm -rf "$LAB"
