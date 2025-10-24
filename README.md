# Dovecot Kubernetes Sysreport Tools

This repository provides two complementary tools for gathering diagnostic information
from Kubernetes environments running **Dovecot**:

- **`k8s-sysreport.sh`** — Orchestrates running [`dovecot-sysreport`](https://github.com/dovecot/core/blob/main/src/util/dovecot-sysreport)
  either inside a Dovecot pod or remotely via `kubectl`.
- **`kubectl-sysreport.sh`** — Collects general Kubernetes-level diagnostics
  (pod, node, logs, events) for any pod, independent of Dovecot.

Both scripts produce timestamped `.tar.gz` archives suitable for attaching to bug reports or sharing with support.

---

## 📦 `k8s-sysreport.sh`

### Purpose

`k8s-sysreport.sh` avoids duplicating functionality from `dovecot-sysreport`.  
It simply orchestrates *how* the report is run and optionally transfers core dumps between host and pod.

### Features
- Runs `dovecot-sysreport` inside the pod or from host via `kubectl`
- Supports optional **core file** inclusion (`--core-file` / `--core-in-pod`)
- Allows specifying custom output directory (`--out-dir`)
- Prints `--help` if run with no parameters
- Returns the full path to the generated archive

---

### Usage

#### **Inside a Pod**
Run when you already have a shell in the Dovecot container:

```bash
curl -O https://raw.githubusercontent.com/dovecot/k8s-sysreport/refs/heads/main/k8s-sysreport.sh
chmod +x k8s-sysreport.sh

# Basic usage (no core)
./k8s-sysreport.sh

# Save to a specific directory
./k8s-sysreport.sh --out-dir /data/reports

# If a core file already exists in the container
./k8s-sysreport.sh --core-in-pod /tmp/core.1234
```

**Result:**
```
/tmp/k8s-sysreport-20251024T092553Z/dovecot-sysreport-20251024T092553Z.tar.gz
```

---

#### **From Admin Host (via `kubectl`)**

Run directly from a system that can reach the cluster.

```bash
./k8s-sysreport.sh   --namespace mail   --pod dovecot-backend-0   --container dovecot   --out-dir /tmp/reports
```

This automatically executes `dovecot-sysreport` inside the target container
and copies the resulting archive to `/tmp/reports` on the host.

---

### Including a Core File

If a Dovecot crash occurred, you can attach a core dump for deeper analysis.

#### Step 1: Dump the core on the host

Use `coredumpctl` to extract a specific Dovecot crash:

```bash
coredumpctl list dovecot
sudo coredumpctl dump -o /tmp/core.dovecot.1234 1234
```

#### Step 2: Run `k8s-sysreport.sh` with the core file

```bash
./k8s-sysreport.sh   --namespace mail   --pod dovecot-backend-0   --container dovecot   --core-file /tmp/core.dovecot.1234   --out-dir /tmp/reports
```

This will:

1. Copy `/tmp/core.dovecot.1234` into `/tmp` inside the pod
2. Run `dovecot-sysreport --core /tmp/core.dovecot.1234` inside the container
3. Copy the generated report tarball back to `/tmp/reports` on the host

---

### Parameters

| Parameter         | Description                                                              |
| ----------------- | ------------------------------------------------------------------------ |
| `--namespace, -n` | Kubernetes namespace of target pod (required in host mode)               |
| `--pod, -p`       | Pod name (required in host mode)                                         |
| `--container, -c` | Optional container name                                                  |
| `--out-dir, -o`   | Output directory (default: `/tmp` inside pod, current directory on host) |
| `--core-file`     | Path to host core file to copy into the pod before running               |
| `--core-in-pod`   | Path to an existing core file inside the pod                             |
| `--help, -h`      | Show usage help                                                          |

If no parameters are given, the script displays the help screen.

---

### Example Archive Content (from `dovecot-sysreport`)

```
dovecot-sysreport-20251024T200000Z/
├── dovecot.conf
├── dovecot.log
├── env.txt
├── ps.txt
├── netstat.txt
└── sysctl.txt
```

---

## ☸️ `kubectl-sysreport.sh`

### Purpose

Collects general Kubernetes diagnostics for a specific pod and its node.
Useful for identifying cluster-level or scheduling issues.

### Features

* Gathers:
  * Pod manifest and `kubectl describe`
  * Node information and events
  * Container logs (current and previous)
* Supports `--out-dir` for custom destination
* Safe to run — read-only and non-destructive

---

### Usage

```bash
curl -O https://raw.githubusercontent.com/dovecot/k8s-sysreport/refs/heads/main/kubectl-sysreport.sh
chmod +x kubectl-sysreport.sh

./kubectl-sysreport.sh   --namespace mail   --pod dovecot-backend-0   --out-dir /tmp/reports
```

**Output example:**
```
/tmp/reports/kubectl-sysreport-mail-dovecot-backend-0-20251024T093500Z.tar.gz
```

### Example Contents

```
kubectl-sysreport-mail-dovecot-backend-0-20251024T093500Z/
├── pod.yaml
├── pod.describe.txt
├── node.yaml
├── node.describe.txt
├── events.txt
├── log-dovecot.txt
└── log-dovecot-prev.txt
```

---

## 🧰 Notes

* Both scripts are **read-only** — they only collect information.
* No secret data is dumped; only references (e.g., secret names) may appear.
* `dovecot-sysreport` must be present inside the Dovecot container.
* Requires `kubectl` access when used from a host system.
* Running either script with no parameters will print its usage instructions.

---

## 📘 References

* [Dovecot sysreport](https://github.com/dovecot/core/blob/main/src/util/dovecot-sysreport)
* [coredumpctl man page](https://man7.org/linux/man-pages/man1/coredumpctl.1.html)
* [Kubernetes kubectl exec documentation](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#exec)

