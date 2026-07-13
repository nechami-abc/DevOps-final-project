# Setting up secrets (no local installs required)

Everything below happens in a browser — the AWS Console and the GitHub web UI. No AWS CLI, no
`ssh-keygen`, no local key files to manage day-to-day (you download one `.pem` once in step 2).

## Step 1 — AWS credentials

1. Sign in to the [AWS Console](https://console.aws.amazon.com/) with your free-tier account.
2. Go to **IAM → Users → your user → Security credentials** (or create a new IAM user first if you
   normally only use the root account — root access keys work for this lab but a scoped IAM user is
   better practice).
3. **Create access key** → choose "Command Line Interface (CLI)" as the use case → confirm → copy
   both the **Access key ID** and **Secret access key**. This is the only time the secret is shown —
   copy it now.
4. Make sure the user/role has permissions for EC2 (including key pairs and security groups) and
   IAM (to create the SSM role/instance profile in `terraform/main.tf`). For a training account,
   attaching `AdministratorAccess` is the simplest option — **this is a training-only
   simplification, not a production practice.**
5. In your GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**.
   Add two:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

## Step 2 — one-time SSH key pair (before the first `apply`)

`create-infra.yml` no longer generates a keypair per run — you create one AWS key pair once, and
it's reused for the life of the repo (this is also what fixes the earlier issue where a
per-run-generated key stopped matching an already-running instance).

1. AWS Console → **EC2 → Key Pairs → Create key pair**.
2. Name it something you'll remember — e.g. `shoplist-key` (this is the value you'll pass as the
   `key_name` input every time you run `create-infra.yml`).
3. Key type: **ED25519** (or RSA, either works). Format: **.pem**.
4. Click **Create key pair** — this downloads a `.pem` file. This is the only copy AWS keeps of the
   public half registered against that name; the private half only exists in the file you just
   downloaded.
5. Open the downloaded `.pem` file in a text editor (Notepad on Windows), copy its **entire
   contents** (including the `-----BEGIN`/`-----END` lines), and add it as a new repo secret named
   `EC2_SSH_KEY` (Settings → Secrets and variables → Actions → New repository secret). This is the
   same secret name `ci-cd.yml` already uses for its SSH deploy step, so both pipelines share one
   key.

## Step 3 — run the pipelines (see [README.md](README.md) for the full order)

Run `ci-cd.yml` once, make the packages public, then run `create-infra.yml` twice — once with
`stage: plan` (review the job summary), once with `stage: confirm` and the **same** `action` and
`key_name` values (the pipeline checks these match and refuses to apply a stale/mismatched plan) —
see [create-infra-pipeline.md](create-infra-pipeline.md).

When the `confirm` run finishes (action: apply), its job summary prints the one remaining secret to
add:

```
### ShopList lab instance is up

App: http://<public-ip>:30080

Next step — add 1 repo secret ...
EC2_HOST = <public-ip>
```

## Step 4 — add that secret

Copy the IP address straight from the job summary into a new repo secret named `EC2_HOST`. Once
it's set, push to `main` (or manually re-run `ci-cd.yml`) and the deploy step will run instead of
skipping.

## Step 5 — at the end of the session

Run `create-infra.yml` again with `action: destroy` (same plan-then-confirm flow) to tear down the
EC2 instance and avoid ongoing AWS charges. `EC2_SSH_KEY` and the AWS key pair itself don't need to
be removed — they're reusable for the next time you provision the lab. You can leave `EC2_HOST` in
place too (the next `apply` will just print a new value to overwrite it with), or delete it if
you're done with the lab for good.
