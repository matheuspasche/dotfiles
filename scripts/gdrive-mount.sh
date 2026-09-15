#!/usr/bin/env bash
# ============================================================================
# gdrive-mount.sh -- Google Drive como pasta local via rclone (Linux)
#
# OPCIONAL e fora do fluxo principal: nenhum outro script chama este.
# Baseado em github.com/matheuspasche/tutorial-google-drive-kde-fedora.md.
#
# Por que rclone e nao o kio-gdrive nativo do KDE? O kio-gdrive usa uma
# credencial de API compartilhada entre todos os usuarios do KDE no mundo; ao
# ser limitada pelo Google, quebra com "Requested resource is forbidden"
# mesmo com login correto. O rclone usa credencial propria e nao sofre disso.
#
# Uso:
#   ./scripts/gdrive-mount.sh --instalar             instala o rclone
#   ./scripts/gdrive-mount.sh --configurar [nome]     assistente rclone config
#   ./scripts/gdrive-mount.sh --montar [nome] [pasta] monta uma vez (--daemon)
#   ./scripts/gdrive-mount.sh --desmontar [pasta]     desmonta
#   ./scripts/gdrive-mount.sh --servico [nome] [pasta] monta no login (systemd)
#   ./scripts/gdrive-mount.sh --status [pasta]        mostra o estado atual
#   ./scripts/gdrive-mount.sh --simular ...           so mostra o que faria
#
# "nome" e o remote do rclone (padrao: google_account); "pasta" e o ponto de
# montagem (padrao: ~/GoogleDrive).
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ACAO=""
SIMULAR=0
REMOTE="google_account"
PASTA="$HOME/GoogleDrive"

executar() {
  if [ "$SIMULAR" = "1" ]; then
    echo "    [simular] $*"
    return 0
  fi
  echo "    \$ $*"
  "$@"
}

# ------------------------------------------------------------------- ajuda --
ajuda() {
  sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

# -------------------------------------------------------------- argumentos --
[ $# -eq 0 ] && ajuda

case "$1" in
  --instalar|--configurar|--montar|--desmontar|--servico|--status)
    ACAO="${1#--}"; shift ;;
  -h|--help) ajuda ;;
  *) morre "argumento desconhecido: $1 (veja --help)" ;;
esac

# Os dois argumentos posicionais seguintes, quando presentes e nao forem
# flags, sao remote e pasta -- nessa ordem, como documentado no uso.
POSICAO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --simular) SIMULAR=1; shift ;;
    -h|--help) ajuda ;;
    --*) morre "argumento desconhecido: $1" ;;
    *)
      POSICAO=$(( POSICAO + 1 ))
      case "$POSICAO" in
        1) REMOTE="$1" ;;
        2) PASTA="$1" ;;
        *) morre "argumento inesperado: $1" ;;
      esac
      shift
      ;;
  esac
done
# "~" digitado a mao (fora de aspas o shell ja expande; entre aspas, nao).
PASTA="${PASTA/#\~/$HOME}"

[ "$SIMULAR" = "1" ] && aviso "modo simulacao: nada sera executado"

SERVICO="gdrive-mount@${REMOTE}.service"
SERVICO_ARQUIVO="$HOME/.config/systemd/user/${SERVICO%@*}@.service"

# ------------------------------------------------------------------ Linux ---
if [ "$(detectar_os)" = "gitbash" ]; then
  morre "este script e para Linux (rclone mount usa FUSE, indisponivel no Windows nativo)"
fi

# -------------------------------------------------------------- instalar ----
if [ "$ACAO" = "instalar" ]; then
  if command -v rclone >/dev/null 2>&1; then
    ok "rclone ja instalado: $(rclone version | head -1)"
    exit 0
  fi

  ger="$(detectar_gerenciador)"
  info "instalando rclone via $ger"
  case "$ger" in
    dnf)  executar sudo dnf install -y rclone ;;
    apt)  executar sudo apt-get install -y rclone ;;
    brew) executar brew install rclone ;;
    *)    morre "gerenciador de pacotes nao suportado para instalar rclone -- veja https://rclone.org/install/" ;;
  esac

  # FUSE 3 e exigido pelo "rclone mount"; a maioria das distros ja traz, mas
  # confirmar aqui evita um erro obscuro so na hora de montar.
  if [ "$ger" = "dnf" ] && ! rpm -q fuse3 >/dev/null 2>&1; then
    executar sudo dnf install -y fuse3
  elif [ "$ger" = "apt" ] && ! dpkg -s fuse3 >/dev/null 2>&1; then
    executar sudo apt-get install -y fuse3
  fi

  ok "rclone instalado"
  echo
  info "proximo passo: ./scripts/gdrive-mount.sh --configurar"
  exit 0
fi

command -v rclone >/dev/null 2>&1 || morre "rclone nao encontrado -- rode: ./scripts/gdrive-mount.sh --instalar"

# ------------------------------------------------------------- configurar ---
if [ "$ACAO" = "configurar" ]; then
  info "assistente interativo do rclone (remote: $REMOTE)"
  echo "   Escolha: n (novo remote) -> nome '$REMOTE' -> Google Drive ->"
  echo "   client_id/secret em branco -> scope 1 -> auto config y -> faca"
  echo "   login no navegador -> Shared Drive n -> y para confirmar -> q para sair."
  echo
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] rodaria: rclone config"
  else
    rclone config
  fi

  echo
  if rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
    ok "remote configurado: ${REMOTE}:"
    echo
    info "proximo passo: ./scripts/gdrive-mount.sh --montar $REMOTE"
  else
    aviso "remote '${REMOTE}:' nao apareceu em 'rclone listremotes' -- confira o nome usado"
  fi
  exit 0
fi

rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:" ||
  morre "remote '${REMOTE}:' nao existe -- rode: ./scripts/gdrive-mount.sh --configurar $REMOTE"

# ------------------------------------------------------------------ montar --
if [ "$ACAO" = "montar" ]; then
  if mountpoint -q "$PASTA" 2>/dev/null; then
    ok "ja montado: $PASTA"
    exit 0
  fi
  executar mkdir -p "$PASTA"
  executar rclone mount "${REMOTE}:" "$PASTA" --vfs-cache-mode writes --daemon
  ok "montado: $PASTA (remote ${REMOTE}:)"
  exit 0
fi

# --------------------------------------------------------------- desmontar --
if [ "$ACAO" = "desmontar" ]; then
  if ! mountpoint -q "$PASTA" 2>/dev/null; then
    ok "nao esta montado: $PASTA"
    exit 0
  fi
  executar fusermount -u "$PASTA"
  ok "desmontado: $PASTA"
  exit 0
fi

# ----------------------------------------------------------------- servico --
# Servico de usuario do systemd com template (@.service): o nome do remote
# fica no nome da instancia (%i), entao o mesmo arquivo serve para montar
# varias contas do Google, uma por unidade -- "gdrive-mount@trabalho.service",
# "gdrive-mount@pessoal.service" etc.
if [ "$ACAO" = "servico" ]; then
  executar mkdir -p "$HOME/.config/systemd/user"

  if [ "$SIMULAR" = "1" ]; then
    info "[simular] instalaria $SERVICO_ARQUIVO"
  else
    sed "s#{{PASTA}}#${PASTA}#g" \
      "$DOTFILES_RAIZ/config/gdrive/gdrive-mount@.service" \
      > "$SERVICO_ARQUIVO"
    ok "servico gravado: $SERVICO_ARQUIVO"
  fi

  executar systemctl --user daemon-reload
  executar systemctl --user enable --now "$SERVICO"
  ok "servico ativo: $SERVICO (monta $PASTA no login)"
  echo
  info "status:  systemctl --user status $SERVICO"
  exit 0
fi

# ------------------------------------------------------------------ status --
if [ "$ACAO" = "status" ]; then
  info "remote: $REMOTE"
  rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:" \
    && ok "configurado" || aviso "nao configurado"

  info "pasta: $PASTA"
  if mountpoint -q "$PASTA" 2>/dev/null; then
    ok "montado"
  else
    aviso "nao montado"
  fi

  if systemctl --user list-unit-files "$SERVICO" >/dev/null 2>&1 &&
     systemctl --user list-unit-files "$SERVICO" | grep -q "$SERVICO"; then
    systemctl --user status "$SERVICO" --no-pager -l | sed 's/^/    /'
  else
    aviso "servico $SERVICO nao instalado -- ./scripts/gdrive-mount.sh --servico $REMOTE $PASTA"
  fi
  exit 0
fi
