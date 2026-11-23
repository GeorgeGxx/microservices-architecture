output "public_ip" {
  description = "Public Elastic IP assigned to the compact host"
  value       = aws_eip.compact_ip.public_ip
}

output "ssh_command" {
  description = "SSH connection string"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_eip.compact_ip.public_ip}"
}

output "ansible_quickstart" {
  description = "Ansible playbook execution command for compact microservices stack"
  value       = "ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/deploy-compact-stack.yml"
}

output "jenkins_url" {
  description = "Jenkins Web UI URL (available when Jenkins Controller playbook is deployed)"
  value       = "http://${aws_eip.compact_ip.public_ip}:8080"
}

output "ansible_jenkins_controller" {
  description = "Ansible playbook execution command to set up Jenkins Controller"
  value       = "ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-jenkins-controller.yml"
}

output "ansible_jenkins_worker" {
  description = "Ansible playbook execution command to set up Jenkins DevSecOps Worker Agent"
  value       = "ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-jenkins-worker.yml"
}
