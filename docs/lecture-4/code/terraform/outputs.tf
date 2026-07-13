output "public_ip" {
  description = "Public IP of the lab instance — use as EC2_HOST and for SSH/browser access"
  value       = aws_instance.shoplist.public_ip
}

output "app_url" {
  description = "URL for the ShopList frontend once minikube and the app are deployed"
  value       = "http://${aws_instance.shoplist.public_ip}:30080"
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i <path-to-private-key> ubuntu@${aws_instance.shoplist.public_ip}"
}
