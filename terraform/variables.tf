variable "aws_region" {
  description = "AWS region in which to deploy the lab instance"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name used to tag the EC2 instance and its security group"
  type        = string
  default     = "shoplist"
}

variable "instance_type" {
  description = "EC2 instance type — t3.micro is free-tier eligible"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair (create one in the AWS console first) used for SSH and for the GitHub Actions deploy step"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instance — restrict this to your own IP/32 in real use"
  type        = string
  default     = "0.0.0.0/0"
}
