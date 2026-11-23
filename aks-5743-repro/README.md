# AKS NVMe readahead in Azure Government

Test whether the [published DaemonSet](https://github.com/Azure/AKS/issues/5743#issuecomment-6265013208) restores readahead after a disk attach or detach on Azure Linux FIPS. The runner uses one disposable node and two Premium SSD PVCs.

## Deploy and test

Sign in to Azure CLI for `AzureUSGovernment` and select an authorized test subscription. From this directory, use Bash with `az`, `kubectl`, `jq`, `curl`, and `shasum`. On Windows, use WSL with the tools installed there.

```bash
AZ_CLOUD=AzureUSGovernment LOCATION=usgovvirginia \
  VM_SIZE=Standard_D4ads_v6 OS_SKU=AzureLinux FIPS=true \
  bash reproduce.sh disk
```

- Use `preflight` instead of `disk` to check regional SKU and AKS version availability without provisioning. The default patch is `1.36.5`; set `AKS_VERSION` to an offered patch if needed. Preflight cannot guarantee image availability, quota, or capacity.
- Use `fingerprint` to boot the node and inspect its natural queues without writing them or deploying the DaemonSet. To add an Ubuntu FIPS comparison, set `CONTROL_POOLS="ubu:Standard_D4ads_v6:Ubuntu:true"` on the same command. The `Ubuntu` alias does not pin the release. A SCSI control (`scsi:Standard_D8ads_v5:AzureLinux:true`) can be added if the SKU is available in the subscription.
- If GitHub is blocked, set `DAEMONSET_YAML=/path/to/posted.yaml` to the original manifest. The same pinned SHA-256 is required. `TARGET_RA_KB` defaults to `128`; the DaemonSet only lowers the value.

The disk test keeps the first PVC mounted while attaching and detaching the second. It compares untreated resets with three DaemonSet cycles and replaces the DaemonSet pod once. The privileged pods run only on the dedicated test nodes.

On exit, the runner deletes the tagged lab group, checks that **both resource groups report `exists: false`** in Azure Government, and restores the original CLI cloud. If interrupted before cleanup, use the printed group names in the same cloud and subscription to remove the tagged lab group and verify both. Do not switch clouds in another session sharing the CLI configuration during the run.

## How to read the result

The printed output directory contains `fingerprint.json` (guest FIPS state, OS, kernel, and natural disk settings), `queues.log` (one sample per second), the DaemonSet logs, and `debug/run.log`. Follow the original PVC device in the queue log, not the disk being attached or detached.

| Observation | Meaning |
|---|---|
| Managed NVMe `io_opt` is `33554432` bytes | `HOST_FIX_ABSENT`; expect 65,536 KiB on a kernel that applies twice the hint. |
| Managed NVMe `io_opt` is `262144` bytes | `HOST_FIX_PRESENT`; expect 512 KiB on a kernel that applies twice the hint. |
| Another managed NVMe hint | `OTHER`; inspect the recorded value. SCSI and local disks do not get this verdict. |
| Ubuntu FIPS shows 128 KiB with a 32 MiB hint | The observed queue does not follow twice the hint. Record the kernel and check for guest overrides before attributing the difference to the kernel. |

The verdict applies only to the sampled disk, not the region. This test measures disk queues, not Elasticsearch performance.

## Government results: November 23, 2026

**The DaemonSet restored 128 KiB, but did not prevent resets.** On one `Standard_D4ads_v6` Azure Linux FIPS node in `usgovvirginia` (AKS `1.36.5`), the mounted PVC reset to 65,536 KiB after all six treated events. It returned to 128 KiB in **13.06 to 50.17 seconds**, measured from the first high sample to the next low sample. The replacement pod also corrected the queue. Both untreated events left it at 65,536 KiB.

A separate fingerprint run confirmed guest FIPS was enabled on both operating systems. Managed OS and data disks matched across the pools:

| Guest OS | Kernel | Managed NVMe hint | Natural readahead |
|---|---|---:|---:|
| Azure Linux 3.0 | `6.6.159.1-2.azl3` | 33,554,432 bytes | 65,536 KiB |
| Ubuntu 22.04.5 LTS | `5.15.0-1125-azure-fips` | 33,554,432 bytes | 65,536 KiB |

All four managed disks reported `HOST_FIX_ABSENT`. Both local temp disks reported 128 KiB. The Ubuntu 20.04/5.4 hypothesis was not tested, the SCSI SKU was restricted, and the host build was not visible from either guest. Both runs verified deletion of their lab and node resource groups.

## Commercial reference: November 21-22, 2026

With no overrides, `bash reproduce.sh` still uses commercial Azure, West US 2, and one non-FIPS Ubuntu `Standard_D8as_v7` node. The original disk test observed six recoveries to 128 KiB and a successful pod replacement. On November 22, the six recoveries took 13.03 to 52.08 seconds.

The November 22 commercial Elasticsearch replay completed 2,304 measured requests with no errors or timeouts. Cold reads averaged 4.159 MiB/query before and after live correction, then 0.380 MiB/query after a JVM restart. No Elasticsearch run was performed in Azure Government.
