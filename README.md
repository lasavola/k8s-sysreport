# Kubernetes Sysreport

This utility collects system and Kubernetes diagnostics similar to
[`dovecot-sysreport`](https://github.com/dovecot/core/blob/main/src/util/dovecot-sysreport),
but adapted for containerized and cluster environments.

It helps debugging pod-level and cluster-level issues by gathering:
- OS, process, and resource info
- Network configuration and cgroup limits
- Environment variables (redacted)
- Application-specific logs (Dovecot aware)
- Kubernetes pod/node descriptions, events, and logs

## Usage

### A) Inside a Pod
```bash
curl -O https://example.com/k8s-sysreport.sh
chmod +x k8s-sysreport.sh
./k8s-sysreport.sh
```

This generates `/tmp/k8s-sysreport-<timestamp>.tar.gz` inside the container.

You can retrieve it via:
```bash
kubectl cp <namespace>/<pod>:/tmp/k8s-sysreport-<timestamp>.tar.gz .
```

### B) From Outside (Admin Host)
```bash
curl -O https://example.com/kubectl-sysreport.sh
chmod +x kubectl-sysreport.sh
./kubectl-sysreport.sh <namespace> <pod>
```

This collects logs, events, node info, and manifests for the pod and saves them into a tarball:
```
k8s-sysreport-<namespace>-<pod>-<timestamp>.tar.gz
```

## Notes
- The scripts are safe to run read-only; they don’t modify the system.
- Secret data is **not** dumped, only referenced.
- Works with BusyBox, Debian, or Alpine base images.
