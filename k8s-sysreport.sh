#!/usr/bin/env bash
# Full k8s-sysreport.sh script
set -uo pipefail
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="/tmp/k8s-sysreport-${STAMP}"
ARCHIVE="/tmp/k8s-sysreport-${STAMP}.tar.gz"
mkdir -p "$OUT_DIR"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
save_cmd() {
  local path="$1"; shift
  {
    echo '$' "$@"
    timeout 10s "$@" 2>&1 || true
  } > "$OUT_DIR/$path"
}

log "Collecting basic info"
save_cmd uname.txt uname -a
save_cmd date.txt date -u
save_cmd id.txt id
save_cmd whoami.txt whoami

log "Collecting OS info"
save_cmd os-release.txt cat /etc/os-release
save_cmd cpuinfo.txt head -200 /proc/cpuinfo
save_cmd meminfo.txt head -200 /proc/meminfo

log "Collecting process info"
save_cmd ps.txt ps -ef
save_cmd top.txt sh -c 'command -v top && top -b -n1 || echo no top'
save_cmd pstree.txt sh -c 'command -v pstree && pstree -al || true'

log "Collecting network info"
save_cmd resolv.conf cat /etc/resolv.conf
save_cmd hosts cat /etc/hosts
save_cmd interfaces.txt sh -c 'ip -brief addr || ifconfig -a || true'
save_cmd routes.txt sh -c 'ip route || route -n || true'
save_cmd ss.txt sh -c 'ss -pant || netstat -pant || true'

log "Collecting env (redacted)"
REDACT='PASS|SECRET|TOKEN|KEY|AWS_|GCP_|AZURE_'
{ 
  env | sort | while IFS='=' read -r k v; do
    if echo "$k" | grep -Eiq "$REDACT"; then
      echo "$k=****REDACTED****"
    else
      echo "$k=$v"
    fi
  done
} > "$OUT_DIR/env.txt"

log "Collecting filesystem info"
save_cmd df.txt df -h
save_cmd mounts.txt cat /proc/self/mountinfo

log "Packaging"
tar -C "$OUT_DIR" -czf "$ARCHIVE" .
log "Done: $ARCHIVE"
echo "$ARCHIVE"
