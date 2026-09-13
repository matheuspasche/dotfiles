#!/usr/bin/env bash
# ============================================================================
# tema-kde.sh -- tema e papel de parede do KDE Plasma
#
# OPCIONAL e fora do fluxo principal: aparencia e gosto pessoal, nao
# infraestrutura. Nenhum outro script chama este.
#
# Uso:
#   ./scripts/tema-kde.sh --salvar     grava o tema ATUAL em config/kde/tema.conf
#   ./scripts/tema-kde.sh --aplicar    aplica o que estiver no tema.conf
#   ./scripts/tema-kde.sh --simular    mostra o que faria
#
# O tema em si (WhiteSur) vem do GitHub do autor, sempre do ramo atual -- nao
# ha versao fixa aqui. As imagens de papel de parede NAO sao versionadas: sao
# 31 MB de licenca desconhecida, entao o script cria as pastas e avisa.
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TEMA_CONF="$DOTFILES_RAIZ/config/kde/tema.conf"
SIMULAR=0
ACAO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --salvar)  ACAO=salvar; shift ;;
    --aplicar) ACAO=aplicar; shift ;;
    --simular) SIMULAR=1; shift ;;
    --sim)     shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

[ -z "$ACAO" ] && morre "escolha --salvar ou --aplicar (veja --help)"

# Plasma 6 e obrigatorio: as ferramentas plasma-apply-* sao dele.
if ! command -v plasma-apply-lookandfeel >/dev/null 2>&1; then
  morre "KDE Plasma 6 nao encontrado -- este script so serve para ele"
fi

executar() {
  if [ "$SIMULAR" = "1" ]; then
    echo "    [simular] $*"
    return 0
  fi
  "$@"
}

# --------------------------------------------------------------- salvar -----
# Le o estado REAL da sessao, e nao os defaults do pacote de tema: e comum
# desviar de um ou outro item (aqui, por exemplo, o estilo de widget e o
# Breeze e nao o kvantum-dark que o WhiteSur sugere).
if [ "$ACAO" = "salvar" ]; then
  ler() { kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null; }

  lookandfeel="$(ler kdeglobals KDE LookAndFeelPackage)"
  icones="$(ler kdeglobals Icons Theme)"
  cores="$(ler kdeglobals General ColorScheme)"
  widget="$(ler kdeglobals KDE widgetStyle)"
  plasma="$(ler plasmarc Theme name)"
  cursor="$(ler kcminputrc Mouse cursorTheme)"
  decor="$(ler kwinrc org.kde.kdecoration2 theme)"

  # Papel de parede: o que vale e o timer, se existir. O slideshow do proprio
  # KDE fica registrado no appletsrc mesmo quando nao esta ativo, entao ler de
  # la daria uma resposta errada -- foi o que aconteceu nesta maquina.
  modo="estatico"
  systemctl --user list-unit-files wallpaper-por-hora.timer >/dev/null 2>&1 &&
    modo="hora"

  mkdir -p "$(dirname "$TEMA_CONF")"
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] gravaria $TEMA_CONF"
  else
    cat > "$TEMA_CONF" <<EOF
# ============================================================================
# tema.conf -- aparencia do KDE Plasma, gerado por scripts/tema-kde.sh --salvar
# Aplique com: ./scripts/tema-kde.sh --aplicar
# ============================================================================

# Tema global. Baixado de github.com/vinceliuice/WhiteSur-kde quando faltar.
TEMA_LOOKANDFEEL="$lookandfeel"
TEMA_ICONES="$icones"
TEMA_CORES="$cores"
TEMA_PLASMA="$plasma"
TEMA_CURSOR="$cursor"
TEMA_DECORACAO="$decor"
# Estilo dos widgets. O WhiteSur sugere kvantum-dark; Breeze aqui e escolha.
TEMA_WIDGET="$widget"

# Papel de parede: "hora" troca conforme o periodo do dia (dawn/day/dusk/
# night) por um timer do systemd; "estatico" nao mexe em nada.
WALLPAPER_MODO="$modo"
WALLPAPER_PASTA="\$HOME/Pictures/wallpapers-dynamic"
EOF
    ok "tema atual gravado em $TEMA_CONF"
    grep -E "^TEMA_|^WALLPAPER_" "$TEMA_CONF" | sed 's/^/    /'
  fi
  exit 0
fi

# -------------------------------------------------------------- aplicar -----
[ -f "$TEMA_CONF" ] || morre "nao encontrei $TEMA_CONF -- rode --salvar antes"
# shellcheck disable=SC1090
source "$TEMA_CONF"

# baixar_tema <repo> <marcador> -- clona e roda o install.sh do autor.
#   Sempre o ramo atual, sem versao fixa: sao temas de comunidade, sem
#   release publicada, e um commit fixo aqui envelheceria calado.
baixar_tema() {
  local repo="$1" marcador="$2" dir

  [ -e "$marcador" ] && { ok "ja instalado: $repo"; return 0; }

  if [ "$SIMULAR" = "1" ]; then
    info "[simular] clonaria e instalaria $repo"
    return 0
  fi

  dir="$(mktemp -d)"
  info "baixando $repo"
  if ! git clone --depth=1 -q "https://github.com/$repo" "$dir/t" 2>/dev/null; then
    rm -rf "$dir"
    aviso "nao consegui baixar $repo"
    return 1
  fi
  ( cd "$dir/t" && ./install.sh >/dev/null 2>&1 ) ||
    aviso "o instalador de $repo retornou erro"
  rm -rf "$dir"
  return 0
}

info "aplicando tema: ${TEMA_LOOKANDFEEL:-<vazio>}"

# So baixa o que falta -- numa maquina que ja tem o tema, isto e no-op.
case "${TEMA_LOOKANDFEEL:-}" in
  *vinceliuice.WhiteSur*)
    baixar_tema vinceliuice/WhiteSur-kde \
      "$HOME/.local/share/plasma/look-and-feel/$TEMA_LOOKANDFEEL"
    baixar_tema vinceliuice/WhiteSur-icon-theme \
      "$HOME/.local/share/icons/${TEMA_ICONES:-WhiteSur-dark}"
    baixar_tema vinceliuice/WhiteSur-cursors \
      "$HOME/.local/share/icons/${TEMA_CURSOR:-WhiteSur-cursors}"
    ;;
esac

# O pacote look-and-feel ja carrega cores, icones, decoracao e tema do Plasma
# de uma vez. O resto abaixo e para os itens em que a sua sessao desviou dele.
#
# NUNCA com --resetLayout: o pacote do WhiteSur traz um layout de area de
# trabalho, e essa flag substituiria os seus paineis pelos do tema. Ela e
# opt-in justamente por isso, e aqui nao e passada em hipotese alguma.
if [ -n "${TEMA_LOOKANDFEEL:-}" ]; then
  executar plasma-apply-lookandfeel -a "$TEMA_LOOKANDFEEL"
fi

if [ -n "${TEMA_CURSOR:-}" ]; then
  executar plasma-apply-cursortheme "$TEMA_CURSOR"
fi

if [ -n "${TEMA_WIDGET:-}" ]; then
  executar kwriteconfig6 --file kdeglobals --group KDE \
    --key widgetStyle "$TEMA_WIDGET"
fi

ok "tema aplicado"

# ----------------------------------------------------------- papel de parede
if [ "${WALLPAPER_MODO:-estatico}" = "hora" ]; then
  pasta="$(eval echo "${WALLPAPER_PASTA:-$HOME/Pictures/wallpapers-dynamic}")"

  executar mkdir -p "$pasta"/dawn "$pasta"/day "$pasta"/dusk "$pasta"/night
  executar mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
  executar install -m 755 "$DOTFILES_RAIZ/config/kde/wallpaper-por-hora.sh" \
    "$HOME/.local/bin/wallpaper-por-hora.sh"
  executar install -m 644 "$DOTFILES_RAIZ/config/kde/wallpaper-por-hora.service" \
    "$HOME/.config/systemd/user/wallpaper-por-hora.service"
  executar install -m 644 "$DOTFILES_RAIZ/config/kde/wallpaper-por-hora.timer" \
    "$HOME/.config/systemd/user/wallpaper-por-hora.timer"
  executar systemctl --user daemon-reload
  executar systemctl --user enable --now wallpaper-por-hora.timer

  # As imagens nao vem no repositorio: sao dezenas de MB e de licenca que nao
  # e nossa para redistribuir. Elas viajam pelo cofre (config/segredos.lista
  # inclui Pictures/wallpapers-dynamic). Sem elas o script roda e nao faz
  # nada, o que e pior do que dizer na cara que faltam.
  if [ "$SIMULAR" != "1" ]; then
    total="$(find "$pasta" -type f -iname '*.jpg' 2>/dev/null | wc -l)"
    if [ "$total" -eq 0 ]; then
      aviso "nenhuma imagem em $pasta -- o papel de parede nao vai trocar"
      echo "    Elas viajam no cofre:  ./scripts/cofre.sh abrir"
      echo "    Ou ponha .jpg a mao nas quatro pastas: dawn/ day/ dusk/ night/"
    else
      ok "papel de parede por hora ativo ($total imagens)"
    fi
  fi
fi

echo
info "algumas mudancas so aparecem depois de sair e entrar na sessao."
exit 0
