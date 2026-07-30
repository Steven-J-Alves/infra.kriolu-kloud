#!/usr/bin/env bash
# Cria snapshot semanal da VPS Contabo e mantém apenas os últimos KEEP snapshots.
# Cron: 0 3 * * 1  (segunda-feira às 03:00)
# Depende: cntb CLI com ~/.cntb.yaml configurado
# IMPORTANTE: Contabo limita a 2 snapshots — apaga o mais antigo ANTES de criar.

set -euo pipefail

export HOME=/home/claw  # cntb procura ~/.cntb.yaml; HOME pode não estar definido em CI

INSTANCE_ID="203171298"
KEEP=2
LOGFILE="$(dirname "$0")/snapshot-rotate.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }

# --- Listar snapshots ordenados por data (mais antigo primeiro) ---
SNAPS=$(cntb get snapshots "$INSTANCE_ID" -o json | \
  python3 -c "import sys,json; snaps=sorted(json.load(sys.stdin), key=lambda x: x['createdDate']); [print(s['snapshotId']) for s in snaps]")

COUNT=$(echo "$SNAPS" | grep -c .)
log "Snapshots existentes: $COUNT (limite: $KEEP)"

# --- Apagar os mais antigos ANTES de criar (Contabo tem limite fixo) ---
SLOTS_LIVRES=$(( KEEP - COUNT ))
if [ "$SLOTS_LIVRES" -le 0 ]; then
  EXCESS=$(( COUNT - KEEP + 1 ))
  TO_DELETE=$(echo "$SNAPS" | head -n "$EXCESS")
  while IFS= read -r snap_id; do
    log "A apagar snapshot antigo: $snap_id"
    cntb delete snapshot "$INSTANCE_ID" "$snap_id"
    log "Apagado: $snap_id"
  done <<< "$TO_DELETE"
fi

# --- Criar novo snapshot ---
NAME="weekly-$(date +%Y-%m-%d)"
log "A criar snapshot: $NAME"
SNAP_ID=$(cntb create snapshot "$INSTANCE_ID" --name "$NAME" --description "Weekly automated snapshot")
log "Criado: $SNAP_ID"

log "Rotação concluída. Snapshots actuais:"
cntb get snapshots "$INSTANCE_ID" | tee -a "$LOGFILE"
