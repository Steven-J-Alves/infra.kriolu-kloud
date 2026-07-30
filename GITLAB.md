# GitLab CE — KrioluKloud

Instalação self-hosted do GitLab Community Edition em `gitlab.kriolu-kloud.cv` via Docker.

- **Domínio:** `gitlab.kriolu-kloud.cv`
- **VPS:** OpenClaw (ver `infra/vpsaccess`)
- **Edição:** GitLab CE (gratuita)
- **Porta SSH Git:** `22` (porta padrão — `git@host` funciona sem config extra)
- **Porta SSH do host (VPS):** `52222` (movida da `22` para libertar para o GitLab)
- **HTTP/HTTPS:** servidos pelo **Traefik** (na stack `~/traefik`). GitLab serve só HTTP
  internamente na rede Docker `traefik-public`; o Traefik termina o TLS e faz proxy.
- **TLS cert:** emitido pelo Traefik (Let's Encrypt, HTTP-01). GitLab **não** trata de certs.

---

## 1. Pré-requisitos na VPS

Antes de copiar os ficheiros, confirma:

| Recurso       | Mínimo | Recomendado | Notas                                    |
| ------------- | ------ | ----------- | ---------------------------------------- |
| RAM           | 4 GB   | 8 GB        | <4GB → criar swap (ver §6)               |
| CPU           | 2 vCPU | 4 vCPU      |                                          |
| Disco livre   | 20 GB  | 50 GB+      | Repos + LFS + backups crescem rápido     |
| Portas livres | 22            | — | Só a `22` para git SSH (host sshd já está em 52222). HTTP/HTTPS são do Traefik. |
| Traefik       | stack `~/traefik` a correr | — | Rede `traefik-public` tem de existir; sem isto o GitLab não fica acessível |
| DNS           | A record `gitlab.kriolu-kloud.cv` → IP da VPS | — | Necessário para o Traefik emitir o cert Let's Encrypt |

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

## 2.1. Como o tráfego flui (Traefik → GitLab)

```
Internet
   │
   ▼  :80 (HTTP) e :443 (HTTPS) — publicados pelo container `traefik`
┌─────────┐
│ traefik │  ← termina TLS, redireciona HTTP→HTTPS, valida Let's Encrypt
└─────────┘
   │
   │  rede Docker `traefik-public` (interna, sem portas no host)
   ▼
┌────────┐
│ gitlab │  ← serve só HTTP na porta 80 do container, com proxy headers
└────────┘
   │
   ▼  :22 (host) — publicado pelo container `gitlab`, para git SSH
Internet
```

**Em runtime:**
- Quem chega via HTTPS: Internet → Traefik (TLS) → GitLab (HTTP via rede Docker)
- Quem chega via HTTP: Internet → Traefik → redirect 301 → HTTPS
- Quem usa `git clone git@…`: Internet → diretamente para o container GitLab na 22

O routing está no `docker-compose.yml` do GitLab (labels `traefik.http.routers.gitlab.*`).
Não há entry no `~/traefik/dynamic.yml` — usamos o **Docker provider** do Traefik.

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
dig +short gitlab.kriolu-kloud.cv
curl -s https://api.ipify.org
```

Os dois devem ser iguais. Caso contrário, **não prossigas** — o Traefik (que emite o cert
Let's Encrypt) vai falhar e podes ficar com rate-limit.

### 3.4. Mover o sshd do host da porta 22 para a 52222

⚠️ **Passo crítico — feito mal, podes ficar trancado fora da VPS.** Faz na ordem indicada
e **mantém a sessão SSH atual aberta** até ao fim, como rede de segurança.

1. Abrir uma **segunda** ligação SSH à VPS (mantém-na aberta em paralelo):

   ```bash
   ssh openclaw
   ```

2. Editar `/etc/ssh/sshd_config` — adicionar a porta nova **sem remover ainda a 22**:

   ```bash
   sudo nano /etc/ssh/sshd_config
   ```

   Encontra (ou adiciona) as linhas:

   ```sshconfig
   Port 22
   Port 52222
   ```

3. Aplicar a config:

   ```bash
   sudo systemctl reload ssh   # ou: sudo systemctl reload sshd
   ```

4. Abrir a porta no firewall:

   ```bash
   sudo ufw allow 52222/tcp comment 'VPS SSH (host)'
   # se usares iptables/nftables, faz o equivalente
   ```

5. A partir do **portátil** (NÃO na VPS), abrir uma terceira ligação na porta nova:

   ```bash
   ssh -p 52222 claw@<ip-da-vps>
   ```

   Se conseguires login, ótimo — segue em frente. Se falhar, **não fechas as outras
   sessões** e investiga (`sudo journalctl -u ssh -n 50`).

6. Agora, e **só agora**, remover a porta 22 do `sshd_config`:

   ```bash
   sudo nano /etc/ssh/sshd_config
   # remove a linha 'Port 22', deixa apenas 'Port 52222'
   sudo systemctl reload ssh
   ```

7. Atualizar o teu `~/.ssh/config` local para usar `Port 52222` no host `openclaw`:

   ```sshconfig
   Host openclaw
       Hostname <ip-da-vps>
       Port 52222
       User claw
       IdentityFile ~/.ssh/claw_vps
   ```

8. Fechar a porta 22 do firewall apenas depois de confirmares acesso pela 52222
   (vai voltar a ser aberta quando o GitLab arrancar — esse é o git SSH, não o host):

   ```bash
   sudo ufw delete allow 22/tcp     # se existir uma regra antiga
   sudo ufw allow 22/tcp comment 'GitLab git SSH'   # para o container do GitLab
   sudo ufw allow 80,443/tcp comment 'Traefik HTTP/HTTPS'   # já devem estar abertas
   ```

> Confirma `sudo ss -tlnp | grep ':22 '` — não deve aparecer `sshd`. Se aparecer,
> o GitLab vai falhar a arrancar com `bind: address already in use`.

### 3.5. Criar swap (só se RAM < 4 GB)

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

### 3.6. Correr o instalador

```bash
cd ~/gitlab
./install.sh
```

O script:

1. Verifica RAM, disco e a porta `22` (git SSH)
2. Confirma DNS
3. Instala Docker (se em falta) + docker-compose plugin
4. Confirma que a rede `traefik-public` existe e que o container `traefik` corre
5. Cria `data/{config,logs,data}/`
6. Faz `docker compose pull` + `up -d`
7. Mostra como obter a password inicial do `root`

### 3.7. Primeiro arranque (5–10 minutos)

```bash
# Acompanhar o estado:
watch -n 5 'docker ps --filter name=gitlab --format "table {{.Names}}\t{{.Status}}"'

# Acompanhar logs:
cd ~/gitlab && docker compose logs -f gitlab
```

Aguarda até o status mostrar `(healthy)`.

### 3.8. Obter password inicial do `root`

```bash
docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

> ⚠️ Esta password é apagada automaticamente após **24 horas**. Faz login e altera já.

### 3.9. Primeiro login

1. Abre <https://gitlab.kriolu-kloud.cv>
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
git clone https://gitlab.kriolu-kloud.cv/user/repo.git
```

GitLab pede username + **personal access token** (não a password).
Cria em: **User → Preferences → Access Tokens**.

### Via SSH (porta 22 — padrão)

1. Vai a **User Settings → SSH Keys** e cola a tua chave pública.
2. (Opcional) Configura `~/.ssh/config` no teu portátil — só precisas se quiseres
   forçar uma `IdentityFile` específica; o `git clone git@...` funciona sem nada:

   ```sshconfig
   Host gitlab.kriolu-kloud.cv
       Hostname gitlab.kriolu-kloud.cv
       User git
       IdentityFile ~/.ssh/id_ed25519
   ```

3. Clona:

   ```bash
   git clone git@gitlab.kriolu-kloud.cv:user/repo.git
   ```

> ⚠️ Se tens `Host gitlab.kriolu-kloud.cv` com `Port 2222` da configuração antiga,
> remove a linha `Port 2222` — caso contrário o cliente vai bater na porta errada.

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

- **Pouca RAM:** processos OOM-killed. Cria swap (§3.5) ou aumenta a VPS.
- **Rede `traefik-public` não existe:** `docker network ls | grep traefik-public` deve aparecer. Se não, arranca a stack `~/traefik` primeiro.
- **502 Bad Gateway no browser:** Traefik está, GitLab ainda não respondeu. Vê `docker logs gitlab` e espera o healthcheck.
- **Cert inválido em https://gitlab.kriolu-kloud.cv:** Traefik ainda não conseguiu emitir. Vê `docker logs traefik | grep -i acme` — DNS errado, porta 80 inacessível, ou rate-limit.

### Mudar o routing Traefik

O routing está nas labels do `docker-compose.yml` do GitLab — não no `~/traefik/dynamic.yml`.
Para alterações, edita o compose do GitLab e faz `docker compose up -d` (recria o container).

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
- [ ] Firewall só com 80, 443 (Traefik) + 22 (git SSH) + 52222 (host SSH) expostos
- [ ] Backup automático no cron e testado um restore
- [ ] Email SMTP configurado (necessário para notificações e reset de password) — ver
      [Omnibus SMTP docs](https://docs.gitlab.com/omnibus/settings/smtp.html)

---

## 11. Recursos

- Docs oficiais: <https://docs.gitlab.com>
- Imagem Docker: <https://hub.docker.com/r/gitlab/gitlab-ce>
- gitlab.rb template: <https://gitlab.com/gitlab-org/omnibus-gitlab/-/blob/master/files/gitlab-config-template/gitlab.rb.template>
