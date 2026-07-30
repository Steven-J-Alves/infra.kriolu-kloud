# Restic — Backup de Dados para S3

Backup incremental diário dos dados críticos da VPS para AWS S3 via Restic.

- **Bucket S3:** `kriolu-kloud-backups` (região `eu-west-1`)
- **Repositório Restic:** `s3:s3.amazonaws.com/kriolu-kloud-backups/vps`
- **IAM user:** `kriolu-kloud-backup` (acesso só a este bucket)
- **Schedule:** todos os dias às 02:00 UTC (01:00 Cabo Verde)
- **Retenção:** 7 diários + 4 semanais

---

## O que é o Restic

Ferramenta de backup incremental com deduplicação e encriptação. Na primeira execução
faz backup completo; nas seguintes só envia o que mudou (blocos novos). O repositório
S3 guarda o histórico de snapshots.

Complementa o snapshot Contabo (ver `CONTABO.md`):

| | Snapshot Contabo | Restic S3 |
|---|---|---|
| O que cobre | Disco inteiro da VPS | Dados críticos selecionados |
| Granularidade | 1 por dia, mantém 2 | 7 diários + 4 semanais |
| Retenção | ~1 dia | ~35 dias |
| Uso | Desastre total (VPS morreu) | Restaurar ficheiros específicos |
| Custo | Incluído no plano Contabo | S3 (~$0.023/GB/mês) |

---

## O que é feito backup

1. **GitLab** — dump interno completo (`gitlab-backup create`) antes do Restic.
   Inclui todos os repos, base de dados, uploads.
2. **Mailcow** — `/opt/mailcow-dockerized/data` (configuração, certificados, dados IMAP).
3. **Projetos** — `/home/claw/companies` (todos os projetos, configs, workspaces).

Excluído: `node_modules`, `.git` dentro de workspaces.

---

## Estrutura dos ficheiros

```
infra/
├── RESTIC.md          ← este ficheiro
└── restic/
    └── backup.sh      ← script de backup (não contém credenciais)
```

---

## Credenciais

### Ficheiro de ambiente (VPS)

`/home/claw/.config/restic/env` — **não versionado, não sair da VPS.**

```bash
export AWS_ACCESS_KEY_ID=AKIAYWXEGOGVTMG73ZIA
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=eu-west-1
export RESTIC_REPOSITORY=s3:s3.amazonaws.com/kriolu-kloud-backups/vps
export RESTIC_PASSWORD=<password-encriptacao-restic>
```

Este ficheiro é lido pelo `backup.sh` com `source` e passado ao `restic-backup`
wrapper que corre como root (ver secção abaixo).

### Wrapper root (`/usr/local/bin/restic-backup`)

O Restic precisa de correr como `root` para aceder a ficheiros do Docker e do GitLab.
O `sudo` limpa variáveis de ambiente, por isso existe este wrapper:

```bash
#!/usr/bin/env bash
set -a
source /home/claw/.config/restic/env
set +a
exec /usr/local/bin/restic "$@"
```

O utilizador `claw` pode correr `sudo /usr/local/bin/restic-backup` sem password
(configurado em `/etc/sudoers.d/restic`).

### IAM user AWS

- **User:** `kriolu-kloud-backup`
- **Política:** `S3BackupAccess` — só `s3:PutObject`, `GetObject`, `DeleteObject`, `ListBucket` no bucket `kriolu-kloud-backups`
- **Access key:** guardada em `/home/claw/.config/restic/env`

Para rodar a access key:

```bash
# Local (com steven-prod):
AWS_PROFILE=steven-prod aws iam create-access-key --user-name kriolu-kloud-backup
AWS_PROFILE=steven-prod aws iam delete-access-key --user-name kriolu-kloud-backup \
  --access-key-id <key-antiga>
# Atualizar /home/claw/.config/restic/env na VPS com a nova key
```

---

## Operações manuais

### Correr backup imediatamente

```bash
ssh openclaw
bash /home/claw/companies/kriolu-kloud.cv/infra.kriolu-kloud/restic/backup.sh
```

### Listar snapshots no repositório

```bash
ssh openclaw "source ~/.config/restic/env && sudo /usr/local/bin/restic-backup snapshots"
```

### Ver conteúdo de um snapshot

```bash
ssh openclaw "source ~/.config/restic/env && sudo /usr/local/bin/restic-backup ls <snapshot-id>"
```

### Restaurar um ficheiro específico

```bash
ssh openclaw
source ~/.config/restic/env
sudo /usr/local/bin/restic-backup restore <snapshot-id> \
  --target /tmp/restore \
  --include /home/claw/companies/kriolu-kloud.cv/infra.kriolu-kloud/gitlab/data/config/gitlab.rb
```

### Restaurar tudo de um snapshot

```bash
ssh openclaw
source ~/.config/restic/env
sudo /usr/local/bin/restic-backup restore <snapshot-id> --target /
```

⚠️ Cuidado — sobrescreve ficheiros existentes. Usa `--target /tmp/restore` para
inspecionar antes.

---

## GitLab CI

O pipeline `restic-backup` no projeto `kriolu-kloud/devops/infra` corre todos os
dias às 02:00 UTC (antes do snapshot Contabo às 04:00).

### Ver schedules

```bash
glab api "/projects/1/pipeline_schedules"
```

### Forçar execução imediata

```bash
glab api "/projects/1/pipeline_schedules/2/play" --method POST
```

### Ver logs da última execução

No GitLab UI: `devops/infra → Build → Pipelines` (filtrar por `schedule`).

---

## Bucket S3

- **Nome:** `kriolu-kloud-backups`
- **Região:** `eu-west-1` (Irlanda — mais perto de Cabo Verde)
- **Versionamento:** activado
- **Acesso público:** totalmente bloqueado
- **Prefixo do repositório Restic:** `/vps`

### Ver tamanho do bucket

```bash
AWS_PROFILE=steven-prod aws s3 ls s3://kriolu-kloud-backups/vps/ --recursive --human-readable --summarize \
  | tail -2
```

### Custo estimado

Restic tem deduplicação — após o primeiro backup completo só envia deltas.
Com ~3 GB iniciais e mudanças diárias pequenas, espera ~5–10 GB no S3.
Custo: ~$0.10–$0.25/mês em `eu-west-1`.

---

## Inicializar repositório Restic (novo setup)

Só necessário se o repositório for apagado ou mudares de bucket:

```bash
ssh openclaw
source ~/.config/restic/env
sudo /usr/local/bin/restic-backup init
```

---

## Troubleshooting

### "Fatal: unable to open config file"

O repositório Restic não foi inicializado. Corre `restic-backup init` (ver acima).

### "Fatal: wrong password or no key found"

A `RESTIC_PASSWORD` em `/home/claw/.config/restic/env` está errada. A password
de encriptação tem de ser a mesma usada quando o repositório foi criado — se perdida,
os backups ficam inacessíveis.

### Erros "permission denied" no backup

O `restic-backup` wrapper não está a correr como root. Verifica:

```bash
cat /etc/sudoers.d/restic
# deve conter: claw ALL=(ALL) NOPASSWD: /usr/local/bin/restic-backup
ls -la /usr/local/bin/restic-backup
# deve ser: -rwxr-x--- root root
```

### Aviso GitLab "gitlab.rb and gitlab-secrets.json not included"

Mensagem normal do `gitlab-backup create` — refere-se ao dump interno do GitLab.
O Restic **inclui** estes ficheiros porque corre como root e faz backup de
`/home/claw/companies/.../gitlab/data/config/`. O aviso pode ser ignorado.

### Pipeline falha com "No space left on device"

O disco da VPS encheu durante o backup dos dumps do GitLab. Limpa dumps antigos:

```bash
ssh openclaw
docker exec gitlab find /var/opt/gitlab/backups -name "*.tar" -mtime +2 -delete
```
