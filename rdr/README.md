### There are few steps that are must before running RDR workload

- Create a fork for this repo https://docs.github.com/en/get-started/quickstart/fork-a-repo
- Navigate to subscriptions/channel and update the `PLACEHOLDER` with github user name
- Navigate to subscriptions/busybox/drpc.yaml 
  - Update `PLACEHOLDER-DRPOLICY-NAME` with drpolicy name 
    - To find out drpolicy name use `oc get drpolicy`
  - Update `PLACEHOLDER-C1-ClusterName` with cluster name where you want to run io and this cluster will act as primary site
- **Important** make sure you have storageclass created for rbd-mirror usage with name as `ocs-storagecluster-ceph-rbd-mirror

### For Running the RDR workload

- ####git clone the fork repo
- ####now run this cmd **`oc create -k rdr/subscriptions/ ; oc create -k rdr/subscriptions/busybox`** from hub cluster

 