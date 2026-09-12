#!/usr/bin/env bash
# ============================================================================
# cofre.sh -- cofre cifrado de credenciais
#
# Empacota os arquivos listados em config/segredos.lista num tar e cifra com
# age usando passphrase. O resultado (segredos.age) pode ser guardado em
# qualquer lugar -- Google Drive, pendrive, repositorio -- porque sem a
# passphrase e ruido.
#
# A passphrase e digitada por voce, direto no prompt do age. Ela nao passa por
# argumento de linha de comando, nao vai para o historico do shell e nao e
# gravada em lugar nenhum. Se voce perder a passphrase, o cofre vira lixo --
# nao ha recuperacao. Guarde-a no gerenciador de senhas.
#
# Uso:
#   ./scripts/cofre.sh fechar [destino]   cria o cofre cifrado
#   ./scripts/cofre.sh abrir  [arquivo]   restaura os arquivos no HOME
#   ./scripts/cofre.sh listar [arquivo]   mostra o conteudo sem restaurar
#
# Exemplos:
#   ./scripts/cofre.sh fechar "/g/Meu Drive/cofre"
#   ./scripts/cofre.sh abrir  "/g/Meu Drive/cofre/segredos.age"
# ============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

LISTA="$DOTFILES_RAIZ/config/segredos.lista"
PADRAO_DESTINO="$DOTFILES_RAIZ/cofre"

# No Git Bash o age instalado pelo winget nao entra no PATH: o winget cria um
# alias em WindowsApps, que so o PowerShell e o cmd enxergam. Procura a pasta
# real do pacote antes de desistir.
if ! command -v age >/dev/null 2>&1 && [ "$(detectar_os)" = "gitbash" ]; then
  # $LOCALAPPDATA vem no formato Windows; cygpath converte para POSIX, senao
  # o teste de arquivo executavel falha com os separadores misturados.
  _base="${LOCALAPPDATA:-}"
  if command -v cygpath >/dev/null 2>&1 && [ -n "$_base" ]; then
    _base="$(cygpath -u "$_base")"
  fi
  for _d in "$_base/Microsoft/WinGet/Packages"/FiloSottile.age_*/age; do
    if [ -x "$_d/age.exe" ]; then
      PATH="$_d:$PATH"
      export PATH
      break
    fi
  done
  unset _base _d
fi

command -v age >/dev/null 2>&1 || morre \
  "age nao encontrado. Instale com: dnf install age | brew install age | winget install FiloSottile.age"

# Le config/segredos.lista e imprime os caminhos que existem de fato.
caminhos_existentes() {
  [ -f "$LISTA" ] || morre "lista nao encontrada: $LISTA"
  local linha caminho
  while IFS= read -r linha; do
    caminho="$(printf '%s' "$linha" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$caminho" ] && continue
    case "$caminho" in \#*) continue ;; esac
    if [ -e "$HOME/$caminho" ]; then
      printf '%s\n' "$caminho"
    fi
  done < "$LISTA"
}

# ----------------------------------------------------------------- fechar ---
cmd_fechar() {
  local destino="${1:-$PADRAO_DESTINO}"
  mkdir -p "$destino"
  local saida="$destino/segredos.age"

  local -a itens=()
  while IFS= read -r c; do itens+=("$c"); done < <(caminhos_existentes)

  [ "${#itens[@]}" -eq 0 ] && morre "nenhum dos caminhos de segredos.lista existe nesta maquina"

  info "${#itens[@]} itens encontrados:"
  printf '    %s\n' "${itens[@]}"

  if [ -f "$saida" ]; then
    local backup="$saida.anterior"
    mv "$saida" "$backup"
    aviso "cofre anterior renomeado: $backup"
  fi

  echo
  info "o age vai pedir uma passphrase. Use uma forte e guarde no gerenciador de senhas."
  aviso "passphrase perdida = cofre irrecuperavel."
  echo

  # O tar escreve na saida padrao e o age le dali: o conteudo em texto claro
  # nunca toca o disco.
  tar -C "$HOME" -czf - "${itens[@]}" | age --passphrase --output "$saida"

  chmod 600 "$saida" 2>/dev/null || true

  ok "cofre criado: $saida"
  echo "    tamanho: $(du -h "$saida" | cut -f1)"
  echo
  info "guarde uma copia em pelo menos dois lugares separados, por exemplo:"
  echo "    - Google Drive"
  echo "    - pendrive guardado fisicamente"
  aviso "a passphrase NAO deve ficar junto do cofre."
}

# ------------------------------------------------------------------ abrir ---
cmd_abrir() {
  local arquivo="${1:-$PADRAO_DESTINO/segredos.age}"
  [ -f "$arquivo" ] || morre "cofre nao encontrado: $arquivo"

  info "restaurando de: $arquivo"
  aviso "arquivos existentes no HOME com o mesmo nome serao sobrescritos."
  echo
  info "digite a passphrase do cofre:"

  age --decrypt "$arquivo" | tar -C "$HOME" -xzf -

  # Permissao restritiva: o ssh recusa chave privada legivel por outros.
  [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh" && chmod 600 "$HOME/.ssh/"* 2>/dev/null || true
  [ -d "$HOME/.gnupg" ] && chmod 700 "$HOME/.gnupg" 2>/dev/null || true

  ok "cofre restaurado no HOME"
  echo
  info "confira:"
  echo "    gh auth status"
  echo "    ssh -T git@github.com"
  echo "    docker info | grep Username"
}

# ----------------------------------------------------------------- listar ---
cmd_listar() {
  local arquivo="${1:-$PADRAO_DESTINO/segredos.age}"
  [ -f "$arquivo" ] || morre "cofre nao encontrado: $arquivo"
  info "conteudo de $arquivo (nada e escrito em disco):"
  age --decrypt "$arquivo" | tar -tzf -
}

# ------------------------------------------------------------------ fluxo ---
case "${1:-}" in
  fechar) shift; cmd_fechar "${1:-}" ;;
  abrir)  shift; cmd_abrir  "${1:-}" ;;
  listar) shift; cmd_listar "${1:-}" ;;
  *)
    sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
