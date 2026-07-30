# Contabo — Snapshots da VPS

Rotação automática de snapshots do disco completo da VPS Contabo via GitLab CI.

- **VPS ID:** `203171298`
- **Plano:** Cloud VPS 6 (2026) — limite fixo de **2 snapshots**
- **Ferramenta:** `cntb` CLI (Contabo API v1)
- **Schedule:** todos os dias às 04:00 UTC (03:00 Cabo Verde)
- **Retenção:** 2 snapshots — ontem + hoje
- **Perda máxima de dados:** 23 horas

---

## O que é um snapshot Contabo

Imagem completa do disco da VPS num dado momento. Cobre tudo: sistema operativo,
Docker, volumes, configs, código. Permite restaurar a VPS inteira ao estado anterior.

Diferente do Restic (ver `RESTIC.md`) — o snapshot é a "rede de segurança" para
desastre total (VPS corrompida, apagada acidentalmente, falha de disco). O Restic
cobre os dados críticos com mais granularidade.

---

## Como funciona a rotação

O Contabo limita a 2 snapshots por instância. O script apaga o mais antigo **antes**
de criar o novo (ordem importa — criar primeiro falha com erro 402).

```
Dia 1:  [snapshot-A]
Dia 2:  apaga A → cria B  →  [snapshot-B]  (só 1 hoje, amanhã volta a 2)
Dia 3:  apaga B → cria C  →  [snapshot-B] [snapshot-C]
Dia 4:  apaga C → cria D  →  [snapshot-C] [snapshot-D]
```

Em regime estável tens sempre **ontem** e **hoje**.

---

## Estrutura dos ficheiros

```
infra/
├── CONTABO.md              ← este ficheiro
└── contabo/
    └── snapshot-rotate.sh  ← script de rotação
```

As credenciais Contabo ficam em `~/.cntb.yaml` na máquina local — **nunca versionadas**.

---

## Credenciais e CLI

### Instalar `cntb` localmente

```bash
curl -sL https://github.com/contabo/cntb/releases/download/v1.7/cntb_v1.7_linux_amd64.tar.gz \
  | tar -xz -C /tmp && sudo mv /tmp/cntb /usr/local/bin/cntb && chmod +x /usr/local/bin/cntb
```

### Configurar `~/.cntb.yaml`

```yaml
debug: warn
oauth2-tokenurl: https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token
oauth2-clientid: INT-14768128
oauth2-user: stevenalves512@gmail.com
oauth2-password: <password-contabo>
oauth2-client-secret: <client-secret>
api: https://api.contabo.com
```

Credenciais em 1Password / painel Contabo → API → Credentials.

### Instalar `cntb` na VPS (necessário para o GitLab CI)

```bash
ssh openclaw
curl -sL https://github.com/contabo/cntb/releases/download/v1.7/cntb_v1.7_linux_amd64.tar.gz \
  | tar -xz -C /tmp && sudo mv /tmp/cntb /usr/local/bin/cntb
# Copiar ~/.cntb.yaml local para a VPS:
scp -P 52222 ~/.cntb.yaml claw@<ip>:~/.cntb.yaml
chmod 600 ~/.cntb.yaml
```

---

## Operações manuais

### Listar snapshots

```bash
cntb get snapshots 203171298
```

### Criar snapshot manual

```bash
cntb create snapshot 203171298 --name "manual-$(date +%Y-%m-%d)" --description "Motivo"
```

### Apagar snapshot

```bash
cntb delete snapshot 203171298 <snapshotId>
```

### Correr rotação manualmente

```bash
bash infra/contabo/snapshot-rotate.sh
```

---

## GitLab CI

O pipeline `contabo-snapshot-rotate` no projeto `kriolu-kloud/devops/infra` corre
o script todos os dias às 04:00 UTC via um schedule configurado no GitLab.

### Ver schedules

```bash
glab api "/projects/1/pipeline_schedules"
```

### Alterar frequência

```bash
# Editar o schedule ID 1:
glab api "/projects/1/pipeline_schedules/1" --method PUT -f cron="0 4 * * *"
```

Sintaxe cron: `minuto hora dia mês dia-semana`

### Forçar execução imediata

No GitLab UI: `devops/infra → Build → Schedules → Run pipeline`.

Ou via API:

```bash
glab api "/projects/1/pipeline_schedules/1/play" --method POST
```

### Ver logs da última execução

```bash
glab api "/projects/1/pipelines?source=schedule&per_page=5" | python3 -m json.tool
```

---

## Restaurar a VPS a partir de um snapshot

⚠️ **Operação destrutiva — apaga o estado atual da VPS.**

1. Acede ao painel Contabo: <https://my.contabo.com>
2. VPS → Instance `203171298` → Snapshots
3. Seleciona o snapshot → **Restore**
4. Confirma — a VPS reinicia com o estado do snapshot

Alternativa via CLI:

```bash
cntb apply snapshot 203171298 <snapshotId>
```

Após restauro, todos os dados criados depois do snapshot estão perdidos.
Para os dados críticos (GitLab repos, email), usa o Restic (ver `RESTIC.md`).

---

## Troubleshooting

### Erro 402 ao criar snapshot

```
Error while creating snapshot: 402 - Total snapshots exceed the total max limit of 2 snapshots
```

O script apaga antes de criar. Se acontecer manualmente, apaga um snapshot antes:

```bash
cntb delete snapshot 203171298 <snapshotId-mais-antigo>
cntb create snapshot 203171298 --name "manual-$(date +%Y-%m-%d)"
```

### Pipeline falha com "cntb: command not found"

O `cntb` não está instalado na VPS. Instala seguindo a secção "Instalar cntb na VPS".

### Pipeline falha com "authentication failed"

O `~/.cntb.yaml` na VPS tem credenciais erradas ou expiradas. Valida:

```bash
ssh openclaw "cntb get snapshots 203171298"
```

### Auto-delete inesperado

O Contabo apaga snapshots automaticamente após ~30 dias. Com rotação diária, o
mais antigo nunca passa de 1 dia — o auto-delete nunca é acionado.
