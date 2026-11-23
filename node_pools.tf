resource "tls_private_key" "node_pool_keypair" {
  count       = var.node_pool_keypair_name == null ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "random_id" "node_pool_keypair_id" {
  count       = var.node_pool_keypair_name == null ? 1 : 0
  byte_length = 4
}

resource "opentelekomcloud_compute_keypair_v2" "node_pool_keypair" {
  count      = var.node_pool_keypair_name == null ? 1 : 0
  name       = "${local.node_pool_name_base}-keypair-${random_id.node_pool_keypair_id[0].hex}"
  public_key = tls_private_key.node_pool_keypair[0].public_key_openssh
}

locals {
  node_pool_keypair_name = try(opentelekomcloud_compute_keypair_v2.node_pool_keypair[0].name, var.node_pool_keypair_name)
}

resource "random_id" "node_pool_storage_encryption_key_id" {
  count       = var.node_pool_storage_encryption_enabled && var.node_pool_storage_encryption_kms_key_name == null ? 1 : 0
  byte_length = 4
}

resource "opentelekomcloud_kms_key_v1" "node_pool_storage_encryption_key" {
  count           = var.node_pool_storage_encryption_enabled && var.node_pool_storage_encryption_kms_key_name == null ? 1 : 0
  key_alias       = "${local.node_pool_name_base}-${random_id.node_pool_storage_encryption_key_id[0].hex}"
  key_description = "${local.node_pool_name_base} CCE Node Pool volume encryption key"
  pending_days    = 7
  is_enabled      = "true"
  rotation_enabled  = var.node_pool_storage_encryption_kms_key_rotation_interval != null
  rotation_interval = var.node_pool_storage_encryption_kms_key_rotation_interval
}

data "opentelekomcloud_kms_key_v1" "node_storage_encryption_existing_key" {
  count     = var.node_pool_storage_encryption_enabled && var.node_pool_storage_encryption_kms_key_name != null ? 1 : 0
  key_alias = var.node_pool_storage_encryption_kms_key_name
}

locals {
  node_pool_storage_encryption_kms_id = var.node_pool_storage_encryption_enabled ? (var.node_pool_storage_encryption_kms_key_name == null ? opentelekomcloud_kms_key_v1.node_pool_storage_encryption_key[0].id : data.opentelekomcloud_kms_key_v1.node_storage_encryption_existing_key[0].id) : null
}

# Rotates the pool name suffix on any ForceNew attribute change so create_before_destroy can avoid OTC's HTTP 409 on duplicate pool names.
# The pool's name attribute is mutable, so adopting this on an existing unsuffixed pool is an in-place rename rather than a rollout.
resource "random_id" "node_pool_unique_suffix_id" {
  byte_length = 4
  keepers = {
    pool_config_hash = sha256(jsonencode({
      flavor                     = var.node_pool_flavor
      availability_zone          = var.node_pool_availability_zone
      os                         = var.node_pool_os
      runtime                    = var.node_pool_container_runtime
      subnet_id                  = var.node_pool_subnet_id
      max_pods                   = var.node_pool_max_pods
      docker_base_size           = var.node_pool_docker_base_size
      docker_lvm_config_override = var.node_pool_docker_lvm_config_override
      server_group_reference     = var.node_pool_server_group_reference
      security_group_ids         = var.node_pool_security_group_ids
      root_volume_size           = var.node_pool_root_volume_size
      root_volume_type           = var.node_pool_root_volume_type
      storage_size               = var.node_pool_storage_size
      storage_type               = var.node_pool_storage_type
      storage_runtime_size       = var.node_pool_storage_runtime_size
      storage_kubernetes_size    = var.node_pool_storage_kubernetes_size
      storage_remainder_path     = var.node_pool_storage_remainder_path
      storage_encryption_enabled = var.node_pool_storage_encryption_enabled
      storage_encryption_kms_key = var.node_pool_storage_encryption_kms_key_name
      keypair_name               = var.node_pool_keypair_name
    }))
  }
}

locals {
  node_pool_name = "${local.node_pool_name_base}-${random_id.node_pool_unique_suffix_id.hex}"
}

resource "opentelekomcloud_cce_node_pool_v3" "node_pool" {
  cluster_id             = data.opentelekomcloud_cce_clusters_v3.clusters.clusters[0].id
  name                   = local.node_pool_name
  availability_zone      = var.node_pool_availability_zone
  flavor                 = var.node_pool_flavor
  os                     = var.node_pool_os
  user_tags              = var.node_pool_user_tags
  subnet_id              = var.node_pool_subnet_id
  preinstall             = var.node_pool_preinstall
  postinstall            = var.node_pool_postinstall
  key_pair               = local.node_pool_keypair_name
  security_group_ids     = var.node_pool_security_group_ids
  server_group_reference = var.node_pool_server_group_reference

  initial_node_count       = var.node_pool_node_count
  scale_enable             = var.node_pool_enable_scaling
  min_node_count           = local.node_pool_node_count_min
  max_node_count           = local.node_pool_node_count_max
  scale_down_cooldown_time = var.node_pool_scale_down_cooldown_time
  priority                 = var.node_pool_scale_priority

  runtime                    = var.node_pool_container_runtime
  docker_base_size           = var.node_pool_docker_base_size
  docker_lvm_config_override = var.node_pool_docker_lvm_config_override
  k8s_tags                   = var.node_pool_k8s_labels
  max_pods                   = var.node_pool_max_pods

  dynamic "taints" {
    for_each = var.node_pool_k8s_taints
    content {
      effect = taints.value.effect
      key    = taints.value.key
      value  = taints.value.value
    }
  }

  storage = local.is_disk_spacing_default ? null : jsonencode({
    storageSelectors = [
      {
        name        = "cceUse"
        storageType = "evs"
        matchLabels = {
          count             = "1"
          metadataCmkid     = local.node_pool_storage_encryption_kms_id
          metadataEncrypted = var.node_pool_storage_encryption_enabled ? "1" : "0"
          size              = tostring(var.node_pool_storage_size)
          volumeType        = var.node_pool_storage_type
        }
      }
    ]
    storageGroups = [
      {
        name       = "vgpaas"
        cceManaged = true
        selectorNames = [
          "cceUse"
        ]
        virtualSpaces = concat([
          {
            name = "runtime"
            size = "${var.node_pool_storage_runtime_size}%"
            runtimeConfig = {
              lvType = "linear"
            }
          },
          {
            name = "kubernetes"
            size = "${var.node_pool_storage_kubernetes_size}%"
            lvmConfig = {
              lvType = "linear"
            }
          }
          ], var.node_pool_storage_remainder_path == null ? [] : [
          {
            name = "user"
            size = "${100 - var.node_pool_storage_kubernetes_size - var.node_pool_storage_runtime_size}%"
            lvmConfig = {
              lvType = "linear"
            }
        }])
      }
    ]
  })

  root_volume {
    size       = var.node_pool_root_volume_size
    volumetype = var.node_pool_root_volume_type
    kms_id     = local.node_pool_storage_encryption_kms_id
  }

  data_volumes {
    size       = var.node_pool_storage_size
    volumetype = var.node_pool_storage_type
    kms_id     = local.node_pool_storage_encryption_kms_id
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
    # Replacement pool gets a fresh name via random_id.node_pool_unique_suffix_id, so this stands up the new pool without colliding on the existing one's name.
    create_before_destroy = true
  }
}
