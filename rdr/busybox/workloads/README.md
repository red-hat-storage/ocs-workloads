# OpenShift SCC Testing Workloads

Test busybox workloads with different Security Context Constraints (SCC) and storage types.

## Structure

```
workloads/
├── app-busybox-scc-restricted/     # Restricted SCC (most secure)
│   ├── base/                       # Common SCC configuration
│   └── overlays/
│       ├── rbd/                    # RBD storage overlay
│       └── cephfs/                 # CephFS storage overlay
├── app-busybox-scc-anyuid/         # Anyuid SCC
│   ├── base/
│   └── overlays/
│       ├── rbd/
│       └── cephfs/
└── app-busybox-scc-privileged/     # Privileged SCC (testing only)
    ├── base/
    └── overlays/
        ├── rbd/
        └── cephfs/
```

## Quick Start

### Choose SCC Level + Storage Type

| SCC Level | Storage | Command |
|-----------|---------|---------|
| **Restricted** | RBD | `oc create -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/rbd/` |
| **Restricted** | CephFS | `oc create -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/cephfs/` |
| **Anyuid** | RBD | `oc create -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/rbd/` |
| **Anyuid** | CephFS | `oc create -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/cephfs/` |
| **Privileged** | RBD | `oc create -k rdr/busybox/workloads/app-busybox-scc-privileged/overlays/rbd/` |
| **Privileged** | CephFS | `oc create -k rdr/busybox/workloads/app-busybox-scc-privileged/overlays/cephfs/` |

**Note**: Anyuid and Privileged require additional SCC grants (see individual READMEs).

## SCC Levels

### Restricted (Recommended)
- **Directory**: `app-busybox-scc-restricted/`
- **Security**: Most secure, non-root, no capabilities
- **Use**: Production environments

### Anyuid
- **Directory**: `app-busybox-scc-anyuid/`
- **Security**: Runs as UID 1000, dropped capabilities
- **Use**: When specific UID/GID is required

### Privileged
- **Directory**: `app-busybox-scc-privileged/`
- **Security**: Full privileges, SYS_ADMIN capability
- **Use**: Testing/debugging only

## Storage Types

### RBD (Block Storage)
- **Path**: `overlays/rbd/`
- **StorageClass**: `ocs-storagecluster-ceph-rbd`
- **Access Mode**: ReadWriteOnce
- **Use**: Single pod access

### CephFS (File Storage)
- **Path**: `overlays/cephfs/`
- **StorageClass**: `ocs-storagecluster-cephfs`
- **Access Mode**: ReadWriteMany
- **Use**: Multi-pod shared access

## What Gets Deployed

Each workload deploys:
- **1 ServiceAccount**: `busybox-scc-sa`
- **10 Deployments**: `busybox-1` through `busybox-10`
- **10 PVCs**: With chosen storage class (RBD or CephFS)

## Examples

### Example 1: Restricted SCC with RBD
```bash
oc create -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/rbd/ -n my-test
```

### Example 2: Anyuid SCC with CephFS
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/cephfs/ -n my-test

# Grant SCC
oc adm policy add-scc-to-user anyuid system:serviceaccount:my-test:busybox-scc-sa

# Restart
oc rollout restart deployment -l scc-testing=true -n my-test
```

## Verification

```bash
# Check assigned SCC
oc get pod -o jsonpath='{.items[*].metadata.annotations.openshift\.io/scc}'

# Check storage class
oc get pvc -o jsonpath='{.items[*].spec.storageClassName}'

# Check access mode
oc get pvc -o jsonpath='{.items[*].spec.accessModes}'

# Check UID/GID
oc exec deployment/busybox-1 -- id
```

## See Also

- Individual SCC level READMEs in each `app-busybox-scc-*/` directory
- Base deployment configs: `rdr/busybox/base/`
