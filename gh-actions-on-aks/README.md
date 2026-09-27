# GitHub Actions runners on AKS

Runs GitHub Actions jobs in pods on an Azure Kubernetes Service (AKS) cluster by using
[Actions Runner Controller (ARC)](https://docs.github.com/en/actions/concepts/runners/actions-runner-controller).
The runner scale set scales from zero: ARC creates a runner pod when a job is queued and deletes the pod when the
job finishes.

## Quick start

```bash
export GITHUB_PAT=<token>                                   # Optional: deploy.sh prompts for it
export GITHUB_CONFIG_URL=https://github.com/<owner>/<repo>  # Optional: defaults to this clone's origin
./deploy.sh    # ~8 minutes
./destroy.sh   # Unregisters the runners from GitHub, then deletes the resource group
```

You need the Azure CLI (signed in with `az login`), `kubectl` and `helm`. [Azure Cloud Shell](https://shell.azure.com)
has all three. `deploy.sh` checks the token against the GitHub API before it creates any Azure resources.

Optional settings: `LOCATION`, `RESOURCE_GROUP`, `NODE_VM_SIZE`, `MAX_RUNNERS` (default `3`) and `ARC_VERSION`
(Helm chart version; default: latest).

### Token permissions

ARC uses the token to register and remove runners. It needs these
[permissions](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api):

| Runners registered with | Personal access token (classic) | Fine-grained personal access token |
| --- | --- | --- |
| A repository (`https://github.com/<owner>/<repo>`) | `repo` scope | **Administration**: Read and write |
| An organization (`https://github.com/<org>`) | `admin:org` scope | **Administration**: Read, **Self-hosted runners**: Read and write |

The token is stored only in the Kubernetes secret `arc-runners/arc-github-secret`. For production, use a
[GitHub App](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api#authenticating-arc-with-a-github-app)
instead of a personal access token.

## What gets deployed

- [`infra/main.bicep`](infra/main.bicep): an AKS cluster (Free tier, 1 node).
- Helm release `arc` in namespace `arc-systems`: the ARC controller
  ([`gha-runner-scale-set-controller`](https://github.com/actions/actions-runner-controller/tree/master/charts/gha-runner-scale-set-controller)).
- Helm release `arc-runner-set` in namespace `arc-runners`: a runner scale set
  ([`gha-runner-scale-set`](https://github.com/actions/actions-runner-controller/tree/master/charts/gha-runner-scale-set))
  with 0 to `MAX_RUNNERS` runners. The release name is the label that workflows use in `runs-on`.

## Run a job on the cluster

This repository includes [`.github/workflows/main.yml`](../.github/workflows/main.yml), a manually triggered workflow
with `runs-on: arc-runner-set`. When you register the runners with this repository (or your fork of it), run the
workflow from the **Actions** tab (**Actions Runner Controller Demo** > **Run workflow**) or with the GitHub CLI:

```bash
gh workflow run main.yml --repo <owner>/<repo>
```

Then watch ARC create a runner pod for the job and delete it afterward:

```bash
kubectl get pods -n arc-runners --watch
```

Any workflow in the registered repository or organization can use the runners:

```yaml
jobs:
  build:
    runs-on: arc-runner-set
```

## Explore

```bash
# The controller and the listener pod that long-polls GitHub for jobs
kubectl get pods -n arc-systems

# The runner scale set and its current number of runners
kubectl get autoscalingrunnersets -n arc-runners

# Controller logs (start here when runners don't show up)
kubectl logs -n arc-systems deployment/arc-gha-rs-controller
```

In GitHub, the runner scale set appears under **Settings** > **Actions** > **Runners**.

## Clean up

```bash
./destroy.sh   # Asks for confirmation. Use --yes to skip the prompt.
```

`destroy.sh` uninstalls the runner scale set first, so ARC removes its registration from GitHub. Then it deletes the
resource group that `deploy.sh` created (tagged `azure-demos=gh-actions-on-aks`) and the kubectl context.

## Troubleshooting

- **`deploy.sh` says the token can't manage self-hosted runners**: check the token's permissions in the table above,
  and that `GITHUB_CONFIG_URL` points to the repository or organization that you want.
- **The listener doesn't start**: check the controller logs (see [Explore](#explore)). Re-run `./deploy.sh` with a new
  token if the token expired.
- **Jobs stay queued**: the workflow's `runs-on` value must be exactly `arc-runner-set`.
