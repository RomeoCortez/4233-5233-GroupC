# 4233-5233-GroupC — Nextcloud deployment CI/CD

Target repository: https://github.com/RomeoCortez/4233-5233-GroupC

Default branch: `main`. Workflow: `.github/workflows/nextcloud-ci.yml`.

After pushing, open https://github.com/RomeoCortez/4233-5233-GroupC/actions to inspect the run. Successful main-branch delivery publishes `ghcr.io/romeocortez/4233-5233-groupc/nextcloud:<commit-sha>`.

Open `nextcloud-cicd.code-workspace` in **Visual Studio Code**. This folder contains files to copy into the root of your `4233-5233-GroupC` repository. It does not need the large `nextcloud/server` source repository.

## What is included

- `.github/workflows/nextcloud-ci.yml`: GitHub Actions configuration.
- `compose.yaml`: Apache HTTPS edge, Nginx load balancer, two Nextcloud app nodes, PostgreSQL, Redis, one cron worker, and persistent Docker volumes.
- `docker/`: Dockerfile and small PHP configuration addition.
- `apache/` and `nginx/`: reverse proxy and load balancer configuration.
- `scripts/`: setup, ordered startup, and integration/backup checks.
- `docs/PIPELINE-EXPLANATION.md`: architecture mapping, job explanations, limitations, and future staging deployment requirements.
- `docs/TEST-RECORD.md`: fields to complete from your real Actions run.

## Run locally

Install Docker Desktop with Docker Compose v2, Python 3, and OpenSSL. On Windows, use WSL2 with Docker Desktop integration; the scripts require Bash. On macOS/Linux, use a Bash-capable terminal. Docker must be running. Allocate enough memory for two Nextcloud nodes and the database (start with 6–8 GB available to Docker).

In the VS Code terminal, from this project's root:

```bash
bash scripts/setup.sh
docker compose config -q
docker build -f docker/Dockerfile -t nextcloud-group-c:ci .
bash scripts/start.sh
bash scripts/test.sh
```

The setup generates disposable random passwords in `.env` and a seven-day local TLS certificate. Nextcloud is at `https://localhost:8443`; your browser will warn about the self-signed development certificate. Automated tests explicitly trust the generated certificate with `--cacert`, instead of turning off certificate validation. Do not use these certificates for a public server. Credentials stay on your machine and are ignored by Git.

To stop while keeping data:

```bash
docker compose down
```

To reset this disposable environment **and delete its database/files**:

```bash
docker compose down -v
```

Regenerate the certificate after seven days by removing the local `certs` folder and rerunning setup. If the fixed demonstration subnet overlaps an existing Docker network, choose another unused private /24 in `compose.yaml` and update the load balancer/edge addresses and `TRUSTED_PROXIES` together.

## Put the files in your GitHub repository

If you already cloned your repository, copy this folder's **contents** into its root, including `.github`, `.gitignore`, and `.gitattributes`. Do not put the whole project inside another folder: GitHub discovers workflows only at the repository root's `.github/workflows/` path. Merge existing files rather than overwriting unrelated work.

For a fresh clone in a separate directory:

```bash
git clone https://github.com/RomeoCortez/4233-5233-GroupC.git
cd 4233-5233-GroupC
```

Copy the extracted project contents here, then:

```bash
git status
git add .github .vscode .gitignore .gitattributes compose.yaml docker apache nginx scripts docs README.md nextcloud-cicd.code-workspace
git commit -m "Add Nextcloud deployment CI and delivery pipeline"
git push origin main
```

A push to `main` runs the checks and, if they pass, publishes the tested application image to GHCR. Pull requests run checks without publishing. Manual runs test and upload the artifact without publishing. No external server is deployed automatically.

Open the repository's **Actions** tab and select **Group C Nextcloud CI and delivery**. Save the actual run URL and results in `docs/TEST-RECORD.md`. If publishing is denied, inspect repository Actions permissions and package access; the publish job requests `packages: write`. Package visibility is governed by GitHub package settings.

## Verification status

The generated files have been checked for YAML/JSON structure, shell syntax, expected service references, and delivery dependencies. Docker and PHP were not installed in the generation environment, so container startup, PHP syntax inside the image, the integration tests, and registry publishing have **not** been executed here. The workflow performs those checks when you push. Do not report a successful pipeline until your actual GitHub Actions run completes.
