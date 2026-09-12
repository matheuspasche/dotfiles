#!/usr/bin/env bash
# ============================================================================
# setup-r.sh -- ambiente R no Linux e macOS: Makevars, BLAS e bibliotecas
#
# Gemeo POSIX do setup-r.ps1. A logica de instalacao e de diagnostico vive em
# scripts/r/instalar.R e scripts/r/verificar.R, compartilhada com o Windows.
#
# Uso:
#   ./scripts/setup-r.sh                     usa LIBS_R do perfil.conf
#   ./scripts/setup-r.sh --conjuntos "r-core r-rcpp"
#   ./scripts/setup-r.sh --listar
#   ./scripts/setup-r.sh --verificar
#   ./scripts/setup-r.sh --simular
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
carregar_perfil

SIMULAR=0
VERIFICAR=0
LISTAR=0
PRIMEIRO_PLANO=0
CONJUNTOS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --simular)          SIMULAR=1; shift ;;
    --verificar)        VERIFICAR=1; shift ;;
    --listar)           LISTAR=1; shift ;;
    --primeiro-plano)   PRIMEIRO_PLANO=1; shift ;;
    --conjuntos)        CONJUNTOS="${2:-}"; shift 2 ;;
    -h|--help)          sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

# ------------------------------------------------------------------ listar ---
if [ "$LISTAR" = "1" ]; then
  info "Conjuntos de bibliotecas R disponiveis:"
  echo
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    dep="$(conjunto_valor "$id" requer)"
    [ -n "$dep" ] && dep="  (requer $dep)"
    printf '  %-13s %3s min  %s%s\n' "$id" "$(conjunto_valor "$id" minutos)" \
      "$(conjunto_valor "$id" nome)" "$dep"
    printf '  %-13s          %s\n' "" "$(conjunto_valor "$id" pacotes)"
  done < <(conjuntos_de r)
  echo
  echo "Ligue os que quiser em LIBS_R no perfil.conf."
  exit 0
fi

# ---------------------------------------------------------------- R existe ---
command -v Rscript >/dev/null 2>&1 || morre \
  "R nao encontrado. Instale com: sudo dnf install R | sudo apt install r-base | brew install r"
ok "Rscript: $(command -v Rscript)"

# ------------------------------------------------------- biblioteca pessoal ---
# Sem uma biblioteca do usuario gravavel, todo install.packages tenta escrever
# na biblioteca do sistema e pede root -- o que nao deve ser o caminho normal.
LIB_USUARIO="$(Rscript -e 'cat(Sys.getenv("R_LIBS_USER"))' 2>/dev/null)"
if [ -n "$LIB_USUARIO" ] && [ ! -d "$LIB_USUARIO" ]; then
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] criaria a biblioteca do usuario: $LIB_USUARIO"
  else
    mkdir -p "$LIB_USUARIO"
    ok "biblioteca do usuario criada: $LIB_USUARIO"
  fi
else
  ok "biblioteca do usuario: ${LIB_USUARIO:-padrao do R}"
fi

# ------------------------------------------------------- Makevars com -j certo
NUCLEOS="$(Rscript -e 'cat(parallel::detectCores(logical = FALSE))' 2>/dev/null || echo 2)"
[ -z "$NUCLEOS" ] && NUCLEOS=2
# Deixa um nucleo livre: compilar com todos deixa a maquina inutilizavel.
J=$(( NUCLEOS > 1 ? NUCLEOS - 1 : 1 ))

MAKEVARS="$HOME/.R/Makevars"
if [ "$SIMULAR" = "1" ]; then
  info "[simular] ajustaria MAKEFLAGS=-j$J em $MAKEVARS"
elif [ -f "$MAKEVARS" ]; then
  if grep -q 'MAKEFLAGS' "$MAKEVARS"; then
    sed -i.bak "s/MAKEFLAGS[[:space:]]*=[[:space:]]*-j[0-9]*/MAKEFLAGS = -j$J/" "$MAKEVARS"
    rm -f "$MAKEVARS.bak"
    ok "MAKEFLAGS ajustado para -j$J ($NUCLEOS nucleos fisicos)"
  else
    printf '\nMAKEFLAGS = -j%s\n' "$J" >> "$MAKEVARS"
    ok "MAKEFLAGS = -j$J acrescentado"
  fi
else
  aviso "$MAKEVARS nao encontrado -- rode ./install.sh antes"
fi

# ------------------------------------------------------- toolchain e BLAS ----
GER="$(detectar_gerenciador)"

if ! command -v make >/dev/null 2>&1 || ! command -v g++ >/dev/null 2>&1; then
  aviso "toolchain de compilacao incompleto -- Rcpp nao vai compilar"
  case "$GER" in
    dnf) echo "    sudo dnf install gcc-c++ gcc-gfortran make" ;;
    apt) echo "    sudo apt install build-essential gfortran" ;;
    brew) echo "    xcode-select --install" ;;
  esac
fi

# Bibliotecas de sistema que varios pacotes R exigem para compilar. A falta
# delas produz erro de compilacao confuso, longe da causa real.
if [ "$(detectar_os)" != "macos" ]; then
  faltando=""
  case "$GER" in
    dnf)
      for p in libcurl-devel openssl-devel libxml2-devel fontconfig-devel \
               freetype-devel libpng-devel libtiff-devel libjpeg-turbo-devel \
               harfbuzz-devel fribidi-devel; do
        rpm -q "$p" >/dev/null 2>&1 || faltando="$faltando $p"
      done
      ;;
    apt)
      for p in libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev \
               libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
               libharfbuzz-dev libfribidi-dev; do
        dpkg -s "$p" >/dev/null 2>&1 || faltando="$faltando $p"
      done
      ;;
  esac
  if [ -n "$faltando" ]; then
    aviso "bibliotecas de sistema ausentes (tidyverse e afins nao compilam sem elas):"
    echo "    sudo $GER install -y$faltando"
    if [ "$SIMULAR" != "1" ]; then
      printf '    instalar agora? [s/N] '
      read -r resposta
      case "$resposta" in
        [sS]*)
          if [ "$GER" = "dnf" ]; then
            # shellcheck disable=SC2086
            sudo dnf install -y $faltando
          else
            # shellcheck disable=SC2086
            sudo apt-get install -y $faltando
          fi
          ;;
        *) aviso "pulado -- alguns pacotes R podem falhar" ;;
      esac
    fi
  else
    ok "bibliotecas de sistema para compilar pacotes R: presentes"
  fi
fi

# --------------------------------------------------------------- verificar ---
if [ "$VERIFICAR" = "1" ]; then
  echo
  info "diagnostico do ambiente R"
  Rscript "$DOTFILES_RAIZ/scripts/r/verificar.R"
  exit $?
fi

# ------------------------------------------------------------- bibliotecas ---
ESCOLHA="${CONJUNTOS:-$LIBS_R}"

if [ -z "$ESCOLHA" ]; then
  echo
  aviso "nenhum conjunto de bibliotecas R escolhido."
  echo "Defina LIBS_R no perfil.conf, ou passe --conjuntos."
  echo "Veja as opcoes com: ./scripts/setup-r.sh --listar"
  exit 0
fi

# Resolve dependencias declaradas em "requer", sem repetir conjunto.
resolvidos=""
for id in $ESCOLHA; do
  if [ -z "$(conjunto_valor "$id" nome)" ]; then
    aviso "conjunto desconhecido, ignorado: $id"
    continue
  fi
  dep="$(conjunto_valor "$id" requer)"
  if [ -n "$dep" ]; then
    case " $resolvidos " in *" $dep "*) ;; *) resolvidos="$resolvidos $dep" ;; esac
  fi
  case " $resolvidos " in *" $id "*) ;; *) resolvidos="$resolvidos $id" ;; esac
done

pacotes=""
minutos=0
for id in $resolvidos; do
  pacotes="$pacotes $(conjunto_valor "$id" pacotes)"
  m="$(conjunto_valor "$id" minutos)"
  [ -n "$m" ] && minutos=$(( minutos + m ))
done

# Remove duplicatas preservando a ordem.
pacotes="$(printf '%s\n' $pacotes | awk '!visto[$0]++' | tr '\n' ' ')"
total="$(printf '%s\n' $pacotes | grep -c .)"

echo
info "$(printf '%s\n' $resolvidos | grep -c .) conjunto(s), $total pacotes, ~$minutos min"
for id in $resolvidos; do echo "    $id -- $(conjunto_valor "$id" nome)"; done

if [ "$SIMULAR" = "1" ]; then
  info "[simular] Rscript instalar.R $pacotes"
  exit 0
fi

INSTALADOR="$DOTFILES_RAIZ/scripts/r/instalar.R"

if [ "$LIBS_EM_SEGUNDO_PLANO" = "sim" ] && [ "$PRIMEIRO_PLANO" = "0" ]; then
  mkdir -p "$DOTFILES_RAIZ/logs"
  LOG="$DOTFILES_RAIZ/logs/r-$(date +%Y%m%d-%H%M%S).log"
  # nohup mantem a compilacao viva depois que o terminal fechar.
  # shellcheck disable=SC2086
  nohup Rscript "$INSTALADOR" $pacotes > "$LOG" 2>&1 &
  echo
  ok "instalacao rodando em segundo plano (PID $!, ~$minutos min)"
  echo "    log:  $LOG"
  echo "    siga: tail -f '$LOG'"
  echo "    depois: ./scripts/setup-r.sh --verificar"
else
  # shellcheck disable=SC2086
  Rscript "$INSTALADOR" $pacotes
  codigo=$?
  echo
  if [ "$codigo" -eq 0 ]; then
    ok "bibliotecas instaladas"
    Rscript "$DOTFILES_RAIZ/scripts/r/verificar.R"
  else
    aviso "alguns pacotes falharam -- veja a saida acima"
    exit "$codigo"
  fi
fi
