* This is Applicable for Subscption Workloads*

### There are few steps that are must before running RDR workload

- Create a fork for this repo https://docs.github.com/en/get-started/quickstart/fork-a-repo
- Navigate to subscriptions/channel and update the `PLACEHOLDER` with github user name
- Navigate to subscriptions/busybox/drpc.yaml 
  - Update `PLACEHOLDER-DRPOLICY-NAME` with drpolicy name 
    - To find out drpolicy name use `oc get drpolicy`
  - Update `PLACEHOLDER-C1-ClusterName` with cluster name where you want to run io and this cluster will act as primary site

### For Running the RDR workload

- **busybox**
- #### git clone the fork repo
- #### now run this cmd **`oc create -k rdr/$workload/app-$workload-1/subscriptions/ ; oc create -k rdr/$workload/app-$workload-1/subscriptions/busybox`** from hub cluster

 
* This is Applicable for AppSet Workloads*

### There are few steps that are must before running RDR workload

- Create a fork for this repo https://docs.github.com/en/get-started/quickstart/fork-a-repo
- Navigate to AppSet and update the `PLACEHOLDER` with ManagedCluster Name
