#!/usr/bin/env bash
set -euo pipefail
SCRIPT="./kubectl-sysreport.sh"
chmod +x "$SCRIPT"
TMPDIR=$(mktemp -d)
export PATH="$TMPDIR:$PATH"
cat > "$TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$@" in
  *"get pod"*) echo "fake pod yaml" ;;
  *"describe pod"*) echo "fake pod description" ;;
  *"get node"*) echo "fake node yaml" ;;
  *"describe node"*) echo "fake node description" ;;
  *"get events"*) echo "fake event list" ;;
  *"logs"*) echo "fake logs from container" ;;
  *) echo "kubectl mock: $@" ;;
esac
EOF
chmod +x "$TMPDIR/kubectl"
echo "=== Testing kubectl-sysreport.sh (mock mode) ==="
./kubectl-sysreport.sh default testpod
OUTFILE=$(ls k8s-sysreport-default-testpod-*.tar.gz 2>/dev/null | tail -n1)
if [ -f "$OUTFILE" ]; then
  echo "✔ Archive created: $OUTFILE"
  tar -tzf "$OUTFILE" | head -n 10
else
  echo "✖ Failed: archive not created"
  exit 1
fi
echo "✅ kubectl-sysreport.sh test completed successfully."
