#!/usr/bin/env bash
# Deletes everything the cni-overlay demo created: the resource
# group (AKS cluster, load balancer, public IP) and the kubectl context.
#
# Usage: ./destroy.sh [--yes]
#
# Optional environment variables:
#   RESOURCE_GROUP  Resource group to delete (default: rg-cni-overlay)

set -Eeuo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../scripts/common.sh
source "$DEMO_DIR/../scripts/common.sh"
init_demo "$@"

require_tools az
require_az_login
if confirm_destroy; then
  destroy_resource_group
fi
