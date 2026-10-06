#!/usr/bin/env bash
# For each terminal PID given, print the working directory of its shell and of
# every Claude Code session running under it, and the program the shell runs
# (its newest child, such as herdr or btop), one per line:
#   <terminal-pid> shell <cwd>
#   <terminal-pid> claude <cwd>
#   <terminal-pid> program <name>

set -u

table=$(ps -eo pid=,ppid=,comm=)

for term in "$@"; do
  while read -r pid kind; do
    if [ "$kind" = program ]; then
      printf '%s program %s\n' "$term" "$(awk -v p="$pid" '$1 == p { print $3; exit }' <<<"$table")"
      continue
    fi
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) && printf '%s %s %s\n' "$term" "$kind" "$cwd"
  done < <(awk -v root="$term" '
    { parent[$1] = $2; name[$1] = $3 }
    END {
      for (pid in name) {
        if (parent[pid] == root && !shell) { shell = pid; print pid, "shell" }
        if (name[pid] != "claude") continue
        for (p = parent[pid]; (p in parent) && p != root; p = parent[p]) ;
        if (p == root) print pid, "claude"
      }
      if (!shell) exit
      for (pid in name) if (parent[pid] == shell && pid + 0 > program + 0) program = pid
      if (program) print program, "program"
    }' <<<"$table")
done
