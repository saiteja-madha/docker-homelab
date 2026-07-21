# Backup and recovery

Dokploy's control-plane backup is necessary but not sufficient. A recoverable
system needs separate coverage for the platform, application databases, and
persistent volumes.

## Backup matrix

| Asset                                       | System of record                    | Backup mechanism                      | Important limitation                                |
| ------------------------------------------- | ----------------------------------- | ------------------------------------- | --------------------------------------------------- |
| Host provisioning                           | This Git repository                 | Git remote                            | Does not contain secrets or app state               |
| Dokploy configuration and Compose state     | Dokploy database and `/etc/dokploy` | Web Server backup to S3               | Restore with a compatible Dokploy version           |
| Managed PostgreSQL/MySQL/MariaDB/Mongo data | Application database                | Per-database backup to S3             | Configure and test each database separately         |
| Docker named volumes                        | Docker host                         | Dokploy Volume Backups to S3          | Only selected named volumes are covered             |
| Bind mounts / Dokploy `../files`            | Server filesystem                   | Separate file backup if used          | Not covered by Dokploy Volume Backups               |
| Application source                          | Application GitHub repository       | Git remote and repository protections | Uncommitted runtime changes are not source          |
| Recovery credentials                        | Password manager/off-server vault   | Vault export or provider recovery     | Never rely on the failed VPS or its S3 backup alone |

Relevant upstream documentation:

- <https://docs.dokploy.com/docs/core/backups>
- <https://docs.dokploy.com/docs/core/databases/backups>
- <https://docs.dokploy.com/docs/core/volume-backups>
- <https://docs.dokploy.com/docs/core/docker-compose>

## Required backup configuration

1. Configure a least-privilege S3 destination for backups.
2. Schedule a Web Server backup for the Dokploy control plane.
3. Configure every stateful database in its own Backup tab.
4. Configure every required named volume in Volume Backups.
5. Identify bind mounts and provide a separate backup or migrate them to named
   volumes where Dokploy-managed restoration is required.
6. Set retention in both Dokploy and the bucket lifecycle policy.
7. Enable bucket encryption and, where appropriate, versioning or object lock.
8. Alert on failed jobs and periodically confirm new objects exist.
9. Perform restores; a successful upload is not proof of recoverability.

Store these outside Dokploy and outside the VPS:

- S3 endpoint, bucket, region, access key, and secret key
- Cloudflare account recovery and tunnel recreation instructions
- Tailscale account recovery
- GitHub organization/repository recovery and webhook secret rotation procedure
- DNS registrar recovery
- last known Dokploy version and this repository's commit hash
- inventory of databases, volumes, bind mounts, and expected domains

## Bare-metal restore runbook

### 1. Contain and record

If compromise is possible, isolate the old server and rotate credentials rather
than immediately reconnecting it. Record the failure time, last successful
backup timestamps, Dokploy version, and repository commit.

### 2. Provision the replacement host

Follow [Provisioning](provisioning.md) through Docker, Tailscale, Cockpit, and
the firewall. Use a new VPS and new credentials when compromise is suspected.

### 3. Install a compatible Dokploy version

Prefer the version recorded with the backup:

```bash
sudo DOKPLOY_VERSION=vX.Y.Z bash scripts/05-dokploy.sh
```

Avoid restoring an old control database into an arbitrarily newer release. Once
the restore is validated, use Dokploy's supported upgrade process.

### 4. Reconnect S3 and restore the control plane

Using the externally stored S3 credentials, configure the destination and
restore the Web Server backup. Dokploy restores its PostgreSQL database and
replaces `/etc/dokploy` with the backup contents. Expect to authenticate again.

After a different-server restore, review the server IP, Git provider callbacks,
DNS records, domains, certificates, and Traefik configuration.

### 5. Restore application data

Restore each application database from its own database backup. Restore named
volumes only after stopping containers that use them and following Dokploy's
required target-volume naming. Restore bind-mounted data through its separate
backup process.

Do not assume the control-plane archive contains application volume contents.

### 6. Restore integrations

Reinstall or reconnect Cloudflare Tunnel:

```bash
sudo bash scripts/06-cloudflared.sh
```

Recreate or rotate the Cloudflare tunnel token when necessary. Then access
Dokploy through Tailscale and manually deploy the restored webhook-proxy Compose
service. This first deployment cannot depend on its own GitHub webhook. Confirm
the application and webhook hostnames point to the replacement tunnel.

### 7. Validate before cutover

- Dokploy is reachable only through Tailscale.
- No Docker-published port is exposed on the public IP.
- Every expected application is healthy through its public/private path.
- Database row counts or application-level integrity checks pass.
- Named-volume data is present.
- GitHub test delivery succeeds and an unsigned delivery is rejected.
- Scheduled control-plane, database, and volume backups are enabled.
- A new post-recovery backup succeeds.

### 8. Close recovery

Rotate temporary credentials, revoke the old Tailscale machine and tunnel,
remove stale DNS records, and record recovery time, data-loss window, failures,
and follow-up work.

## Restore-test cadence

Perform at least a quarterly tabletop review and a periodic isolated restore.
Also test after material changes to Dokploy, storage layout, backup provider, or
network architecture. Record the date, backup object, versions, duration,
integrity checks, and unresolved gaps.
