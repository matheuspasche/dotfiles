#!/usr/bin/env bash
# ============================================================================
# common.sh -- biblioteca compartilhada dos scripts POSIX do kit
#
# Fornece: deteccao de ambiente, log colorido, helpers de link simbolico e
# leitura do manifesto pacotes.yaml.
#
# Uso:  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# Funciona em: Linux, macOS, Git Bash (Windows) e WSL.
# ============================================================================

set -o pipefail

# ---------------------------------------------------------------- caminhos --
# Raiz do repositorio, resolvida a partir da localizacao deste arquivo, para
# que os scripts funcionem chamados de qualquer diretorio.
DOTFILES_RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_RAIZ
MANIFESTO="${DOTFILES_RAIZ}/pacotes.yaml"
export MANIFESTO
BIBLIOTECAS="${DOTFILES_RAIZ}/bibliotecas.yaml"
export BIBLIOTECAS
PERFIL="${DOTFILES_RAIZ}/perfil.conf"
export PERFIL

# ------------------------------------------------------------------- cores --
# Só emite cor quando a saida e um terminal; em pipe/CI fica texto puro.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _C_VERDE=$'\033[0;32m'; _C_AMAR=$'\033[0;33m'; _C_VERM=$'\033[0;31m'
  _C_AZUL=$'\033[0;34m';  _C_OFF=$'\033[0m'
else
  _C_VERDE=''; _C_AMAR=''; _C_VERM=''; _C_AZUL=''; _C_OFF=''
fi

info()  { printf '%s==>%s %s\n' "$_C_AZUL"  "$_C_OFF" "$*"; }
ok()    { printf '%s ok %s %s\n' "$_C_VERDE" "$_C_OFF" "$*"; }
aviso() { printf '%saviso%s %s\n' "$_C_AMAR" "$_C_OFF" "$*" >&2; }
erro()  { printf '%serro %s %s\n' "$_C_VERM" "$_C_OFF" "$*" >&2; }
morre() { erro "$*"; exit 1; }

# --------------------------------------------------------------- ambiente ---
# eh_container -- verdadeiro dentro de container (Docker, Podman, toolbox).
#
# Importa porque o Docker Desktop no Windows roda os containers sobre um
# kernel WSL2: sem este teste, /proc/version faz o codigo concluir "WSL" e
# tentar falar com o cmd.exe do Windows, que nao existe la dentro.
eh_container() {
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  grep -qE '/(docker|lxc|containerd)/' /proc/1/cgroup 2>/dev/null && return 0
  [ "${container:-}" = "podman" ] && return 0
  return 1
}

# detectar_os imprime um entre: linux, macos, wsl, gitbash, desconhecido
#
# Ordem importa: container antes de WSL (o kernel pode ser o mesmo) e WSL
# antes de linux (WSL tambem responde "Linux" em uname). Git Bash aparece
# como MINGW64_NT-*.
detectar_os() {
  local sistema
  sistema="$(uname -s)"
  case "$sistema" in
    Linux*)
      # Dentro de container o sabor do kernel do host e irrelevante: o que
      # vale sao os caminhos Linux.
      if eh_container; then
        echo linux
      # /proc/version cita "microsoft" dentro do WSL (WSL1 e WSL2).
      elif grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    Darwin*)            echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo gitbash ;;
    *)                  echo desconhecido ;;
  esac
}

# Verdadeiro quando o ambiente roda sobre um kernel/host Windows, ou seja
# quando os caminhos de configuracao do Windows estao acessiveis.
eh_windows_host() {
  local os; os="$(detectar_os)"
  [ "$os" = "gitbash" ] || [ "$os" = "wsl" ]
}

# Gerenciador de pacotes nativo do ambiente atual: dnf, apt, brew, winget ou
# vazio quando nao ha um utilizavel (ex.: WSL antes de configurado).
detectar_gerenciador() {
  case "$(detectar_os)" in
    linux|wsl)
      if command -v dnf >/dev/null 2>&1;     then echo dnf
      elif command -v apt-get >/dev/null 2>&1; then echo apt
      else echo ""; fi
      ;;
    macos)
      command -v brew >/dev/null 2>&1 && echo brew || echo ""
      ;;
    gitbash)
      command -v winget >/dev/null 2>&1 && echo winget || echo ""
      ;;
    *) echo "" ;;
  esac
}

# Diretorio HOME do usuario Windows, visto de dentro de Git Bash ou WSL.
# Devolve string vazia quando nao ha host Windows ou nao foi possivel achar.
home_windows() {
  case "$(detectar_os)" in
    gitbash)
      # Em Git Bash, $HOME ja e o perfil do usuario Windows.
      printf '%s' "$HOME"
      ;;
    wsl)
      # Pergunta ao proprio Windows qual e o perfil e traduz para caminho WSL.
      local perfil
      perfil="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')"
      [ -z "$perfil" ] && return 0
      if command -v wslpath >/dev/null 2>&1; then
        wslpath -u "$perfil" 2>/dev/null
      fi
      ;;
    *) printf '' ;;
  esac
}

# ------------------------------------------------------------- manifesto ----
# manifesto_ids [grupo]
#   Lista os ids de pacote do manifesto. Com argumento, filtra pelo grupo.
manifesto_ids() {
  local filtro="${1:-}" arquivo="${2:-$MANIFESTO}"
  [ -f "$arquivo" ] || morre "manifesto nao encontrado: $arquivo"
  awk -v filtro="$filtro" '
    # Início de um novo item da lista.
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      if (id != "" && (filtro == "" || grupo == filtro)) print id
      id = $0; sub(/^[^:]*:[[:space:]]*/, "", id); gsub(/"/, "", id)
      grupo = ""
      next
    }
    /^[[:space:]]+grupo:[[:space:]]*/ {
      grupo = $0; sub(/^[^:]*:[[:space:]]*/, "", grupo); gsub(/"/, "", grupo)
      next
    }
    END { if (id != "" && (filtro == "" || grupo == filtro)) print id }
  ' "$arquivo"
}

# manifesto_grupos -- lista, sem repetir, os grupos declarados no manifesto.
manifesto_grupos() {
  local arquivo="${1:-$MANIFESTO}"
  [ -f "$arquivo" ] || morre "manifesto nao encontrado: $arquivo"
  awk '/^[[:space:]]+grupo:[[:space:]]*/ {
         g = $0; sub(/^[^:]*:[[:space:]]*/, "", g); gsub(/"/, "", g)
         sub(/[[:space:]]+$/, "", g)
         if (!(g in visto)) { visto[g]; print g }
       }' "$arquivo"
}

# manifesto_valor <id> <chave>
#   Devolve o valor de uma chave do item. String vazia quando a chave nao
#   existe ou quando vale "-" (indisponivel naquele gerenciador).
manifesto_valor() {
  local alvo="$1" chave="$2" arquivo="${3:-$MANIFESTO}"
  [ -f "$arquivo" ] || morre "manifesto nao encontrado: $arquivo"
  awk -v alvo="$alvo" -v chave="$chave" '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      atual = $0; sub(/^[^:]*:[[:space:]]*/, "", atual); gsub(/"/, "", atual)
      dentro = (atual == alvo)
      next
    }
    dentro {
      linha = $0
      sub(/^[[:space:]]+/, "", linha)
      if (index(linha, chave ":") == 1) {
        valor = linha; sub(/^[^:]*:[[:space:]]*/, "", valor)
        gsub(/"/, "", valor)
        sub(/[[:space:]]+$/, "", valor)
        if (valor != "-") print valor
        exit
      }
    }
  ' "$arquivo"
}

# pacotes_para <gerenciador> [grupo]
#   Imprime, um por linha, o identificador nativo de cada pacote que existe
#   para aquele gerenciador. Pacotes marcados "-" sao silenciosamente pulados.
pacotes_para() {
  local ger="$1" grupo="${2:-}" id valor
  local -a partes
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    valor="$(manifesto_valor "$id" "$ger")"
    [ -z "$valor" ] && continue
    # Um id pode valer varios pacotes nativos (ex.: "kate spectacle filelight
    # kcalc"). Sem este split, o chamador recebe a linha inteira como um
    # elemento so de array, e "apt-get install -y" tenta instalar um pacote
    # cujo nome tem espaco dentro -- que nunca existe.
    read -ra partes <<< "$valor"
    printf '%s\n' "${partes[@]}"
  done < <(manifesto_ids "$grupo")
  # Sem este return, o status seria o do ultimo teste do laco -- que e falso
  # sempre que o ultimo pacote lido nao existe para este gerenciador.
  return 0
}

# ------------------------------------------------------------ bibliotecas ---
# conjuntos_de <linguagem>
#   Lista os ids de conjunto de bibliotecas daquela linguagem (r | python).
conjuntos_de() {
  local linguagem="$1" id
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if [ "$(manifesto_valor "$id" linguagem "$BIBLIOTECAS")" = "$linguagem" ]; then
      printf '%s\n' "$id"
    fi
  done < <(manifesto_ids "" "$BIBLIOTECAS")
  return 0
}

# conjunto_valor <id> <chave> -- le uma chave de um conjunto de bibliotecas.
conjunto_valor() {
  manifesto_valor "$1" "$2" "$BIBLIOTECAS"
}

# ----------------------------------------------------------------- perfil ---
# carregar_perfil [caminho]
#   Le perfil.conf definindo as variaveis nele. Quando o arquivo nao existe,
#   aplica padroes conservadores: instala o basico e nao mexe em biblioteca
#   nenhuma. Assim o kit funciona recem-clonado, sem configuracao.
carregar_perfil() {
  local arquivo="${1:-$PERFIL}"

  # Padroes. Definidos antes do source para que o arquivo do usuario mande.
  GIT_NOME="${GIT_NOME:-}"
  GIT_EMAIL="${GIT_EMAIL:-}"
  GIT_ASSINAR="${GIT_ASSINAR:-nao}"
  STACKS="${STACKS:-base}"
  LIBS_R="${LIBS_R:-}"
  LIBS_PY="${LIBS_PY:-}"
  LIBS_EM_SEGUNDO_PLANO="${LIBS_EM_SEGUNDO_PLANO:-sim}"
  NAVEGADOR="${NAVEGADOR:-nenhum}"
  VSCODE_EXTENSOES="${VSCODE_EXTENSOES:-base}"
  FEDORA_RPMFUSION="${FEDORA_RPMFUSION:-sim}"
  FEDORA_CODECS="${FEDORA_CODECS:-sim}"
  FEDORA_GPU="${FEDORA_GPU:-sim}"
  FEDORA_FIRMWARE="${FEDORA_FIRMWARE:-sim}"
  FEDORA_FONTES_MS="${FEDORA_FONTES_MS:-nao}"
  FEDORA_DNF_RAPIDO="${FEDORA_DNF_RAPIDO:-sim}"
  COFRE_DESTINO="${COFRE_DESTINO:-}"
  SNAPSHOT_DESTINO="${SNAPSHOT_DESTINO:-}"

  if [ -f "$arquivo" ]; then
    # O arquivo e so CHAVE="valor". Uma verificacao rapida evita que um
    # perfil editado a mao com um comando dentro seja executado em silencio.
    if grep -qvE '^[[:space:]]*(#.*)?$|^[A-Z_][A-Z0-9_]*="[^"$`]*"[[:space:]]*(#.*)?$' "$arquivo"; then
      morre "perfil.conf tem linha fora do formato CHAVE=\"valor\". Corrija ou rode scripts/configurar.sh"
    fi
    # shellcheck disable=SC1090
    . "$arquivo"
    PERFIL_CARREGADO=1
  else
    PERFIL_CARREGADO=0
  fi
  return 0
}

# tem_stack <nome> -- verdadeiro quando o stack esta ligado no perfil.
tem_stack() {
  case " ${STACKS:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# eh_cask <id> -- verdadeiro quando o pacote deve ir por "brew install --cask"
eh_cask() {
  [ "$(manifesto_valor "$1" cask)" = "sim" ]
}

# ------------------------------------------------------------------ links ---
# ligar <origem> <destino>
#   Cria link simbolico de <destino> apontando para <origem>. Se ja existir
#   algo em <destino>, guarda um backup com timestamp antes de substituir.
#   Em Git Bash, onde symlink costuma falhar sem privilegio, cai para copia.
ligar() {
  local origem="$1" destino="$2"
  [ -e "$origem" ] || { aviso "origem inexistente, pulando: $origem"; return 0; }

  mkdir -p "$(dirname "$destino")"

  # Já aponta para o lugar certo: nada a fazer.
  if [ -L "$destino" ] && [ "$(readlink "$destino")" = "$origem" ]; then
    ok "ja ligado: $destino"
    return 0
  fi

  if [ -e "$destino" ] || [ -L "$destino" ]; then
    local backup="${destino}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$destino" "$backup"
    aviso "backup do arquivo anterior: $backup"
  fi

  if ln -s "$origem" "$destino" 2>/dev/null; then
    ok "link: $destino -> $origem"
  else
    # Git Bash sem modo desenvolvedor: symlink nao e permitido.
    cp -r "$origem" "$destino"
    aviso "symlink indisponivel, copiado: $destino"
  fi
}

# Exporta as funcoes para subshells que facam source indireto.
export -f detectar_os detectar_gerenciador eh_windows_host home_windows 2>/dev/null || true
