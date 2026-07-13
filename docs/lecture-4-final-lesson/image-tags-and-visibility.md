# Image tag management and package visibility

## How tags work today

`ci-cd.yml` never pushes a `:latest` tag — it only ever pushes the **short commit SHA**
(`${GITHUB_SHA::8}`, e.g. `a1b2c3d4`) for both `shoplist-backend` and `shoplist-frontend`. This is
deliberate: SHA tags are unambiguous (every build maps to exactly one commit) and let the deploy
step (`kubectl set image ...:${SHORT_SHA}`) always know precisely which image it's rolling out.

`create-infra.yml`'s `image_tag` input follows the same convention — leave it blank and it resolves
to the **current checked-out commit's** short SHA (`${GITHUB_SHA::8}`), matching exactly what
`ci-cd.yml` would have built for that commit. This means:

- **`ci-cd.yml` must run at least once for a given commit before `create-infra.yml` deploys it** —
  otherwise the tag `create-infra.yml` asks Ansible to deploy doesn't exist in `ghcr.io` yet, and
  the pod gets stuck in `ImagePullBackOff`. See the run order in [README.md](README.md).
- To deploy something other than the current commit (e.g. re-deploy an older, known-good build),
  pass that commit's short SHA explicitly as the `image_tag` input when running `create-infra.yml`.

## Making the ghcr.io packages public

**This is a one-time manual step, required before the first deploy — not something the pipelines
can safely automate.** GHCR (`ghcr.io`) packages are **private by default**, even in a public repo.
minikube on the lab instance pulls images anonymously (no registry credentials configured), so a
private package leaves every pod stuck in `ImagePullBackOff` with a permission-denied error buried in
`kubectl describe pod` — easy to lose a lot of the 45 minutes debugging this if it's missed.

The package is created the first time `ci-cd.yml` pushes an image (private by default) — so do this
right after that first manual `ci-cd.yml` run, before running `create-infra.yml`:

1. Go to your GitHub profile → **Packages** tab (or from the repo page, the **Packages** section in
   the right sidebar).
2. Click **shoplist-backend** → the gear icon (**Package settings**).
3. Scroll to **Danger Zone** → **Change visibility** → **Public** → type the package name to confirm.
4. Repeat steps 2–3 for **shoplist-frontend**.

Visibility persists once set — you don't need to repeat this for every new tag/push, only once per
package (i.e., twice total: backend and frontend).

### Why not automate this in the pipeline?

Changing a package's visibility requires the GitHub **Packages API**, which needs a personal access
token with package-admin scope — the default `GITHUB_TOKEN` used everywhere else in these pipelines
can push/pull images but cannot change visibility. Automating it would mean adding a PAT as another
repo secret purely for a one-time, one-click action — not worth the extra secret-management surface
for a single-session lab. If this course later runs more sessions or has many repeated repos, it'd
be worth revisiting with a `GH_PACKAGES_PAT` secret and a `gh api --method PATCH
/user/packages/container/{package}/visibility -f visibility=public` step in `ci-cd.yml`.
