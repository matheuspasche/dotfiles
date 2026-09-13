#!/usr/bin/env bash
# ============================================================================
# setup-linux.sh -- instala o stack de desenvolvimento no Fedora/Ubuntu
#
# Le pacotes.yaml (fonte unica da verdade) e instala com dnf ou apt, conforme
# a distribuicao. Tambem serve dentro do WSL.
#
# Uso:
#   ./scripts/setup-linux.sh              instala o que o perfil.conf pedir
#   ./scripts/setup-linux.sh --grupo r    so o grupo r, ignorando o perfil
#   ./scripts/setup-linux.sh --simular    mostra o que faria
#
# O que sera instalado vem de STACKS no perfil.conf. Sem perfil, so o basico.
# Para escolher: ./scripts/configurar.sh
# ============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
carregar_perfil

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

# Sem perfil e sem --grupo, o script nao adivinha o que voce quer. O padrao
# e o minimo (stack base), e ele avisa como escolher de verdade.
if [ "$PERFIL_CARREGADO" = "0" ] && [ -z "$GRUPO" ]; then
  echo
  aviso "nenhum perfil.conf encontrado."
  echo "   Sem ele, so o stack 'base' sera instalado (git, editor, utilitarios)."
  echo "   Para escolher o que instalar:  ./scripts/configurar.sh"
  echo
  if [ "$SIMULAR" != "1" ]; then
    printf "   Continuar so com o basico? [S/n] "
    read -r resposta
    case "$resposta" in
      [nN]*) info "rode ./scripts/configurar.sh e tente de novo"; exit 0 ;;
    esac
  fi
fi

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
      # Baixar o .repo direto e o que o "config-manager --add-repo" fazia. A
      # opcao foi removida no dnf5 (Fedora 41+), que quer "addrepo
      # --from-repofile="; curl funciona nas duas versoes e nao exige detectar
      # qual delas esta na maquina.
      if ! sudo curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
             -o /etc/yum.repos.d/docker-ce.repo; then
        # Repositorio de terceiro fora do ar nao pode derrubar a instalacao
        # inteira: o resto do manifesto continua valido.
        sudo rm -f /etc/yum.repos.d/docker-ce.repo
        aviso "nao foi possivel adicionar o repositorio do Docker; siga sem ele"
      fi
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
# resolver_java <gerenciador> <pacote-do-manifesto>
#   O pacote de JDK do manifesto e um numero fixo (ex.: java-17-openjdk-devel),
#   mas Fedora e Ubuntu descontinuam versoes antigas do OpenJDK a cada par de
#   releases -- foi exatamente isso que quebrou java-17-openjdk-devel no
#   Fedora 44 ("Nenhuma correspondencia para o argumento"). Em vez de fixar
#   um numero que expira, confere se o pacote pinado ainda existe e, se nao
#   existir mais, escolhe a versao numerada mais alta disponivel no lugar.
#   Nunca escolhe builds "latest"/pre-lancamento (java-latest-openjdk no
#   dnf): sao instaveis demais para um ambiente de trabalho.
resolver_java() {
  local ger="$1" pinado="$2" nome versao maior=0 pacote=""

  case "$ger" in
    dnf)
      if dnf list available "$pinado" >/dev/null 2>&1; then
        printf '%s\n' "$pinado"
        return 0
      fi
      while IFS= read -r nome; do
        # primeira coluna da saida do dnf, sem o sufixo de arquitetura
        # (".x86_64"): "java-25-openjdk-devel.x86_64" -> "java-25-openjdk-devel"
        nome="${nome%%[[:space:]]*}"
        nome="${nome%.*}"
        [[ "$nome" =~ ^java-([0-9]+)-openjdk-devel$ ]] || continue
        versao="${BASH_REMATCH[1]}"
        if [ "$versao" -gt "$maior" ]; then
          maior="$versao"
          pacote="$nome"
        fi
      done < <(dnf list available 'java-*-openjdk-devel' 2>/dev/null)
      ;;
    apt)
      if apt-cache show "$pinado" >/dev/null 2>&1; then
        printf '%s\n' "$pinado"
        return 0
      fi
      while IFS= read -r nome; do
        [[ "$nome" =~ ^openjdk-([0-9]+)-jdk$ ]] || continue
        versao="${BASH_REMATCH[1]}"
        if [ "$versao" -gt "$maior" ]; then
          maior="$versao"
          pacote="$nome"
        fi
      done < <(apt-cache pkgnames 'openjdk-' 2>/dev/null)
      ;;
  esac

  [ -n "$pacote" ] && printf '%s\n' "$pacote"
  return 0
}

instalar_pacotes() {
  local -a lista=()
  local -a grupos=()

  if [ -n "$GRUPO" ]; then
    # --grupo manda: instala exatamente aquele grupo.
    grupos=("$GRUPO")
  else
    # Sem --grupo, obedece o STACKS do perfil. NUNCA "tudo": instalar R,
    # Python e Docker numa maquina que so precisa de navegador nao e util
    # para ninguem.
    read -r -a grupos <<< "$STACKS"
  fi

  info "grupos: ${grupos[*]}"

  local g pkg
  for g in "${grupos[@]}"; do
    while IFS= read -r pkg; do
      [ -n "$pkg" ] && lista+=("$pkg")
    done < <(pacotes_para "$GER" "$g")
  done

  # Navegador: entra so o escolhido no perfil, nao os tres.
  if [ "$NAVEGADOR" != "nenhum" ] && [ -n "$NAVEGADOR" ]; then
    pkg="$(manifesto_valor "$NAVEGADOR" "$GER")"
    if [ -n "$pkg" ]; then
      lista+=("$pkg")
      info "navegador: $NAVEGADOR ($pkg)"
    else
      aviso "navegador '$NAVEGADOR' nao disponivel para $GER -- veja docs/"
    fi
  fi

  # O pacote de JDK pode ter saido do repositorio desde a ultima vez que o
  # manifesto foi atualizado (ver resolver_java acima). So mexe em quem bate
  # com o formato conhecido -- nunca troca um pacote que nao seja JDK.
  local i pacote_java
  for i in "${!lista[@]}"; do
    case "${lista[$i]}" in
      java-*-openjdk-devel|openjdk-*-jdk)
        pacote_java="$(resolver_java "$GER" "${lista[$i]}")"
        if [ -z "$pacote_java" ]; then
          aviso "nenhuma versao do OpenJDK disponivel -- pulando ${lista[$i]}"
          unset 'lista[i]'
        elif [ "$pacote_java" != "${lista[$i]}" ]; then
          aviso "${lista[$i]} nao existe mais no repositorio -- usando $pacote_java no lugar"
          lista[i]="$pacote_java"
        fi
        ;;
    esac
  done
  lista=("${lista[@]}")

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
# instalar_flatpak <id-flatpak> <rotulo>
#   Instala do Flathub o que nao existe no repositorio da distribuicao.
#   Ausencia de flatpak vira aviso, nao erro: e um programa a menos, nao um
#   motivo para abortar o resto do setup.
instalar_flatpak() {
  local app="$1" rotulo="$2"

  if ! command -v flatpak >/dev/null 2>&1; then
    aviso "flatpak indisponivel -- instale o $rotulo manualmente"
    return 0
  fi

  if flatpak list --app 2>/dev/null | grep -qi "$app"; then
    ok "$rotulo ja instalado"
    return 0
  fi

  info "instalando $rotulo via Flatpak"
  flatpak install -y flathub "$app" ||
    aviso "$rotulo falhou -- instale manualmente"
  return 0
}

# Programas que nao vem em repositorio de distribuicao.
instalar_avulsos() {
  # Cada ferramenta so entra se o stack correspondente estiver ligado. Numa
  # maquina que pediu apenas "base", nada disto e instalado.
  local quer_python=0 quer_dados=0 quer_escritorio=0 quer_opcional=0
  if [ -n "$GRUPO" ]; then
    [ "$GRUPO" = "python" ]     && quer_python=1
    [ "$GRUPO" = "dados" ]      && quer_dados=1
    [ "$GRUPO" = "escritorio" ] && quer_escritorio=1
    [ "$GRUPO" = "opcional" ]   && quer_opcional=1
  else
    tem_stack python     && quer_python=1
    tem_stack dados      && quer_dados=1
    tem_stack escritorio && quer_escritorio=1
    tem_stack opcional   && quer_opcional=1
  fi

  if [ "$quer_python" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o uv"
    elif command -v uv >/dev/null 2>&1; then
      ok "uv ja instalado"
    else
      # Instalador oficial da Astral; vai para ~/.local/bin, sem sudo. Sob
      # set -e, um curl que falha (rede instavel, proxy corporativo)
      # abortaria o setup-linux.sh inteiro -- inclusive o que vem depois do
      # bloco de Python e nao tem nada a ver com ele (DuckDB, DBeaver,
      # ONLYOFFICE, Obsidian, Docker). Mesmo tratamento que essas ferramentas
      # ja recebem: falha de terceiro vira aviso, nao aborta o resto.
      info "instalando uv"
      curl -LsSf https://astral.sh/uv/install.sh | sh ||
        aviso "nao consegui instalar o uv -- sem rede ou astral.sh bloqueado. Rode de novo, ou instale manualmente: https://docs.astral.sh/uv/"
    fi
  fi

  if [ "$quer_dados" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o DuckDB CLI e o DBeaver"
    else
      # DuckDB CLI: binario unico, sem dependencia.
      if command -v duckdb >/dev/null 2>&1; then
        ok "duckdb ja instalado"
      else
        info "instalando DuckDB CLI"
        curl -fsSL https://install.duckdb.org | sh ||
          aviso "nao consegui instalar o DuckDB CLI -- instale manualmente: https://duckdb.org"
      fi

      # DBeaver via Flatpak: evita conflito de versao de JDK com o Spark.
      instalar_flatpak io.dbeaver.DBeaverCommunity "DBeaver"
    fi
  fi

  # ONLYOFFICE e Obsidian nao existem no dnf nem no apt (ficam "-" no
  # manifesto, e o pacotes_para pula em silencio). Sem isto, quem escolhe
  # "escritorio" ou "opcional" no configurar.sh -- que promete os dois pelo
  # nome -- nao recebe nem o programa nem um aviso.
  if [ "$quer_escritorio" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o ONLYOFFICE"
    else
      instalar_flatpak org.onlyoffice.desktopeditors "ONLYOFFICE"
    fi
  fi

  if [ "$quer_opcional" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o Obsidian"
    else
      instalar_flatpak md.obsidian.Obsidian "Obsidian"
    fi
  fi

  [ "$quer_python" = "0" ] && [ "$quer_dados" = "0" ] &&
    [ "$quer_escritorio" = "0" ] && [ "$quer_opcional" = "0" ] &&
    ok "nenhuma ferramenta avulsa pedida"
  return 0
}

# ------------------------------------------------------------- pos-instalacao
pos_instalacao() {
  # So mexe no Docker se ele foi pedido: habilitar servico e alterar grupo de
  # usuario sao mudancas de sistema que ninguem quer de surpresa.
  if [ -z "$GRUPO" ] && ! tem_stack container; then
    return 0
  fi
  [ -n "$GRUPO" ] && [ "$GRUPO" != "container" ] && return 0

  if [ "$SIMULAR" = "1" ]; then
    info "[simular] habilitaria o docker e adicionaria o usuario ao grupo"
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && [ "$OS" = "linux" ]; then
    sudo systemctl enable --now docker 2>/dev/null ||       aviso "nao consegui habilitar o servico docker"
    # Sem isso, todo comando docker exige sudo.
    if ! groups | grep -q docker; then
      sudo usermod -aG docker "$USER"
      aviso "adicionado ao grupo docker -- faca logout/login para valer"
    fi
  fi
  return 0
}

# -------------------------------------------------------------------- fluxo --
configurar_repos
instalar_pacotes
instalar_avulsos
pos_instalacao

echo
info "setup concluido. Proximos passos:"
echo "  1. ./install.sh --extensoes   aplica configuracoes e extensoes"

# As bibliotecas sao passo separado: o setup-linux.sh instala o interpretador
# e o uv, nunca os pacotes. Sem lembrar aqui, quem segue o terminal -- e nao o
# README -- termina com Python instalado e "No module named pandas".
passo=2
if [ -n "${LIBS_PY:-}" ]; then
  echo "  $passo. ./scripts/setup-python.sh   bibliotecas de Python (~/.venvs/lab)"
  passo=$(( passo + 1 ))
fi
if [ -n "${LIBS_R:-}" ]; then
  echo "  $passo. ./scripts/setup-r.sh        bibliotecas de R"
  passo=$(( passo + 1 ))
fi

echo "  $passo. gh auth login              reautentica o GitHub"
passo=$(( passo + 1 ))
echo "  $passo. ./scripts/cofre.sh abrir   restaura o cofre de segredos"

# O venv e invisivel para o python3 do sistema. E a duvida numero um depois
# de instalar: "instalou, mas o import falha".
if [ -n "${LIBS_PY:-}" ]; then
  echo
  echo "  As bibliotecas de Python vao para ~/.venvs/lab, nao para o Python"
  echo "  do sistema. Para usa-las: source ~/.venvs/lab/bin/activate"
fi
