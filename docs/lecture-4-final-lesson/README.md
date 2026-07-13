# Lecture 4 — Final Lesson (45-minute, Windows-only, zero local installs)

This is a short, live session (~45 minutes) where students deploy the ShopList app — the small
app already in this repo under `app/`, `kubernetes/`, `terraform/`, and `ansible/` — onto a real AWS
EC2 server, entirely through GitHub Actions pipelines.

Students are on **Windows with no WSL2 available**, so there's no time or ability to install
Terraform, Ansible, kubectl, or the AWS CLI locally. Every one of those tools instead runs on a
**GitHub-hosted Actions runner** — a student only needs a browser, a GitHub account, and an AWS
free-tier account. This folder is self-contained: everything needed to run today's session is
documented here.

## What's in this folder

| File | Covers |
|---|---|
| [student-walkthrough.md](student-walkthrough.md) | Plain-language, click-by-click guide for running the pipelines — start here if you're new to this. |
| [create-infra-pipeline.md](create-infra-pipeline.md) | The `create-infra.yml` pipeline that provisions the EC2 instance, installs minikube, and deploys the app — all on a GitHub runner. How Terraform state is handled without any external backend, and the plan → confirm dispatch gate. |
| [cicd-pipeline.md](cicd-pipeline.md) | The existing build/push/deploy pipeline (`ci-cd.yml`), what changed, and when to run it relative to `create-infra.yml`. |
| [secrets-setup.md](secrets-setup.md) | Exact steps to get AWS keys and add all required GitHub repo secrets — no local tools needed for any of it. |
| [image-tags-and-visibility.md](image-tags-and-visibility.md) | How image tags are chosen, and the one-time manual step to make the `ghcr.io` packages public (required or pods get stuck in `ImagePullBackOff`). |

## The 45-minute flow, in order

1. **Push this project to a new personal GitHub repo you own** (create an empty repo on GitHub,
   then push this code to it).
2. **Add AWS credentials as repo secrets** — [secrets-setup.md](secrets-setup.md) step 1.
3. **One-time**: create an AWS key pair and add its private key as the `EC2_SSH_KEY` repo secret —
   [secrets-setup.md](secrets-setup.md) step 2. Do this before the first run of `create-infra.yml`.
4. **Run `ci-cd.yml` once manually** (Actions tab → "Build, Push and Deploy" → Run workflow) so a
   container image exists in `ghcr.io` for the current commit. The deploy job in this run will
   skip cleanly (infra doesn't exist yet) — that's expected.
5. **Make the two `ghcr.io` packages public** — [image-tags-and-visibility.md](image-tags-and-visibility.md).
   Skipping this leaves pods stuck in `ImagePullBackOff` later.
6. **Run `create-infra.yml` with `action: apply`, `stage: plan`, and the `key_name` from step 3**
   (Actions tab → "Create/Destroy Lab Infra" → Run workflow). Review the full Terraform plan in its
   job summary.
7. **Run it again — same `action` and `key_name`, `stage: confirm`.** This applies the exact plan
   from step 6, then provisions the EC2 instance, installs minikube, and deploys the app built in
   step 4. Takes ~5–8 minutes total — Terraform + Ansible run on the runner while you keep talking.
8. **Copy the one secret it produces** (`EC2_HOST`, the public IP) into the repo —
   [secrets-setup.md](secrets-setup.md) step 4. From here on, every push to `main` auto-deploys via
   `ci-cd.yml`.
9. **Demo**: open `http://<public-ip>:30080` in a browser.
10. **At the end of the session**, run `create-infra.yml` with `action: destroy` (same
    plan-then-confirm flow, two dispatches) to avoid ongoing AWS charges.

## Why this shape

- **No local installs**: Terraform, Ansible, and the AWS CLI all run inside the `create-infra.yml`
  job on `ubuntu-latest`. Students never run a command on their own machine.
- **State lives in GitHub, not AWS**: Terraform state is uploaded as a workflow artifact after every
  run and downloaded from the last successful run before the next one — no S3 bucket or Terraform
  Cloud account to set up first. See [create-infra-pipeline.md](create-infra-pipeline.md) for the
  trade-offs of this approach.
- **No Terraform/variable changes**: the existing `terraform/variables.tf` `key_name` variable
  (an existing AWS key pair name) is left exactly as-is — the pipeline just supplies that same
  variable via a workflow input instead of hardcoding it.
- **Nothing touches AWS without a human looking at the plan first — no GitHub Environment needed**:
  `create-infra.yml` takes a `stage` input (`plan`/`confirm`) and is dispatched twice — `plan` always
  runs and is read-only; `confirm` is a separate, deliberate manual dispatch that applies the exact
  plan just reviewed. See [create-infra-pipeline.md](create-infra-pipeline.md).
- **One stable SSH key pair, not a fresh one per run**: you create it once and its private key lives
  in the `EC2_SSH_KEY` repo secret — see [secrets-setup.md](secrets-setup.md) step 2. This also
  avoids a real bug an earlier version had (a freshly-generated key wouldn't match an
  already-running instance, since cloud-init only applies the public key at first boot).
