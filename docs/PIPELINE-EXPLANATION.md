# Pipeline explanation and architecture review

## Scope and diagram interpretation

Your first diagram is a proposed deployment architecture. The second image is a logical view of frontend clients, security, core services, storage, and integrations; it does not prescribe a particular container topology. This project targets the first diagram's main request path, using the logical diagram to select behavior tests.

The first diagram labels the deployment Nextcloud AIO while adding multiple app servers. This project deliberately uses the official Nextcloud Docker application image in a custom Compose deployment to demonstrate two nodes sharing one instance. It does not run the AIO mastercontainer or modify its orchestration. AIO's documented “multiple instances” feature describes separate instances, not proof that its standard mastercontainer supports the shared-instance topology drawn by the group. Label the diagram's scalable section “proposed custom deployment” until that orchestration is separately designed and verified.

Persistent storage in this implementation consists of separate PostgreSQL storage and one shared Nextcloud application/config/data volume. Redis is transient cache/session/lock storage and can be recreated; it is not a user-file backup. For a multi-host deployment, a local Docker volume cannot provide shared storage across hosts. Plan a supported shared filesystem or object storage plus shared configuration, and test that design.

## Build, test, and eventually deploy

| Component/architectural requirement | What this pipeline does | Remaining deployment work |
| --- | --- | --- |
| Nextcloud app servers | Builds official Nextcloud Apache image plus custom PHP config; runs two containers from that image | Lock a reviewed patch/digest and plan one-at-a-time updates with downtime/maintenance controls |
| Apache reverse proxy / HTTPS | Checks Apache config; tests status/auth/files through a TLS endpoint | Real domain, trusted certificate renewal, production headers/timeouts |
| Load balancer | Checks Nginx config; requires two distinct upstream addresses in repeated responses | Failure testing, health-based routing and resilient ingress |
| PostgreSQL | Health-checks service; app installation, authentication and files exercise database integration | Secure credentials, persistence, monitoring and database availability planning |
| Redis | Checks reachability, Redis file-locking config and PHP session-handler config on both nodes | Actual browser session continuity, concurrent locking tests, failure behavior |
| Persistent storage | Uploads explicitly through app1 and downloads explicitly through app2; repeats download after restarting app2 | Multi-host storage design, larger uploads, concurrent operations and capacity checks |
| Authentication / permissions | Valid login, rejected anonymous file request and denied access by a separate user | SSO, sharing-policy matrix, CSRF/CSP and encryption-specific tests |
| Background jobs | Starts one cron worker; manually executes one cron run | Verify scheduled cadence and workload-specific background jobs |
| Backups | Dumps/restores DB into separate temporary DB and checks admin user; archives/extracts one user file and compares bytes | Consistent full-instance backup and restore including config, all files and apps; off-host retention |
| Notify Push | Not started | Add compatible service/app and real-time sync checks |
| Office, document server, Talk, recording, search, Imaginary, ClamAV, whiteboard | Not started | Add only enabled services with matching health/integration checks |
| AIO mastercontainer / AIO backup / community integrations | Not started | Separate AIO deployment workflow if your team selects that deployment model |
| Desktop/mobile clients | Server-facing DAV behavior checked; client programs not built | Real client end-to-end compatibility tests |

This is deployment integration testing. It does not run the upstream PHP or JavaScript unit suites or rebuild Nextcloud's frontend from source, because the app is supplied by its Docker image. If the team begins modifying `nextcloud/server`, add source checkout/submodules, its required PHP/Node versions, upstream unit tests, and frontend build steps as another pipeline.

## Job 1: build-test

Runs on GitHub's standard Ubuntu runner, with a 30-minute limit.

1. **Checkout:** loads your deployment files.
2. **Setup:** generates random disposable database/admin passwords and a local TLS certificate. No staging credentials are needed for CI.
3. **Validate:** Docker Compose checks references/substitution, Bash checks scripts, PHP checks the custom config, and the Apache/Nginx images check their own config. Temporary DNS aliases allow proxy syntax checking before app containers exist.
4. **Build:** creates `nextcloud-group-c:ci` from `nextcloud:32-apache`. This is a version-family tag, not an immutable release pin; other service tags are also floating. After the initial successful course run, review compatible patch versions and resolve/pin digests for reproducible releases.
5. **Ordered startup:** starts PostgreSQL/Redis and app1, polls installation state with a timeout, then starts app2, the one cron worker and proxies. Only the first node performs initial installation. `occ` commands run as `www-data`.
6. **Test:** checks the architecture relationships listed in the table. The cross-node DAV check forces specific nodes, so a successful upload/download cannot accidentally prove only one server works. Restart testing covers persistence, not uninterrupted failover.
7. **Save image:** exports the exact image that passed the checks; runtime volumes and temporary passwords are not part of the image export.
8. **Upload artifact:** provides the compressed image for download for three days.
9. **Diagnostics/cleanup:** on failure, prints recent logs; always removes the disposable containers and volumes. Test users/files/passwords are disposable, and logs should be treated as CI evidence rather than public production telemetry.

Polling waits have a finite limit; failures block artifact delivery and publishing. The workflow timeout also bounds the total run.

## Job 2: publish

Runs only after build-test succeeds on a push to `main`. Downloads and loads the tested image instead of rebuilding it. Uses GitHub's generated token with package-write permission, lowercases the image repository name, and pushes `ghcr.io/romeocortez/4233-5233-groupc/nextcloud:<commit-sha>`.

This is continuous delivery to a registry. It is not deployment to a live server. Pull requests and manually dispatched runs cannot publish. The commit tag identifies the source run, but administrators can still overwrite registry tags; use the published image digest when deploying.

## Eventual staging deployment

An actual server/domain, deployment model and credentials were not supplied, so this package has no pretend SSH deployment with guessed hosts or paths. To extend it:

1. Decide whether staging uses this custom multi-node deployment or supported AIO orchestration. An arbitrary custom image cannot simply replace the AIO-managed Nextcloud container.
2. Provision staging storage, database, Redis and ingress; configure a real certificate, cron, monitoring and only the optional services you actually use.
3. Create a GitHub `staging` environment, store its actual access secrets, and restrict deployment concurrency. Configure environment review rules if your group wants them.
4. Add a deploy job after publish. Select the published image by digest; back up data/database/config and confirm restore procedures before an update.
5. Perform migrations once under maintenance/update coordination before enabling other nodes. Ordered first installation in CI is not a complete safe production rolling-upgrade strategy; nodes sharing application files can both be affected by an update.
6. Run status, authenticated DAV, permissions and enabled-integration checks through the real HTTPS URL. Define recovery for image/config AND database changes; rolling back an image alone may not undo schema migrations.

The single database and single proxy in the diagram remain potential single points of failure. Two app nodes do not by themselves establish a highly available system.

## Sources checked during generation

- Official Nextcloud Docker configuration: https://github.com/nextcloud/docker/blob/master/README.md
- Official AIO capabilities: https://github.com/nextcloud/all-in-one/blob/main/readme.md
- AIO separate-instance guidance: https://github.com/nextcloud/all-in-one/blob/main/multiple-instances.md
- GitHub image publishing: https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images

## AI interaction record

AI tool: ChatGPT/Codex.

User prompt: “The diagram above is our modle 1 architecture diagram for Nextcloud the second image/png is their own diagram. Identify what our pipeline needs to build and test, and eventually deploy. Generate the pipline configuration and make it able to export into visual studio so i can later push into github. Explain the configuration if that needs to be in the comments on a separate file.”

Generated: workflow, Dockerfile/PHP config, Compose topology, Apache/Nginx configs, setup/start/test scripts, VS Code workspace/tasks, documentation and a test-record template.

AI implementation choices: custom deployment rather than claiming AIO-managed scaling; two representative app nodes; ordered installation; explicit cross-node file test; TLS certificate verification; exact tested-image reuse for publishing; defer server deployment until actual infrastructure is provided.

Human decisions/corrections: record your team's actual review here after reviewing/running the files. Do not describe these AI implementation choices as changes the team already made.
