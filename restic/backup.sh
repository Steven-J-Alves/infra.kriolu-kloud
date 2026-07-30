#!/usr/bin/env bash
# Backup diário da VPS para S3 via Restic.
# Corre via GitLab CI (schedule diário às 02:00 UTC).
# Credenciais em /home/claw/.config/restic/env (não versionado).
set -euo pipefail

source /home/claw/.config/restic/env

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- GitLab: dump interno antes de fazer backup ---
log "A criar backup interno do GitLab..."
docker exec gitlab gitlab-backup create STRATEGY=copy SKIP=registry 2>&1 | tail -5
GITLAB_BACKUP_DIR="/home/claw/companies/kriolu-kloud.cv/infra.kriolu-kloud/gitlab/data/data/backups"

# sudo limpa env vars — passar explicitamente
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
