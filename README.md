# Azure Central Logging → Event Hubs (Terraform)

**Objective:** centralize logs from Linux/Windows VMs and Azure services (Functions, App Service, Key Vault, etc.) into Azure Event Hubs. Reference project for a DEV lab, to be hardened before production.

## Architecture

**Linux and Windows VMs**

```text
Linux VM (Syslog) --------\
                           +--> Azure Monitor Agent --> DCR --> Log Analytics
Windows VM (Event Logs) --/                                   |
                                                               v
                                                        Data Export
                                                               |
                                                               v
                                                         eh-vm-logs
```

**Functions, App Service, Key Vault, Storage, and AKS control plane**

```text
Functions / App Service --\
Key Vault / Storage -------+--> Diagnostic Settings --> eh-app-logs
AKS control plane ---------/                         \-> eh-platform-logs
```

Each resource sends to one configured Event Hub (`apps` or `platform`).

**Consumers**

```text
eh-vm-logs -----------\
eh-app-logs -----------+--> Elastic / Logstash / SIEM
eh-platform-logs -----/
```

**Note:** each Diagnostic Setting targets a single Event Hub according to `platform_resources[*].hub`. The `eh-activity-logs` hub is provisioned, but exporting Subscription Activity Logs requires additional configuration at the subscription level (not deployed in this lab).

## Exact scope

| Source | Path | Managed here |
|---|---|---|
| Linux Syslog | AMA → DCR → LAW → Data Export → Event Hubs | Yes, existing VM |
| Windows Application/System events | AMA → DCR → LAW → Data Export → Event Hubs | Yes, existing VM |
| Azure Function logs `FunctionAppLogs` | Diagnostic Settings → Event Hubs | Yes, existing Function |
| App Service / Key Vault / Storage / AKS control plane | Diagnostic Settings → Event Hubs | Yes, existing resources and compatible categories |
| Application Insights traces / exceptions | Workspace-based App Insights → LAW → Data Export | No, to be added via supported tables |
| Arbitrary application files on VM | AMA Custom Text Logs or Fluent Bit | No, extension to plan |
| Azure Subscription Activity Logs | Subscription diagnostic setting → Event Hubs | No, extension to plan |
| AKS stdout/stderr containers | AMA / Container Insights or collector | No, extension to plan |

This repository does **not create** VMs or Functions; it connects to their ARM IDs. It does not claim to export all logs automatically. Categories are resource-specific. Data Export is a stream of **new data**, not a historical export.

## Prerequisites

- Terraform >= 1.6, Azure CLI, and subscription deployment rights.
- A valid Azure subscription with Event Hubs quotas.
- Existing source resources in the **same region** as the Event Hubs namespace for regional resource Diagnostic Settings.
- An Azure Storage backend **created separately** before `terraform init` (container `tfstate`, Blob Data Contributor RBAC for the principal running Terraform).
- Permissions to read Event Hubs SAS rule keys and create Diagnostic Settings on the target resources.
- For existing VMs: verify that an AMA extension or equivalent DCR association is not already managed elsewhere; if so, import it rather than duplicate it.

## Step 1 — Azure authentication

```bash
az login --tenant <TENANT_ID>
az account set --subscription <SUBSCRIPTION_ID>
az account show --query '{subscription:id,tenant:tenantId}' -o json
```

## Step 2 — Prepare the Terraform backend

Create an RG, a Storage Account, and a `tfstate` container outside this module. Then:

```bash
cd terraform
cp backend.hcl.example backend.hcl
# Fill in backend.hcl (real Storage Account and DEV key)
cp terraform.tfvars.example terraform.tfvars
# Fill in subscription_id, location, and ARM IDs of the existing VMs and services.
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

For a **local test without remote state** (not recommended for PROD): `terraform init -backend=false` is not enough to enable local state if the backend block remains declared. Prepare a real backend or temporarily isolate the backend configuration in a copy of the lab.

## Step 3 — Retrieve ARM IDs

```bash
az vm show -g rg-app -n vm-linux-01 --query id -o tsv
az functionapp show -g rg-app -n func-orders-prod --query id -o tsv
az webapp show -g rg-app -n app-api-prod --query id -o tsv
```

## Step 4 — Check log categories

```bash
./scripts/check-categories.sh '<RESOURCE_ARM_ID>'
# or
az monitor diagnostic-settings categories list --resource '<RESOURCE_ARM_ID>' -o table
```

From the repo root. Then add the following to `terraform/terraform.tfvars`:

```hcl
platform_resources = {
  function_orders = {
    resource_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Web/sites/func-orders-prod"
    categories = ["FunctionAppLogs"]
    hub = "apps"
  }
}
```

For a Function, **enable log generation** in its runtime/configuration; the presence of a Diagnostic Setting does not create logs by itself. For Application Insights telemetry (requests, dependencies, exceptions), plan a separate export of compatible tables from a workspace-based Application Insights instance.

## Step 5 — Test Linux

```bash
# On the Linux VM
logger -p user.err 'CENTRAL-LOGGING-TEST-001'
```

In Log Analytics, after ingestion:

```kusto
Syslog
| where TimeGenerated > ago(30m)
| where SyslogMessage contains "CENTRAL-LOGGING-TEST-001"
| project TimeGenerated, Computer, Facility, SeverityLevel, SyslogMessage
```

Then check Event Hubs → Monitoring → Metrics → Incoming Messages. To verify the **content**, run the consumer below (Azure Event Hubs Data Receiver is required for the identity being used):

```bash
pip install azure-eventhub azure-identity
export EVENTHUB_NAMESPACE='evhns-....servicebus.windows.net'
export EVENTHUB_NAME='eh-vm-logs'
python examples/consumer.py
```

This consumer is a **demonstration**: it does not record checkpoints. A production consumer must use a dedicated consumer group, a checkpoint store, retries, and handle duplicates.

## Security / production

- The resources are publicly accessible over the network in this lab; **do not deploy as-is in production**. Define network rules, Private Endpoints, and a trusted Microsoft services strategy compatible with Diagnostic Settings.
- Azure Monitor Diagnostic Settings currently require a namespace SAS rule with **Manage + Send + Listen**; do not distribute this key to applications. Consumers use **Entra ID / RBAC**.
- Limit categories and retention; mask secrets/PII before emitting them. The Terraform state contains sensitive information: encrypted backend, strict RBAC, locking, and no keys in Git.
- Monitor Incoming Messages, Throttled Requests, Server Errors, Log Analytics ingestion, export errors, and costs.
- Check sizing (TU, partitions, retention), SLA, quotas, and recovery requirements. Event Hubs is not long-term storage.
- Isolate DEV/QA/PROD via separate states and ideally separate namespaces; only run `apply` after review and approval. The GitHub Actions workflow currently only does `fmt/init/validate`, without credentials or deployment.
- Be aware of possible conflicts with existing Diagnostic Settings, AMA extensions, and DCRs already in place: import the resources before managing them with Terraform.

## Structure

```text
.
├── .github/
│   └── workflows/
│       └── terraform.yml            Terraform CI validation (no apply)
├── examples/
│   └── consumer.py                  Event Hubs smoke-test consumer
├── function-app/
│   ├── function_app.py              HTTP-triggered log-generation Function
│   ├── host.json                    Azure Functions host configuration
│   └── requirements.txt             Function app dependencies
├── scripts/
│   └── check-categories.sh          Discover supported diagnostic categories
├── terraform/
│   ├── main.tf                      Logging resources, hubs, AMA, DCR, export
│   ├── vm-lab.tf                    Optional Linux VM lab and AMA association
│   ├── function-lab.tf              Optional Function lab and diagnostics
│   ├── variables.tf                 Configuration variables
│   ├── outputs.tf                   Useful resource names and IDs
│   ├── versions.tf                  Providers and backend configuration
│   ├── .terraform.lock.hcl          Provider dependency lock file
│   ├── terraform.tfvars.example     Example variables (no local secrets)
│   └── backend.hcl.example          Example remote-state configuration
├── .gitignore
└── README.md
```

## References

- [Azure Monitor Diagnostic Settings](https://learn.microsoft.com/en-us/azure/azure-monitor/platform/diagnostic-settings)
- [Log Analytics data export](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-data-export)
- [Data Collection Rules](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/data-collection-rule-overview)
- [Terraform AzureRM provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

**Validation:** generated files exist, but `terraform init/validate/plan` were not run in this environment (Terraform binary is absent). Run the commands above and resolve any schema differences related to the effective provider version before deployment.
