#!/usr/bin/env bash
# ============================================================================
# install.sh -- aplica as configuracoes do kit nos caminhos do sistema
#
# Funciona em Linux, macOS, WSL e Git Bash. Idempotente: pode rodar quantas
# vezes quiser. Arquivo pre-existente vira backup com timestamp.
#
# Uso:
#   ./install.sh              aplica tudo
#   ./install.sh --extensoes  tambem instala extensoes do VS Code
#   ./install.sh --simular    mostra o que faria, sem escrever
# ============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"

SIMULAR=0
EXTENSOES=0

for arg in "$@"; do
  case "$arg" in
    --simular)   SIMULAR=1 ;;
    --extensoes) EXTENSOES=1 ;;
    -h|--help)
      sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) morre "argumento desconhecido: $arg" ;;
  esac
done

OS="$(detectar_os)"
info "sistema detectado: $OS"
info "kit: $DOTFILES_RAIZ"
[ "$SIMULAR" = "1" ] && aviso "modo simulacao: nada sera escrito"

# aplicar <origem> <destino> <rotulo>
# Envolve ligar() para respeitar --simular.
aplicar() {
  local origem="$1" destino="$2" rotulo="$3"
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] $rotulo -> $destino"
    return 0
  fi
  ligar "$origem" "$destino"
}

# ------------------------------------------------------------------- git ----

aplicar "$DOTFILES_RAIZ/config/gitconfig"        "$HOME/.gitconfig"        "gitconfig"
aplicar "$DOTFILES_RAIZ/config/gitignore_global" "$HOME/.gitignore_global" "gitignore global"

# ~/.gitconfig.local guarda o que muda por maquina e nao vai para o repositorio.
# O gitconfig versionado faz include dele; sem o arquivo, o git reclama.
if [ ! -f "$HOME/.gitconfig.local" ]; then
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] criaria $HOME/.gitconfig.local"
  else
    # O credential helper muda por sistema -- por isso fica no arquivo local.
    case "$OS" in
      macos)   helper="osxkeychain" ;;
      gitbash) helper="manager" ;;
      *)       helper="cache --timeout=86400" ;;
    esac
    cat > "$HOME/.gitconfig.local" <<EOF
# Configuracao Git especifica desta maquina. Nao versionada.
[credential]
	helper = $helper
EOF
    ok "criado: $HOME/.gitconfig.local"
  fi
else
  ok "ja existe: $HOME/.gitconfig.local"
fi

# --------------------------------------------------------------- VS Code ----

# O diretorio de configuracao do VS Code muda em cada sistema.
case "$OS" in
  macos)   VSCODE_USER="$HOME/Library/Application Support/Code/User" ;;
  gitbash)
    # $APPDATA vem no formato Windows (C:\...); cygpath normaliza para POSIX
    # e evita caminho com separadores misturados.
    if command -v cygpath >/dev/null 2>&1; then
      VSCODE_USER="$(cygpath -u "$APPDATA")/Code/User"
    else
      VSCODE_USER="$APPDATA/Code/User"
    fi
    ;;
  wsl)
    # Dentro do WSL, o VS Code roda no lado Windows via Remote-WSL: a
    # configuracao que vale e a do perfil Windows, nao a do Linux.
    win_home="$(home_windows)"
    if [ -n "$win_home" ]; then
      VSCODE_USER="$win_home/AppData/Roaming/Code/User"
    else
      VSCODE_USER="$HOME/.config/Code/User"
    fi
    ;;
  *)       VSCODE_USER="$HOME/.config/Code/User" ;;
esac

aplicar "$DOTFILES_RAIZ/config/vscode/settings.json" \
        "$VSCODE_USER/settings.json" "VS Code settings.json"

if [ -f "$DOTFILES_RAIZ/config/vscode/keybindings.json" ]; then
  aplicar "$DOTFILES_RAIZ/config/vscode/keybindings.json" \
          "$VSCODE_USER/keybindings.json" "VS Code keybindings.json"
fi

# ----------------------------------------------------------------- R -------

# No Windows o R le Documents/.R/Makevars.win; no resto, ~/.R/Makevars.
if [ "$OS" = "gitbash" ]; then
  aplicar "$DOTFILES_RAIZ/config/Makevars.win" \
          "$HOME/Documents/.R/Makevars.win" "Makevars.win"
else
  aplicar "$DOTFILES_RAIZ/config/Makevars" "$HOME/.R/Makevars" "Makevars"
fi

if [ -f "$DOTFILES_RAIZ/config/Rprofile" ]; then
  aplicar "$DOTFILES_RAIZ/config/Rprofile" "$HOME/.Rprofile" ".Rprofile"
fi

# ------------------------------------------------------- extensoes VS Code --

if [ "$EXTENSOES" = "1" ]; then
  lista="$DOTFILES_RAIZ/config/vscode/extensions.txt"
  if ! command -v code >/dev/null 2>&1; then
    aviso 'comando "code" nao esta no PATH -- pulando extensoes.'
  elif [ ! -f "$lista" ]; then
    aviso "lista nao encontrada: $lista"
  else
    while IFS= read -r linha; do
      ext="$(printf '%s' "$linha" | tr -d '[:space:]')"
      [ -z "$ext" ] && continue
      case "$ext" in \#*) continue ;; esac
      if [ "$SIMULAR" = "1" ]; then
        info "[simular] code --install-extension $ext"
      else
        info "extensao: $ext"
        code --install-extension "$ext" --force >/dev/null 2>&1 || \
          aviso "falhou: $ext"
      fi
    done < "$lista"
    ok "extensoes processadas"
  fi
fi

echo
ok "install concluido."
echo "Confira com:  git config --global --list"
