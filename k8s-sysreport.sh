#!/usr/bin/env bash
# ==============================================================================
# k8s-sysreport.sh (orchestrator)
#
# Purpose: Avoid duplicating functionality from dovecot-sysreport.
#          This script only orchestrates how dovecot-sysreport is executed:
#            - Inside a pod (default): run dovecot-sysreport (optionally with --core)
#            - From host via kubectl: copy optional host core into pod, run
#              dovecot-sysreport there, and copy the resulting archive back.
#
# Requirements:
#   - Inside pod: dovecot-sysreport available in PATH.
#   - Host mode: kubectl access to the target pod (and dovecot-sysreport in container).
#
# Output:
#   - Path to the dovecot-sysreport archive on the host (host mode) or inside the pod.
# ==============================================================================

set -euo pipefail

usage() {
  cat <<EOF
Usage:
  Inside a pod:
    $0 [--out-dir <path>] [--core-in-pod </tmp/corefile>]

  From admin host (kubectl mode):
    $0 --namespace <ns> --pod <pod> [--container <name>] [--out-dir <path>] [--core-file </path/to/core>]

Options:
  -o, --out-dir <path>      Output directory (default: /tmp in pod, CWD on host)
  -n, --namespace <ns>      Namespace of target pod (enables kubectl mode)
  -p, --pod <pod>           Pod name (enables kubectl mode)
  -c, --container <name>    Specific container in the pod (optional)
      --core-file <path>    Host path to core file; copied into pod before running
      --core-in-pod <path>  Path to core file that already exists inside the pod
  -h, --help                Show this help
EOF
  exit 1
}

# Show help if no parameters given
[[ $# -eq 0 ]] && usage

# Defaults
OUT_BASE="$(pwd)"    # Host default; overridden to /tmp in pod mode
NS=""                # Namespace (if set -> kubectl mode)
POD=""               # Pod (if set -> kubectl mode)
CONTAINER=""         # Optional container name
CORE_FILE_HOST=""    # Optional host-side core file to copy into pod
CORE_IN_POD=""       # Optional in-pod core file path

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out-dir)   OUT_BASE="$2"; shift 2 ;;
    -n|--namespace) NS="$2"; shift 2 ;;
    -p|--pod)       POD="$2"; shift 2 ;;
    -c|--container) CONTAINER="$2"; shift 2 ;;
    --core-file)    CORE_FILE_HOST="$2"; shift 2 ;;
    --core-in-pod)  CORE_IN_POD="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
find_ds_archive_cmd='ls -1t /tmp/dovecot-sysreport-*.tar.* 2>/dev/null | head -n1'

# ------------------------------------------------------------------------------
# Mode A: Host (kubectl) mode
# ------------------------------------------------------------------------------
if [[ -n "$NS" && -n "$POD" ]]; then
  command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found" >&2; exit 1; }
  mkdir -p "$OUT_BASE"

  # If host core file is provided, copy it into pod:/tmp/<basename>
  CORE_IN_POD_PATH=""
  if [[ -n "$CORE_FILE_HOST" ]]; then
    [[ -f "$CORE_FILE_HOST" ]] || { echo "Core file not found: $CORE_FILE_HOST" >&2; exit 1; }
    bn="$(basename "$CORE_FILE_HOST")"
    CORE_IN_POD_PATH="/tmp/$bn"
    log "Copying core to pod: $CORE_FILE_HOST -> $CORE_IN_POD_PATH"
    if [[ -n "$CONTAINER" ]]; then
      kubectl -n "$NS" cp "$CORE_FILE_HOST" "$POD:$CORE_IN_POD_PATH" -c "$CONTAINER"
    else
      kubectl -n "$NS" cp "$CORE_FILE_HOST" "$POD:$CORE_IN_POD_PATH"
    fi
  fi

  # Build dovecot-sysreport command
  DS_CMD="dovecot-sysreport"
  if [[ -n "$CORE_IN_POD_PATH" ]]; then
    DS_CMD="$DS_CMD --core $CORE_IN_POD_PATH"
  fi

  log "Running dovecot-sysreport in $NS/$POD${CONTAINER:+ (container=$CONTAINER)}"
  if [[ -n "$CONTAINER" ]]; then
    kubectl -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -lc "$DS_CMD" || true
    DS_ARCHIVE_PATH="$(kubectl -n "$NS" exec "$POD" -c "$CONTAINER" -- sh -lc "$find_ds_archive_cmd" | tr -d '\r')"
  else
    kubectl -n "$NS" exec "$POD" -- sh -lc "$DS_CMD" || true
    DS_ARCHIVE_PATH="$(kubectl -n "$NS" exec "$POD" -- sh -lc "$find_ds_archive_cmd" | tr -d '\r')"
  fi

  [[ -n "${DS_ARCHIVE_PATH:-}" ]] || { echo "dovecot-sysreport archive not found in pod" >&2; exit 1; }

  # Copy the archive to host OUT_BASE
  host_dst="$OUT_BASE/$(basename "$DS_ARCHIVE_PATH")"
  log "Copying archive to host: $host_dst"
  if [[ -n "$CONTAINER" ]]; then
    kubectl -n "$NS" cp "$POD:$DS_ARCHIVE_PATH" "$host_dst" -c "$CONTAINER"
  else
    kubectl -n "$NS" cp "$POD:$DS_ARCHIVE_PATH" "$host_dst"
  fi

  log "Done: $host_dst"
  echo "$host_dst"
  exit 0
fi

# ------------------------------------------------------------------------------
# Mode B: Inside pod
# ------------------------------------------------------------------------------
: "${OUT_BASE:=/tmp}"   # In-pod default

# Ensure dovecot-sysreport exists in the container
if ! command -v dovecot-sysreport >/dev/null 2>&1; then
  echo "dovecot-sysreport not found in PATH inside the pod" >&2
  exit 1
fi

# Run dovecot-sysreport (no --core by default)
DS_CMD="dovecot-sysreport"
if [[ -n "$CORE_IN_POD" ]]; then
  DS_CMD="$DS_CMD --core $CORE_IN_POD"
  log "Running dovecot-sysreport with --core $CORE_IN_POD"
else
  log "Running dovecot-sysreport (no core)"
fi

sh -lc "$DS_CMD" || true

# Find the produced archive and copy to OUT_BASE for convenience
ds_archive="$(sh -lc "$find_ds_archive_cmd" | tr -d '\r' || true)"
[[ -n "$ds_archive" && -f "$ds_archive" ]] || { echo "dovecot-sysreport archive not found inside pod" >&2; exit 1; }

mkdir -p "$OUT_BASE"
dest="$OUT_BASE/$(basename "$ds_archive")"
cp -f "$ds_archive" "$dest" || true

log "Done: $dest"
echo "$dest"
