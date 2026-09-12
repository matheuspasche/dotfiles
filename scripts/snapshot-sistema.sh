#!/usr/bin/env bash
# ============================================================================
# snapshot-sistema.sh -- fotografa o estado da maquina antes de formatar
#
# Gera, em snapshots/<sistema>-<data>/:
#   pacotes-sistema.txt   pacotes do dnf/apt/brew instalados explicitamente
#   extensoes-vscode.txt  extensoes do VS Code
#   pacotes-r.txt         pacotes R do usuario
#   pacotes-python.txt    pip freeze
#   ferramentas-uv.txt    ferramentas instaladas com uv tool
#   docker-imagens.txt    imagens Docker locais
#   docker-volumes.txt    volumes Docker
#   servicos.txt          servicos systemd habilitados
#   discos.txt            layout de discos e montagens
#   hardware.txt          CPU, memoria, placa de rede
#   resumo.md             indice legivel de tudo acima
#
# NAO coleta segredo nenhum. Credenciais sao responsabilidade do
# scripts/cofre.sh, que cifra antes de gravar.
#
# Uso:
#   ./scripts/snapshot-sistema.sh
#   ./scripts/snapshot-sistema.sh /mnt/pendrive/backup
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

OS="$(detectar_os)"
GER="$(detectar_gerenciador)"
DESTINO="${1:-$DOTFILES_RAIZ/snapshots}"
CARIMBO="$(date +%Y-%m-%d)"
PASTA="$DESTINO/$OS-$CARIMBO"

mkdir -p "$PASTA"
info "gravando em: $PASTA"

# coletar <arquivo> <rotulo> <comando...>
# Grava a saida do comando num arquivo. Comando ausente nao aborta o snapshot.
coletar() {
  local arquivo="$1" rotulo="$2"; shift 2
  local caminho="$PASTA/$arquivo"
  if "$@" > "$caminho" 2>/dev/null && [ -s "$caminho" ]; then
    ok "$rotulo -> $arquivo"
  else
    echo "(indisponivel nesta maquina)" > "$caminho"
    aviso "$rotulo -- sem dados"
  fi
}

# --------------------------------------------------------- pacotes do sistema
case "$GER" in
  dnf)
    # --userinstalled lista so o que foi pedido explicitamente, nao as
    # dependencias arrastadas junto -- e essa a lista que importa recriar.
    coletar pacotes-sistema.txt "pacotes dnf" dnf repoquery --userinstalled --qf '%{name}'
    ;;
  apt)
    coletar pacotes-sistema.txt "pacotes apt" apt-mark showmanual
    ;;
  brew)
    coletar pacotes-sistema.txt "formulas brew" brew leaves
    coletar pacotes-casks.txt   "casks brew"    brew list --cask
    ;;
  winget)
    # Git Bash sobre Windows: a lista de programas sai bem melhor pelo
    # PowerShell, que enxerga winget, registro e drivers.
    aviso "ambiente Windows -- use scripts/snapshot-windows.ps1 para a lista de programas"
    ;;
  *)
    aviso "gerenciador nao identificado -- pulando pacotes do sistema"
    ;;
esac

# Flatpaks, quando existirem.
if command -v flatpak >/dev/null 2>&1; then
  coletar flatpaks.txt "flatpaks" flatpak list --app --columns=application
fi

# ------------------------------------------------------------------ VS Code --
if command -v code >/dev/null 2>&1; then
  coletar extensoes-vscode.txt "extensoes do VS Code" code --list-extensions
else
  aviso "comando code indisponivel"
fi

# ------------------------------------------------------------------------ R --
if command -v Rscript >/dev/null 2>&1; then
  coletar pacotes-r.txt "pacotes R" Rscript -e \
    'ip <- installed.packages(); ip <- ip[is.na(ip[,"Priority"]), c("Package","Version")]; write.table(ip, quote=FALSE, row.names=FALSE)'
else
  aviso "Rscript indisponivel"
fi

# ------------------------------------------------------------------- Python --
if command -v python3 >/dev/null 2>&1; then
  coletar pacotes-python.txt "pacotes Python" python3 -m pip freeze
fi
if command -v uv >/dev/null 2>&1; then
  coletar ferramentas-uv.txt "ferramentas uv" uv tool list
fi

# ------------------------------------------------------------------- Docker --
if command -v docker >/dev/null 2>&1; then
  coletar docker-imagens.txt "imagens Docker" docker image ls
  coletar docker-volumes.txt "volumes Docker" docker volume ls
fi

# ------------------------------------------------------------------ sistema --
if command -v systemctl >/dev/null 2>&1; then
  coletar servicos.txt "servicos habilitados" \
    systemctl list-unit-files --state=enabled --no-pager
fi

if command -v lsblk >/dev/null 2>&1; then
  coletar discos.txt "discos" lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL
elif command -v diskutil >/dev/null 2>&1; then
  coletar discos.txt "discos" diskutil list
fi

# fstab guarda as montagens permanentes -- sem ele, remontar disco de dados
# depois de formatar vira tentativa e erro.
if [ -f /etc/fstab ]; then
  cp /etc/fstab "$PASTA/fstab.txt" 2>/dev/null && ok "fstab -> fstab.txt"
fi

if command -v lscpu >/dev/null 2>&1; then
  {
    echo "== CPU =="; lscpu
    echo; echo "== memoria =="; free -h
    echo; echo "== rede =="; ip -brief addr 2>/dev/null || true
  } > "$PASTA/hardware.txt" 2>/dev/null && ok "hardware -> hardware.txt"
elif [ "$OS" = "macos" ]; then
  system_profiler SPHardwareDataType > "$PASTA/hardware.txt" 2>/dev/null && \
    ok "hardware -> hardware.txt"
fi

# ------------------------------------------------------------------- resumo --
cat > "$PASTA/resumo.md" <<RESUMO
# Snapshot -- $OS -- $CARIMBO

Maquina: $(hostname)
Usuario: ${USER:-${USERNAME:-desconhecido}}
Gerenciador: ${GER:-nenhum}
Gerado: $(date '+%Y-%m-%d %H:%M')

## Como restaurar

Pacotes do sistema:

    # Fedora
    sudo dnf install -y \$(cat pacotes-sistema.txt)
    # Ubuntu
    sudo apt-get install -y \$(cat pacotes-sistema.txt)
    # macOS
    brew install \$(cat pacotes-sistema.txt)

Extensoes do VS Code:

    cat extensoes-vscode.txt | xargs -n1 code --install-extension

Pacotes R:

    Rscript -e 'install.packages(read.table("pacotes-r.txt", header=TRUE)\$Package)'

Pacotes Python: prefira recriar o ambiente pelo pyproject.toml de cada
projeto. O pacotes-python.txt serve de conferencia, nao de receita.

## O que este snapshot NAO contem

Segredo nenhum. Token, senha e credencial ficam no cofre cifrado --
ver scripts/cofre.sh e docs/segredos.md.

## Antes de formatar

- [ ] Copiar esta pasta para fora do disco que sera formatado
- [ ] Gerar o cofre: ./scripts/cofre.sh fechar
- [ ] Conferir docker-volumes.txt -- volume com dado local nao volta sozinho
- [ ] git status em todo repositorio com trabalho nao commitado
RESUMO
ok "resumo.md"

echo
ok "snapshot completo: $PASTA"
aviso "copie esta pasta para fora do disco antes de formatar."
