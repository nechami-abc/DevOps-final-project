# Lecture 4 — Cloud Deployment (Free Tier)
## Validation Checklist

**Rules:**
- Complete every step in order — later steps assume earlier ones passed
- Do not look at `student-guide.md` while validating; if a step fails, re-read the relevant concept first
- Verify each expected output before moving to the next step
- Run all commands from the project root unless a step says otherwise

---

### Step 1 — File structure

```bash
ls terraform/ ansible/inventory/ ansible/playbooks/ .github/workflows/
```

**Expected:**
- `terraform/`: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` — no leftover VPC/EKS module files
- `ansible/inventory/`: `hosts.ini.example` (and your own `hosts.ini`, not committed)
- `ansible/playbooks/`: `install-minikube.yml`, `deploy-app.yml`
- `.github/workflows/`: `ci-cd.yml` (no `build-and-push.yml` left behind)

- [ ] No extra files beyond what's listed above

---

### Step 2 — Terraform plan is clean

```bash
cd terraform
terraform plan -var="key_name=YOUR_KEY_NAME"
```

**Expected:** `Plan: 2 to add, 0 to change, 0 to destroy.` (or `No changes.` if already applied)

- [ ] No errors, no unexpected resource changes

---

### Step 3 — Infrastructure startup

```bash
terraform output public_ip
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@$(terraform output -raw public_ip) "kubectl get nodes"
```

**Expected:** one node listed, status `Ready`

- [ ] EC2 instance reachable over SSH
- [ ] minikube node shows `Ready`

---

### Step 4 — Health endpoint

```bash
curl -s http://YOUR_PUBLIC_IP:30080/api/health
```

**Expected:** the same JSON response as the backend's `/health` route returned in Lecture 1/2 — routed through nginx's `/api/` proxy to the backend Service, now reachable over the public internet instead of only `localhost`.

- [ ] Returns a `200` with the expected health JSON

---

### Step 5 — Functional check (CRUD via curl)

```bash
curl -s -X POST http://YOUR_PUBLIC_IP:30080/api/products \
  -H "Content-Type: application/json" -d '{"name":"cloud-test","price":9.99}'
curl -s http://YOUR_PUBLIC_IP:30080/api/products
curl -s -X DELETE http://YOUR_PUBLIC_IP:30080/api/products/<id-from-above>
```

**Expected:** create returns the new product, list includes it, delete removes it — identical
behavior to Lecture 1/2, now running on AWS

- [ ] Create, list, and delete all succeed over the public IP

---

### Step 6 — Browser check

Open `http://YOUR_PUBLIC_IP:30080` in a browser (ideally from a different device/network than your
own laptop — a phone on cellular data is a good test).

**Expected:** the ShopList UI loads and lets you add/remove products, exactly like the local
minikube version

- [ ] UI loads and is functional from a network other than your own

---

### Step 7 — Redeploy check (persistence + automation)

```bash
# make a small visible change, e.g. a heading in app/frontend/index.html
git add -A && git commit -m "test: redeploy check" && git push github feature/lecture-4:main
# watch the Actions tab until `deploy` finishes, then:
curl -s http://YOUR_PUBLIC_IP:30080 | grep -o "<title>.*</title>"
curl -s http://YOUR_PUBLIC_IP:30080/api/products
```

**Expected:** the visible change is live without any manual `kubectl` command, and the product data
from Step 5 is still present — the redeploy updated the app without touching the database

- [ ] GitHub Actions `deploy` job completes successfully
- [ ] The change is visible without manual intervention
- [ ] Existing product data survived the redeploy

---

### Step 8 — Git check

```bash
git status
git log --oneline -3
git remote -v
```

**Expected:**
- Working tree clean
- Latest commit message follows the `<type>: <description>` format from `docs/bootstrap-kit.md`
- Both `origin` (GitLab) and `github` remotes are configured
- `.gitlab-ci.yml` still passes on GitLab, unmodified in behavior from Lecture 3

- [ ] Clean working tree, correctly formatted commit messages
- [ ] Both remotes present and both pipelines green

---

### Step 9 — Knowledge check

Answer these without looking at `student-guide.md` (honor system):

1. What problem does Terraform's state file solve?
2. Why doesn't AWS EKS fit the free tier?
3. What does "idempotent" mean, and where does `install-minikube.yml` demonstrate it?
4. Why is infrastructure provisioning kept out of the GitHub Actions pipeline?
5. How does the deploy job update the running app without any AWS credentials?

**Pass criteria:** Answer all 5 without hesitation.

---

## Completion

When all 9 steps pass:

```bash
git add terraform/ ansible/ .github/workflows/ci-cd.yml .gitlab-ci.yml
git commit -m "infra: add free-tier EC2 provisioning and GitHub Actions deploy pipeline (Lecture 4)"
git checkout dev
git merge feature/lecture-4
git push origin dev
```

**Expected:** `git push origin dev` completes without errors.

---

## Project Complete

Lecture 4 is the last lecture in this course. Once `dev` is verified — all four lectures' work
present and green — perform the one merge that is only ever correct at this point, per
`docs/bootstrap-kit.md` §5 and §8:

```bash
git checkout main
git merge dev
git push origin main
```

This is intentionally different from every other lecture's completion action (which stops at `dev`).
Only merge to `main` here, once, when the entire project is done.
