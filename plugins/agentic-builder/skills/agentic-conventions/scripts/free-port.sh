#!/usr/bin/env bash
# Print the first TCP port from <base> upward (at most 100 tries) that nothing
# listens on, so parallel builds' local test servers do not collide.
#
#   free-port.sh <base-port> [--after <port>]
#
#   --after  start from the port after this one (the retry after EADDRINUSE)
# Exit: 0 port printed | 1 none free in range, or bad arguments
set -euo pipefail

base="${1:-}"; [[ "$base" =~ ^[0-9]+$ ]] || { echo "usage: free-port.sh <base-port> [--after <port>]" >&2; exit 1; }
if [ "${2:-}" = "--after" ]; then base=$(( ${3:?--after needs a port} + 1 )); fi

listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -Hltn "sport = :$1" | grep -q .
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}

for port in $(seq "$base" $(( base + 99 ))); do
  if ! listening "$port"; then echo "$port"; exit 0; fi
done
echo "no free port in $base-$(( base + 99 ))" >&2
exit 1
