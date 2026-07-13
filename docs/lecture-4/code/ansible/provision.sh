#!/usr/bin/env bash
# Manual, one-time entry point for Lecture 4's infra.
# Run by hand from the project root: ./ansible/provision.sh <github-owner> [image_tag]
#
# 1. terraform apply    -> creates the EC2 instance
# 2. writes ansible/inventory/hosts.ini from the real public IP
# 3. installs minikube  -> ansible/playbooks/install-minikube.yml
# 4. deploys the app    -> ansible/playbooks/deploy-app.yml
#
# Never run this from a pipeline — it's a manual, deliberate step so infra
# changes and AWS cost never happen silently on a git push.

set -euo pipefail

GITHUB_OWNER="${1:?Usage: ansible/provision.sh <github-owner> [image_tag] [ssh_key_path]}"
IMAGE_TAG="${2:-latest}"
SSH_KEY_PATH="${3:-$HOME/.ssh/id_rsa}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> terraform apply"
cd "$REPO_ROOT/terraform"
terraform init -input=false
terraform apply -auto-approve
PUBLIC_IP="$(terraform output -raw public_ip)"
cd "$REPO_ROOT"

echo "==> writing ansible/inventory/hosts.ini ($PUBLIC_IP)"
cat > ansible/inventory/hosts.ini <<EOF
[shoplist]
$PUBLIC_IP ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_KEY_PATH
EOF

echo "==> waiting for SSH to come up"
until ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ubuntu@$PUBLIC_IP" true 2>/dev/null; do
  sleep 5
done

echo "==> installing minikube"
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/install-minikube.yml

echo "==> deploying ShopList"
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/deploy-app.yml \
  -e "github_owner=$GITHUB_OWNER" -e "image_tag=$IMAGE_TAG"

echo "==> done — app should be live at http://$PUBLIC_IP:30080"
echo "==> now add these as GitHub Actions secrets in your new repo:"
echo "      EC2_HOST     = $PUBLIC_IP"
echo "      EC2_SSH_KEY  = contents of $SSH_KEY_PATH"
