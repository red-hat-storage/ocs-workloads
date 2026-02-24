# Busybox SCC Testing - Privileged

Test busybox workloads with **privileged** SCC using either RBD or CephFS storage.

**WARNING**: Use only in testing environments.

## Security Level: Privileged

- Privileged container mode
- SYS_ADMIN capability
- Full permissions

## Usage

### Option 1: RBD Storage (Block, ReadWriteOnce)
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-privileged/overlays/rbd/ -n <namespace>

# Grant SCC
oc adm policy add-scc-to-user privileged system:serviceaccount:<namespace>:busybox-scc-sa

# Restart pods
oc rollout restart deployment -l scc-testing=true -n <namespace>
```

### Option 2: CephFS Storage (File, ReadWriteMany)
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-privileged/overlays/cephfs/ -n <namespace>

# Grant SCC
oc adm policy add-scc-to-user privileged system:serviceaccount:<namespace>:busybox-scc-sa

# Restart pods
oc rollout restart deployment -l scc-testing=true -n <namespace>
```

## Verification

```bash
# Check SCC (should show 'privileged')
oc get pod -o jsonpath='{.items[*].metadata.annotations.openshift\.io/scc}'

# Verify privileged mode
oc exec deployment/busybox-1 -- cat /proc/1/status | grep Cap

# Check storage class
oc get pvc -o jsonpath='{.items[*].spec.storageClassName}'
```

## Cleanup

```bash
# Remove SCC binding
oc adm policy remove-scc-from-user privileged system:serviceaccount:<namespace>:busybox-scc-sa

# Delete workload (RBD or CephFS)
oc delete -k rdr/busybox/workloads/app-busybox-scc-privileged/overlays/rbd/ -n <namespace>
# OR
oc delete -k rdr/busybox/workloads/app-busybox-scc-privileged/overlays/cephfs/ -n <namespace>
```
