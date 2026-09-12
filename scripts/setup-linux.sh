#!/usr/bin/env bash
# ============================================================================
# setup-linux.sh -- instala o stack de desenvolvimento no Fedora/Ubuntu
#
# Le pacotes.yaml (fonte unica da verdade) e instala com dnf ou apt, conforme
# a distribuicao. Tambem serve dentro do WSL.
#
# Uso:
#   ./scripts/setup-linux.sh              instala tudo menos o grupo opcional
#   ./scripts/setup-linux.sh --grupo r    so o grupo r
#   ./scripts/setup-linux.sh --simular    mostra o que faria
# ============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SIMULAR=0
GRUPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --simular) SIMULAR=1; shift ;;
    --grupo)   GRUPO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

OS="$(detectar_os)"
case "$OS" in
  linux|wsl) ;;
  *) morre "este script e para Linux/WSL. Sistema detectado: $OS" ;;
esac

GER="$(detectar_gerenciador)"
[ -z "$GER" ] && morre "nem dnf nem apt encontrados"
info "distribuicao usa: $GER"
[ "$SIMULAR" = "1" ] && aviso "modo simulacao: nada sera instalado"

# --------------------------------------------------------------- repositorios
# Alguns pacotes so existem em repositorio de terceiro. Configurado antes de
# qualquer instalacao, senao o gerenciador nao encontra o pacote.
configurar_repos() {
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] configuraria repositorios de terceiros"
    return 0
  fi

  if [ "$GER" = "dnf" ]; then
    # VS Code (repositorio da Microsoft)
    if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
      info "adicionando repositorio do VS Code"
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      printf '%s\n' \
        '[code]' \
        'name=Visual Studio Code' \
        'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
        'enabled=1' \
        'gpgcheck=1' \
        'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' \
        | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
    fi

    # RPM Fusion: codecs e drivers que o Fedora nao distribui por licenca.
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
      info "adicionando RPM Fusion"
      sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    fi

    # Docker CE (o docker do repositorio padrao do Fedora e o moby, mais velho)
    if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
      info "adicionando repositorio do Docker"
      sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    fi
  fi

  if [ "$GER" = "apt" ]; then
    sudo apt-get update -qq

    if ! command -v curl >/dev/null 2>&1; then
      sudo apt-get install -y curl gnupg
    fi

    # VS Code
    if [ ! -f /etc/apt/sources.list.d/vscode.list ]; then
      info "adicionando repositorio do VS Code"
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    fi

    # GitHub CLI
    if [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
      info "adicionando repositorio do GitHub CLI"
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    fi

    # Docker CE
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
      info "adicionando repositorio do Docker"
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi

    sudo apt-get update -qq
  fi
}

# ----------------------------------------------------------------- instalar --
instalar_pacotes() {
  local -a lista=()
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && lista+=("$pkg")
  done < <(pacotes_para "$GER" "$GRUPO")

  # Sem --grupo, remove o grupo opcional da lista.
  if [ -z "$GRUPO" ]; then
    local -a filtrada=()
    local id pkg
    while IFS= read -r id; do
      [ "$(manifesto_valor "$id" grupo)" = "opcional" ] && continue
      pkg="$(manifesto_valor "$id" "$GER")"
      [ -n "$pkg" ] && filtrada+=("$pkg")
    done < <(manifesto_ids)
    lista=("${filtrada[@]}")
  fi

  [ "${#lista[@]}" -eq 0 ] && { aviso "nada a instalar"; return 0; }

  info "${#lista[@]} pacotes: ${lista[*]}"

  if [ "$SIMULAR" = "1" ]; then
    info "[simular] sudo $GER install -y ${lista[*]}"
    return 0
  fi

  # Instalacao em bloco unico: muito mais rapido que um pacote por vez e o
  # gerenciador resolve as dependencias de uma vez so.
  if [ "$GER" = "dnf" ]; then
    sudo dnf install -y "${lista[@]}"
  else
    sudo apt-get install -y "${lista[@]}"
  fi
}

# ------------------------------------------------------ ferramentas avulsas --
# Programas que nao vem em repositorio de distribuicao.
instalar_avulsos() {
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] instalaria uv, duckdb e DBeaver"
    return 0
  fi

  # uv: instalador oficial da Astral, vai para ~/.local/bin
  if ! command -v uv >/dev/null 2>&1; then
    info "instalando uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    ok "uv ja instalado"
  fi

  # DuckDB CLI: binario unico, sem dependencia.
  if ! command -v duckdb >/dev/null 2>&1; then
    info "instalando DuckDB CLI"
    curl -fsSL https://install.duckdb.org | sh
  else
    ok "duckdb ja instalado"
  fi

  # DBeaver: Flatpak evita o conflito de versao de JDK com o Spark.
  if command -v flatpak >/dev/null 2>&1; then
    if ! flatpak list | grep -qi dbeaver; then
      info "instalando DBeaver via Flatpak"
      flatpak install -y flathub io.dbeaver.DBeaverCommunity || \
        aviso "DBeaver falhou -- instale manualmente"
    else
      ok "DBeaver ja instalado"
    fi
  else
    aviso "flatpak indisponivel -- instale o DBeaver manualmente"
  fi
}

# ------------------------------------------------------------- pos-instalacao
pos_instalacao() {
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] habilitaria o docker e adicionaria o usuario ao grupo"
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && [ "$OS" = "linux" ]; then
    sudo systemctl enable --now docker 2>/dev/null || \
      aviso "nao consegui habilitar o servico docker"
    # Sem isso, todo comando docker exige sudo.
    if ! groups | grep -q docker; then
      sudo usermod -aG docker "$USER"
      aviso "adicionado ao grupo docker -- faca logout/login para valer"
    fi
  fi
}

# -------------------------------------------------------------------- fluxo --
configurar_repos
instalar_pacotes
instalar_avulsos
pos_instalacao

echo
info "setup concluido. Proximos passos:"
echo "  1. ./install.sh --extensoes   aplica configuracoes e extensoes"
echo "  2. gh auth login              reautentica o GitHub"
echo "  3. ./scripts/cofre.sh abrir   restaura o cofre de segredos"
