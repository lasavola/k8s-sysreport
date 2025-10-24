---

````markdown
# Kubernetes Sysreport

This utility collects system and Kubernetes diagnostics similar to
[`dovecot-sysreport`](https://github.com/dovecot/core/blob/main/src/util/dovecot-sysreport),
but adapted for containerized and cluster environments.

It helps debug pod-level and cluster-level issues by gathering:
- OS, process, and resource info  
- Network configuration and cgroup limits  
- Environment variables (with sensitive data redacted)  
- Application-specific logs (Dovecot-aware)  
- Kubernetes Pod and Node descriptions, events, and logs  

---

## Usage

### A) Inside a Pod
```bash
curl -O https://example.com/k8s-sysreport.sh
chmod +x k8s-sysreport.sh
./k8s-sysreport.sh
````

This generates `/tmp/k8s-sysreport-<timestamp>.tar.gz` inside the container.

Retrieve it with:

```bash
kubectl cp <namespace>/<pod>:/tmp/k8s-sysreport-<timestamp>.tar.gz .
```

---

### B) From Outside (Admin Host)

```bash
curl -O https://example.com/dovecot-k8s-sysreport
chmod +x dovecot-k8s-sysreport
./dovecot-k8s-sysreport --namespace <namespace> --pod <pod>
```

Example:

```bash
./dovecot-k8s-sysreport --namespace mail --pod dovecot-proxy-0
```

This collects logs, events, node info, and manifests for the pod and saves them into a tarball:

```
k8s-sysreport-<namespace>-<pod>-<timestamp>.tar.gz
```

---

## Output Example

```
k8s-sysreport-mail-dovecot-proxy-0-20251024T193400Z/
├── pod.yaml
├── pod.describe.txt
├── node.yaml
├── node.describe.txt
├── events.txt
├── log-dovecot.txt
└── log-dovecot-prev.txt
```

---

## Notes

* Scripts are **read-only** — they do not modify the system or cluster.
* No Kubernetes Secrets or ConfigMaps are dumped; only names may be referenced.
* Works in environments using **BusyBox**, **Debian**, or **Alpine** base images.
* The `--namespace` and `--pod` flags make it safe and explicit which pod is inspected.

```
---
```
