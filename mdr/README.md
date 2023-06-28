## This is Applicable for Subscription Workloads

#### There are few steps that are must before running MDR workload

- Create a fork for this repo (reference how to fork a repo https://docs.github.com/en/get-started/quickstart/fork-a-repo)
- Navigate to mdr/subscriptions/busybox-app-1/channel.yaml and update the `PLACEHOLDER` with github user name
- Navigate to mdr/subscriptions/busybox-app-1/busybox/drpc.yaml
  - Update `PLACEHOLDER-DRPOLICY-NAME` with drpolicy name
    - To find out drpolicy name run `oc get drpolicy` in hub cluster
  - Update `PLACEHOLDER-C1-ClusterName` with cluster name where you want to run io and this cluster will act as primary site

#### For Running the MDR Subscription workload 

- **busybox**
- ##### git clone the fork repo
- ##### now run this cmd **`oc create -k mdr/subscriptions/$workload-app-1/ ; oc create -k mdr/subscriptions/$workload-app-1/$workload/`** from hub cluster
