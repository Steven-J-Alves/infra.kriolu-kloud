#!/usr/bin/env bash
# Backup diário da VPS para S3 via Restic.
# Corre via GitLab CI (schedule diário às 02:00 UTC).
# Credenciais injectadas pelo GitLab CI a partir das variáveis do grupo kriolu-kloud:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION,
#   RESTIC_REPOSITORY, RESTIC_PASSWORD
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- GitLab: dump interno antes de fazer backup ---
log "A criar backup interno do GitLab..."
docker exec gitlab gitlab-backup create STRATEGY=copy SKIP=registry 2>&1 | tail -5
GITLAB_BACKUP_DIR="/home/claw/companies/kriolu-kloud.cv/infra.kriolu-kloud/gitlab/data/data/backups"

# O wrapper /usr/local/bin/restic-backup corre como root e exporta as variáveis
# de ambiente recebidas do GitLab CI para o processo restic.
RESTIC_CMD="sudo /usr/local/bin/restic-backup"

# --- Backup Restic (sudo para aceder a ficheiros root/docker) ---
log "A iniciar backup Restic..."
$RESTIC_CMD backup \
  "$GITLAB_BACKUP_DIR" \
  /opt/mailcow-dockerized/data \
  /home/claw/companies \
  --exclude="/home/claw/companies/kriolu-kloud.cv/clawbuddy-dashboard/workspace/node_modules" \
  --exclude="/home/claw/companies/kriolu-kloud.cv/clawbuddy-dashboard/workspace/**/.git" \
  --tag "daily" \
  --verbose 2>&1

# --- Retenção: manter 7 diários + 4 semanais ---
log "A aplicar política de retenção..."
$RESTIC_CMD forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --prune \
  --tag "daily" 2>&1

log "A verificar integridade do repositório..."
$RESTIC_CMD check 2>&1

log "Backup concluído."
$RESTIC_CMD snapshots 2>&1
