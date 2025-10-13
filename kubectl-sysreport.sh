#!/usr/bin/env bash
# Full kubectl-sysreport.sh script
set -euo pipefail
NS="${1:-}"
POD="${2:-}"
[ -z "$NS" ] && { echo "Namespace required"; exit 1; }
[ -z "$POD" ] && { echo "Pod name required"; exit 1; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="k8s-sysreport-${NS}-${POD}-${STAMP}"
mkdir -p "$ROOT"
log(){ printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

log "Collecting kubectl data"
kubectl -n "$NS" get pod "$POD" -o yaml > "$ROOT/pod.yaml"
kubectl -n "$NS" describe pod "$POD" > "$ROOT/pod.describe.txt"
NODE="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.nodeName}')"
kubectl get node "$NODE" -o yaml > "$ROOT/node.yaml"
kubectl describe node "$NODE" > "$ROOT/node.describe.txt"
kubectl -n "$NS" get events --sort-by=.lastTimestamp > "$ROOT/events.txt" || true

log "Collecting logs"
mapfile -t C < <(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}')
for c in "${C[@]}"; do
  kubectl -n "$NS" logs "$POD" -c "$c" --timestamps --tail=50000 > "$ROOT/log-${c}.txt" || true
  kubectl -n "$NS" logs "$POD" -c "$c" --timestamps --previous --tail=50000 > "$ROOT/log-${c}-prev.txt" 2>/dev/null || true
done

log "Packaging"
tar -czf "${ROOT}.tar.gz" "$ROOT"
echo "Created: ${ROOT}.tar.gz"
