#!/usr/bin/env bash
# ============================================================================
# setup-python.sh -- ambiente Python no Linux e macOS
#
# Gemeo POSIX do setup-python.ps1. O diagnostico vive em
# scripts/py/verificar.py, compartilhado com o Windows.
#
# Uso:
#   ./scripts/setup-python.sh                      usa LIBS_PY do perfil.conf
#   ./scripts/setup-python.sh --conjuntos "py-core py-ml"
#   ./scripts/setup-python.sh --listar
#   ./scripts/setup-python.sh --verificar
#   ./scripts/setup-python.sh --simular
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
carregar_perfil

SIMULAR=0
VERIFICAR=0
LISTAR=0
PRIMEIRO_PLANO=0
CONJUNTOS=""
AMBIENTE="lab"

while [ $# -gt 0 ]; do
  case "$1" in
    --simular)        SIMULAR=1; shift ;;
    # Aceito e ignorado: este script nao pergunta nada. Existe para que
    # "--sim" possa ser passado a todos os scripts do fluxo sem que um deles
    # pare com "argumento desconhecido" no meio de uma instalacao desatendida.
    --sim)            shift ;;
    --verificar)      VERIFICAR=1; shift ;;
    --listar)         LISTAR=1; shift ;;
    --primeiro-plano) PRIMEIRO_PLANO=1; shift ;;
    --conjuntos)      CONJUNTOS="${2:-}"; shift 2 ;;
    --ambiente)       AMBIENTE="${2:-lab}"; shift 2 ;;
    -h|--help)        sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

VENV="$HOME/.venvs/$AMBIENTE"
PYTHON_VENV="$VENV/bin/python"

# ------------------------------------------------------------------ listar ---
if [ "$LISTAR" = "1" ]; then
  info "Conjuntos de bibliotecas Python disponiveis:"
  echo
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    dep="$(conjunto_valor "$id" requer)"
    [ -n "$dep" ] && dep="  (requer $dep)"
    printf '  %-13s %3s min  %s%s\n' "$id" "$(conjunto_valor "$id" minutos)" \
      "$(conjunto_valor "$id" nome)" "$dep"
    printf '  %-13s          %s\n' "" "$(conjunto_valor "$id" pacotes)"
  done < <(conjuntos_de python)
  echo
  echo "Ligue os que quiser em LIBS_PY no perfil.conf."
  exit 0
fi

# ---------------------------------------------------------------------- uv ---
if ! command -v uv >/dev/null 2>&1; then
  if [ "$SIMULAR" = "1" ]; then
    info "[simular] instalaria o uv"
  else
    info "instalando uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # O instalador poe o binario em ~/.local/bin, que nem sempre esta no PATH
    # da sessao corrente.
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

if command -v uv >/dev/null 2>&1; then
  ok "uv: $(uv --version)"
elif [ "$SIMULAR" != "1" ]; then
  aviso "uv instalado mas fora do PATH -- acrescente ~/.local/bin e rode de novo"
  exit 1
fi

# ~/.local/bin no PATH permanente, para o uv sobreviver ao proximo terminal.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  if ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] acrescentaria ~/.local/bin ao PATH em $rc"
    else
      printf '\n# ~/.local/bin no PATH -- acrescentado por scripts/setup-python.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      ok "~/.local/bin acrescentado ao PATH em $rc"
    fi
  fi
done

# ----------------------------------------------------------- ambiente base ---
if [ "$SIMULAR" = "1" ]; then
  info "[simular] criaria o ambiente $VENV"
elif [ -x "$PYTHON_VENV" ]; then
  ok "ambiente ja existe: $VENV"
else
  mkdir -p "$HOME/.venvs"
  info "criando ambiente base em $VENV"
  # --seed instala pip: varias ferramentas ainda assumem que ele existe.
  uv venv "$VENV" --seed || morre "uv venv falhou"
  ok "ambiente criado: $VENV"
fi

# --------------------------------------------------------------- verificar ---
if [ "$VERIFICAR" = "1" ]; then
  PY="$PYTHON_VENV"
  [ -x "$PY" ] || PY="$(command -v python3 || command -v python)"
  echo
  info "diagnostico do ambiente Python"
  "$PY" "$DOTFILES_RAIZ/scripts/py/verificar.py"
  exit $?
fi

# ------------------------------------------------------------- bibliotecas ---
ESCOLHA="${CONJUNTOS:-$LIBS_PY}"

if [ -z "$ESCOLHA" ]; then
  echo
  aviso "nenhum conjunto de bibliotecas Python escolhido."
  echo "Defina LIBS_PY no perfil.conf, ou passe --conjuntos."
  echo "Veja as opcoes com: ./scripts/setup-python.sh --listar"
  exit 0
fi

resolvidos=""
tem_notebook=0
tem_spark=0
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
  [ "$id" = "py-notebook" ] && tem_notebook=1
  [ "$id" = "py-spark" ] && tem_spark=1
done

pacotes=""
minutos=0
for id in $resolvidos; do
  pacotes="$pacotes $(conjunto_valor "$id" pacotes)"
  m="$(conjunto_valor "$id" minutos)"
  [ -n "$m" ] && minutos=$(( minutos + m ))
done
pacotes="$(printf '%s\n' $pacotes | awk '!visto[$0]++' | tr '\n' ' ')"
total="$(printf '%s\n' $pacotes | grep -c .)"

echo
info "$(printf '%s\n' $resolvidos | grep -c .) conjunto(s), $total pacotes, ~$minutos min"
for id in $resolvidos; do echo "    $id -- $(conjunto_valor "$id" nome)"; done

if [ "$SIMULAR" = "1" ]; then
  info "[simular] uv pip install --python $PYTHON_VENV $pacotes"
  [ "$tem_notebook" = "1" ] && info "[simular] registraria o kernel do Jupyter '$AMBIENTE'"
  [ "$tem_spark" = "1" ] && info "[simular] configuraria JAVA_HOME e PYSPARK_PYTHON"
  exit 0
fi

if [ "$LIBS_EM_SEGUNDO_PLANO" = "sim" ] && [ "$PRIMEIRO_PLANO" = "0" ]; then
  mkdir -p "$DOTFILES_RAIZ/logs"
  LOG="$DOTFILES_RAIZ/logs/python-$(date +%Y%m%d-%H%M%S).log"
  # shellcheck disable=SC2086
  nohup uv pip install --python "$PYTHON_VENV" $pacotes > "$LOG" 2>&1 &
  ok "instalacao rodando em segundo plano (PID $!, ~$minutos min)"
  echo "    log:  $LOG"
  echo "    siga: tail -f '$LOG'"
else
  info "instalando"
  # shellcheck disable=SC2086
  uv pip install --python "$PYTHON_VENV" $pacotes || morre "instalacao falhou"
  ok "bibliotecas instaladas"

  # Sem o kernel registrado, o ambiente nao aparece no seletor de notebook do
  # VS Code -- o motivo mais comum de "o VS Code nao acha meu venv".
  if [ "$tem_notebook" = "1" ]; then
    info "registrando kernel do Jupyter"
    if "$PYTHON_VENV" -m ipykernel install --user --name "$AMBIENTE" \
         --display-name "Python ($AMBIENTE)" >/dev/null 2>&1; then
      ok "kernel registrado: Python ($AMBIENTE)"
    else
      aviso "nao consegui registrar o kernel"
    fi
  fi
fi

# -------------------------------------------------------------------- Spark --
if [ "$tem_spark" = "1" ]; then
  echo
  info "configurando o Spark"

  if [ -z "${JAVA_HOME:-}" ]; then
    # No Linux, o caminho canonico sai do proprio binario java resolvido.
    if command -v java >/dev/null 2>&1; then
      JAVA_REAL="$(readlink -f "$(command -v java)" 2>/dev/null)"
      JAVA_DETECTADO="$(dirname "$(dirname "$JAVA_REAL")")"
    else
      JAVA_DETECTADO=""
    fi

    if [ -n "$JAVA_DETECTADO" ] && [ -d "$JAVA_DETECTADO" ]; then
      for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        if ! grep -q 'JAVA_HOME' "$rc" 2>/dev/null; then
          printf '\n# JAVA_HOME para o Spark -- acrescentado por scripts/setup-python.sh\nexport JAVA_HOME="%s"\n' "$JAVA_DETECTADO" >> "$rc"
          ok "JAVA_HOME acrescentado em $rc: $JAVA_DETECTADO"
        fi
      done
    else
      aviso "Java nao encontrado -- o Spark nao sobe sem JDK 17"
      echo "    sudo dnf install java-17-openjdk-devel"
      echo "    sudo apt install openjdk-17-jdk"
    fi
  else
    ok "JAVA_HOME ja definido: $JAVA_HOME"
  fi

  # Sem PYSPARK_PYTHON, o Spark usa o Python do sistema nos workers e quebra
  # com "Python worker failed to connect back".
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if ! grep -q 'PYSPARK_PYTHON' "$rc" 2>/dev/null; then
      printf 'export PYSPARK_PYTHON="%s"\nexport PYSPARK_DRIVER_PYTHON="%s"\n' \
        "$PYTHON_VENV" "$PYTHON_VENV" >> "$rc"
      ok "PYSPARK_PYTHON acrescentado em $rc"
    fi
  done
fi

echo
ok "setup do Python concluido."
echo "    ambiente:  $VENV"
echo "    ativar:    source '$VENV/bin/activate'"
echo "    conferir:  ./scripts/setup-python.sh --verificar"
