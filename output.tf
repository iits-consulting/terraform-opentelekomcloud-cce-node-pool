output "node_pool_id" {
  value       = opentelekomcloud_cce_node_pool_v3.node_pool.id
  description = "UUID of the node pool."
}

output "node_pool_keypair_name" {
  value       = local.node_pool_keypair_name
  description = "Name of the SSH keypair used by the node pool (auto-generated or supplied via node_pool_keypair_name)."
}

output "node_pool_keypair_private_key" {
  sensitive   = true
  value       = try(tls_private_key.node_pool_keypair[0].private_key_openssh, null)
  description = "Private key of the generated SSH keypair in OpenSSH format. Returns null when node_pool_keypair_name is supplied."
}

output "node_pool_keypair_public_key" {
  sensitive   = true
  value       = try(tls_private_key.node_pool_keypair[0].public_key_openssh, null)
  description = "Public key of the generated SSH keypair in OpenSSH format. Returns null when node_pool_keypair_name is supplied."
}

output "node_pool_name" {
  value       = opentelekomcloud_cce_node_pool_v3.node_pool.name
  description = "Name of the node pool."
}

output "node_pool" {
  sensitive   = true
  value       = opentelekomcloud_cce_node_pool_v3.node_pool
  description = "Complete configuration of the created node pool."
}
