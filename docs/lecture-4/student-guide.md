# Lecture 4 — Cloud Deployment (Free Tier)
## Student Guide

> **No cloud/Terraform/Ansible background? Start here:**
> Read [cloud-primer.md](cloud-primer.md) before this guide.
> It explains the AWS free tier, Infrastructure as Code, and configuration management in plain language (15 min).

---

## Lecture Outcome (STRICT)

**What exists at the end of this lecture:**

| File | Change | Purpose |
|------|--------|---------|
| `terraform/main.tf` | Modified | 1 EC2 instance + 1 security group — replaces the old EKS/VPC draft |
| `terraform/variables.tf` | Modified | `aws_region`, `instance_type`, `key_name`, `allowed_ssh_cidr` |
| `terraform/outputs.tf` | Modified | `public_ip`, `app_url`, `ssh_command` |
| `ansible/inventory/hosts.ini.example` | New | Inventory template |
| `ansible/playbooks/install-minikube.yml` | New | Installs Docker + kubectl + minikube on the EC2 box |
| `ansible/playbooks/deploy-app.yml` | New | Applies `kubernetes/*.yml` to the remote minikube |
| `ansible/provision.sh` | New | The one manual command that runs the whole provisioning flow |
| `.github/workflows/ci-cd.yml` | Modified (renamed from `build-and-push.yml`) | Adds a `deploy` job on top of Lecture 3's build/push |

**What does NOT exist yet — and never will, in this course:**
- No managed Kubernetes (EKS/GKE) — doesn't fit the free tier
- No multi-node cluster, no autoscaling
- No HTTPS/TLS or custom domain
- No monitoring/alerting stack

**What you CAN do after this lecture:**
- Provision a real AWS EC2 instance from Terraform and tear it down again with `terraform destroy`
- Install minikube on a remote Linux box over SSH using Ansible, idempotently
- Deploy ShopList to that remote minikube and reach it from any browser via a public IP
- Push a code change to your own GitHub repo and watch GitHub Actions rebuild and redeploy automatically
- Explain why infrastructure provisioning and application deployment should not share a trigger

**What you CANNOT do yet:**
- Survive the EC2 instance itself failing (single box, single point of failure — a deliberate free-tier trade-off)
- Roll out zero-downtime across multiple nodes
- Serve traffic over HTTPS with a real domain name

---

## What You Will Build

Two separate flows, on purpose:

```
MANUAL — run once, by hand:

  ansible/provision.sh
       │
       ▼
  terraform apply ──────────► EC2 instance (t3.micro, free tier)
       │                       + security group (22, 30080)
       ▼
  ansible install-minikube.yml ─► Docker + kubectl + minikube installed
       │                          --driver=none, 2GB swap added
       ▼
  ansible deploy-app.yml ──────► kubernetes/*.yml applied
                                  (image swapped to ghcr.io:<tag>)


AUTOMATIC — every push to your new GitHub repo:

  git push
       │
       ▼
  .github/workflows/ci-cd.yml
       │
  ┌────┴─────────────────────────────┐
  │ build-backend / build-frontend   │  (same pattern as Lecture 3)
  │   → push images to ghcr.io       │
  └────┬─────────────────────────────┘
       ▼
  verify-registry
       ▼
  deploy  ──► SSH into EC2_HOST, `kubectl set image ...`, `kubectl rollout status`
       ▼
  ShopList live at http://<public-ip>:30080, new version
```

**Application code is unchanged.** Zero modifications to `app.py`, `nginx.conf`, or any `Dockerfile`.
The `kubernetes/*.yml` files used by Lecture 2/3 are also unchanged — Ansible copies them and swaps
the image line at deploy time, it never edits the originals.

---

## What You Will Learn

- What AWS's free tier actually covers, and why managed Kubernetes (EKS) doesn't qualify
- What Infrastructure as Code is, and what problem Terraform's state file solves
- What configuration management is, and what "idempotent" means in an Ansible playbook
- How minikube's `--driver=none` mode lets a NodePort service be reachable directly on a box's public IP
- Why provisioning (Terraform + Ansible install) and deployment (CI/CD) are kept as two separate, separately-triggered flows
- How a GitHub Actions job can deploy a new app version with nothing but an SSH key — no AWS credentials in CI at all

---

## Prerequisites

Before starting, verify every item:

- [ ] Lecture 3 complete — `.gitlab-ci.yml` builds and pushes images; the minikube cluster from Lecture 2/3 is still running locally
- [ ] An AWS account with the free tier active, and the AWS CLI configured (`aws configure`) with credentials that can create EC2 instances and security groups
- [ ] An EC2 key pair already created in your AWS account/region (EC2 console → Key Pairs → Create key pair). Save the `.pem` file — you'll need it for SSH and for `key_name` in Terraform
- [ ] `terraform >= 1.6` and `ansible >= 2.15` installed (see `docs/bootstrap-kit.md` §6)
- [ ] A GitHub account and the ability to create a new repository
- [ ] You are on branch `feature/lecture-4` (`git checkout -b feature/lecture-4`)

If any item fails, stop and resolve it before continuing.

---

## Part 1 — Core Concepts

Read this section before writing any files. If any term is unfamiliar, re-read `cloud-primer.md` first.

---

### Concept: AWS Free Tier

New AWS accounts get 750 hours/month of a `t2.micro`/`t3.micro` EC2 instance and 30GB of storage,
free, for 12 months.

#### Why It Exists

AWS wants developers to try the platform without financial risk. It covers exactly one small Linux
box running continuously — enough for a single-instance lab, not enough for a managed control plane.

#### How It Works

| Resource | Free tier limit |
|---|---|
| EC2 `t2.micro`/`t3.micro` | 750 hrs/month (effectively: one instance, running all month) |
| EBS storage | 30GB |
| Data transfer out | 100GB/month |
| EKS control plane | **Not included at any usage level** — flat ~$0.10/hr |

> ⚠️ **Common mistake:** leaving the instance running after the lecture. `terraform destroy` is not
> optional cleanup — it's how you stop being billed. Free tier hours are also capped per month;
> forgetting to destroy across several lab sessions can burn through them.

---

### Concept: Infrastructure as Code (Terraform)

Terraform lets you describe cloud infrastructure in a file and have a tool create it, rather than
clicking through a console or running one-off CLI commands.

#### Why It Exists

Manually-created infrastructure is not reproducible, not reviewable in a pull request, and easy to
forget to tear down. A `.tf` file is all three: reproducible, reviewable, and destroyable with one
command.

#### How It Works

| Command | Effect |
|---|---|
| `terraform init` | Downloads the `hashicorp/aws` provider plugin |
| `terraform plan` | Computes and prints the diff between current state and desired state — changes nothing |
| `terraform apply` | Applies that diff — creates/updates real AWS resources |
| `terraform destroy` | Deletes everything Terraform's state file says it created |

Terraform decides *what* to create from `data` blocks (read-only lookups, like "the default VPC") and
`resource` blocks (things it owns and manages, like the EC2 instance).

> ⚠️ **Common mistake:** running `terraform apply` from a different directory than the one containing
> the state file, or on a different machine, creates a *second* untracked instance instead of managing
> the first one. Always run Terraform commands from `terraform/` in this repo.

---

### Concept: Configuration Management (Ansible)

Ansible installs and configures software on remote machines over plain SSH, described declaratively
in YAML **playbooks**.

#### Why It Exists

Terraform's job stops the instant the EC2 instance exists. Something still has to log in and install
Docker, kubectl, and minikube. Doing that by hand, consistently, across every lab environment, doesn't
scale — a playbook does it the same way every time.

#### How It Works

- An **inventory** (`ansible/inventory/hosts.ini`) lists which hosts to run against
- A **playbook** (e.g. `install-minikube.yml`) lists ordered **tasks**, each using a built-in module
  (`ansible.builtin.apt`, `ansible.builtin.copy`, etc.)
- Ansible connects over SSH using the key in the inventory — no agent pre-installed on the target
- Playbooks aim to be **idempotent**: running them twice produces the same end state. Look at the
  "Check for existing swap file" task in `install-minikube.yml` — it only creates the swap file if
  one doesn't already exist, so re-running the playbook doesn't fail or double-allocate.

> ⚠️ **Common mistake:** treating a playbook like a one-shot shell script and assuming re-running it
> is always safe without checking. Most Ansible modules (`apt`, `systemd`, `file`) are idempotent by
> default; raw `command`/`shell` tasks (like `fallocate -l 2G /swapfile`) are not — that's exactly why
> that task is wrapped in a `when: not swapfile.stat.exists` guard.

---

### Concept: minikube with `--driver=none`

On your laptop, minikube usually runs inside a VM or a Docker container acting as the "node." On a
cloud VM, it can run directly on the host instead.

#### Why It Exists

A `t3.micro` (1 vCPU, 1GB RAM) has no room for a nested VM on top of an already-thin OS. `--driver=none`
skips that layer: the kubelet, API server, and other components run as ordinary processes on the
Ubuntu host itself.

#### How It Works

| Aspect | Laptop minikube (`--driver=docker`) | EC2 minikube (`--driver=none`) |
|---|---|---|
| Node | Runs inside a container | *Is* the host machine |
| NodePort reachability | `localhost:<port>` (or `minikube service` / tunnel) | Host's public IP directly — no tunnel needed |
| Resource overhead | VM/container layer + k8s components | k8s components only |
| Typical use | Local development | Single disposable cloud lab instance |

This is why the security group only needs to open port `30080` (the frontend NodePort) — there's no
extra networking layer between "the Service" and "the internet."

> ⚠️ **Common mistake:** forgetting `CHANGE_MINIKUBE_NONE_USER=true` when starting minikube as root
> (which `--driver=none` requires). Without it, the kubeconfig stays owned by `root` and your SSH
> user's `kubectl` commands fail with permission errors.

---

### Concept: Two Pipelines, Two Purposes

Provisioning (Terraform + the initial Ansible install) and deployment (rebuilding and redeploying the
app) are kept as two separate flows with two separate triggers.

#### Why It Exists

Provisioning costs money and takes minutes; you want it deliberate. Deployment should be fast, cheap,
and safe to run on every commit. If they were the same pipeline, every `git push` would risk
re-provisioning or even destroying real infrastructure.

#### How It Works

- **Provisioning** = `ansible/provision.sh`, run **by hand**, **once** (or whenever you deliberately
  want to recreate the instance)
- **Deployment** = `.github/workflows/ci-cd.yml`'s `deploy` job, runs **automatically on every push**,
  and only ever touches the *running* app — it never calls `terraform apply` or reinstalls minikube

| | Provisioning | Deployment |
|---|---|---|
| Trigger | Manual (`./ansible/provision.sh`) | Automatic (`git push`) |
| Tooling | Terraform + Ansible (full playbook) | `kubectl set image` over SSH |
| Frequency | Rare | Every commit |
| Risk if wrong | Creates/destroys real AWS resources | Worst case: bad image tag, easy rollback |

> ⚠️ **Common mistake:** "simplifying" by wiring `terraform apply` into the CI/CD pipeline "to save a
> step." This is the single most common way free-tier labs turn into surprise AWS bills.

---

### Concept: SSH-based Deployment (no AWS credentials in CI)

The `deploy` job in `ci-cd.yml` never calls any AWS API. It SSHes into the box and runs `kubectl`
directly — the exact same commands you'd type yourself.

#### Why It Exists

A single EC2 instance has no managed control-plane API to call, unlike EKS. SSH is the only interface
that already exists, so the pipeline uses it instead of introducing AWS IAM roles/access keys just for
a demo lab.

#### How It Works

```yaml
- name: Update running deployment over SSH
  uses: appleboy/ssh-action@v1.0.3
  with:
    host: ${{ secrets.EC2_HOST }}
    username: ubuntu
    key: ${{ secrets.EC2_SSH_KEY }}
    script: |
      kubectl set image deployment/backend backend=ghcr.io/OWNER/shoplist-backend:SHA -n shoplist
      kubectl set image deployment/frontend frontend=ghcr.io/OWNER/shoplist-frontend:SHA -n shoplist
      kubectl rollout status deployment/backend -n shoplist --timeout=120s
      kubectl rollout status deployment/frontend -n shoplist --timeout=120s
```

`kubectl set image` patches only the container image on an existing Deployment — it's a targeted
update, not a full manifest re-apply, which is why the CI job doesn't need Ansible or the
`kubernetes/*.yml` files at all for a routine redeploy.

> ⚠️ **Common mistake:** pasting the `.pem` file's contents into `EC2_SSH_KEY` with the wrong line
> endings or a missing trailing newline. Copy the file exactly as-is (`cat key.pem | pbcopy` on macOS,
> or open it in a plain text editor) — a mangled key fails silently with a generic "Permission denied
> (publickey)" error.

---

## Part 2 — Step-by-Step Instructions

---

### Step 1 — Create an AWS key pair and configure credentials

```bash
aws configure
# AWS Access Key ID, Secret Access Key, region (must match terraform/variables.tf aws_region), output format
```

Create a key pair (skip if you already have one for this region):

```bash
aws ec2 create-key-pair --key-name shoplist-key --query 'KeyMaterial' --output text > ~/.ssh/shoplist-key.pem
chmod 400 ~/.ssh/shoplist-key.pem
```

Note the key name (`shoplist-key`) — you'll pass it as `key_name` to Terraform.

---

### Step 2 — Review `terraform/variables.tf`

```hcl
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
  description = "Name of an existing EC2 key pair (create one in the AWS console first)"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instance — restrict this to your own IP/32 in real use"
  type        = string
  default     = "0.0.0.0/0"
}
```

`key_name` has no default — Terraform will prompt for it (or pass it with `-var`).

---

### Step 3 — Review `terraform/main.tf`

```hcl
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "shoplist" {
  name   = "${var.cluster_name}-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "shoplist" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.shoplist.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = { Name = var.cluster_name }
}
```

No VPC module, no EKS module, no generated keys — the default VPC, one security group, one instance.

---

### Step 4 — `terraform init`, `plan`, `apply`

```bash
cd terraform
terraform init
terraform plan -var="key_name=shoplist-key"
```

Read the plan output: it should show exactly 2 resources to add (`aws_security_group.shoplist`,
`aws_instance.shoplist`), nothing to change or destroy.

```bash
terraform apply -var="key_name=shoplist-key"
# type "yes" when prompted
terraform output public_ip
```

You now have a real, billable (though free-tier-covered) EC2 instance. Keep the public IP handy.

---

### Step 5 — Create the Ansible inventory

```bash
cd ..
cp ansible/inventory/hosts.ini.example ansible/inventory/hosts.ini
```

Edit `ansible/inventory/hosts.ini` — replace the placeholder with your real public IP and key path:

```ini
[shoplist]
YOUR_PUBLIC_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/shoplist-key.pem
```

Verify SSH works before running Ansible:

```bash
ssh -i ~/.ssh/shoplist-key.pem ubuntu@YOUR_PUBLIC_IP
exit
```

---

### Step 6 — Run `install-minikube.yml`

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/install-minikube.yml
```

**Expected:** the play recap shows `failed=0`; the last task ("Wait for the node to be Ready") succeeds.

This installs Docker, crictl, CNI plugins, and a generated containerd config, adds a 2GB swap file,
and starts minikube with `--driver=none --container-runtime=containerd --force`. Every one of those
extra pieces exists because a plain `minikube start --driver=none` genuinely fails on a real
`t3.micro` — see `runbook.md`'s "Issues Found During Real Execution" table if you want the full story
of what breaks and why, in the exact order it breaks.

---

### Step 7 — Run `deploy-app.yml`

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/deploy-app.yml \
  -e "github_owner=YOUR_GITHUB_USERNAME" -e "image_tag=latest"
```

**Expected:** both rollout status tasks succeed, and the final debug task prints
`ShopList is live at http://YOUR_PUBLIC_IP:30080`.

Open that URL in a browser and confirm the ShopList UI loads.

> **Two things that must be true before this step works:** the ghcr.io packages must be **public**
> (Package settings → Change visibility — a private package leaves pods stuck in `ImagePullBackOff`
> with no useful error until you check `kubectl describe pod`), and a `:latest` tag must actually
> exist (the CI pipeline only ever pushes SHA tags on purpose — push `:latest` once by hand for this
> manual run, or pass the real SHA as `image_tag`). If you're building images locally on an Apple
> Silicon Mac to push manually, add `docker buildx build --platform linux/amd64 ...` — otherwise the
> pod fails with a platform-mismatch error, since the EC2 instance is `amd64`. See `runbook.md` for
> the exact commands.

---

### Step 8 — Or just run both with `provision.sh`

Steps 4–7 are exactly what `ansible/provision.sh` automates:

```bash
./ansible/provision.sh YOUR_GITHUB_USERNAME latest ~/.ssh/shoplist-key.pem
```

This is the single manual command referenced throughout this lecture. Run the steps by hand once so
you understand each stage, then use the script for any later re-provisioning.

---

### Step 9 — Create a new GitHub repo and push the project

```bash
# On github.com: create a new empty repository, e.g. "devops-tikshuv-project"
git remote add github https://github.com/YOUR_GITHUB_USERNAME/devops-tikshuv-project.git
git push github feature/lecture-4:main
```

Your GitLab remote (`origin`) is untouched — you now have two remotes, and `.gitlab-ci.yml` keeps
working exactly as it did in Lecture 3.

In the new GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**, add:

- `EC2_HOST` = the public IP from Step 4
- `EC2_SSH_KEY` = the full contents of `~/.ssh/shoplist-key.pem`

---

### Step 10 — Push a change and watch it redeploy

Make a trivial, visible change (e.g. a comment in `app/frontend/index.html`), commit, and push to
`main` on the `github` remote. In the GitHub repo's **Actions** tab, watch `build-backend`,
`build-frontend`, `verify-registry`, then `deploy` run in sequence.

```bash
curl -s http://YOUR_PUBLIC_IP:30080 | grep -o "<title>.*</title>"
```

Confirm the change is live without you running any manual `kubectl` command.

---

### Step 11 — Clean up

```bash
cd terraform
terraform destroy -var="key_name=shoplist-key"
```

Free tier or not, always destroy lab infrastructure you're not actively using.

---

## Interview Questions

1. **What is Infrastructure as Code, and what problem does Terraform's state file solve that a plain shell script doesn't?**
   IaC means infrastructure is described declaratively in files instead of created by hand. Terraform's state file records exactly what it created, so `terraform destroy` (or a future `apply`) knows precisely what to remove or change — a shell script has no memory of what it already ran.

2. **Why doesn't AWS EKS qualify for the free tier, and what did we use instead?**
   EKS bills its control plane a flat hourly rate regardless of usage, with no free tier coverage. We used a single free-tier-eligible EC2 instance running minikube with `--driver=none` instead.

3. **What does "idempotent" mean in an Ansible playbook, and where do you see it in `install-minikube.yml`?**
   Idempotent means running the same playbook repeatedly produces the same end state without errors or duplicate side effects. The swap-file task checks `swapfile.stat.exists` before creating `/swapfile`, so re-running the playbook doesn't fail or allocate a second swap file.

4. **Why is infrastructure provisioning kept out of the GitHub Actions pipeline, and what could go wrong if it were triggered automatically?**
   Provisioning creates or destroys real, billable infrastructure and should be deliberate. If it ran on every push, a routine commit could accidentally recreate or tear down the EC2 instance, causing downtime or unexpected AWS charges.

5. **How does the GitHub Actions deploy job update the running app without AWS credentials, and what are the two secrets it depends on?**
   It SSHes directly into the EC2 instance and runs `kubectl set image` against the already-running minikube cluster — no AWS API calls are involved. It depends on `EC2_HOST` (the public IP) and `EC2_SSH_KEY` (the private key matching the instance's key pair).

---

## Appendix — Cost Safety Checklist

- [ ] `instance_type` is `t3.micro` (or `t2.micro`) — never bump it up "just to be safe," that leaves the free tier
- [ ] You ran `terraform destroy` at the end of every session where you don't need the instance running
- [ ] `allowed_ssh_cidr` is restricted to your own IP in anything beyond a disposable class lab
- [ ] You are not also running an EKS/GKE/AKS cluster left over from experimentation — check the AWS console's EC2 and EKS pages directly, don't rely on memory
