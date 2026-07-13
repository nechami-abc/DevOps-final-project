# The `ci-cd.yml` pipeline (existing, one small change)

File: [`.github/workflows/ci-cd.yml`](../../.github/workflows/ci-cd.yml)

This is the "Build, Push and Deploy" pipeline already in this repo — it already matched the
zero-local-install goal (it builds and pushes images to `ghcr.io`, then deploys over SSH; no
Terraform or Ansible involved). **No changes needed for the Windows-only constraint.**

## The one change made today

The `deploy` job SSHes into `${{ secrets.EC2_HOST }}` using `${{ secrets.EC2_SSH_KEY }}`. Before
`create-infra.yml` has been run at least once, those secrets don't exist yet, and the SSH step would
fail with a confusing connection error. Added a guard step before it:

```yaml
- name: Check whether the lab instance has been created yet
  id: check_infra
  env:
    EC2_HOST: ${{ secrets.EC2_HOST }}
  run: echo "ready=$([ -n "$EC2_HOST" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"

- name: Update running deployment over SSH
  if: steps.check_infra.outputs.ready == 'true'
  uses: appleboy/ssh-action@v1.0.3
  ...
```

Note: the `secrets` context can't be referenced directly inside any `if:` condition (job- or
step-level) — GitHub Actions doesn't expose it there. The fix is to read the secret into a step
`env:` (which *is* allowed to use `secrets`), turn it into a step output, then gate the next step's
`if:` on that output instead.

With this, the deploy job now **skips cleanly** instead of failing when infra doesn't exist yet.

## When to run it, relative to `create-infra.yml`

`EC2_SSH_KEY` is set up front, once, before any of this (see [secrets-setup.md](secrets-setup.md)
step 2) — it no longer comes out of a `create-infra.yml` run. `EC2_HOST` is the only secret that
still gets produced along the way. Run order:

1. **First**, trigger `ci-cd.yml` manually (Actions tab → Run workflow) so an image exists in
   `ghcr.io` tagged with the current commit's short SHA. The deploy job in this run will skip
   (no `EC2_HOST` yet) — expected, ignore it.
2. **Then** run `create-infra.yml` twice — `stage: plan`, then `stage: confirm` — with
   `action: apply`. It deploys the image tag built in step 1 as part of provisioning (see
   [create-infra-pipeline.md](create-infra-pipeline.md)).
3. **Then** add the `EC2_HOST` secret from the `confirm` run's job summary
   ([secrets-setup.md](secrets-setup.md) step 4).
4. **From here on**, every push to `main` touching `app/backend/**` or `app/frontend/**` runs
   `ci-cd.yml` automatically: builds a new SHA-tagged image, pushes it, and SSHes in to
   `kubectl set image` the running deployment — no further manual steps.

If you push to `main` *before* running `create-infra.yml` at all, the pipeline still builds and
pushes the image successfully — only the deploy job skips, and it'll pick up that same image next
time you demo a fresh deploy after infra exists (as long as the tag matches what `create-infra.yml`
was told to deploy).

See [image-tags-and-visibility.md](image-tags-and-visibility.md) for how the SHA-based tag scheme
works, and the one-time step to make the pushed packages public (required before
`create-infra.yml`'s deploy step can pull them).
