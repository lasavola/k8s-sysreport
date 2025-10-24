#!/usr/bin/env bash
set -euo pipefail

SCRIPT="./kubectl-sysreport.sh"   # or ./dovecot-k8s-sysreport
chmod +x "$SCRIPT"

TMPDIR="$(mktemp -d)"
export PATH="$TMPDIR:$PATH"

cat > "$TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"

# Minimal mock behavior for queries used by the script
if [[ "$args" == *"get pod"* && "$args" == *"jsonpath='{.spec.nodeName}'"* ]]; then
  echo "mock-node-1"
elif [[ "$args" == *"get pod"* && "$args" == *"jsonpath='{.spec.containers[*].name}'"* ]]; then
  echo "dovecot sidecar"
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

echo "=== Testing kubectl-sysreport.sh (mock mode) ==="
# Use new flags instead of positional args
"$SCRIPT" --namespace default --pod testpod

OUTFILE=$(ls k8s-sysreport-default-testpod-*.tar.gz 2>/dev/null | tail -n1)
if [ -f "$OUTFILE" ]; then
  echo "✔ Archive created: $OUTFILE"
  tar -tzf "$OUTFILE" | head -n 10
else
  echo "✖ Failed: archive not created"
  exit 1
fi

echo "✅ kubectl-sysreport.sh test completed successfully."