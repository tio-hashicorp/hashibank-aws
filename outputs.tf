# Outputs file

output "bankapp_ip" {
  value = "http://${aws_eip.hashibank.public_ip}"
}

output "private_key" {
  value = tls_private_key.hashibank.private_key_pem
  sensitive = true
}
output "bankapp_url" {
  value = "http://${aws_eip.hashibank.public_dns}"
}
