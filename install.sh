#!/usr/bin/env bash
# ============================================================================
# install.sh -- aplica as configuracoes do kit nos caminhos do sistema
#
# Funciona em Linux, macOS, WSL e Git Bash. Idempotente: pode rodar quantas
# vezes quiser. Arquivo pre-existente vira backup com timestamp.
#
# Uso:
#   ./install.sh                  aplica o que o perfil.conf pedir
#   ./install.sh --extensoes      tambem instala extensoes do VS Code
#   ./install.sh --simular        mostra o que faria, sem escrever
#   ./install.sh --apenas r       so as configuracoes de R (Makevars, Rprofile)
#   ./install.sh --apenas "git r" mais de uma area, entre aspas
#
# Areas: git | vscode | r | kde
#
# O --apenas existe para a maquina que nao e sua: numa maquina de trabalho
# voce quer o Makevars (sem ele os pacotes de R compilam errado) sem que o
# kit sobrescreva o .gitconfig e as settings do VS Code da empresa.
# ============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"
carregar_perfil

SIMULAR=0
EXTENSOES=0

# Areas de configuracao aplicaveis.
#
# Sem --apenas, seguem o perfil: nao ha por que escrever um ~/.gitconfig numa
# maquina que nao pediu o stack "dev", nem settings do VS Code sem o stack
# "editor", nem Makevars sem o stack "r". Sem perfil nenhum, aplica todas --
# quem roda o install.sh cru esta pedindo o kit inteiro.
AREAS_VALIDAS="git vscode r kde"
AREAS=""
if [ "${PERFIL_CARREGADO:-0}" = "1" ]; then
  case " ${STACKS:-} " in *" dev "*)    AREAS="$AREAS git" ;; esac
  case " ${STACKS:-} " in *" editor "*) AREAS="$AREAS vscode" ;; esac
  case " ${STACKS:-} " in *" r "*)      AREAS="$AREAS r" ;; esac
  case " ${STACKS:-} " in *" produtividade "*) AREAS="$AREAS kde" ;; esac
  AREAS="${AREAS# }"
else
  AREAS="$AREAS_VALIDAS"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --simular)   SIMULAR=1; shift ;;
    # Aceito e ignorado: o install.sh nao pergunta nada. Existe para que
    # "--sim" possa ser passado a todos os scripts do fluxo sem que um deles
    # pare com "argumento desconhecido" no meio de uma instalacao desatendida.
    --sim)       shift ;;
    --extensoes) EXTENSOES=1; shift ;;
    --apenas)    AREAS="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

for area in $AREAS; do
  case " $AREAS_VALIDAS " in
    *" $area "*) ;;
    *) morre "area desconhecida: $area (validas: $AREAS_VALIDAS)" ;;
  esac
done

# quer_area <nome> -- verdadeiro quando aquela area deve ser aplicada.
quer_area() {
  case " $AREAS " in *" $1 "*) return 0 ;; esac
  return 1
}

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

if quer_area git; then

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
    {
      echo "# Configuracao Git especifica desta maquina. Nao versionada."
      echo "# Gerado por install.sh a partir do perfil.conf."
      # Identidade so entra se o perfil declarou. Sem isso, o git pergunta no
      # primeiro commit -- que e melhor do que assinar com o nome errado.
      if [ -n "${GIT_NOME:-}" ] || [ -n "${GIT_EMAIL:-}" ]; then
        echo "[user]"
        [ -n "${GIT_NOME:-}" ]  && echo "	name = $GIT_NOME"
        [ -n "${GIT_EMAIL:-}" ] && echo "	email = $GIT_EMAIL"
      fi
      echo "[credential]"
      echo "	helper = $helper"
    } > "$HOME/.gitconfig.local"
    ok "criado: $HOME/.gitconfig.local"
    if [ -z "${GIT_NOME:-}" ] && [ -z "${GIT_EMAIL:-}" ]; then
      aviso "identidade do git nao definida -- preencha GIT_NOME e GIT_EMAIL no perfil.conf"
      aviso "ou rode: ./scripts/configurar.sh"
    fi
  fi
else
  ok "ja existe: $HOME/.gitconfig.local"
fi

fi  # quer_area git

# --------------------------------------------------------------- VS Code ----

if quer_area vscode; then

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

fi  # quer_area vscode

# ----------------------------------------------------------------- R -------

if quer_area r; then

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

fi  # quer_area r

# ------------------------------------------------------------------ KDE ----

if quer_area kde; then

# Ctrl+Alt+Del abre o Monitor do Sistema, como no Windows.
#
# No KDE o padrao desse atalho e a tela de encerrar sessao. Mas quem aperta
# Ctrl+Alt+Del quase sempre quer ver o que travou a maquina, nao deslogar --
# e a tela de sessao continua acessivel pelo menu. O par de linhas mexe nas
# duas pontas: tira o atalho do logout e o da ao monitor.
#
# plasma-systemmonitor, e nao gnome-system-monitor: o do GNOME arrasta a
# pilha GTK inteira para uma maquina KDE para entregar a mesma janela.
if [ "$OS" != "linux" ] && [ "$OS" != "wsl" ]; then
  :
elif ! command -v kwriteconfig6 >/dev/null 2>&1; then
  ok "sem KDE Plasma 6 aqui -- atalho do Monitor do Sistema pulado"
elif [ "$SIMULAR" = "1" ]; then
  info "[simular] Ctrl+Alt+Del -> Monitor do Sistema (kglobalshortcutsrc)"
else
  kwriteconfig6 --file kglobalshortcutsrc     --group "services" --group "org.kde.plasma-systemmonitor.desktop"     --key "_launch" "Ctrl+Alt+Del"
  # O formato e "atual,padrao,descricao": "none" no primeiro campo desliga o
  # atalho sem perder qual era o padrao do KDE.
  kwriteconfig6 --file kglobalshortcutsrc     --group "ksmserver" --key "Log Out"     "none,Ctrl+Alt+Del,Mostrar tela para encerrar sessao"
  ok "Ctrl+Alt+Del -> Monitor do Sistema (vale no proximo login)"
fi

fi  # quer_area kde

# ------------------------------------------------------- extensoes VS Code --

if [ "$EXTENSOES" = "1" ] && quer_area vscode; then
  lista="$DOTFILES_RAIZ/config/vscode/extensions.txt"
  if ! command -v code >/dev/null 2>&1; then
    aviso 'comando "code" nao esta no PATH -- pulando extensoes.'
  elif [ ! -f "$lista" ]; then
    aviso "lista nao encontrada: $lista"
  else
    # A lista e dividida em secoes "[grupo]": instala so os grupos que o
    # perfil pediu em VSCODE_EXTENSOES. Quem nao escreve R nao espera a
    # extensao de R baixar.
    grupo_atual=""
    instalar_este=0
    while IFS= read -r linha; do
      ext="$(printf '%s' "$linha" | tr -d '[:space:]')"
      [ -z "$ext" ] && continue
      case "$ext" in
        '#'*) continue ;;
        '['*']')
          grupo_atual="${ext#[}"
          grupo_atual="${grupo_atual%]}"
          case " ${VSCODE_EXTENSOES:-} " in
            *" $grupo_atual "*) instalar_este=1; info "grupo: $grupo_atual" ;;
            *)                  instalar_este=0 ;;
          esac
          continue
          ;;
      esac
      [ "$instalar_este" = "1" ] || continue
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
if [ -z "$AREAS" ]; then
  ok "install concluido -- nenhuma area a aplicar para os stacks deste perfil."
  exit 0
fi
ok "install concluido (areas: $AREAS)."
# A dica precisa falar do que foi realmente aplicado: mandar conferir o git
# depois de um "--apenas r" so confunde. O "|| true" nao e decorativo: sob
# "set -e", a ultima dica que nao se aplica derrubaria o codigo de saida
# para 1 num install que deu certo.
quer_area git    && echo "Confira com:  git config --global --list" || true
quer_area r      && echo "Confira com:  R CMD config CFLAGS" || true
quer_area vscode && echo "Confira com:  code --list-extensions" || true
exit 0
