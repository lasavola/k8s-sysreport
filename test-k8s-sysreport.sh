#!/usr/bin/env bash
set -euo pipefail

# Optional --out-dir (default ./out for CI artifact collection)
OUT_DIR="out"
if [[ "${1:-}" == "--out-dir" ]]; then
  OUT_DIR="$2"; shift 2
fi
mkdir -p "$OUT_DIR"

SCRIPT="./k8s-sysreport.sh"
chmod +x "$SCRIPT"

echo "=== Preparing mocks ==="
MOCKROOT="$(mktemp -d)"
PODROOT="$MOCKROOT/podfs"      # fake pod filesystem root
mkdir -p "$MOCKROOT/bin" "$PODROOT/tmp"
export PATH="$MOCKROOT/bin:$PATH"

# --- Mock dovecot-sysreport (used for inside-pod mode) ---
cat > "$MOCKROOT/bin/dovecot-sysreport" <<'EOF'
#!/usr/bin/env bash
# Creates a tarball under /tmp to simulate real dovecot-sysreport output
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/dovecot-sysreport-${STAMP}.tar.gz"
TMPD="$(mktemp -d)"
echo "mock dovecot report" > "$TMPD/report.txt"
tar -czf "$OUT" -C "$TMPD" report.txt
echo "Created $OUT" >&2
EOF
chmod +x "$MOCKROOT/bin/dovecot-sysreport"

# --- Robust kubectl mock (SKIPS GLOBAL FLAGS before subcommand) ---
cat > "$MOCKROOT/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PODROOT="${PODROOT:-/tmp/fakepod}"

# Consume global flags (e.g., -n default, --namespace default, etc.)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace|--context|--cluster|--user|--kubeconfig)
      # flags with a value
      [[ $# -ge 2 ]] || exit 1
      shift 2
      ;;
    --) shift; break ;;
    -*)
      # single-arg global flags with no value
      shift
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -gt 0 ]] || { echo "[kubectl-mock] no subcommand" >&2; exit 1; }
sub="$1"; shift

case "$sub" in
  cp)
    # Accept optional -c/--container/-n/--namespace anywhere; last two non-flags are SRC DST
    nonflags=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -c|--container|-n|--namespace) shift 2 ;;
        --) shift ;;  # ignore
        -* ) shift ;;
        *  ) nonflags+=("$1"); shift ;;
      esac
    done
    [[ ${#nonflags[@]} -ge 2 ]] || { echo "[kubectl-mock] cp: need SRC DST" >&2; exit 1; }
    SRC="${nonflags[-2]}"
    DST="${nonflags[-1]}"

    if [[ "$SRC" == *:* && "$DST" != *:* ]]; then
      # pod -> host
      podpath="${SRC#*:}"
      srcpath="$PODROOT$podpath"
      cp -f "$srcpath" "$DST"
      echo "[kubectl-mock] cp pod:$podpath -> $DST" >&2
    elif [[ "$DST" == *:* && "$SRC" != *:* ]]; then
      # host -> pod
      podpath="${DST#*:}"
      dstpath="$PODROOT$podpath"
      mkdir -p "$(dirname "$dstpath")"
      cp -f "$SRC" "$dstpath"
      echo "[kubectl-mock] cp $SRC -> pod:$podpath" >&2
    else
      echo "[kubectl-mock] unsupported cp form: SRC=$SRC DST=$DST" >&2
      exit 1
    fi
    ;;

  exec)
    # Form: exec <pod> [ -c <container> ] -- sh -lc "<cmd>"
    [[ $# -gt 0 ]] || { echo "[kubectl-mock] exec: missing pod" >&2; exit 1; }
    pod="$1"; shift

    # Consume optional flags until '--'
    while [[ $# -gt 0 && "$1" != "--" ]]; do
      case "$1" in
        -c|--container|-n|--namespace) shift 2 ;;
        -* ) shift ;;
        *  ) shift ;;
      esac
    done

    # Expect '--'
    [[ $# -gt 0 && "$1" == "--" ]] && shift || true

    # Remaining should be: sh -lc "<cmd>" (we grab whatever follows -lc)
    if [[ "$1" == "sh" && "${2:-}" == "-lc" ]]; then
      shift 2
      run="$*"
    else
      run="$*"
    fi

    mkdir -p "$PODROOT/tmp"

    # IMPORTANT: check the 'ls' listing FIRST so it doesn't match the 'dovecot-sysreport' condition
    if [[ "$run" == *"ls -1t /tmp/dovecot-sysreport-"* ]]; then
      # List newest tar (strip PODROOT so it looks in-pod)
      ls -1t "$PODROOT"/tmp/dovecot-sysreport-*.tar.* 2>/dev/null | sed "s|$PODROOT||" | head -n1
      exit 0
    fi

    # Produce a dovecot-sysreport tar inside the pod FS
    if [[ "$run" == *"dovecot-sysreport"* ]]; then
      STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
      OUT="$PODROOT/tmp/dovecot-sysreport-${STAMP}.tar.gz"
      TD="$(mktemp -d)"
      echo "mock dovecot report (pod)" > "$TD/report.txt"
      tar -czf "$OUT" -C "$TD" report.txt
      echo "[kubectl-mock] exec: produced $OUT" >&2
      exit 0
    fi

    echo "[kubectl-mock] exec: $run" >&2
    ;;

  *)
    echo "[kubectl-mock] unsupported subcommand: $sub" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCKROOT/bin/kubectl"

export PODROOT  # for the kubectl mock to know where the "pod fs" lives

echo "kubectl used: $(command -v kubectl)"

echo "=== Test 1: inside-pod mode (uses mocked dovecot-sysreport) ==="
OUT1="$("$SCRIPT" --out-dir "$OUT_DIR/out1" | tail -n1)"
if [[ -f "$OUT1" ]]; then
  echo "✔ Archive created (inside-pod): $OUT1"
  tar -tzf "$OUT1" | head -n 5
else
  echo "✖ Failed (inside-pod): no archive created"
  exit 1
fi

echo "=== Test 2: kubectl mode (no core) ==="
OUT2="$("$SCRIPT" --namespace default --pod testpod --out-dir "$OUT_DIR/out2" | tail -n1)"
if [[ -f "$OUT2" ]]; then
  echo "✔ Archive created (kubectl no-core): $OUT2"
  tar -tzf "$OUT2" | head -n 5
else
  echo "✖ Failed (kubectl no-core): no archive created"
  exit 1
fi

echo "=== Test 3: kubectl mode with --core-file ==="
FAKECORE="$MOCKROOT/core.dovecot.9999"
echo "fake core" > "$FAKECORE"
OUT3="$("$SCRIPT" --namespace default --pod testpod --out-dir "$OUT_DIR/out3" --core-file "$FAKECORE" | tail -n1)"
if [[ -f "$OUT3" ]]; then
  echo "✔ Archive created (kubectl with core-file): $OUT3"
  tar -tzf "$OUT3" | head -n 5
else
  echo "✖ Failed (kubectl with core-file): no archive created"
  exit 1
fi

echo "✅ All k8s-sysreport.sh tests passed."
