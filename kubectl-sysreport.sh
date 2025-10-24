#!/usr/bin/env bash
# kubectl-sysreport — Collect Kubernetes diagnostics for a specific pod
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --namespace <namespace> --pod <pod> [--out-dir <dir>]

Options:
  -n, --namespace <namespace>   Kubernetes namespace of the pod (required)
  -p, --pod <pod>               Name of the pod to collect diagnostics from (required)
  -o, --out-dir <dir>           Output directory (default: current working directory)
  -h, --help                    Show this help message
EOF
  exit 1
}

NS=""
POD=""
OUT_BASE="$(pwd)"

# Parse command-line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NS="$2"; shift 2 ;;
    -p|--pod)
      POD="$2"; shift 2 ;;
    -o|--out-dir)
      OUT_BASE="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2
      usage ;;
  esac
done

if [[ -z "$NS" || -z "$POD" ]]; then
  echo "Error: both --namespace and --pod are required." >&2
  usage
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="${OUT_BASE%/}/kubectl-sysreport-${NS}-${POD}-${STAMP}"
ARCHIVE="${ROOT}.tar.gz"
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
tar -czf "$ARCHIVE" -C "$(dirname "$ROOT")" "$(basename "$ROOT")"
log "Done: $ARCHIVE"
echo "$ARCHIVE"
