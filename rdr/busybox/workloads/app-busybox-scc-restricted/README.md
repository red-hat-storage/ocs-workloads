# Busybox SCC Testing - Restricted

Test busybox workloads with **restricted** SCC (most secure) using either RBD or CephFS storage.

## Security Level: Restricted

- Non-root execution required
- No privilege escalation
- All capabilities dropped
- RuntimeDefault seccomp profile

## Usage

### Option 1: RBD Storage (Block, ReadWriteOnce)
```bash
oc create -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/rbd/ -n <namespace>
```

### Option 2: CephFS Storage (File, ReadWriteMany)
```bash
oc create -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/cephfs/ -n <namespace>
```

## Verification

```bash
# Check SCC (should show 'restricted' or 'restricted-v2')
oc get pod -o jsonpath='{.items[*].metadata.annotations.openshift\.io/scc}'

# Check storage class
oc get pvc -o jsonpath='{.items[*].spec.storageClassName}'

# Verify non-root
oc exec deployment/busybox-1 -- id
```

## Cleanup

```bash
# For RBD
oc delete -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/rbd/ -n <namespace>

# For CephFS
oc delete -k rdr/busybox/workloads/app-busybox-scc-restricted/overlays/cephfs/ -n <namespace>
```
