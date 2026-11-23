# Reproduce AKS #5743 on one NVMe node

From this directory, run the following in an authorized Azure test subscription. The disk test needs Bash, Azure CLI, kubectl, curl, jq and shasum. The two files in this directory are sufficient.

```bash
az account show --query name -o tsv
bash reproduce.sh
```

The runner creates a disposable **Standard_D8as_v7 in West US 2** with a managed NVMe OS disk. It keeps one Premium SSD PVC mounted while attaching and detaching a second. It first seeds the original PVC to 128 KiB to expose an untreated reset. It then applies the exact posted DaemonSet, repeats three attach/detach cycles at different points in the 60-second polling interval, and replaces the DaemonSet pod once. It uses privileged pods on this dedicated node. [Issue #5743](https://github.com/Azure/AKS/issues/5743) · [Posted DaemonSet](https://github.com/Azure/AKS/issues/5743#issuecomment-6265013208)

### What to look for

The runner prints the original PVC's device and major:minor, its natural optimal I/O size in bytes, and its natural readahead in KiB. Follow **that same device** in the timestamped output as the second device appears and disappears. In the November 21, 2026 lab, the data device was `nvme0n2`.

| Observation | Result on the tested node |
|---|---|
| Fresh OS and data disks | 33,554,432-byte optimal I/O and 65,536 KiB readahead |
| Attach or detach with the DaemonSet absent | Original PVC went from 128 back to 65,536 KiB |
| Attach or detach with the DaemonSet running | Original PVC went from 128 to 65,536 and back to 128 KiB on all six events |
| DaemonSet pod replaced while queues were high | New pod corrected the OS disk and both attached PVCs |

The runner saves one independent sample per second in `queues.log` and prints only changes. Subtract the first high timestamp from the next low timestamp to estimate exposure. The lab observed **7–52 seconds**. If samples go directly from 128 to 128 across an event, report “no reset observed.” If the natural default differs, report the value and node image you actually saw.

### Optional Elasticsearch comparison

For the application test, run the following from this directory in the full repository.

```bash
bash reproduce.sh elasticsearch
```

This command provisions its own disposable node. It also needs Python 3.12+. It copies the benchmark inputs from the adjacent `aks-readahead-lab` directory, indexes two million public GeoNames records on a private Elasticsearch node, and repeats the same searches across three conditions.

| Guest-cold search | Guest MiB read per query | Client p95 |
|---|---:|---:|
| JVM started at the natural 64 MiB setting | 4.153 | 5,604 ms |
| DaemonSet corrected to 128 KiB, same JVM and open segment | 4.153 | 5,276 ms |
| JVM restarted at 128 KiB | 0.377 | 22.9 ms |

These are reference measurements from two repetitions. With the index fully resident, all three states issued zero guest reads. Inspect your run's `search/pooled.csv` for results, `search/benchmark.csv` for individual passes and sampled readahead, and `search/raw/bench-events.txt` for any deliberately simulated high baseline. [Full benchmark and limitations](../aks-readahead-lab/REPORT.md)

### Verified replay, November 22, 2026

Both commands completed on fresh AKS clusters. The observer saw all six disk resets correct in 13.03–52.08 seconds, including a DaemonSet pod replacement. The Elasticsearch replay indexed 2,000,000 documents and completed 2,304 measured requests with zero errors or timeouts. Cold guest reads averaged 4.159 MiB/query before and after live correction, then 0.380 MiB/query after restart. Azure confirmed deletion of both clusters’ lab and node resource groups. [Disk-event timeline](../aks-readahead-lab/verification/disk/aks-5743.sWxSUb/observed-events.csv) · [Elasticsearch results](../aks-readahead-lab/verification/elasticsearch/aks-5743.nh6VB8/search/pooled.csv)

### Debug output

The startup line prints the local results directory. Follow `debug/run.log` there for timestamped stages and ingest progress. `search/raw/ingest.log` contains the full indexing output, including the document-count check. If an Elasticsearch API request receives an HTTP error, the client records its method, path, status and up to 4 KiB of the server response. A completed replay prints the pass count, sampled readahead check and request error count. Before cleanup, the runner also collects pod status, events and available server/client logs in `debug/`.

To keep each run under a directory of your choice, use this command.

```bash
REPRO_OUTPUT_DIR="$HOME/aks-repro-runs" bash reproduce.sh elasticsearch
```

### Cleanup and version

Both commands print the unique lab and node resource group names and the local results directory at startup. On exit the runner deletes the tagged lab group and checks that **both group names report `exists: false`**. If the shell is forcibly terminated, use the printed names in the same subscription to delete the lab group and verify both with `az group exists -n GROUP_NAME`.

The default AKS patch is **1.36.5**, matching the original test. If West US 2 no longer offers it, use `az aks get-versions -l westus2 -o table` and pass an available patch as `AKS_VERSION=x.y.z bash reproduce.sh`. Include the substituted patch and printed node image when reporting results.
