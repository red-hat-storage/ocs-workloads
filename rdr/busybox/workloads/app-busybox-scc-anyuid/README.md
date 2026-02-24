# Busybox SCC Testing - Anyuid

Test busybox workloads with **anyuid** SCC using either RBD or CephFS storage.

## Security Level: Anyuid

- Runs as UID/GID 1000:1000
- No privilege escalation
- Dropped capabilities

## Usage

### Option 1: RBD Storage (Block, ReadWriteOnce)
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/rbd/ -n <namespace>

# Grant SCC
oc adm policy add-scc-to-user anyuid system:serviceaccount:<namespace>:busybox-scc-sa

# Restart pods
oc rollout restart deployment -l scc-testing=true -n <namespace>
```

### Option 2: CephFS Storage (File, ReadWriteMany)
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/cephfs/ -n <namespace>

# Grant SCC
oc adm policy add-scc-to-user anyuid system:serviceaccount:<namespace>:busybox-scc-sa

# Restart pods
oc rollout restart deployment -l scc-testing=true -n <namespace>
```

## Verification

```bash
# Check SCC (should show 'anyuid')
oc get pod -o jsonpath='{.items[*].metadata.annotations.openshift\.io/scc}'

# Verify UID/GID (should show uid=1000 gid=1000)
oc exec deployment/busybox-1 -- id

# Check storage class
oc get pvc -o jsonpath='{.items[*].spec.storageClassName}'
```

## Cleanup

```bash
# Remove SCC binding
oc adm policy remove-scc-from-user anyuid system:serviceaccount:<namespace>:busybox-scc-sa

# Delete workload (RBD or CephFS)
oc delete -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/rbd/ -n <namespace>
# OR
oc delete -k rdr/busybox/workloads/app-busybox-scc-anyuid/overlays/cephfs/ -n <namespace>
```
