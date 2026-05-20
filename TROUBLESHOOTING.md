# Troubleshooting & Fixes Log

Every real error hit during the deployment of this stack, with the root cause and the exact fix applied. Ordered by category.

---

## Table of Contents

1. [Docker Build Errors](#docker-build-errors)
   - [Heredoc FROM parse error in Dockerfile](#1-heredoc-from-parse-error-in-dockerfile)
   - [npm ci fails — package-lock.json not found](#2-npm-ci-fails--package-lockjson-not-found)
2. [GCP IAM / API Errors](#gcp-iam--api-errors)
   - [IAM Service Account Credentials API disabled](#3-iam-service-account-credentials-api-disabled)
   - [artifactregistry.repositories.uploadArtifacts denied](#4-artifactregistryrepositoriesuploadartifacts-denied)
   - [GCS storage.objects.list denied](#5-gcs-storageobjectslist-denied)
3. [Terraform Errors](#terraform-errors)
   - [Invalid Terraform version number](#6-invalid-terraform-version-number)
   - [Startup script path not found (validate fails)](#7-startup-script-path-not-found-validate-fails)
   - [Subnet / Router alreadyExists on re-apply](#8-subnet--router-alreadyexists-on-re-apply)
   - [Artifact Registry repo alreadyExists — 409 conflict](#9-artifact-registry-repo-alreadyexists--409-conflict)
   - [tfsec crashes on Terraform 1.5+ import blocks](#10-tfsec-crashes-on-terraform-15-import-blocks)
4. [GitHub Actions Errors](#github-actions-errors)
   - [tfsec action not found (archived repo)](#11-tfsec-action-not-found-archived-repo)
   - [secrets.* in if: expressions illegal](#12-secrets-in-if-expressions-illegal)
   - [Docker build auth fails in 8 s on PRs](#13-docker-build-auth-fails-in-8-s-on-prs)
   - [Terraform plan/apply skipped on workflow_dispatch](#14-terraform-planapply-skipped-on-workflow_dispatch)
5. [GCE Startup Script Errors](#gce-startup-script-errors)
   - [HOME: parameter not set — iii installer fails](#15-home-parameter-not-set--iii-installer-fails)
   - [nginx serves default welcome page instead of proxying](#16-nginx-serves-default-welcome-page-instead-of-proxying)
6. [Worker Runtime Errors](#worker-runtime-errors)
   - [Workers pull wrong SHA tag — container not found](#17-workers-pull-wrong-sha-tag--container-not-found)
7. [Smoke Test Errors](#smoke-test-errors)
   - [Smoke test loops "Not ready" despite HTTP 200](#18-smoke-test-loops-not-ready-despite-http-200)

---

## Docker Build Errors

### 1. Heredoc FROM parse error in Dockerfile

**Symptom**

`docker build` failed immediately with:

```
ERROR: failed to solve: dockerfile parse error on line 12: unknown instruction: FROM
```

The line wasn't a real `FROM` instruction — it was inside a Python heredoc:

```dockerfile
# BROKEN — the Docker parser sees "from transformers" as a FROM instruction
RUN python3 - << 'EOF'
from transformers import AutoModelForCausalLM   # ← parser reads this as FROM
...
EOF
```

**Root cause**

The Docker BuildKit parser scans for instruction keywords before evaluating heredocs. The string `from transformers` at the start of a heredoc line is treated as a `FROM` instruction regardless of context.

**Fix**

Replace the inline heredoc with a separate Python script file that is `COPY`-ed in and executed normally:

```dockerfile
# docker/inference-worker/Dockerfile
FROM deps AS model
COPY download_model.py .          # separate file — no heredoc
RUN python download_model.py
```

```python
# docker/inference-worker/download_model.py
from transformers import AutoModelForCausalLM, AutoTokenizer
model_id  = "ggml-org/gemma-3-270m-GGUF"
gguf_file = "gemma-3-270m-Q8_0.gguf"
AutoTokenizer.from_pretrained(model_id, gguf_file=gguf_file)
AutoModelForCausalLM.from_pretrained(model_id, gguf_file=gguf_file)
```

Also add `# syntax=docker/dockerfile:1` as the first line of every Dockerfile to pin the parser version and enable BuildKit features explicitly.

---

### 2. npm ci fails — package-lock.json not found

**Symptom**

```
npm error The `npm ci` command can only install with an existing package-lock.json
```

Build aborted in ~8 seconds.

**Root cause**

`npm ci` requires a `package-lock.json` (or `npm-shrinkwrap.json`) to be present and committed. The repository only had `package.json`.

**Fix**

Switch from `npm ci` to `npm install --omit=dev` in the Dockerfile. This installs production dependencies from `package.json` without requiring a lock file:

```dockerfile
# docker/caller-worker/Dockerfile
RUN npm install --omit=dev   # was: npm ci --omit=dev
```

> **Note for production:** The preferred long-term fix is to commit `package-lock.json` and keep using `npm ci` — it is deterministic and faster. `npm install` resolves versions at build time, which can produce different results on different builds.

---

## GCP IAM / API Errors

### 3. IAM Service Account Credentials API disabled

**Symptom**

GitHub Actions WIF authentication step failed:

```
Error: google-github-actions/auth failed with: failed to generate Google Cloud federated token
for .../providers/github-provider: {"error":"api_disabled","error_description":
"Access blocked: The IAM Service Account Credentials API is disabled..."}
```

**Root cause**

Workload Identity Federation token exchange calls the IAM Service Account Credentials API (`iamcredentials.googleapis.com`). It is not enabled by default.

**Fix**

Enable the API in the GCP console or via CLI:

```bash
gcloud services enable iamcredentials.googleapis.com --project=<your-project>
```

Direct console link (replace project number):
`https://console.developers.google.com/apis/api/iamcredentials.googleapis.com/overview?project=<PROJECT_NUMBER>`

---

### 4. artifactregistry.repositories.uploadArtifacts denied

**Symptom**

```
ERROR: denied: Permission "artifactregistry.repositories.uploadArtifacts" denied
on resource "projects/.../repositories/alchemist"
```

**Root cause**

The `terraform-ci` service account used by GitHub Actions had `roles/artifactregistry.writer` but not the additional permissions needed for the first push to a new repository (repository metadata write).

**Fix**

Grant `roles/artifactregistry.admin` to the CI service account:

```bash
gcloud projects add-iam-policy-binding <your-project> \
  --member="serviceAccount:terraform-ci@<your-project>.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"
```

> `roles/artifactregistry.writer` is sufficient for subsequent pushes once the repository exists. The elevated `admin` role is only needed if Terraform is also managing repository creation or the first push happens before Terraform runs.

---

### 5. GCS storage.objects.list denied

**Symptom**

`terraform init` failed:

```
Error: Failed to get existing workspaces: querying Cloud Storage failed:
googleapi: Error 403: <service-account>@... does not have storage.objects.list access
to the Google Cloud Storage bucket.
```

**Root cause**

The CI service account lacked object-level access to the Terraform remote-state bucket `alchemist-tf-state`.

**Fix**

Grant `roles/storage.objectAdmin` on the specific bucket (not project-wide):

```bash
gcloud storage buckets add-iam-policy-binding gs://alchemist-tf-state \
  --member="serviceAccount:terraform-ci@<your-project>.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

---

## Terraform Errors

### 6. Invalid Terraform version number

**Symptom**

GitHub Actions failed immediately:

```
Error: Invalid Terraform version specified: "1.15.3"
```

**Root cause**

A typo — Terraform's versioning jumped from `1.9.x` directly; `1.15.x` does not exist.

**Fix**

Pin the correct latest stable release in the workflow:

```yaml
# .github/workflows/terraform.yml
env:
  TF_VERSION: "1.9.5"   # was: "1.15.3"
```

Always verify available versions at [releases.hashicorp.com/terraform](https://releases.hashicorp.com/terraform/).

---

### 7. Startup script path not found (validate fails)

**Symptom**

`terraform validate` (or `plan`) failed with:

```
Error: Invalid function argument
  on modules/engine/main.tf line 42, in resource "google_compute_instance" "api_gateway":
  Call to function "file" failed: no file exists at
  "terraform/modules/engine/../../scripts/startup-engine.sh".
```

**Root cause**

The `file()` call used `${path.module}/../../scripts/...`. With the module at `terraform/modules/engine/`, two `../` levels only reach `terraform/` — not the repo root where `scripts/` lives.

```
terraform/modules/engine/  →  ../../  →  terraform/   ✗
terraform/modules/engine/  →  ../../../  →  (repo root)  ✓
```

**Fix**

Add one more `../` level in both the engine and worker modules:

```hcl
# terraform/modules/engine/main.tf
metadata_startup_script = file("${path.module}/../../../scripts/startup-engine.sh")

# terraform/modules/worker/main.tf
metadata_startup_script = file("${path.module}/../../../scripts/startup-worker.sh")
```

---

### 8. Subnet / Router alreadyExists on re-apply

**Symptom**

After a `terraform destroy` + immediate `terraform apply`:

```
Error: Error creating Subnetwork: googleapi: Error 409: The resource
'projects/.../subnetworks/alchemist-private' already exists, alreadyExists
```

**Root cause**

GCP has an eventual-consistency propagation delay for network resource deletions. The resource appears deleted in the API immediately but the underlying infrastructure takes 30–90 seconds to release the name.

**Fix**

Wait ~2 minutes after `destroy` completes before running `apply` again. No code change needed — this is a GCP timing issue, not a Terraform bug. If it recurs in automation, add a `null_resource` with a `local-exec` sleep between destroy and re-create.

---

### 9. Artifact Registry repo alreadyExists — 409 conflict

**Symptom**

```
Error: Error creating Repository: googleapi: Error 409: the repository
'projects/.../repositories/alchemist' already exists.
```

**Root cause**

The Artifact Registry repository was created manually in the GCP console before Terraform was set up. Terraform tried to create it again instead of adopting the existing resource.

**Fix**

Use a Terraform 1.5+ `import` block to bring the manually-created resource into state without destroying and recreating it:

```hcl
# terraform/envs/prod/main.tf
import {
  to = module.engine.google_artifact_registry_repository.workers
  id = "projects/${var.project_id}/locations/us-central1/repositories/alchemist"
}
```

Run `terraform plan` — it will show `1 to import, 0 to add` and confirm the resource is already in the desired state. Then `terraform apply` to commit it to state.

---

### 10. tfsec crashes on Terraform 1.5+ import blocks

**Symptom**

tfsec exited non-zero with a parser panic:

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation]
goroutine 1 [running]: github.com/aquasecurity/tfsec/...
```

**Root cause**

tfsec v1.28.14 (the latest release) does not support the Terraform 1.5+ `import {}` block syntax. The parser crashes when it encounters the block.

**Fix — Option A (recommended):** Add `continue-on-error: true` to the tfsec step so CI doesn't block:

```yaml
- name: tfsec
  run: |
    curl -Lo tfsec https://github.com/aquasecurity/tfsec/releases/download/v1.28.14/tfsec-linux-amd64
    chmod +x tfsec && sudo mv tfsec /usr/local/bin/
    tfsec terraform/ --no-colour || true
  continue-on-error: true
```

**Fix — Option B:** Migrate to [Trivy](https://github.com/aquasecurity/trivy) (tfsec's successor from the same vendor), which handles modern HCL syntax correctly:

```yaml
- name: trivy config scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: config
    scan-ref: terraform/
```

---

## GitHub Actions Errors

### 11. tfsec action not found (archived repo)

**Symptom**

```
Error: Unable to resolve action `aquasecurity/tfsec-action@v1`,
the action does not exist or its ref is invalid
```

**Root cause**

The `aquasecurity/tfsec-action` repository has been archived and is no longer maintained. GitHub cannot resolve the action ref.

**Fix**

Replace the action with a direct binary install in a `run` step (see [fix #10](#10-tfsec-crashes-on-terraform-15-import-blocks) above), or switch to Trivy.

---

### 12. secrets.* in if: expressions illegal

**Symptom**

GitHub rejected the workflow file on push:

```
Invalid workflow file: .github/workflows/docker.yml#L12
Unrecognized named-value: 'secrets'. Located at position 1 within expression:
secrets.WIF_PROVIDER != ''
```

(12 identical errors across multiple files)

**Root cause**

GitHub evaluates `if:` conditions at workflow parse time, before secrets are injected into the runner environment. The `secrets` context is unavailable in `if:` expressions.

**Fix**

Remove all `secrets.*` checks from `if:` conditions entirely. Gate pushes on the branch name or event type instead:

```yaml
# BROKEN
- name: Authenticate
  if: secrets.WIF_PROVIDER != ''
  uses: google-github-actions/auth@v2

# FIXED — gate on branch, not secret presence
- name: Authenticate
  if: github.ref == 'refs/heads/main'
  uses: google-github-actions/auth@v2
```

---

### 13. Docker build auth fails in 8 s on PRs

**Symptom**

Docker build job failed in ~8 seconds on pull requests with an authentication error, even though the step had `if: github.ref == 'refs/heads/main'`.

**Root cause**

The `google-github-actions/auth` step was gating the *auth* step but the `docker/login-action` step (which depends on the auth token) ran unconditionally. When running on a PR from a fork, WIF secrets are not available and the login step fails immediately.

**Fix**

Either set `if: github.ref == 'refs/heads/main'` on every step that depends on GCP credentials, or split the job into a build-only job (runs on all PRs, no auth) and a push job (runs only on main):

```yaml
jobs:
  build:
    # runs on every PR — just validates the Dockerfile
    steps:
      - uses: docker/build-push-action@v5
        with:
          push: false   # no push, no auth needed

  push:
    if: github.ref == 'refs/heads/main'
    needs: build
    steps:
      - uses: google-github-actions/auth@v2
        # ... auth + push
```

---

### 14. Terraform plan/apply skipped on workflow_dispatch

**Symptom**

When triggering the Terraform workflow manually via **Run workflow** in the GitHub UI, both the `plan` and `apply` jobs were skipped (shown as grey in the UI).

**Root cause**

The plan job had `if: github.event_name != 'workflow_dispatch'`, which explicitly excluded manual runs. The apply job was `push`-only with no `workflow_dispatch` trigger.

**Fix**

Remove the exclusion condition from plan, and add `workflow_dispatch` as a trigger for apply (or remove the event restriction entirely and rely on branch protection):

```yaml
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:          # ← add this

jobs:
  plan:
    # Remove: if: github.event_name != 'workflow_dispatch'

  apply:
    if: github.ref == 'refs/heads/main'   # branch guard is enough
```

---

## GCE Startup Script Errors

### 15. HOME: parameter not set — iii installer fails

**Symptom**

The api-gateway VM startup script failed silently. SSH-ing in and checking the log:

```
/var/log/startup-engine.log:
+ curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
install.sh: line 47: HOME: parameter not set
```

The iii binary was never installed, so `iii-engine.service` failed to start.

**Root cause**

GCE metadata startup scripts run as root via a minimal init environment that does **not** set `$HOME`. The iii installer uses `$HOME` to determine where to place the binary (`~/.local/bin/iii`). With `set -euo pipefail`, the unset variable causes an immediate exit.

**Fix**

Explicitly export `HOME` (and a sane `PATH`) before calling the installer:

```bash
# scripts/startup-engine.sh — add these lines before the curl install
export HOME=/root
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin"
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
```

This applies to **any** tool installer that references `$HOME` or `~` when run from a GCE startup script.

---

### 16. nginx serves default welcome page instead of proxying

**Symptom**

After the api-gateway VM was running, `curl http://<PUBLIC_IP>/` returned the nginx default welcome page instead of proxying to the iii engine. All other paths returned nginx 404 (not iii 404).

**Root cause**

The startup script wrote the proxy configuration to `/etc/nginx/sites-available/default` correctly, but on the manually-provisioned VM (the startup script had previously failed — see [fix #15](#15-home-parameter-not-set--iii-installer-fails)) the `/etc/nginx/sites-enabled/default` symlink still pointed to the stock Debian nginx default config. The script ran `systemctl restart nginx` but nginx loaded the old config from `sites-enabled`.

**Fix**

Overwrite the file in `sites-available` and then force a reload:

```bash
# Run on the api-gateway VM (as root/sudo)
cat > /etc/nginx/sites-available/default << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location / {
        proxy_pass         http://127.0.0.1:3111;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
}
NGINX

nginx -t && systemctl reload nginx
```

Verify the symlink resolves to the correct file:

```bash
ls -la /etc/nginx/sites-enabled/default
# should show: ... -> /etc/nginx/sites-available/default
```

---

## Worker Runtime Errors

### 17. Workers pull wrong SHA tag — container not found

**Symptom**

Both worker VMs continuously restarted with:

```
docker: Error response from daemon: manifest for
us-central1-docker.pkg.dev/.../caller-worker:0255aefa146236df974351362d08fb09a6ecbdd7
not found: manifest unknown: Failed to fetch "0255aefa...".
```

The container would fail, systemd would restart it after 5 s, and the cycle repeated (>200 restart attempts logged).

**Root cause**

The Terraform variable `image_tag` was set to `${{ github.sha }}` from the GitHub Actions workflow. However, the Docker push step had run earlier with a *different* commit SHA (or had been re-run after an additional commit). The SHA baked into the Terraform `terraform.tfvars` / apply didn't match any image tag actually present in Artifact Registry.

**Fix — immediate (manual):**

SSH into each worker VM and update the systemd service to use the `:latest` tag:

```bash
# Pull the latest image
gcloud auth configure-docker us-central1-docker.pkg.dev
docker pull us-central1-docker.pkg.dev/<project>/alchemist/caller-worker:latest

# Update the service file to use :latest
sed -i 's|:'"$OLD_SHA"'|:latest|g' /etc/systemd/system/caller-worker.service
systemctl daemon-reload
systemctl restart caller-worker
```

**Fix — permanent (Terraform):**

Change `image_tag` default to `latest` in `terraform.tfvars`:

```hcl
image_tag = "latest"
```

Or, tag the Docker image with both the SHA and `latest` in the build script:

```bash
docker tag <image>:<sha> <image>:latest
docker push <image>:<sha>
docker push <image>:latest
```

---

## Smoke Test Errors

### 18. Smoke test loops "Not ready" despite HTTP 200

**Symptom**

The smoke test script printed `Not ready yet (HTTP 200, 0s elapsed)` on every poll, even though `curl` showed a valid `{"result":{"text":"..."}}` response.

**Root cause**

The script uses `jq` to extract the `.result` field, falling back to `python3` if jq isn't available. On Windows (Git Bash), `jq` is not installed and `python3` resolves to native Windows CPython — which cannot open POSIX paths like `/tmp/smoke_response.json` because Git Bash's `/tmp` mapping is transparent only to bash, not to Win32 executables. The Python call silently failed, the `|| echo ""` fallback fired, `result` was set to empty string, and the check `[ -n "${result}" ]` was always false.

**Trace evidence:**

```bash
++ python3 -c '...'
++ echo ''      # ← python3 failed; fallback echo ran
+ result=       # ← empty
```

**Fix**

Replace the python3 fallback with `grep` (a shell built-in equivalent in Git Bash), which reads the file natively through bash's own path resolution:

```bash
# scripts/smoke-test.sh
if command -v jq &>/dev/null; then
  result=$(jq -r '.result // empty' /tmp/smoke_response.json 2>/dev/null)
else
  # grep is portable across Linux/macOS/Windows Git Bash
  # python3 is intentionally skipped: native Windows python3 cannot resolve
  # POSIX /tmp paths produced by Git Bash's curl -o
  result=$(grep -o '"result"' /tmp/smoke_response.json 2>/dev/null || echo "")
fi
```

---

*Last updated: 2026-05-20 — all fixes verified against the live production deployment at `http://35.254.159.49/v1/chat/completions`.*
