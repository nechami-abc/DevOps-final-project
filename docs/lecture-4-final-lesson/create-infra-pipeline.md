# The `create-infra.yml` pipeline

File: [`.github/workflows/create-infra.yml`](../../.github/workflows/create-infra.yml)

Replaces the manual `ansible/provision.sh` step (which needs a local shell, Terraform, Ansible, and
a pre-created SSH key) with a `workflow_dispatch` pipeline that does the same work on a GitHub
runner. Nothing in `terraform/` or `ansible/` was changed — this pipeline calls the exact same
Terraform config (`terraform/`) and Ansible playbooks (`ansible/playbooks/`) already in this repo.

## No GitHub Environment needed — the gate is a second manual dispatch

There's no `environment:`/required-reviewers setup here. Instead the workflow takes a `stage` input
(`plan` or `confirm`) and you dispatch it **twice**:

1. **`stage: plan`** — always run this first. Computes the Terraform plan and posts the full
   `terraform show` output to the job summary. Nothing touches AWS beyond a read-only plan.
2. Read the job summary. If it looks right, dispatch the workflow **again**, same `action` and
   `key_name`, with **`stage: confirm`**. This downloads the exact plan artifact from step 1 and
   runs `terraform apply` on it — no re-planning, so nothing can drift between what you reviewed and
   what actually happens.

The `confirm` job double-checks it's applying the plan you think it is: the `plan` job writes a
small `plan-meta.txt` (the `action`+`key_name` it was computed for) into the same artifact, and
`confirm` fails loudly if that doesn't match what you just typed in — so confirming with the wrong
`action`/`key_name`, or after some other run snuck in between plan and confirm, gets caught instead
of silently applying the wrong thing.

## Running it

Actions tab → **Create/Destroy Lab Infra** → **Run workflow**, choose:

- **action**: `apply` (create/update the instance) or `destroy` (tear it down)
- **stage**: `plan` the first time, `confirm` the second time
- **key_name**: the name of the AWS key pair you created once (see
  [secrets-setup.md](secrets-setup.md) step 2) — must match on both the `plan` and `confirm` runs
- **image_tag**: only used on `action: apply` + `stage: confirm`. Leave blank to use the current
  commit's short SHA (recommended — make sure `ci-cd.yml` already built and pushed that tag, and
  the packages are public — see [image-tags-and-visibility.md](image-tags-and-visibility.md))

## What it does, step by step

**`plan` job (only runs when `stage: plan`; read-only against AWS):**

1. Configures AWS credentials from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` repo secrets.
2. Looks up the last successful run of this same workflow via `gh run list` and downloads its
   `tfstate` artifact, if one exists, into `terraform/` before `terraform init`. First-ever run: no
   artifact exists yet, which is fine — `terraform init` starts from empty state.
3. Runs `terraform plan -var key_name=<input> -out=tfplan` (or `plan -destroy` for the destroy
   action) — the same command you'd run from a local terminal, just executed on the runner instead.
   **No SSH key is generated here anymore** — `key_name` refers to an AWS key pair you already
   created (see [secrets-setup.md](secrets-setup.md) step 2), so plan/apply just reference it by
   name.
4. Posts the full `terraform show` output to the job summary, plus a reminder of the exact
   action/key_name to re-dispatch with for `stage: confirm`.
5. Uploads the plan file and its `plan-meta.txt` as the `tfplan` artifact, and re-uploads
   `terraform.tfstate` unchanged as the `tfstate` artifact (so "last successful run" always has a
   fresh state file to hand to the next `plan` or `confirm` run, regardless of which kind of run
   was most recent).

**`confirm` job (only runs when `stage: confirm`):**

6. Looks up the last successful run of this workflow (expected to be the `plan` run from step 1–5)
   and downloads its `tfplan` and `tfstate` artifacts.
7. Verifies `plan-meta.txt` matches the `action`/`key_name` given now — fails with a clear error
   otherwise instead of applying a stale or mismatched plan.
8. Runs `terraform apply tfplan` — replays the **exact** reviewed plan.
9. **On apply**: reads the private key from the `EC2_SSH_KEY` repo secret (never generated, never
   printed — written straight to a local file from the secret), waits for SSH, writes
   `ansible/inventory/hosts.ini`, installs Ansible on the runner (`pip install ansible`), then runs
   the existing `install-minikube.yml` and `deploy-app.yml` playbooks unchanged. Job summary prints
   the public IP and the one remaining secret to add (`EC2_HOST`).
10. **On destroy**: job summary notes the instance is gone; `EC2_SSH_KEY` and the AWS key pair are
    left alone since they're reusable for the next provision.
11. **Always**: re-uploads `terraform.tfstate` as the `tfstate` artifact, so the next run picks up
    from here.

## Why the SSH key is no longer generated per run

An earlier version of this pipeline generated a fresh ed25519 keypair on every `apply` and
re-imported it into AWS under a fixed name. That has a real bug: cloud-init only bakes the public
key into `~/.ssh/authorized_keys` at **first boot** — recreating the AWS-side key pair object later
doesn't retroactively update an already-running instance's authorized keys. So a second `apply`
against a still-running instance would produce a private key artifact that didn't actually match
the box. Using one stable, user-provided key pair (this version) avoids the whole problem: the same
key is valid for the instance's entire lifetime, across as many `apply`/`confirm` cycles as needed.
