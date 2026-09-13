#!/usr/bin/env bash
# ============================================================================
# configurar.sh -- assistente que escreve o perfil.conf
#
# Faz perguntas e grava as respostas. Sem isso, o kit funciona com padroes
# conservadores; com isso, ele passa a ser SEU: sua identidade no git, seus
# stacks, suas bibliotecas, seu navegador.
#
# Roda quantas vezes quiser -- os valores atuais viram o padrao de cada
# pergunta, entao reconfigurar e so apertar Enter no que nao muda.
#
# Uso:  ./scripts/configurar.sh
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
carregar_perfil

DESTINO="$DOTFILES_RAIZ/perfil.conf"

echo
info "Assistente de configuracao do kit"
echo "   As respostas vao para perfil.conf, que nao e versionado."
echo "   Enter aceita o valor entre colchetes."
echo

# perguntar_texto <rotulo> <valor atual> -- imprime a resposta no stdout.
perguntar_texto() {
  local rotulo="$1" atual="$2" resposta
  printf '%s [%s]: ' "$rotulo" "${atual:-vazio}" >&2
  read -r resposta
  printf '%s' "${resposta:-$atual}"
}

# perguntar_sim_nao <rotulo> <valor atual>
perguntar_sim_nao() {
  local rotulo="$1" atual="$2" resposta padrao
  if [ "$atual" = "sim" ]; then padrao="S/n"; else padrao="s/N"; fi
  printf '%s [%s]: ' "$rotulo" "$padrao" >&2
  read -r resposta
  case "$resposta" in
    [sS]*) printf 'sim' ;;
    [nN]*) printf 'nao' ;;
    *)     printf '%s' "$atual" ;;
  esac
}

# perguntar_lista <rotulo> <opcoes...> -- multipla escolha, devolve os
# escolhidos separados por espaco. O usuario digita os numeros.
perguntar_lista() {
  local rotulo="$1" atuais="$2"; shift 2
  local opcoes=("$@") i=1 escolha saida=""

  printf '\n%s\n' "$rotulo" >&2
  for op in "${opcoes[@]}"; do
    local id="${op%%:*}" desc="${op#*:}" marca=" "
    case " $atuais " in *" $id "*) marca="x" ;; esac
    printf '  [%s] %d) %-14s %s\n' "$marca" "$i" "$id" "$desc" >&2
    i=$(( i + 1 ))
  done
  printf 'Numeros separados por espaco (Enter mantem o marcado): ' >&2
  read -r escolha

  if [ -z "$escolha" ]; then
    printf '%s' "$atuais"
    return 0
  fi

  for n in $escolha; do
    # Ignora entrada que nao seja numero dentro da faixa, em vez de quebrar.
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le "${#opcoes[@]}" ] || continue
    local op="${opcoes[$(( n - 1 ))]}"
    saida="$saida ${op%%:*}"
  done
  # Remove o espaco inicial.
  printf '%s' "${saida# }"
}

# ------------------------------------------------------------------ stacks ---
NOVO_STACKS="$(perguntar_lista '1. Que stacks voce usa?' "$STACKS" \
  "base:curl e terminal -- o minimo de QUALQUER maquina" \
  "pessoal:Spotify, WhatsApp, VLC" \
  "jogos:Steam, Heroic (Epic), Lutris, Proton e ferramentas" \
  "escritorio:LibreOffice, OnlyOffice" \
  "produtividade:utilitarios do KDE, captura de tela, PowerToys (Windows)" \
  "opcional:Obsidian, Syncthing" \
  "dev:git, gh, ripgrep, fd, jq, age" \
  "editor:VS Code, Claude Code e Node" \
  "python:Python e uv" \
  "r:R, RStudio, Quarto e toolchain de compilacao" \
  "dados:DBeaver, DuckDB" \
  "jvm:JDK (requisito do Spark)" \
  "container:Docker")"

# --------------------------------------------------------------- identidade --
# Perguntado DEPOIS dos stacks, e so para quem marcou "dev". Git nao esta em
# "base": numa maquina de uso comum ele nao entra, e nao faz sentido a
# primeira pergunta do assistente ser o e-mail do GitHub de quem so quer
# navegador e LibreOffice.
NOVO_GIT_NOME="$GIT_NOME"
NOVO_GIT_EMAIL="$GIT_EMAIL"
case " $NOVO_STACKS " in
  *" dev "*)
    info "2. Identidade do Git"
    echo "   Usada para assinar seus commits."
    NOVO_GIT_NOME="$(perguntar_texto '   Seu nome' "$GIT_NOME")"
    echo
    echo "   Dica: no GitHub, Settings > Emails > Keep my email addresses private"
    echo "   da um endereco <id>+<usuario>@users.noreply.github.com. Usando ele,"
    echo "   seu e-mail real nao aparece em commit publico nenhum."
    NOVO_GIT_EMAIL="$(perguntar_texto '   Seu e-mail' "$GIT_EMAIL")"
    ;;
  *)
    info "2. Identidade do Git -- pulado (stack dev nao selecionado)"
    ;;
esac

# ------------------------------------------------------------- bibliotecas ---
NOVO_LIBS_R=""
case " $NOVO_STACKS " in
  *" r "*)
    conjuntos_r=()
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      conjuntos_r+=("$id:$(conjunto_valor "$id" nome) (~$(conjunto_valor "$id" minutos) min)")
    done < <(conjuntos_de r)
    NOVO_LIBS_R="$(perguntar_lista '3. Bibliotecas de R' "$LIBS_R" "${conjuntos_r[@]}")"
    ;;
  *)
    info "3. Bibliotecas de R -- pulado (stack r nao selecionado)"
    ;;
esac

NOVO_LIBS_PY=""
case " $NOVO_STACKS " in
  *" python "*)
    conjuntos_py=()
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      conjuntos_py+=("$id:$(conjunto_valor "$id" nome) (~$(conjunto_valor "$id" minutos) min)")
    done < <(conjuntos_de python)
    NOVO_LIBS_PY="$(perguntar_lista '4. Bibliotecas de Python' "$LIBS_PY" "${conjuntos_py[@]}")"
    ;;
  *)
    info "4. Bibliotecas de Python -- pulado (stack python nao selecionado)"
    ;;
esac

echo
# So faz sentido perguntar se ha biblioteca para instalar. Sem R nem Python
# escolhidos, e mais uma confirmacao sobre algo que nao vai acontecer.
NOVO_SEGUNDO_PLANO="$LIBS_EM_SEGUNDO_PLANO"
if [ -n "$NOVO_LIBS_R" ] || [ -n "$NOVO_LIBS_PY" ]; then
  NOVO_SEGUNDO_PLANO="$(perguntar_sim_nao \
    '   Instalar bibliotecas em segundo plano (com log)?' "$LIBS_EM_SEGUNDO_PLANO")"
fi

# --------------------------------------------------------------- navegador ---
echo
info "5. Navegador"
echo "   1) firefox   ja vem no Fedora KDE"
echo "   2) chrome    exige o repositorio do Google no Fedora"
echo "   3) brave     exige o repositorio da Brave no Fedora"
echo "   4) nenhum    nao mexer"
NOVO_NAVEGADOR="$(perguntar_texto '   Escolha (nome ou numero)' "$NAVEGADOR")"
case "$NOVO_NAVEGADOR" in
  1) NOVO_NAVEGADOR="firefox" ;;
  2) NOVO_NAVEGADOR="chrome" ;;
  3) NOVO_NAVEGADOR="brave" ;;
  4) NOVO_NAVEGADOR="nenhum" ;;
esac

# --------------------------------------------------------------- extensoes ---
# Mesma logica da identidade: sem o stack "editor" nao ha VS Code na maquina,
# entao perguntar quais extensoes instalar nele e pedir uma resposta que nao
# vai ser usada.
NOVO_VSCODE="$VSCODE_EXTENSOES"
case " $NOVO_STACKS " in
  *" editor "*)
    NOVO_VSCODE="$(perguntar_lista '6. Extensoes do VS Code' "$VSCODE_EXTENSOES" \
      "base:Claude Code, GitLens, EditorConfig" \
      "python:Pylance, Jupyter, Ruff" \
      "r:extensao do R e depurador" \
      "dados:SQLTools, CSV, visualizador de planilha" \
      "container:Docker, Remote-WSL, Dev Containers" \
      "escrita:Markdown, Quarto")"
    ;;
  *)
    info "6. Extensoes do VS Code -- pulado (stack editor nao selecionado)"
    ;;
esac

# ------------------------------------------------------------------ Fedora ---
NOVO_FEDORA_RPMFUSION="$FEDORA_RPMFUSION"
NOVO_FEDORA_CODECS="$FEDORA_CODECS"
NOVO_FEDORA_GPU="$FEDORA_GPU"
NOVO_FEDORA_FIRMWARE="$FEDORA_FIRMWARE"
NOVO_FEDORA_FONTES_MS="$FEDORA_FONTES_MS"
NOVO_FEDORA_DNF_RAPIDO="$FEDORA_DNF_RAPIDO"

if [ -f /etc/fedora-release ]; then
  echo
  info "7. Fedora: pos-instalacao"
  echo "   Cada passo ainda vai perguntar na hora de executar."
  NOVO_FEDORA_RPMFUSION="$(perguntar_sim_nao '   RPM Fusion (codecs e firmware)?' "$FEDORA_RPMFUSION")"
  NOVO_FEDORA_CODECS="$(perguntar_sim_nao '   Codecs multimidia?' "$FEDORA_CODECS")"
  NOVO_FEDORA_GPU="$(perguntar_sim_nao '   Aceleracao de video da GPU?' "$FEDORA_GPU")"
  NOVO_FEDORA_FIRMWARE="$(perguntar_sim_nao '   Atualizacao de firmware (fwupd)?' "$FEDORA_FIRMWARE")"
  NOVO_FEDORA_FONTES_MS="$(perguntar_sim_nao '   Fontes da Microsoft?' "$FEDORA_FONTES_MS")"
  NOVO_FEDORA_DNF_RAPIDO="$(perguntar_sim_nao '   Acelerar o DNF?' "$FEDORA_DNF_RAPIDO")"
fi

# --------------------------------------------------------------- caminhos ----
echo
info "8. Caminhos"
echo "   Onde guardar o cofre de credenciais e os snapshots."
echo "   Vazio usa a propria pasta do kit."
NOVO_COFRE="$(perguntar_texto '   Pasta do cofre' "$COFRE_DESTINO")"
NOVO_SNAPSHOT="$(perguntar_texto '   Pasta dos snapshots' "$SNAPSHOT_DESTINO")"

# ----------------------------------------------------------------- gravar ----
if [ -f "$DESTINO" ]; then
  cp "$DESTINO" "$DESTINO.anterior"
  aviso "perfil anterior salvo em perfil.conf.anterior"
fi

cat > "$DESTINO" <<PERFIL
# ============================================================================
# perfil.conf -- gerado por scripts/configurar.sh em $(date '+%Y-%m-%d %H:%M')
#
# Pode editar a mao. Formato: CHAVE="valor", sem comando nem variavel.
# Rode o assistente de novo para regerar.
# ============================================================================

# --- identidade ---
GIT_NOME="$NOVO_GIT_NOME"
GIT_EMAIL="$NOVO_GIT_EMAIL"
GIT_ASSINAR="$GIT_ASSINAR"

# --- stacks ---
STACKS="$NOVO_STACKS"

# --- bibliotecas ---
LIBS_R="$NOVO_LIBS_R"
LIBS_PY="$NOVO_LIBS_PY"
LIBS_EM_SEGUNDO_PLANO="$NOVO_SEGUNDO_PLANO"

# --- navegador ---
NAVEGADOR="$NOVO_NAVEGADOR"

# --- editor ---
VSCODE_EXTENSOES="$NOVO_VSCODE"

# --- Fedora: pos-instalacao ---
FEDORA_RPMFUSION="$NOVO_FEDORA_RPMFUSION"
FEDORA_CODECS="$NOVO_FEDORA_CODECS"
FEDORA_GPU="$NOVO_FEDORA_GPU"
FEDORA_FIRMWARE="$NOVO_FEDORA_FIRMWARE"
FEDORA_FONTES_MS="$NOVO_FEDORA_FONTES_MS"
FEDORA_DNF_RAPIDO="$NOVO_FEDORA_DNF_RAPIDO"

# --- caminhos ---
COFRE_DESTINO="$NOVO_COFRE"
SNAPSHOT_DESTINO="$NOVO_SNAPSHOT"
PERFIL

echo
ok "perfil gravado: $DESTINO"
echo

# Estimativa de tempo: a soma dos conjuntos escolhidos e o unico numero que
# o usuario realmente quer saber antes de comecar.
minutos=0
for id in $NOVO_LIBS_R $NOVO_LIBS_PY; do
  m="$(conjunto_valor "$id" minutos)"
  [ -n "$m" ] && minutos=$(( minutos + m ))
done

info "Resumo"
echo "    stacks       $NOVO_STACKS"
echo "    R            ${NOVO_LIBS_R:-nenhum}"
echo "    Python       ${NOVO_LIBS_PY:-nenhum}"
echo "    navegador    $NOVO_NAVEGADOR"
[ "$minutos" -gt 0 ] && echo "    bibliotecas  ~$minutos min de instalacao"

echo
info "Proximos passos"
if [ -f /etc/fedora-release ]; then
  echo "    1. ./scripts/fedora-pos-instalacao.sh   codecs, drivers, Flathub"
  echo "    2. ./scripts/setup-linux.sh             programas do manifesto"
else
  echo "    1. ./scripts/setup-linux.sh             programas do manifesto"
fi
echo "    3. ./install.sh --extensoes             configuracoes e extensoes"
# O "|| true" e o "exit 0" nao sao decoracao: sob "set -e", a ultima dica que
# nao se aplica derrubaria o codigo de saida de um assistente que deu certo.
[ -n "$NOVO_LIBS_R" ]  && echo "    4. ./scripts/setup-r.sh                 bibliotecas de R"  || true
[ -n "$NOVO_LIBS_PY" ] && echo "    5. ./scripts/setup-python.sh            bibliotecas de Python" || true
exit 0
