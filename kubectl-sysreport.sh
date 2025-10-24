#!/usr/bin/env bash
# dovecot-k8s-sysreport — Collect Kubernetes diagnostics for a specific pod
set -euo pipefail

usage() {
  echo "Usage: $0 --namespace <namespace> --pod <pod>"
  echo
  echo "Options:"
  echo "  --namespace, -n   Kubernetes namespace of the pod"
  echo "  --pod, -p         Name of the pod to collect diagnostics from"
  echo "  --help, -h        Show this help message"
  exit 1
}

NS=""
POD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n)
      NS="$2"
      shift 2
      ;;
    --pod|-p)
      POD="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$NS" || -z "$POD" ]]; then
  echo "Error: both --namespace and --pod are required."
  usage
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="k8s-sysreport-${NS}-${POD}-${STAMP}"
mkdir -p "$ROOT"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

log "Collecting kubectl data"
kubectl -n "$NS" get pod "$POD" -o yaml > "$ROOT/pod.yaml"
kubectl -n "$NS" describe pod "$POD" > "$ROOT/pod.describe.txt"
NODE="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.nodeName}')"
kubectl get node "$NODE" -o yaml > "$ROOT/node.yaml"
kubectl describe node "$NODE" > "$ROOT/node.describe.txt"
kubectl -n "$NS" get events --sort-by=.lastTimestamp > "$ROOT/events.txt" || true

log "Collecting logs"
mapfile -t CONTAINERS < <(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}')
for c in "${CONTAINERS[@]}"; do
  kubectl -n "$NS" logs "$POD" -c "$c" --timestamps --tail=50000 > "$ROOT/log-${c}.txt" || true
  kubectl -n "$NS" logs "$POD" -c "$c" --timestamps --previous --tail=50000 > "$ROOT/log-${c}-prev.txt" 2>/dev/null || true
done

log "Packaging"
tar -czf "${ROOT}.tar.gz" "$ROOT"
echo "Created: ${ROOT}.tar.gz"
