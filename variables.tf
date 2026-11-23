#### CCE Cluster config ####
variable "cluster_name" {
  type        = string
  description = "Name of the CCE cluster to provision the node pool for."
  default     = null
}

variable "cluster_id" {
  type        = string
  description = "UUID of the CCE cluster to provision the node pool for."
  default     = null
}

resource "errorcheck_is_valid" "cluster_name_or_cluster_id_exists" {
  name = "Check if at least one of var.cluster_name or var.cluster_id is specified."
  test = {
    assert        = var.cluster_name != null || var.cluster_id != null
    error_message = "At least one of cluster_name or cluster_id must be specified!"
  }
}

data "opentelekomcloud_cce_clusters_v3" "clusters" {
  name       = var.cluster_name
  cluster_id = var.cluster_id
  depends_on = [errorcheck_is_valid.cluster_name_or_cluster_id_exists]
}

locals {
  error_message_cluster_parameters = join(", ", compact([var.cluster_id != null ? "cluster_id=${var.cluster_id}" : null, var.cluster_name != null ? "cluster_name=${var.cluster_name}" : null]))
}

resource "errorcheck_is_valid" "ensure_found_clusters_greater_0" {
  name = "Check if at least one cluster is found."
  test = {
    assert        = length(data.opentelekomcloud_cce_clusters_v3.clusters.clusters) > 0
    error_message = "No clusters found matching parameter(s) ${local.error_message_cluster_parameters}"
  }
}

// This should never be possible but is still added as an additional safeguard
resource "errorcheck_is_valid" "ensure_found_clusters_lesser_2" {
  name = "Check if only one cluster is found."
  test = {
    assert        = length(data.opentelekomcloud_cce_clusters_v3.clusters.clusters) < 2
    error_message = "Multiple clusters found matching parameter(s) ${local.error_message_cluster_parameters}"
  }
}

#### OTC Node pool resource general config ####
variable "node_pool_name" {
  type        = string
  description = "Name for the node pool. (default: <cce-cluster-name>-nodes-<node_pool_availability_zone>)"
  default     = null
}

locals {
  node_pool_name_base = var.node_pool_name == null ? "${data.opentelekomcloud_cce_clusters_v3.clusters.clusters[0].name}-nodes-${var.node_pool_availability_zone}" : var.node_pool_name
}

variable "node_pool_availability_zone" {
  type        = string
  description = "Availability zone for the nodes in the pool."
}

variable "node_pool_flavor" {
  type        = string
  description = "Node specifications in OTC flavor format"
}

variable "node_pool_keypair_name" {
  type        = string
  description = "Name of an existing OTC compute keypair to use for node SSH access. If unspecified, the module generates a new ECDSA P-256 keypair per pool and exposes the private key via the node_pool_keypair_private_key output."
  default     = null
}

variable "node_pool_os" {
  type        = string
  description = "Operating system of nodes in the pool."
  default     = "HCE OS 2.0"
}

variable "node_pool_subnet_id" {
  type        = string
  description = "The UUID of the subnet for the nodes in the pool."
  default     = null
}

variable "node_pool_preinstall" {
  type        = string
  description = "Pre install script for the nodes inside the node pool."
  default     = ""
}

variable "node_pool_postinstall" {
  type        = string
  description = "Post install script for the nodes inside the node pool."
  default     = ""
}

variable "node_pool_security_group_ids" {
  type        = list(string)
  description = "Specifies the list of custom security group IDs for the node pool. If specified, the nodes will be put in these security groups."
  default     = null
}

variable "node_pool_server_group_reference" {
  type        = string
  description = "ECS group ID. If this parameter is specified, all nodes in the node pool will be created in this ECS group."
  default     = null
}

variable "node_pool_user_tags" {
  type        = map(string)
  description = "User tags for the nodes in the pool."
  default     = {}
}

#### Container / k8s config ####
variable "node_pool_container_runtime" {
  type        = string
  description = "The container runtime to use. Must be set to either containerd or docker."
  default     = "containerd"
  validation {
    condition     = contains(["containerd", "docker"], var.node_pool_container_runtime)
    error_message = "Allowed values for node_pool_container_runtime are either \"containerd\" or \"docker\"."
  }
}

variable "node_pool_docker_base_size" {
  type        = number
  description = "Available disk space of a single Docker container on the node using the device mapper."
  default     = 20
}

variable "node_pool_docker_lvm_config_override" {
  type        = string
  description = "ConfigMap of the Docker data disk."
  default     = null
}

variable "node_pool_k8s_labels" {
  default     = {}
  description = "Kubernetes node labels to set for the nodes inside the node pool."
  type        = map(string)
}

variable "node_pool_k8s_taints" {
  type = list(object({
    effect = string
    key    = string
    value  = string
  }))
  description = "Kubernetes node taints to set for the nodes inside the node pool."
  default     = []
}

variable "node_pool_max_pods" {
  type        = number
  description = "Maximum number of kubernetes pods each node is allowed to host."
  default     = null
}

#### Node count and scaling config ####
variable "node_pool_node_count" {
  type        = number
  description = "Number of nodes to create within the node pool."
}

variable "node_pool_enable_scaling" {
  type        = bool
  description = "Enable autoscaling for the node pool. Make sure the CCE Autoscaler Addon is installed for scaling to work."
  default     = true
}

variable "node_pool_node_count_max" {
  type        = number
  description = "Maximum number of nodes allowed for the node pool for autoscaling."
  default     = null
}

variable "node_pool_node_count_min" {
  type        = number
  description = "Minimum number of nodes allowed for the node pool for autoscaling. (default: <node_pool_count>)"
  default     = null
}

locals {
  // Upper bound of servers (default: <node_pool_count>)
  node_pool_node_count_max = var.node_pool_node_count_max == null ? var.node_pool_node_count : var.node_pool_node_count_max
  // Lower bound of servers to always keep (default: <node_pool_count>)
  node_pool_node_count_min = var.node_pool_node_count_min == null ? var.node_pool_node_count : var.node_pool_node_count_min
}

resource "errorcheck_is_valid" "node_pool_node_count_bounds" {
  name = "Check if node_pool_node_count is within the configured min/max bounds."
  test = {
    assert        = local.node_pool_node_count_min <= var.node_pool_node_count && var.node_pool_node_count <= local.node_pool_node_count_max
    error_message = "node_pool_node_count (${var.node_pool_node_count}) must satisfy node_pool_node_count_min (${local.node_pool_node_count_min}) <= node_pool_node_count <= node_pool_node_count_max (${local.node_pool_node_count_max})."
  }
}

variable "node_pool_scale_down_cooldown_time" {
  type        = number
  description = "Interval between two autoscaling operations, in minutes."
  default     = 15
}

variable "node_pool_scale_priority" {
  type        = number
  description = "Weight of a node pool for autoscaling. A node pool with a higher weight has a higher priority during scaling."
  default     = 5
}

#### Storage config ####
variable "node_pool_root_volume_size" {
  type        = number
  description = "Size of the node root (system) disk in GB."
  default     = 50
  validation {
    condition     = var.node_pool_root_volume_size >= 40
    error_message = "node_pool_root_volume_size must be at least 40 GB (OTC minimum for CCE system disks)."
  }
}

variable "node_pool_root_volume_type" {
  type        = string
  description = "Volume type for the node root (system) disk."
  default     = "SSD"
}

variable "node_pool_storage_type" {
  type        = string
  description = "Type of storage for the nodes in node pool."
  default     = "SATA"
}

variable "node_pool_storage_size" {
  type        = number
  description = "Size of the node system disk in GB"
  default     = 100
}

variable "node_pool_storage_encryption_enabled" {
  type        = bool
  description = "Enable OTC KMS volume encryption for the node pool volumes."
  default     = true
}

variable "node_pool_storage_encryption_kms_key_name" {
  type        = string
  description = "Allows using an existing KMS key defined by the user. If left unspecified a KMS key will be created automatically if node_pool_storage_encryption_enabled is enabled."
  default     = null
}

variable "node_pool_storage_encryption_kms_key_rotation_interval" {
  # Has no effect if node_pool_storage_encryption_enabled is false or an existing key is passed via node_pool_storage_encryption_kms_key_name.
  type        = number
  description = "Rotation interval in days (30-365) for the KMS key created by this module. Setting a value enables automatic key rotation. null turns rotation off, also on a key where it was enabled outside of Terraform. Has no effect if node_pool_storage_encryption_enabled is false or an existing key is passed via node_pool_storage_encryption_kms_key_name. (default: null)"
  default     = null
  validation {
    condition     = var.node_pool_storage_encryption_kms_key_rotation_interval == null ? true : var.node_pool_storage_encryption_kms_key_rotation_interval >= 30 && var.node_pool_storage_encryption_kms_key_rotation_interval <= 365
    error_message = "node_pool_storage_encryption_kms_key_rotation_interval not in range 30 <= x <= 365"
  }
}

variable "node_pool_storage_runtime_size" {
  type        = number
  default     = null
  description = "How much of the data disk (in percent) is reserved for the node runtime storage (i.e. docker images). OTC default is 90"
  validation {
    condition     = var.node_pool_storage_runtime_size == null ? true : var.node_pool_storage_runtime_size >= 10 && var.node_pool_storage_runtime_size <= 90
    error_message = "node_pool_storage_runtime_size not in range 10 <= x <= 90"
  }
}

variable "node_pool_storage_kubernetes_size" {
  type        = number
  default     = null
  description = "How much of the data disk (in percent) is reserved for the kubernetes runtime storage (i.e. ephemeral storage). OTC default is 10"
  validation {
    condition     = var.node_pool_storage_kubernetes_size == null ? true : var.node_pool_storage_kubernetes_size >= 10 && var.node_pool_storage_kubernetes_size <= 90
    error_message = "node_pool_storage_kubernetes_size not in range 10 <= x <= 90"
  }
}

variable "node_pool_storage_remainder_path" {
  type        = string
  default     = null
  description = "If the runtime & kubernetes sizes do not add up to 100(%), otc wants to know where/how to mount the remaining space. Note that there are forbidden paths, see otc-documentation for which paths are forbidden."
}

locals {
  is_disk_spacing_default = var.node_pool_storage_runtime_size == null && var.node_pool_storage_kubernetes_size == null
}

resource "errorcheck_is_valid" "node_pool_storage_remainder_path" {
  name = "Check if node_pool_storage_remainder_path is set up correctly."
  test = {
    assert        = local.is_disk_spacing_default ? var.node_pool_storage_remainder_path == null : var.node_pool_storage_runtime_size + var.node_pool_storage_kubernetes_size == 100 ? var.node_pool_storage_remainder_path == null : var.node_pool_storage_remainder_path != null && try(length(var.node_pool_storage_remainder_path) > 0, false)
    error_message = "If the runtime & kubernetes size do not sum up to 100(%%) node_pool_storage_remainder_path must be set, otherwise it must be unset."
  }
}

resource "errorcheck_is_valid" "node_pool_storage_size_both_set" {
  name = "Check if node_pool_storage_remainder_path and node_pool_storage_kubernetes_size are set up correctly."
  test = {
    assert        = local.is_disk_spacing_default ? true : var.node_pool_storage_runtime_size != null && var.node_pool_storage_kubernetes_size != null
    error_message = "Either both runtime & kubernetes sizes need to be unset, or both need to be set."
  }
}

resource "errorcheck_is_valid" "node_pool_storage_size_combined" {
  name = "Check if node_pool_storage_remainder_path and cluster_storage_kubernetes_size are set up correctly."
  test = {
    assert        = local.is_disk_spacing_default ? true : var.node_pool_storage_runtime_size + var.node_pool_storage_kubernetes_size <= 100
    error_message = "The sum of node_pool_storage_runtime_size and node_pool_storage_kubernetes_size cannot exceed 100(%%)."
  }
}
