## DEPRECATED.  Use:  https://github.com/elastic/cloud-on-k8s/blob/master/hack/diagnostics/eck-dump.sh


## ECK Diagnostics

Collects Docker, System and Kubernetes level information from ECK for Elastic Support Team

- Docker ps,info,images, and container stats (`-d`), run on the kubernetes node
- Various System Information (OS, processes, disk, network, SAR stats) (`-s`), run on the kubernetes node
- Kubernetes version, nodes, elastic-related resources, and elastic-related pod logs (`-k`), run anywhere you have `kubectl`



## Usage

```
[root@yourhost]# ./eck-diagnostics.sh
ECK Diagnostics
Usage: ./eck-diagnostics.sh [OPTIONS]

Options:
-s|--system #collects system information
-d|--docker #collects docker information
-k|--kubernetes #collects kubernetes information Optionally specify kinds | pods,pv,pvc,configmap,ingress,service,deployment,statefulset,events,networkpolicies
-n|--kubernetes-namespace #location of user resources | default
-N|--kubernetes-operator-namespace # location of elastic operators | elastic-system
-t|--kubernetes-logs-since #kubernetes logs since | 1h (max 10000)
-nl|--kubernetes-skip-logs #don't collect kubernetes logs
-o|--output-path #Specifies the output directory to dump the diagnostic bundles | /tmp
-h|--help #shows this

Sample usage:
"./eck-diagnostics.sh -d -s -k" #collects docker, system and kubernetes level info
```

## Examples

Collect Docker, Sytem, and Kubernetes information from the default namespace, including the last hour of logs from user pods and the elastic operator pod

```
./eck-diagnostics.sh -d -s -k
```

Collect the last 24 hours of pod logs, and use a non-default namespace

```
./eck-diagnostics.sh -d -s -k -t 24h -n my-elastic-namespace 
```

Collect Kubernetes information and output to a custom directory 

```
./eck-diagnostics.sh -k -o /custom/storage   
```

Restrict resource collection to pods and configmaps.  Note that this does not prevent the capture of elastic custom resources (kubectl get elastic), or collection of base information (kubectl get nodes, e.g.)

```
./eck-diagnostics.sh -k pods,configmaps
```
