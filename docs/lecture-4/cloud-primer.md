# Cloud Deployment Primer
## Plain-language background for Lecture 4 (15 min read)

> Read this before `student-guide.md` if any of these terms are new to you:
> cloud computing, AWS free tier, Infrastructure as Code, Terraform, Ansible, SSH-based deployment.

---

## What "the cloud" actually is

Every cluster you've run so far (Lecture 2 and 3) lived on your own laptop. minikube gave you
a real Kubernetes API server and real pods — but the machine underneath was yours, reachable
only from `localhost`.

"The cloud" just means: **someone else's computer, that you rent by the hour, with a public IP
address.** AWS (Amazon Web Services) is one such rental company. When you "deploy to the cloud,"
you are renting a virtual machine, installing the same software you already know how to run
locally, and pointing your CI/CD pipeline at it instead of at your own laptop.

Nothing about Kubernetes, Docker, or the ShopList app changes. What changes is *where it runs*
and *who can reach it*.

---

## The AWS Free Tier — and why it has limits

New AWS accounts get 750 hours/month of a `t2.micro` or `t3.micro` EC2 instance (1 vCPU, 1GB RAM)
for 12 months, plus 30GB of storage. That's enough to run one small Linux box, all month, for $0.

It is **not** enough to run a managed Kubernetes service. AWS EKS bills its control plane at a flat
rate (~$0.10/hour, ~$73/month) regardless of how small your workloads are — there is no free EKS
control plane. That's why Lecture 4 does not use EKS: it would cost real money the moment you
create it, whether or not you ever deploy a pod to it.

The free-tier-compatible answer is the same tool you already know: **run minikube**, just on a
rented EC2 box instead of your laptop, using the `--driver=none` mode so it runs directly on the
host without a nested VM.

---

## Infrastructure as Code (Terraform)

Until now, you've created things by hand: `docker build`, `kubectl apply`, clicking around in a
UI. **Infrastructure as Code (IaC)** means you write a file describing the infrastructure you want,
and a tool creates (or updates, or deletes) it to match.

Terraform is the IaC tool this course uses. Four commands matter:

| Command | What it does |
|---|---|
| `terraform init` | Downloads the AWS provider plugin |
| `terraform plan` | Shows what *would* change, without changing anything |
| `terraform apply` | Actually creates/updates the resources in AWS |
| `terraform destroy` | Deletes everything Terraform created — **run this when you're done, or AWS keeps billing you** |

Terraform tracks what it created in a **state file**. That's how `terraform destroy` knows exactly
what to remove — it's not guessing, it's reading its own record of what it built.

---

## Configuration Management (Ansible)

Terraform's job ends the moment the EC2 instance exists — it hands you a blank Ubuntu box with an
IP address. Something still has to install Docker, kubectl, and minikube *on* that box, over SSH.
That's **Ansible**'s job.

Ansible reads a **playbook** (a YAML file describing tasks) and an **inventory** (a list of hosts to
run it against), then connects over plain SSH — no agent needs to be pre-installed on the target.

The key property Ansible aims for is **idempotency**: running the same playbook twice should produce
the same end state, not double-install anything or fail the second time. You'll see this directly in
`install-minikube.yml`, where the swap-file task first checks whether `/swapfile` already exists
before creating it.

---

## Why provisioning and deployment are two separate things

This lecture deliberately keeps two flows apart:

1. **Provisioning** (`ansible/provision.sh`) — creates the EC2 instance and installs minikube.
   Run **once, by hand**. It costs money and takes minutes; nobody wants it triggered by an
   accidental `git push`.
2. **Deployment** (`.github/workflows/ci-cd.yml`) — builds a new image and updates the already-running
   app. Runs **automatically on every push**, because it's fast, free, and reversible.

Mixing these two would mean every commit risks re-provisioning or tearing down real infrastructure.
Keeping them separate is a real-world pattern, not just a teaching simplification.

---

## SSH-based deployment (no AWS credentials in CI)

Because the free-tier setup is "one box on the internet" rather than a managed cloud API, GitHub
Actions doesn't need any AWS credentials at all to deploy. It just needs to SSH into the box and run
`kubectl` — the same command you'd type yourself. Two secrets make this possible:

- `EC2_HOST` — the box's public IP
- `EC2_SSH_KEY` — the private half of the key pair Terraform used to create the instance

That's the whole trust boundary: whoever holds that SSH key can update the app. No IAM roles, no
AWS access keys sitting in GitHub.

---

You now have enough background for `student-guide.md`. Keep this page open — you'll come back to the
Terraform/Ansible/IaC vocabulary throughout the lecture.
