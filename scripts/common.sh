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
# detectar_os imprime um entre: linux, macos, wsl, gitbash, desconhecido
#
# Ordem importa: WSL tambem responde "Linux" em uname, entao o teste de WSL
# vem antes. Git Bash aparece como MINGW64_NT-*.
detectar_os() {
  local sistema
  sistema="$(uname -s)"
  case "$sistema" in
    Linux*)
      # /proc/version cita "microsoft" dentro do WSL (WSL1 e WSL2).
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
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
  local filtro="${1:-}"
  [ -f "$MANIFESTO" ] || morre "manifesto nao encontrado: $MANIFESTO"
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
  ' "$MANIFESTO"
}

# manifesto_valor <id> <chave>
#   Devolve o valor de uma chave do item. String vazia quando a chave nao
#   existe ou quando vale "-" (indisponivel naquele gerenciador).
manifesto_valor() {
  local alvo="$1" chave="$2"
  [ -f "$MANIFESTO" ] || morre "manifesto nao encontrado: $MANIFESTO"
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
  ' "$MANIFESTO"
}

# pacotes_para <gerenciador> [grupo]
#   Imprime, um por linha, o identificador nativo de cada pacote que existe
#   para aquele gerenciador. Pacotes marcados "-" sao silenciosamente pulados.
pacotes_para() {
  local ger="$1" grupo="${2:-}" id valor
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    valor="$(manifesto_valor "$id" "$ger")"
    [ -n "$valor" ] && printf '%s\n' "$valor"
  done < <(manifesto_ids "$grupo")
  # Sem este return, o status seria o do ultimo teste do laco -- que e falso
  # sempre que o ultimo pacote lido nao existe para este gerenciador.
  return 0
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
