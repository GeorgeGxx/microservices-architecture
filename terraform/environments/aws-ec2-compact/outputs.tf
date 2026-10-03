output "public_ip" {
  description = "Public Elastic IP assigned to the compact host"
  value       = aws_eip.compact_ip.public_ip
}

output "ssh_command" {
  description = "SSH connection string"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_eip.compact_ip.public_ip}"
}

output "ansible_quickstart" {
  description = "Ansible playbook execution command"
  value       = "ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/deploy-compact-stack.yml"
}
