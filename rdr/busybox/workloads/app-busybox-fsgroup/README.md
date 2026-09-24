# Busybox - FSGroup and SupplementalGroups Testing

Test filesystem group ownership and supplemental groups for storage access control.

## Security Feature: FSGroup & SupplementalGroups

- **fsGroup**: 2000 - All volumes owned by this GID
- **supplementalGroups**: [3000, 4000] - Additional group memberships
- Use case: Multi-user storage access, database workloads
- Works with persistent volumes

## How It Works

1. **fsGroup**: All files created in volumes get GID 2000
2. **supplementalGroups**: Process runs with additional group memberships
3. Enables fine-grained access control to shared storage
4. Important for database and multi-tenant workloads

## Usage

### Option 1: RBD Storage
```bash
oc create -k rdr/busybox/workloads/app-busybox-fsgroup/overlays/rbd/ -n <namespace>
```

### Option 2: CephFS Storage
```bash
oc create -k rdr/busybox/workloads/app-busybox-fsgroup/overlays/cephfs/ -n <namespace>
```

## Verification

```bash
# Check groups in container
oc exec deployment/busybox-1 -- id
# Should show: groups=2000,3000,4000

# Create file and check ownership
oc exec deployment/busybox-1 -- touch /mnt/test/testfile
oc exec deployment/busybox-1 -- ls -l /mnt/test/testfile
# Group should be 2000

# Check all groups
oc exec deployment/busybox-1 -- cat /proc/self/status | grep Groups
```

## Use Cases

### Database Workloads
```yaml
# PostgreSQL example
securityContext:
  fsGroup: 26  # postgres group
  supplementalGroups: [999]  # Additional access
```

### Shared Storage Access
```yaml
# Multiple users accessing same PVC
securityContext:
  fsGroup: 5000  # Shared group
  supplementalGroups: [5001, 5002]  # Team groups
```

### Log Aggregation
```yaml
# Sidecar pattern with shared log volume
securityContext:
  fsGroup: 1000  # Log group
  supplementalGroups: [1001]  # Monitoring group
```

## Storage Considerations

- **RBD**: Works with fsGroup for block storage
- **CephFS**: Full POSIX permissions, fsGroup applied
- **NFS**: Depends on server squash settings
- **HostPath**: fsGroup may not apply (depends on host FS)

## Cleanup

```bash
oc delete -k rdr/busybox/workloads/app-busybox-fsgroup/overlays/rbd/ -n <namespace>
```

## Notes

- Requires SCC that allows fsGroup (anyuid, nonroot with supplemental groups)
- Some storage classes may ignore fsGroup
- Check storage class supports fsGroup before using
- Useful for database statefulsets and shared storage scenarios
