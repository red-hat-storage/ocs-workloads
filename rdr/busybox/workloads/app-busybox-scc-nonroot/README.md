# Busybox SCC Testing - NonRoot

Test busybox workloads with **nonroot** SCC (middle ground between restricted and anyuid).

## Security Level: NonRoot

- Must run as non-root user (UID > 0)
- Can specify UID (1001 in this case)
- No privilege escalation
- All capabilities dropped
- More flexible than restricted, more secure than anyuid

## Usage

### Option 1: RBD Storage
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-nonroot/overlays/rbd/ -n <namespace>

# Grant SCC
oc adm policy add-scc-to-user nonroot system:serviceaccount:<namespace>:busybox-scc-sa

# Restart pods
oc rollout restart deployment -l scc-testing=true -n <namespace>
```

### Option 2: CephFS Storage
```bash
# Deploy
oc create -k rdr/busybox/workloads/app-busybox-scc-nonroot/overlays/cephfs/ -n <namespace>

# Grant SCC
oc adm policy add-scc-to-user nonroot system:serviceaccount:<namespace>:busybox-scc-sa

# Restart pods
oc rollout restart deployment -l scc-testing=true -n <namespace>
```

## Verification

```bash
# Check SCC (should show 'nonroot')
oc get pod -o jsonpath='{.items[*].metadata.annotations.openshift\.io/scc}'

# Verify UID (should show uid=1001)
oc exec deployment/busybox-1 -- id
```

## Cleanup

```bash
oc adm policy remove-scc-from-user nonroot system:serviceaccount:<namespace>:busybox-scc-sa
oc delete -k rdr/busybox/workloads/app-busybox-scc-nonroot/overlays/rbd/ -n <namespace>
```
