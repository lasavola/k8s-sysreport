#!/usr/bin/env bash
set -euo pipefail
echo "=== Testing k8s-sysreport.sh ==="
chmod +x ./k8s-sysreport.sh
OUT=$(./k8s-sysreport.sh | tail -n1)
if [ -f "$OUT" ]; then
  echo "✔ Archive created: $OUT"
  tar -tzf "$OUT" | head -n 10
else
  echo "✖ Failed: no archive created"
  exit 1
fi
echo "✅ k8s-sysreport.sh test completed successfully."
