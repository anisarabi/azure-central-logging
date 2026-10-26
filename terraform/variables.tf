variable "subscription_id" { type = string }

variable "resource_group_name" {
  type    = string
  default = "rg-central-logging-dev"
}

variable "prefix" {
  description = "Prefixe utilise pour nommer les ressources Azure."
  type        = string
  default     = "clog"
}

variable "environment" {
  description = "Environnement de deploiement."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Region Azure."
  type        = string
  default     = "swedencentral"
}


variable "tags" {
  description = "Tags appliques aux ressources Azure."
  type        = map(string)
  default     = {}
}

variable "eventhub_capacity" {
  description = "Nombre de Throughput Units Event Hubs Standard."
  type        = number
  default     = 1
}

variable "eventhub_partitions" {
  description = "Nombre de partitions par Event Hub."
  type        = number
  default     = 2
}

variable "eventhub_retention_days" {
  description = "Retention des evenements en jours."
  type        = number
  default     = 1
}

variable "linux_vm_ids" {
  description = "Map des identifiants ARM des VM Linux."
  type        = map(string)
  default     = {}
}

variable "windows_vm_ids" {
  description = "Map des identifiants ARM des VM Windows."
  type        = map(string)
  default     = {}
}

variable "platform_resources" {
  description = "Ressources Azure, categories de logs et Event Hub cible."

  type = map(object({
    resource_id = string
    categories  = list(string)
    hub         = string
  }))

  default = {}

  validation {
    condition = alltrue([
      for r in values(var.platform_resources) :
      contains(["platform", "apps", "activity"], r.hub)
      && length(r.categories) > 0
    ])

    error_message = "Chaque ressource doit avoir au moins une categorie et un hub valide : platform, apps ou activity."
  }
}

variable "enable_vm_pipeline" {
  description = "Active la collecte des logs VM via AMA, DCR et Log Analytics."
  type        = bool
  default     = true
}

variable "vm_size" {
  description = "Taille de la VM Linux de test."
  type        = string
  default     = "Standard_B2s"
}

variable "ssh_public_key_path" {
  description = "Chemin de la cle SSH publique."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "enable_function_lab" {
  type    = bool
  default = false
}

variable "enable_function_diagnostics" {
  type    = bool
  default = false
}
