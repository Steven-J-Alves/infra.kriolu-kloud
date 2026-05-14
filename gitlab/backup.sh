#!/usr/bin/env bash
# Backup do GitLab — corre dentro da VPS
# Cria: 1) backup de dados/repos (gitlab-backup) + 2) cópia da /etc/gitlab
set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_OUT_DIR="${COMPOSE_DIR}/backups"
TS=$(date +%Y%m%d-%H%M%S)

mkdir -p "${BACKUP_OUT_DIR}"

echo "==> A criar backup de dados/repos..."
docker exec -t gitlab gitlab-backup create CRON=1 STRATEGY=copy

echo "==> A copiar tarball para ${BACKUP_OUT_DIR}..."
docker cp gitlab:/var/opt/gitlab/backups/. "${BACKUP_OUT_DIR}/data-${TS}/"

echo "==> A copiar /etc/gitlab (segredos e config)..."
docker exec -t gitlab tar -C / -czf "/tmp/etc-gitlab-${TS}.tar.gz" etc/gitlab
docker cp "gitlab:/tmp/etc-gitlab-${TS}.tar.gz" "${BACKUP_OUT_DIR}/etc-gitlab-${TS}.tar.gz"
docker exec gitlab rm -f "/tmp/etc-gitlab-${TS}.tar.gz"

echo "==> Limpar backups locais com mais de 30 dias..."
find "${BACKUP_OUT_DIR}" -maxdepth 2 -mtime +30 -delete 2>/dev/null || true

echo "==> OK. Backup em ${BACKUP_OUT_DIR}"
ls -lh "${BACKUP_OUT_DIR}" | tail -5
