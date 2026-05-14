# GitLab CE — KrioluKloud

Instalação self-hosted do GitLab Community Edition em `git.kriolu-kloud.cv` via Docker.

- **Domínio:** `git.kriolu-kloud.cv`
- **VPS:** OpenClaw (ver `infra/vpsaccess`)
- **Edição:** GitLab CE (gratuita)
- **Porta SSH Git:** `2222` (porta `22` continua a ser o SSH normal da VPS)
- **HTTPS:** Let's Encrypt (renovação automática)

---

## 1. Pré-requisitos na VPS

Antes de copiar os ficheiros, confirma:

| Recurso       | Mínimo | Recomendado | Notas                                    |
| ------------- | ------ | ----------- | ---------------------------------------- |
| RAM           | 4 GB   | 8 GB        | <4GB → criar swap (ver §6)               |
| CPU           | 2 vCPU | 4 vCPU      |                                          |
| Disco livre   | 20 GB  | 50 GB+      | Repos + LFS + backups crescem rápido     |
| Portas livres | 80, 443, 2222 | — | 80/443 para HTTP/HTTPS, 2222 para git SSH |
| DNS           | A record `git.kriolu-kloud.cv` → IP da VPS | — | Tem de estar propagado antes de arrancar |

> ⚠️ Esta VPS já corre o **OpenClaw (Bear)**. Confirma que tens RAM suficiente para os dois.
> Faz `free -h` e `df -h /` antes de instalar.

---

## 2. Estrutura dos ficheiros

```
infra/
├── GITLAB.md                 ← este ficheiro
└── gitlab/
    ├── docker-compose.yml    ← definição do container
    ├── install.sh            ← arrancar tudo (verifica + instala)
    ├── backup.sh             ← backup manual
    ├── .gitignore            ← exclui data/ e backups/
    ├── data/                 ← volumes persistentes (criado em runtime)
    │   ├── config/           ← /etc/gitlab (segredos, gitlab.rb)
    │   ├── logs/             ← /var/log/gitlab
    │   └── data/             ← /var/opt/gitlab (repos, DB, uploads)
    └── backups/              ← tarballs de backup (criado pelo backup.sh)
```

---

## 3. Instalação passo-a-passo

### 3.1. Copiar ficheiros para a VPS

A partir da máquina local:

```bash
# Tu (Steven) corres isto:
scp -i ~/.ssh/claw_vps -r \
    /home/stevenalves/Desktop/company/projects/kriolukloud/infra/gitlab \
    claw@100.73.87.120:~/gitlab
```

Ou, com o alias do `~/.ssh/config` que já tens:

```bash
scp -r /home/stevenalves/Desktop/company/projects/kriolukloud/infra/gitlab openclaw:~/gitlab
```

### 3.2. SSH para a VPS

```bash
ssh openclaw
```

### 3.3. Verificar DNS

```bash
dig +short git.kriolu-kloud.cv
curl -s https://api.ipify.org
```

Os dois devem ser iguais. Caso contrário, **não prossigas** — Let's Encrypt vai falhar e
podes ficar com rate-limit.

### 3.4. Criar swap (só se RAM < 4 GB)

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

### 3.5. Correr o instalador

```bash
cd ~/gitlab
./install.sh
```

O script:

1. Verifica RAM, disco e portas livres
2. Confirma DNS
3. Instala Docker (se em falta) + docker-compose plugin
4. Cria `data/{config,logs,data}/`
5. Faz `docker compose pull` + `up -d`
6. Mostra como obter a password inicial do `root`

### 3.6. Primeiro arranque (5–10 minutos)

```bash
# Acompanhar o estado:
watch -n 5 'docker ps --filter name=gitlab --format "table {{.Names}}\t{{.Status}}"'

# Acompanhar logs:
cd ~/gitlab && docker compose logs -f gitlab
```

Aguarda até o status mostrar `(healthy)`.

### 3.7. Obter password inicial do `root`

```bash
docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

> ⚠️ Esta password é apagada automaticamente após **24 horas**. Faz login e altera já.

### 3.8. Primeiro login

1. Abre <https://git.kriolu-kloud.cv>
2. Login com `root` + password do passo 3.7
3. Vai a **User Settings → Password** e muda a password
4. Vai a **Admin Area → Settings → General → Sign-up restrictions** e desativa
   "Sign-up enabled" (caso queiras instância privada)

---

## 4. Operações diárias

Todos os comandos correm a partir de `~/gitlab` na VPS.

| Acção                              | Comando                                                    |
| ---------------------------------- | ---------------------------------------------------------- |
| Estado                             | `docker compose ps`                                        |
| Logs                               | `docker compose logs -f gitlab`                            |
| Reiniciar                          | `docker compose restart gitlab`                            |
| Parar                              | `docker compose stop`                                      |
| Arrancar                           | `docker compose up -d`                                     |
| Shell dentro do container          | `docker exec -it gitlab bash`                              |
| `gitlab-ctl` (control)             | `docker exec -it gitlab gitlab-ctl status`                 |
| Recarregar config após editar      | `docker exec -it gitlab gitlab-ctl reconfigure`            |
| Rails console (cuidado!)           | `docker exec -it gitlab gitlab-rails console`              |

---

## 5. Editar configuração (`gitlab.rb`)

As alterações `GITLAB_OMNIBUS_CONFIG` do `docker-compose.yml` são aplicadas a cada
`docker compose up -d`. Para mudanças avulsas:

```bash
# Edita o ficheiro persistente:
sudo nano ~/gitlab/data/config/gitlab.rb

# Aplica:
docker exec -it gitlab gitlab-ctl reconfigure
```

---

## 6. Clonar/empurrar repos

### Via HTTPS

```bash
git clone https://git.kriolu-kloud.cv/user/repo.git
```

GitLab pede username + **personal access token** (não a password).
Cria em: **User → Preferences → Access Tokens**.

### Via SSH (porta 2222)

1. Vai a **User Settings → SSH Keys** e cola a tua chave pública.
2. Configura `~/.ssh/config` no teu portátil:

   ```sshconfig
   Host git.kriolu-kloud.cv
       Hostname git.kriolu-kloud.cv
       Port 2222
       User git
       IdentityFile ~/.ssh/id_ed25519
   ```

3. Clona:

   ```bash
   git clone git@git.kriolu-kloud.cv:user/repo.git
   ```

---

## 7. Backups

### Manual

```bash
cd ~/gitlab
./backup.sh
```

Resultado em `~/gitlab/backups/`:

- `data-<timestamp>/<n>_gitlab_backup.tar` — repos, DB, uploads
- `etc-gitlab-<timestamp>.tar.gz` — segredos e config

> ⚠️ **Guarda os dois.** Sem `etc/gitlab` os segredos perdem-se e os backups encriptados
> ficam inutilizáveis (2FA tokens, CI variables encriptadas, etc).

### Automatizar (cron diário às 03:00)

```bash
crontab -e
```

Adiciona:

```
0 3 * * * /home/claw/gitlab/backup.sh >> /home/claw/gitlab/backups/cron.log 2>&1
```

### Restaurar

1. Para o GitLab: `docker compose stop`
2. Restaura `/etc/gitlab` do tarball para o volume `data/config/`
3. Copia o `_gitlab_backup.tar` para `data/data/backups/`
4. Arranca em modo restore:

   ```bash
   docker compose up -d
   docker exec -it gitlab gitlab-ctl stop puma sidekiq
   docker exec -it gitlab gitlab-backup restore BACKUP=<timestamp>
   docker exec -it gitlab gitlab-ctl reconfigure
   docker exec -it gitlab gitlab-ctl restart
   ```

Docs oficiais: <https://docs.gitlab.com/ee/raketasks/backup_restore.html>

---

## 8. Atualizar versão

GitLab **não suporta saltar versões major**. Antes de actualizar, lê:
<https://docs.gitlab.com/ee/update/#upgrade-paths>

```bash
cd ~/gitlab
docker compose pull
docker compose up -d
docker compose logs -f gitlab
```

Aguarda `(healthy)` antes de fechar a sessão.

---

## 9. Troubleshooting

### Container não fica "healthy"

```bash
docker compose logs --tail=200 gitlab
docker exec -it gitlab gitlab-ctl tail
```

Causas comuns:

- **Pouca RAM:** processos OOM-killed. Cria swap (§3.4) ou aumenta a VPS.
- **DNS errado:** Let's Encrypt falha. Verifica `dig +short git.kriolu-kloud.cv`.
- **Porta 80 ocupada:** outro serviço (nginx/apache) ocupa-a. `sudo ss -tlnp | grep ':80 '`.

### "Whoops, GitLab is taking too much time to respond"

O container ainda está a arrancar. Aguarda 10 minutos.

### Reset da password do `root`

```bash
docker exec -it gitlab gitlab-rake "gitlab:password:reset[root]"
```

### Apagar tudo e recomeçar (⚠️ destrutivo)

```bash
cd ~/gitlab
docker compose down
sudo rm -rf data/
./install.sh
```

---

## 10. Segurança — checklist pós-instalação

- [ ] Password do `root` alterada
- [ ] Sign-up público desativado (Admin → Settings → Sign-up restrictions)
- [ ] 2FA ativado para o `root`
- [ ] Firewall só com 80, 443, 2222 + porta SSH da VPS expostos
- [ ] Backup automático no cron e testado um restore
- [ ] Email SMTP configurado (necessário para notificações e reset de password) — ver
      [Omnibus SMTP docs](https://docs.gitlab.com/omnibus/settings/smtp.html)

---

## 11. Recursos

- Docs oficiais: <https://docs.gitlab.com>
- Imagem Docker: <https://hub.docker.com/r/gitlab/gitlab-ce>
- gitlab.rb template: <https://gitlab.com/gitlab-org/omnibus-gitlab/-/blob/master/files/gitlab-config-template/gitlab.rb.template>
