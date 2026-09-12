#!/usr/bin/env bash
# ============================================================================
# setup-macos.sh -- instala o stack de desenvolvimento no macOS (Homebrew)
#
# Le pacotes.yaml. Pacotes marcados com "cask: sim" vao por "brew install
# --cask" (aplicativos com interface grafica).
#
# Uso:
#   ./scripts/setup-macos.sh              instala tudo menos o grupo opcional
#   ./scripts/setup-macos.sh --grupo r    so o grupo r
#   ./scripts/setup-macos.sh --simular    mostra o que faria
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

[ "$(detectar_os)" = "macos" ] || morre "este script e para macOS"
[ "$SIMULAR" = "1" ] && aviso "modo simulacao: nada sera instalado"

# ---------------------------------------------------------------- homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] instalaria o Homebrew"
  else
    info "instalando Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon instala em /opt/homebrew, fora do PATH padrao.
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi
else
  ok "Homebrew ja instalado"
fi

# ---------------------------------------------------------------- instalar ---
# Separa em duas listas: formula (linha de comando) e cask (aplicativo).
formulas=()
casks=()

while IFS= read -r id; do
  [ -z "$id" ] && continue
  # Sem --grupo, pula o grupo opcional.
  if [ -z "$GRUPO" ] && [ "$(manifesto_valor "$id" grupo)" = "opcional" ]; then
    continue
  fi
  pkg="$(manifesto_valor "$id" brew)"
  [ -z "$pkg" ] && continue
  if eh_cask "$id"; then
    casks+=("$pkg")
  else
    formulas+=("$pkg")
  fi
done < <(manifesto_ids "$GRUPO")

info "${#formulas[@]} formulas, ${#casks[@]} casks"

if [ "$SIMULAR" = "1" ]; then
  [ "${#formulas[@]}" -gt 0 ] && info "[simular] brew install ${formulas[*]}"
  [ "${#casks[@]}" -gt 0 ]    && info "[simular] brew install --cask ${casks[*]}"
else
  # O brew nao aborta quando um pacote ja esta instalado, entao o bloco unico
  # e seguro e bem mais rapido que um por vez.
  [ "${#formulas[@]}" -gt 0 ] && brew install "${formulas[@]}"
  [ "${#casks[@]}" -gt 0 ]    && brew install --cask "${casks[@]}"
fi

# ----------------------------------------------------------- pos-instalacao --
if [ "$SIMULAR" != "1" ]; then
  # O openjdk do brew nao entra no PATH do sistema sozinho; o Spark precisa.
  if brew list openjdk@17 >/dev/null 2>&1; then
    prefixo="$(brew --prefix openjdk@17)"
    if [ ! -L /Library/Java/JavaVirtualMachines/openjdk-17.jdk ]; then
      aviso "para o Spark achar o JDK 17, rode:"
      echo "  sudo ln -sfn $prefixo/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk"
    fi
  fi
fi

echo
info "setup concluido. Proximos passos:"
echo "  1. ./install.sh --extensoes   aplica configuracoes e extensoes"
echo "  2. gh auth login              reautentica o GitHub"
echo "  3. ./scripts/cofre.sh abrir   restaura o cofre de segredos"
