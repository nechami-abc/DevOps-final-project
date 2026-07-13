# Student Walkthrough — running today's pipelines

No installs, no terminal commands on your own laptop. Everything happens by clicking buttons on
GitHub's website. This page explains, in order, exactly what to click and **why** each step exists.

## First, some vocabulary

- **Pipeline / workflow**: a script that runs on a computer GitHub lends you for a few minutes (not
  your laptop), triggered by you clicking a button.
- **Actions tab**: the tab at the top of your GitHub repo page where you go to run and watch
  pipelines.
- **Secret**: a password-like value your repo remembers so pipelines can use it, without ever
  showing it on screen again once saved. Settings → Secrets and variables → Actions.
- **Terraform**: the tool that actually creates the AWS server. A **plan** is Terraform showing you
  what it *would* do, without doing it yet — like a receipt preview before you pay.
- **Ansible**: the tool that, once the server exists, installs software on it (Kubernetes) and puts
  the ShopList app on it.

## One-time setup (do this once, before anything else)

### 1. AWS credentials

1. Log into the [AWS Console](https://console.aws.amazon.com/).
2. IAM → Users → your user → Security credentials → **Create access key** → choose "CLI" → copy the
   **Access key ID** and **Secret access key** (shown only once — copy both now).
3. In your GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**.
   Add two secrets: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

*Why: the pipelines need to prove to AWS who's asking before AWS lets them create a server.*

### 2. One SSH key, created once

1. AWS Console → EC2 → **Key Pairs → Create key pair**.
2. Name it `shoplist-key`. Type: ED25519. Format: .pem. Click Create — a file downloads.
3. Open that downloaded file in Notepad, select all, copy.
4. GitHub repo → Settings → Secrets and variables → Actions → New repository secret named
   `EC2_SSH_KEY` → paste the whole file contents in.

*Why: later, a pipeline needs to log into the AWS server to install software on it — same idea as an
SSH key you'd use in a terminal, except a pipeline uses it instead of you typing a password.*

## Step 3 — build the app images

Actions tab → **"Build, Push and Deploy"** (this is `ci-cd.yml`) → **Run workflow** button → Run.

**What this does:** packages the ShopList frontend and backend into container images (like sealed,
ready-to-run boxes containing the app) and uploads them to GitHub's container registry
(`ghcr.io`) — think of it as GitHub's version of an app store, just for these images.

Watch it run. Three of its four jobs (`build-backend`, `build-frontend`, `verify-registry`) turn
green. The fourth (`deploy`) turns **grey and gets skipped** — that's expected, there's no server to
deploy to yet.

## Step 4 — make the images public (one click, twice)

1. Your GitHub profile → **Packages** tab.
2. Click **shoplist-backend** → gear icon (Package settings) → scroll to **Danger Zone** → **Change
   visibility → Public** → type the name to confirm.
3. Repeat for **shoplist-frontend**.

**Why:** by default these images are private. The AWS server will later try to download them
anonymously (it doesn't have a login of its own) — if they're still private, that download fails and
the app never starts.

## Step 5 — preview what will be created (`plan`)

Actions tab → **"Create/Destroy Lab Infra"** (this is `create-infra.yml`) → **Run workflow**, and
fill in:

- **action**: `apply`
- **stage**: `plan`
- **key_name**: `shoplist-key`
- **image_tag**: leave blank

Run it. When it finishes, click into the run and read its **Summary** — it prints out exactly what
Terraform *would* create (one EC2 server, a security group, an IAM role). Nothing has actually been
created in AWS yet — this step is safe to run as many times as you like.

## Step 6 — actually create it (`confirm`)

Once the plan looks right, run the **same workflow again**, with the **same** `action` and
`key_name`, but this time:

- **stage**: `confirm`

**What this does, over about 5–8 minutes:**
1. Creates the real EC2 server in AWS.
2. Waits for it to be reachable.
3. Installs Docker and Kubernetes (minikube) on it.
4. Deploys the ShopList app onto it, using the image built in Step 3.

When it's done, its **Summary** prints a public IP address and tells you to add one more secret.

## Step 7 — add the last secret

Copy the IP address from the Summary. GitHub repo → Settings → Secrets and variables → Actions →
New repository secret named `EC2_HOST` → paste the IP in.

**Why:** the *next* pipeline (`ci-cd.yml`, from step 3) needs to know where to send future updates —
this secret is how it finds the server.

## Step 8 — see it live

Open `http://<the-ip-address>:30080` in your browser. That's the ShopList app, running on a real AWS
server you just created entirely by clicking buttons.

## Step 9 — make a change and watch it redeploy

Edit something in `app/backend/` or `app/frontend/` and push to `main` (or just re-run `ci-cd.yml`
manually). This time the `deploy` job **won't** skip — it builds a new image and updates the running
app over SSH automatically.

## Step 10 — clean up at the end

Run `create-infra.yml` again, same two-step dance: first `stage: plan` with `action: destroy` to see
what will be removed, then `stage: confirm` with `action: destroy` to actually tear it down.

**Why this matters:** AWS charges for a running server by the hour. Destroying it when you're done
avoids a surprise bill. Your `EC2_SSH_KEY` secret and AWS key pair are safe to leave in place — you
can spin the whole thing back up later without redoing the one-time setup.
