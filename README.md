## OTC Cloud Container Engine Node Pool Terraform module

A module designed to create node pools for OTC CCE while simplifying the configuration for ease of use.

This module is part of a set of three CCE modules that are meant to be used together:

| Module | Purpose |
| ------ | ------- |
| [`cce-cluster`](https://github.com/iits-consulting/terraform-opentelekomcloud-cce-cluster) | Provisions the CCE control plane and optionally bundles the Autoscaler and Metrics Server addons. |
| `cce-node-pool` (this module) | Provisions worker node pools and attaches them to an existing CCE cluster. |
| [`cce-addon`](https://github.com/iits-consulting/terraform-opentelekomcloud-cce-addon) | Installs a single CCE addon into an existing cluster (for anything not bundled here). |

A bare `cce-cluster` has no worker nodes - pair it with one or more `cce-node-pool` modules before scheduling workloads.

> **WARNING:** Volume encryption (enabled by default via `node_pool_storage_encryption_enabled`) requires an agency granting the OTC EVS service KMS access:
>
> - Agency Name = `EVSAccessKMS`
> - Agency Type = `Account`
> - Delegated Account = `op_svc_evs`
> - Permissions = `KMS Administrator` within the project
>
> Set `node_pool_storage_encryption_enabled = false` if you cannot create this agency.

### Usage

#### Autoscaling pool spread across AZs

The typical setup is one pool per availability zone, driven by `for_each`. The Autoscaler addon bundled with `cce-cluster` picks the pool to scale based on `node_pool_scale_priority`.

```hcl
module "cce_node_pool" {
  source   = "iits-consulting/cce-node-pool/opentelekomcloud"
  for_each = toset(["eu-de-02", "eu-de-03"])

  cluster_id                  = module.cce_cluster.cluster_id
  node_pool_availability_zone = each.key
  node_pool_node_count        = 2
  node_pool_flavor            = "s9.xlarge.4"
  node_pool_enable_scaling    = true
  node_pool_node_count_min    = 2
  node_pool_node_count_max    = 4
}
```

#### GPU pool with taints

Dedicate a pool to GPU workloads and use taints to keep non-GPU pods off it. Pair with the `gpu-beta` addon shown in the [`cce-cluster`](https://github.com/iits-consulting/terraform-opentelekomcloud-cce-cluster) README.

```hcl
module "cce_gpu_node_pool" {
  source = "iits-consulting/cce-node-pool/opentelekomcloud"

  cluster_id                  = module.cce_cluster.cluster_id
  node_pool_availability_zone = "eu-de-03"
  node_pool_node_count        = 2
  node_pool_flavor            = "pi5e.2xlarge.4"
  node_pool_storage_type      = "SSD"
  node_pool_storage_size      = 100
  node_pool_k8s_taints = [{
    effect = "PreferNoSchedule"
    key    = "gpu-node"
    value  = "true"
  }]
}
```

### Autoscaling

`node_pool_enable_scaling` is opt-in per pool and requires the CCE Autoscaler addon to be installed on the cluster. `cce-cluster` installs it by default (`addon_autoscaler_enabled = true`), so scaling functions without explicit autoscaler addon configuration unless that default was overridden.

- `node_pool_node_count_min` / `node_pool_node_count_max` bound the pool; both default to `node_pool_node_count` when unset.
- `node_pool_scale_priority` controls scale-out ordering across pools (higher wins).
- `node_pool_scale_down_cooldown_time` is in minutes.

### Storage layout

The module attaches one data volume sized by `node_pool_storage_size` (GB) and lets you partition it between the container runtime, kubelet ephemeral storage, and an optional user-mounted remainder:

- Leave `node_pool_storage_runtime_size` and `node_pool_storage_kubernetes_size` unset to use OTC defaults (90% runtime / 10% kubernetes).
- Set both (each in percent) to customize the split. They must either sum to 100, or leave a remainder covered by `node_pool_storage_remainder_path` (mount point for the leftover space - note OTC has a list of forbidden paths).

### Disk encryption

All volumes (root, data, and any partitioned spaces) are encrypted with a KMS key when `node_pool_storage_encryption_enabled = true` (default). By default the module creates a dedicated KMS key per pool - for multi-AZ deployments where one `for_each` spawns several pools, pre-create a shared key and pass its alias via `node_pool_storage_encryption_kms_key_name` to avoid a KMS key per pool.

### SSH access

Each pool gets its own freshly generated ECDSA P-256 keypair registered in OTC. The private key is exposed as the sensitive output `node_pool_keypair_private_key` - persist it via your state backend or pipe it into a secret store; it cannot be recovered from OTC after creation. To share one keypair across pools (or reuse one pre-registered in OTC), set `node_pool_keypair_name` - the module will skip generating a new one and the keypair outputs will return `null`.

### Rolling node pools

OTC rejects creating a node pool with a name that already exists on the cluster (HTTP 409). Combined with the provider marking the pool's name as the destination of a `create_before_destroy` lifecycle, any change to a `ForceNew` attribute (flavor, OS, runtime, root volume, storage layout, encryption settings, keypair, etc.) needs the replacement pool to land under a distinct name.

The module solves this internally by appending an 8-character suffix to the pool name, driven by `random_id.node_pool_unique_suffix_id`. The suffix rotates automatically whenever any `ForceNew` attribute changes, so rollouts pass the duplicate-name check without manual UI intervention. The keypair and KMS key keep referencing the unsuffixed base name, so they stay stable across pool rollouts and don't get recreated as a side effect.

The pool's `name` attribute is mutable in the OTC API. Adopting this module on top of an existing unsuffixed pool is therefore an in-place rename, not a rollout - see [`MIGRATION.md`](./MIGRATION.md) for the predecessor-to-successor flow.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_errorcheck"></a> [errorcheck](#requirement\_errorcheck) | 3.0.3 |
| <a name="requirement_opentelekomcloud"></a> [opentelekomcloud](#requirement\_opentelekomcloud) | >= 1.36.52, < 2.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_errorcheck"></a> [errorcheck](#provider\_errorcheck) | 3.0.3 |
| <a name="provider_opentelekomcloud"></a> [opentelekomcloud](#provider\_opentelekomcloud) | >= 1.36.52, < 2.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [errorcheck_is_valid.cluster_name_or_cluster_id_exists](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [errorcheck_is_valid.ensure_found_clusters_greater_0](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [errorcheck_is_valid.ensure_found_clusters_lesser_2](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [errorcheck_is_valid.node_pool_node_count_bounds](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [errorcheck_is_valid.node_pool_storage_remainder_path](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [errorcheck_is_valid.node_pool_storage_size_both_set](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [errorcheck_is_valid.node_pool_storage_size_combined](https://registry.terraform.io/providers/iits-consulting/errorcheck/3.0.3/docs/resources/is_valid) | resource |
| [opentelekomcloud_cce_node_pool_v3.node_pool](https://registry.terraform.io/providers/opentelekomcloud/opentelekomcloud/latest/docs/resources/cce_node_pool_v3) | resource |
| [opentelekomcloud_compute_keypair_v2.node_pool_keypair](https://registry.terraform.io/providers/opentelekomcloud/opentelekomcloud/latest/docs/resources/compute_keypair_v2) | resource |
| [opentelekomcloud_kms_key_v1.node_pool_storage_encryption_key](https://registry.terraform.io/providers/opentelekomcloud/opentelekomcloud/latest/docs/resources/kms_key_v1) | resource |
| [random_id.node_pool_keypair_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_id.node_pool_storage_encryption_key_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_id.node_pool_unique_suffix_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [tls_private_key.node_pool_keypair](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [opentelekomcloud_cce_clusters_v3.clusters](https://registry.terraform.io/providers/opentelekomcloud/opentelekomcloud/latest/docs/data-sources/cce_clusters_v3) | data source |
| [opentelekomcloud_kms_key_v1.node_storage_encryption_existing_key](https://registry.terraform.io/providers/opentelekomcloud/opentelekomcloud/latest/docs/data-sources/kms_key_v1) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_node_pool_availability_zone"></a> [node\_pool\_availability\_zone](#input\_node\_pool\_availability\_zone) | Availability zone for the nodes in the pool. | `string` | n/a | yes |
| <a name="input_node_pool_flavor"></a> [node\_pool\_flavor](#input\_node\_pool\_flavor) | Node specifications in OTC flavor format | `string` | n/a | yes |
| <a name="input_node_pool_node_count"></a> [node\_pool\_node\_count](#input\_node\_pool\_node\_count) | Number of nodes to create within the node pool. | `number` | n/a | yes |
| <a name="input_cluster_id"></a> [cluster\_id](#input\_cluster\_id) | UUID of the CCE cluster to provision the node pool for. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the CCE cluster to provision the node pool for. | `string` | `null` | no |
| <a name="input_node_pool_container_runtime"></a> [node\_pool\_container\_runtime](#input\_node\_pool\_container\_runtime) | The container runtime to use. Must be set to either containerd or docker. | `string` | `"containerd"` | no |
| <a name="input_node_pool_docker_base_size"></a> [node\_pool\_docker\_base\_size](#input\_node\_pool\_docker\_base\_size) | Available disk space of a single Docker container on the node using the device mapper. | `number` | `20` | no |
| <a name="input_node_pool_docker_lvm_config_override"></a> [node\_pool\_docker\_lvm\_config\_override](#input\_node\_pool\_docker\_lvm\_config\_override) | ConfigMap of the Docker data disk. | `string` | `null` | no |
| <a name="input_node_pool_enable_scaling"></a> [node\_pool\_enable\_scaling](#input\_node\_pool\_enable\_scaling) | Enable autoscaling for the node pool. Make sure the CCE Autoscaler Addon is installed for scaling to work. | `bool` | `true` | no |
| <a name="input_node_pool_k8s_labels"></a> [node\_pool\_k8s\_labels](#input\_node\_pool\_k8s\_labels) | Kubernetes node labels to set for the nodes inside the node pool. | `map(string)` | `{}` | no |
| <a name="input_node_pool_k8s_taints"></a> [node\_pool\_k8s\_taints](#input\_node\_pool\_k8s\_taints) | Kubernetes node taints to set for the nodes inside the node pool. | <pre>list(object({<br/>    effect = string<br/>    key    = string<br/>    value  = string<br/>  }))</pre> | `[]` | no |
| <a name="input_node_pool_keypair_name"></a> [node\_pool\_keypair\_name](#input\_node\_pool\_keypair\_name) | Name of an existing OTC compute keypair to use for node SSH access. If unspecified, the module generates a new ECDSA P-256 keypair per pool and exposes the private key via the node\_pool\_keypair\_private\_key output. | `string` | `null` | no |
| <a name="input_node_pool_max_pods"></a> [node\_pool\_max\_pods](#input\_node\_pool\_max\_pods) | Maximum number of kubernetes pods each node is allowed to host. | `number` | `null` | no |
| <a name="input_node_pool_name"></a> [node\_pool\_name](#input\_node\_pool\_name) | Name for the node pool. (default: <cce-cluster-name>-nodes-<node\_pool\_availability\_zone>) | `string` | `null` | no |
| <a name="input_node_pool_node_count_max"></a> [node\_pool\_node\_count\_max](#input\_node\_pool\_node\_count\_max) | Maximum number of nodes allowed for the node pool for autoscaling. | `number` | `null` | no |
| <a name="input_node_pool_node_count_min"></a> [node\_pool\_node\_count\_min](#input\_node\_pool\_node\_count\_min) | Minimum number of nodes allowed for the node pool for autoscaling. (default: <node\_pool\_count>) | `number` | `null` | no |
| <a name="input_node_pool_os"></a> [node\_pool\_os](#input\_node\_pool\_os) | Operating system of nodes in the pool. | `string` | `"HCE OS 2.0"` | no |
| <a name="input_node_pool_postinstall"></a> [node\_pool\_postinstall](#input\_node\_pool\_postinstall) | Post install script for the nodes inside the node pool. | `string` | `""` | no |
| <a name="input_node_pool_preinstall"></a> [node\_pool\_preinstall](#input\_node\_pool\_preinstall) | Pre install script for the nodes inside the node pool. | `string` | `""` | no |
| <a name="input_node_pool_root_volume_size"></a> [node\_pool\_root\_volume\_size](#input\_node\_pool\_root\_volume\_size) | Size of the node root (system) disk in GB. | `number` | `50` | no |
| <a name="input_node_pool_root_volume_type"></a> [node\_pool\_root\_volume\_type](#input\_node\_pool\_root\_volume\_type) | Volume type for the node root (system) disk. | `string` | `"SSD"` | no |
| <a name="input_node_pool_scale_down_cooldown_time"></a> [node\_pool\_scale\_down\_cooldown\_time](#input\_node\_pool\_scale\_down\_cooldown\_time) | Interval between two autoscaling operations, in minutes. | `number` | `15` | no |
| <a name="input_node_pool_scale_priority"></a> [node\_pool\_scale\_priority](#input\_node\_pool\_scale\_priority) | Weight of a node pool for autoscaling. A node pool with a higher weight has a higher priority during scaling. | `number` | `5` | no |
| <a name="input_node_pool_security_group_ids"></a> [node\_pool\_security\_group\_ids](#input\_node\_pool\_security\_group\_ids) | Specifies the list of custom security group IDs for the node pool. If specified, the nodes will be put in these security groups. | `list(string)` | `null` | no |
| <a name="input_node_pool_server_group_reference"></a> [node\_pool\_server\_group\_reference](#input\_node\_pool\_server\_group\_reference) | ECS group ID. If this parameter is specified, all nodes in the node pool will be created in this ECS group. | `string` | `null` | no |
| <a name="input_node_pool_storage_encryption_enabled"></a> [node\_pool\_storage\_encryption\_enabled](#input\_node\_pool\_storage\_encryption\_enabled) | Enable OTC KMS volume encryption for the node pool volumes. | `bool` | `true` | no |
| <a name="input_node_pool_storage_encryption_kms_key_name"></a> [node\_pool\_storage\_encryption\_kms\_key\_name](#input\_node\_pool\_storage\_encryption\_kms\_key\_name) | Allows using an existing KMS key defined by the user. If left unspecified a KMS key will be created automatically if node\_pool\_storage\_encryption\_enabled is enabled. | `string` | `null` | no |
| <a name="input_node_pool_storage_encryption_kms_key_rotation_interval"></a> [node\_pool\_storage\_encryption\_kms\_key\_rotation\_interval](#input\_node\_pool\_storage\_encryption\_kms\_key\_rotation\_interval) | Rotation interval in days (30-365) for the KMS key created by this module. Setting a value enables automatic key rotation. null turns rotation off, also on a key where it was enabled outside of Terraform. Has no effect if node\_pool\_storage\_encryption\_enabled is false or an existing key is passed via node\_pool\_storage\_encryption\_kms\_key\_name. (default: null) | `number` | `null` | no |
| <a name="input_node_pool_storage_kubernetes_size"></a> [node\_pool\_storage\_kubernetes\_size](#input\_node\_pool\_storage\_kubernetes\_size) | How much of the data disk (in percent) is reserved for the kubernetes runtime storage (i.e. ephemeral storage). OTC default is 10 | `number` | `null` | no |
| <a name="input_node_pool_storage_remainder_path"></a> [node\_pool\_storage\_remainder\_path](#input\_node\_pool\_storage\_remainder\_path) | If the runtime & kubernetes sizes do not add up to 100(%), otc wants to know where/how to mount the remaining space. Note that there are forbidden paths, see otc-documentation for which paths are forbidden. | `string` | `null` | no |
| <a name="input_node_pool_storage_runtime_size"></a> [node\_pool\_storage\_runtime\_size](#input\_node\_pool\_storage\_runtime\_size) | How much of the data disk (in percent) is reserved for the node runtime storage (i.e. docker images). OTC default is 90 | `number` | `null` | no |
| <a name="input_node_pool_storage_size"></a> [node\_pool\_storage\_size](#input\_node\_pool\_storage\_size) | Size of the node system disk in GB | `number` | `100` | no |
| <a name="input_node_pool_storage_type"></a> [node\_pool\_storage\_type](#input\_node\_pool\_storage\_type) | Type of storage for the nodes in node pool: SAS, SSD, GPSSD, GPSSD2 or ESSD. SATA only works for existing node pools. | `string` | `"GPSSD"` | no |
| <a name="input_node_pool_subnet_id"></a> [node\_pool\_subnet\_id](#input\_node\_pool\_subnet\_id) | The UUID of the subnet for the nodes in the pool. | `string` | `null` | no |
| <a name="input_node_pool_user_tags"></a> [node\_pool\_user\_tags](#input\_node\_pool\_user\_tags) | User tags for the nodes in the pool. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_node_pool"></a> [node\_pool](#output\_node\_pool) | Complete configuration of the created node pool. |
| <a name="output_node_pool_id"></a> [node\_pool\_id](#output\_node\_pool\_id) | UUID of the node pool. |
| <a name="output_node_pool_keypair_name"></a> [node\_pool\_keypair\_name](#output\_node\_pool\_keypair\_name) | Name of the SSH keypair used by the node pool (auto-generated or supplied via node\_pool\_keypair\_name). |
| <a name="output_node_pool_keypair_private_key"></a> [node\_pool\_keypair\_private\_key](#output\_node\_pool\_keypair\_private\_key) | Private key of the generated SSH keypair in OpenSSH format. Returns null when node\_pool\_keypair\_name is supplied. |
| <a name="output_node_pool_keypair_public_key"></a> [node\_pool\_keypair\_public\_key](#output\_node\_pool\_keypair\_public\_key) | Public key of the generated SSH keypair in OpenSSH format. Returns null when node\_pool\_keypair\_name is supplied. |
| <a name="output_node_pool_name"></a> [node\_pool\_name](#output\_node\_pool\_name) | Name of the node pool. |
<!-- END_TF_DOCS -->
