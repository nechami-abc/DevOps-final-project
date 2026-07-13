# Lecture 4 Exercises
## Free-Tier Cloud Deployment

---

## Exercise 1 — Inspect the Terraform Plan (Easy)

**Type:** Observation only
**Duration:** ~10 minutes
**Goal:** Read a Terraform plan closely enough to predict exactly what it will create, before applying anything.

### Task

1. From `terraform/`, run `terraform plan -var="key_name=YOUR_KEY_NAME"` (do **not** run `apply` yet)
2. Read the full output, resource by resource
3. Answer the questions below **before** running `apply`

**Commands to research:** `terraform plan`, `terraform show`, `terraform state list`

### Expected result

You should be able to answer, from the plan output alone:
1. How many resources will be created? (Expected: 2 — `aws_security_group.shoplist`, `aws_instance.shoplist`)
2. What AMI ID will the instance use, and where did Terraform get it from? (Expected: from `data.aws_ami.ubuntu`, resolved at plan time — not hardcoded in the file)
3. Which two ports does the security group open, and to which CIDR blocks?
4. Will anything be changed or destroyed? (Expected: no — this is a from-scratch plan)

### Validation

```bash
terraform plan -var="key_name=YOUR_KEY_NAME" | grep -E "Plan:|will be created"
```

Expected: `Plan: 2 to add, 0 to change, 0 to destroy.`

---

## Exercise 2 — Break the Security Group and Observe (Medium)

**Type:** Break-and-fix
**Duration:** ~15 minutes
**Goal:** Experience exactly what happens when the free-tier lab is unreachable, then restore it.

---

### Part A — Introduce the break

Edit `terraform/main.tf`. Remove the NodePort ingress rule from `aws_security_group.shoplist`:

**Before:**
```hcl
  ingress {
    description = "ShopList frontend NodePort"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
```

**After (broken):** delete the whole block above, leaving only the SSH `ingress` block.

Apply the change:
```bash
terraform apply -var="key_name=YOUR_KEY_NAME"
```

---

### Part B — Observe and record the failure

Try to load the app:
```bash
curl -v --max-time 5 http://YOUR_PUBLIC_IP:30080
```

Answer these questions:
1. What happens — a connection error, a timeout, or an HTTP error code?
2. Is the app itself still running inside minikube? (Check with `ssh ... "kubectl get pods -n shoplist"`)
3. Why does removing a Terraform-managed security group rule affect reachability, when nothing about the app or the pods changed?

**Expected observations:**
- `curl` times out or reports "Connection timed out" — never reaches the server at all
- `kubectl get pods -n shoplist` (over SSH) shows all pods still `Running` — the app is healthy
- The failure is purely at the network layer: the security group is the only thing standing between the NodePort and the internet, and it's now closed

---

### Part C — Restore the fix

Add the ingress block back to `terraform/main.tf` and re-apply:
```bash
terraform apply -var="key_name=YOUR_KEY_NAME"
curl -s http://YOUR_PUBLIC_IP:30080 | grep -o "<title>.*</title>"
```

Verify the app is reachable again.

---

## Exercise 3 — Remove the Swap File Task and Observe (Medium)

**Type:** Remove-and-observe
**Duration:** ~20 minutes
**Goal:** See directly why the swap-file task in `install-minikube.yml` exists, by removing it.

> This exercise needs a **fresh** instance — run it against a second `terraform apply` (a different
> `cluster_name`/tag) or destroy and recreate your existing one, so minikube starts from scratch.

### Part A — Remove the safeguard

In `ansible/playbooks/install-minikube.yml`, comment out (or delete) the entire "Check for existing
swap file" and "Create 2GB swap file" tasks.

Re-run the playbook against a fresh instance:
```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/install-minikube.yml
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/deploy-app.yml \
  -e "github_owner=YOUR_GITHUB_USERNAME"
```

### Part B — Observe and record

Over SSH, check memory pressure and pod health:
```bash
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@YOUR_PUBLIC_IP "free -h && kubectl get pods -n shoplist"
```

**What you are observing:** a `t3.micro` has only 1GB of RAM. Without the 2GB swap file, minikube's
control-plane components and the ShopList pods are competing for a very tight memory budget — you
should see pods in `CrashLoopBackOff`/`OOMKilled`, or the node itself reporting memory pressure, far
more often than with the swap file present. This is the same class of failure the readinessProbe on
`/health` was designed to surface back in Lecture 2 — a pod that looks like it started but can't stay
up under real resource pressure.

### Part C — Restore the fix

Uncomment the swap-file tasks, re-run `install-minikube.yml` against a fresh instance, and confirm
`free -h` shows a 2GB swap entry and pods stay `Running`.

---

## Bonus Exercise — Add a Post-Deploy Smoke Test (Optional)

### Background

Right now, `deploy` in `.github/workflows/ci-cd.yml` finishes as soon as `kubectl rollout status`
succeeds — that confirms the Deployment is healthy, but not that the app actually answers HTTP
requests correctly.

### Task

Add a final step to the `deploy` job's SSH script that curls the app and fails the job if it doesn't
get a `200`:

```yaml
      script: |
        kubectl set image deployment/backend backend=ghcr.io/${{ github.repository_owner }}/shoplist-backend:${{ env.SHORT_SHA }} -n shoplist
        kubectl set image deployment/frontend frontend=ghcr.io/${{ github.repository_owner }}/shoplist-frontend:${{ env.SHORT_SHA }} -n shoplist
        kubectl rollout status deployment/backend -n shoplist --timeout=120s
        kubectl rollout status deployment/frontend -n shoplist --timeout=120s
        curl -sf http://localhost:30080 > /dev/null || (echo "Smoke test failed" && exit 1)
```

### What to verify

Push a deliberately broken frontend change (e.g. an image tag typo) and confirm the `deploy` job now
fails on the smoke-test line, not silently succeeding with a broken app live in production.

### Expected pipeline with the bonus

`build-backend` → `build-frontend` → `verify-registry` → `deploy` (now including the curl smoke test
as its last step, failing the whole job — and turning the GitHub Actions run red — if the app doesn't
respond).
