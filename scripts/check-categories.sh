#!/usr/bin/env bash
set -euo pipefail
: "${1:?Usage: scripts/check-categories.sh <azure-resource-id>}"
az monitor diagnostic-settings categories list --resource "$1" --output table
