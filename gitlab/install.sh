#!/usr/bin/env bash
# GitLab CE install script for KrioluKloud VPS
# Run as user with sudo. Idempotent — pode correr várias vezes.
set -euo pipefail

DOMAIN="git.kriolu-kloud.cv"
SSH_GIT_PORT="2222"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_red()   { printf "\033[31m%s\033[0m\n" "$*"; }
c_green() { printf "\033[32m%s\033[0m\n" "$*"; }
c_yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
c_blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || { c_red "FALTA: $1"; return 1; }; }

step_check_root() {
  if [ "$EUID" -ne 0 ]; then
    c_yellow "Não está como root. Vou usar sudo quando necessário."
    SUDO="sudo"
  else
    SUDO=""
  fi
}

step_check_resources() {
  c_blue "==> Verificar recursos..."
  local mem_mb disk_gb
  mem_mb=$(free -m | awk '/^Mem:/ {print $2}')
  disk_gb=$(df -BG --output=avail "$COMPOSE_DIR" | tail -1 | tr -dc '0-9')

  echo "RAM total: ${mem_mb} MB"
  echo "Disco livre em $COMPOSE_DIR: ${disk_gb} GB"

  if [ "$mem_mb" -lt 3500 ]; then
    c_red "AVISO: GitLab recomenda 4GB+ de RAM. Tens ${mem_mb}MB."
    c_yellow "Considera criar swap antes de continuar (ver GITLAB.md)."
    read -r -p "Continuar mesmo assim? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
  fi

  if [ "$disk_gb" -lt 20 ]; then
    c_red "AVISO: Disco livre <20GB (${disk_gb}GB). GitLab + repos crescem rápido."
    read -r -p "Continuar mesmo assim? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
  fi
}

step_check_ports() {
  c_blue "==> Verificar portas 80/443/${SSH_GIT_PORT}..."
  local busy=0
  for port in 80 443 "${SSH_GIT_PORT}"; do
    if ${SUDO} ss -tlnp 2>/dev/null | awk '{print $4}' | grep -E "(^|:)${port}$" >/dev/null; then
      c_red "Porta ${port} ocupada:"
      ${SUDO} ss -tlnp | grep -E "(^|:)${port}\b" || true
      busy=1
    fi
  done
  if [ $busy -ne 0 ]; then
    c_red "Liberta as portas ocupadas antes de prosseguir."
    exit 1
  fi
  c_green "OK — portas livres."
}

step_check_dns() {
  c_blue "==> Verificar DNS para ${DOMAIN}..."
  local ip_resolved ip_public
  ip_resolved=$(getent hosts "${DOMAIN}" | awk '{print $1}' | head -1 || true)
  ip_public=$(curl -fsS https://api.ipify.org 2>/dev/null || echo "")

  echo "DNS resolve para: ${ip_resolved:-<vazio>}"
  echo "IP público desta VPS: ${ip_public:-<desconhecido>}"

  if [ -z "$ip_resolved" ]; then
    c_red "Domínio não resolve. Confirma o registo DNS A antes de continuar (Let's Encrypt vai falhar)."
    read -r -p "Continuar mesmo assim? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
  elif [ -n "$ip_public" ] && [ "$ip_resolved" != "$ip_public" ]; then
    c_yellow "DNS aponta para ${ip_resolved} mas o IP público é ${ip_public}. Let's Encrypt pode falhar."
    read -r -p "Continuar mesmo assim? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
  else
    c_green "OK — DNS aponta para esta VPS."
  fi
}

step_install_docker() {
  c_blue "==> Verificar Docker..."
  if ! command -v docker >/dev/null 2>&1; then
    c_yellow "Docker não encontrado. A instalar..."
    curl -fsSL https://get.docker.com | ${SUDO} sh
    ${SUDO} systemctl enable --now docker
  else
    c_green "Docker já instalado: $(docker --version)"
  fi

  if ! docker compose version >/dev/null 2>&1; then
    c_red "docker compose plugin não disponível. Instala manualmente:"
    echo "  sudo apt-get install -y docker-compose-plugin"
    exit 1
  fi
  c_green "Docker Compose: $(docker compose version | head -1)"
}

step_prepare_dirs() {
  c_blue "==> Preparar diretórios de dados..."
  mkdir -p "${COMPOSE_DIR}/data/config" "${COMPOSE_DIR}/data/logs" "${COMPOSE_DIR}/data/data"
  c_green "OK"
}

step_start() {
  c_blue "==> A iniciar GitLab (pode demorar 5–10 minutos no primeiro arranque)..."
  cd "${COMPOSE_DIR}"
  ${SUDO} docker compose pull
  ${SUDO} docker compose up -d
  c_green "Container iniciado."
  echo
  c_yellow "Aguarda até o healthcheck reportar 'healthy':"
  echo "  watch -n 5 'docker ps --filter name=gitlab --format \"{{.Status}}\"'"
  echo
  c_yellow "Acompanha o log:"
  echo "  docker compose -f ${COMPOSE_DIR}/docker-compose.yml logs -f gitlab"
}

step_show_root_password() {
  c_blue "==> Password inicial do utilizador 'root' (válida 24h):"
  echo "Quando o container estiver 'healthy', corre:"
  echo
  echo "  docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password"
  echo
  c_yellow "Faz login em https://${DOMAIN} com utilizador 'root' e essa password."
  c_yellow "Muda a password imediatamente (User Settings → Password)."
}

main() {
  step_check_root
  step_check_resources
  step_check_ports
  step_check_dns
  step_install_docker
  step_prepare_dirs
  step_start
  step_show_root_password
  c_green "==> Instalação iniciada. Vê GITLAB.md para próximos passos."
}

main "$@"
