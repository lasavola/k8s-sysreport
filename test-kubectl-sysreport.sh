#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./kubectl-sysreport.sh"
chmod +x "$SCRIPT"

TMPDIR="$(mktemp -d)"
OUTDIR="$TMPDIR/out"
mkdir -p "$OUTDIR"
export PATH="$TMPDIR:$PATH"

# Mock kubectl binary
cat > "$TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == *"get pod"* && "$args" == *"jsonpath='{.spec.nodeName}'"* ]]; then
  echo "mock-node"
elif [[ "$args" == *"get pod"* && "$args" == *"jsonpath='{.spec.containers[*].name}'"* ]]; then
  echo "main sidecar"
elif [[ "$args" == *"get pod"* && "$args" == *"-o yaml"* ]]; then
  echo "fake pod yaml"
elif [[ "$args" == *"describe pod"* ]]; then
  echo "fake pod description"
elif [[ "$args" == *"get node"* && "$args" == *"-o yaml"* ]]; then
  echo "fake node yaml"
elif [[ "$args" == *"describe node"* ]]; then
  echo "fake node description"
elif [[ "$args" == *"get events"* ]]; then
  echo "fake event list"
elif [[ "$args" == *"logs"* ]]; then
  echo "fake logs from container"
else
  echo "kubectl mock: $args"
fi
EOF
chmod +x "$TMPDIR/kubectl"

echo "=== Testing kubectl-sysreport.sh with mock kubectl ==="
ARCHIVE_PATH="$("$SCRIPT" --namespace default --pod testpod --out-dir "$OUTDIR")"

if [ -f "$ARCHIVE_PATH" ]; then
  echo "✔ Archive created: $ARCHIVE_PATH"
  tar -tzf "$ARCHIVE_PATH" | head -n 10
else
  echo "✖ Failed: archive not created at $ARCHIVE_PATH"
  exit 1
fi

echo "✅ kubectl-sysreport.sh test completed successfully."
