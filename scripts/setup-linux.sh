#!/usr/bin/env bash
# ============================================================================
# setup-linux.sh -- instala o stack de desenvolvimento no Fedora/Ubuntu
#
# Le pacotes.yaml (fonte unica da verdade) e instala com dnf ou apt, conforme
# a distribuicao. Tambem serve dentro do WSL.
#
# Uso:
#   ./scripts/setup-linux.sh              instala o que o perfil.conf pedir
#   ./scripts/setup-linux.sh --grupo r    so o grupo r, ignorando o perfil
#   ./scripts/setup-linux.sh --simular    mostra o que faria
#   ./scripts/setup-linux.sh --sim        nao pergunta nada
#
# O que sera instalado vem de STACKS no perfil.conf. Sem perfil, so o basico.
# Para escolher: ./scripts/configurar.sh
# ============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
carregar_perfil

SIMULAR=0
GRUPO=""
SIM_A_TUDO=0

while [ $# -gt 0 ]; do
  case "$1" in
    --simular) SIMULAR=1; shift ;;
    --sim)     SIM_A_TUDO=1; shift ;;
    --grupo)   GRUPO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

OS="$(detectar_os)"
case "$OS" in
  linux|wsl) ;;
  *) morre "este script e para Linux/WSL. Sistema detectado: $OS" ;;
esac

GER="$(detectar_gerenciador)"
[ -z "$GER" ] && morre "nem dnf nem apt encontrados"
info "distribuicao usa: $GER"
[ "$SIMULAR" = "1" ] && aviso "modo simulacao: nada sera instalado"

# Sem perfil e sem --grupo, o script nao adivinha o que voce quer. O padrao
# e o minimo (stack base), e ele avisa como escolher de verdade.
if [ "$PERFIL_CARREGADO" = "0" ] && [ -z "$GRUPO" ]; then
  echo
  aviso "nenhum perfil.conf encontrado."
  echo "   Sem ele, so o stack 'base' sera instalado (git, editor, utilitarios)."
  echo "   Para escolher o que instalar:  ./scripts/configurar.sh"
  echo
  if [ "$SIMULAR" != "1" ] && [ "$SIM_A_TUDO" != "1" ]; then
    printf "   Continuar so com o basico? [S/n] "
    read -r resposta
    case "$resposta" in
      [nN]*) info "rode ./scripts/configurar.sh e tente de novo"; exit 0 ;;
    esac
  fi
fi

# --------------------------------------------------------------- repositorios
# precisa_repo <id>
#   Verdadeiro quando algum pacote que ESTE run vai instalar declara
#   "repo: <id>" no manifesto. Evita que pedir um grupo so encha a maquina de
#   repositorio alheio: "--grupo r" numa maquina de trabalho nao tem por que
#   acrescentar o repositorio do VS Code nem o do Docker.
precisa_repo() {
  local alvo="$1" g id

  while IFS= read -r g; do
    [ -z "$g" ] && continue
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      # So conta se o pacote for mesmo instalavel neste gerenciador.
      [ -z "$(manifesto_valor "$id" "$GER")" ] && continue
      [ "$(manifesto_valor "$id" repo)" = "$alvo" ] && return 0
    done < <(manifesto_ids "$g")
  done < <(grupos_pedidos)

  # O navegador nao vem por grupo: entra so o escolhido no perfil.
  if [ "${NAVEGADOR:-nenhum}" != "nenhum" ] && [ -n "${NAVEGADOR:-}" ]; then
    [ "$(manifesto_valor "$NAVEGADOR" repo)" = "$alvo" ] && return 0
  fi

  return 1
}

# Alguns pacotes so existem em repositorio de terceiro. Configurado antes de
# qualquer instalacao, senao o gerenciador nao encontra o pacote.
#
# O RPM Fusion NAO entra aqui de proposito: nenhum pacote do manifesto precisa
# dele para resolver (no Fedora 44 ate o vlc vem do repositorio oficial), e ele
# e uma decisao de sistema -- codecs, drivers -- que ja tem dono e pergunta
# propria no fedora-pos-instalacao.sh, sob FEDORA_RPMFUSION.
configurar_repos() {
  if [ "$SIMULAR" = "1" ]; then
    local r
    for r in vscode docker google-chrome brave; do
      precisa_repo "$r" && info "[simular] configuraria o repositorio: $r"
    done
    return 0
  fi

  if [ "$GER" = "dnf" ]; then
    # VS Code (repositorio da Microsoft)
    if precisa_repo vscode && [ ! -f /etc/yum.repos.d/vscode.repo ]; then
      info "adicionando repositorio do VS Code"
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      printf '%s\n' \
        '[code]' \
        'name=Visual Studio Code' \
        'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
        'enabled=1' \
        'gpgcheck=1' \
        'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' \
        | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
    fi

    # Google Chrome. O Fedora ja entrega o arquivo do repositorio pelo pacote
    # fedora-workstation-repositories, so que desabilitado -- entao o certo e
    # habilitar, nao escrever um .repo por cima.
    if precisa_repo google-chrome; then
      if [ -f /etc/yum.repos.d/google-chrome.repo ]; then
        info "habilitando o repositorio do Google Chrome"
        sudo dnf config-manager setopt google-chrome.enabled=1 ||
          aviso "nao consegui habilitar o repositorio do Chrome"
      else
        info "instalando fedora-workstation-repositories (repositorio do Chrome)"
        sudo dnf install -y fedora-workstation-repositories &&
          sudo dnf config-manager setopt google-chrome.enabled=1 ||
          aviso "nao consegui habilitar o repositorio do Chrome"
      fi
    fi

    # Brave. Nao existe em repositorio de distribuicao nenhum; a propria Brave
    # publica o arquivo .repo pronto, com a chave dela dentro.
    if precisa_repo brave && [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
      info "adicionando repositorio do Brave"
      if ! sudo curl -fsSL https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
             -o /etc/yum.repos.d/brave-browser.repo; then
        sudo rm -f /etc/yum.repos.d/brave-browser.repo
        aviso "nao foi possivel adicionar o repositorio do Brave"
      fi
    fi

    # Docker CE (o docker do repositorio padrao do Fedora e o moby, mais velho)
    if precisa_repo docker && [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
      info "adicionando repositorio do Docker"
      # Baixar o .repo direto e o que o "config-manager --add-repo" fazia. A
      # opcao foi removida no dnf5 (Fedora 41+), que quer "addrepo
      # --from-repofile="; curl funciona nas duas versoes e nao exige detectar
      # qual delas esta na maquina.
      if ! sudo curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
             -o /etc/yum.repos.d/docker-ce.repo; then
        # Repositorio de terceiro fora do ar nao pode derrubar a instalacao
        # inteira: o resto do manifesto continua valido.
        sudo rm -f /etc/yum.repos.d/docker-ce.repo
        aviso "nao foi possivel adicionar o repositorio do Docker; siga sem ele"
      fi
    fi
  fi

  if [ "$GER" = "apt" ]; then
    sudo apt-get update -qq

    if ! command -v curl >/dev/null 2>&1; then
      sudo apt-get install -y curl gnupg
    fi

    # VS Code
    if precisa_repo vscode && [ ! -f /etc/apt/sources.list.d/vscode.list ]; then
      info "adicionando repositorio do VS Code"
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    fi

    # GitHub CLI. So no apt: no Fedora o gh vem do repositorio oficial.
    if precisa_repo github-cli && [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
      info "adicionando repositorio do GitHub CLI"
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    fi

    # Docker CE
    if precisa_repo docker && [ ! -f /etc/apt/sources.list.d/docker.list ]; then
      info "adicionando repositorio do Docker"
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi

    sudo apt-get update -qq
  fi
}

# ----------------------------------------------------------------- instalar --
# resolver_java <gerenciador> <pacote-do-manifesto>
#   O pacote de JDK do manifesto e um numero fixo (ex.: java-17-openjdk-devel),
#   mas Fedora e Ubuntu descontinuam versoes antigas do OpenJDK a cada par de
#   releases -- foi exatamente isso que quebrou java-17-openjdk-devel no
#   Fedora 44 ("Nenhuma correspondencia para o argumento"). Em vez de fixar
#   um numero que expira, confere se o pacote pinado ainda existe e, se nao
#   existir mais, escolhe a versao numerada mais alta disponivel no lugar.
#   Nunca escolhe builds "latest"/pre-lancamento (java-latest-openjdk no
#   dnf): sao instaveis demais para um ambiente de trabalho.
resolver_java() {
  local ger="$1" pinado="$2" nome versao maior=0 pacote=""

  case "$ger" in
    dnf)
      if dnf list available "$pinado" >/dev/null 2>&1; then
        printf '%s\n' "$pinado"
        return 0
      fi
      while IFS= read -r nome; do
        # primeira coluna da saida do dnf, sem o sufixo de arquitetura
        # (".x86_64"): "java-25-openjdk-devel.x86_64" -> "java-25-openjdk-devel"
        nome="${nome%%[[:space:]]*}"
        nome="${nome%.*}"
        [[ "$nome" =~ ^java-([0-9]+)-openjdk-devel$ ]] || continue
        versao="${BASH_REMATCH[1]}"
        if [ "$versao" -gt "$maior" ]; then
          maior="$versao"
          pacote="$nome"
        fi
      done < <(dnf list available 'java-*-openjdk-devel' 2>/dev/null)
      ;;
    apt)
      if apt-cache show "$pinado" >/dev/null 2>&1; then
        printf '%s\n' "$pinado"
        return 0
      fi
      while IFS= read -r nome; do
        [[ "$nome" =~ ^openjdk-([0-9]+)-jdk$ ]] || continue
        versao="${BASH_REMATCH[1]}"
        if [ "$versao" -gt "$maior" ]; then
          maior="$versao"
          pacote="$nome"
        fi
      done < <(apt-cache pkgnames 'openjdk-' 2>/dev/null)
      ;;
  esac

  [ -n "$pacote" ] && printf '%s\n' "$pacote"
  return 0
}

# grupos_pedidos -- imprime, um por linha, os grupos que este run deve tratar.
#   --grupo manda: instala exatamente aquele grupo. Sem ele, obedece o STACKS
#   do perfil. NUNCA "tudo": instalar R, Python e Docker numa maquina que so
#   precisa de navegador nao e util para ninguem.
grupos_pedidos() {
  local -a grupos=()
  local g
  if [ -n "$GRUPO" ]; then
    grupos=("$GRUPO")
  else
    read -r -a grupos <<< "$STACKS"
  fi

  for g in ${grupos[@]+"${grupos[@]}"}; do
    # "navegador" nao e um stack: o grupo tem os tres navegadores e o usuario
    # escolhe UM em NAVEGADOR. Tratado como stack, instalaria Firefox, Chrome
    # e Brave de uma vez -- e ainda duplicaria o escolhido, que entra por
    # fora. Quem pedir explicitamente recebe o aviso em vez dos tres.
    # O aviso correspondente sai uma unica vez, em validar_grupos: esta
    # funcao e chamada por varios consumidores e avisaria seis vezes.
    [ "$g" = "navegador" ] && continue
    printf '%s\n' "$g"
  done
  return 0
}

# validar_grupos -- reclama, uma vez so, do que foi pedido e nao existe.
#   Grupo inexistente some sem deixar rastro: pacotes_para devolve vazio e o
#   setup segue como se nada tivesse sido pedido. Isso morde justamente depois
#   de uma renomeacao de grupo, quando um perfil.conf antigo continua pedindo
#   um nome que ja nao existe.
validar_grupos() {
  local -a pedidos=()
  local g
  if [ -n "$GRUPO" ]; then
    pedidos=("$GRUPO")
  else
    read -r -a pedidos <<< "$STACKS"
  fi

  for g in ${pedidos[@]+"${pedidos[@]}"}; do
    if [ "$g" = "navegador" ]; then
      aviso "\"navegador\" nao e um stack -- o setup instala so o escolhido em NAVEGADOR"
      continue
    fi
    if ! manifesto_ids "$g" | grep -q .; then
      aviso "stack \"$g\" nao existe no pacotes.yaml -- nada sera instalado por ele"
      echo "    stacks validos: $(manifesto_grupos | grep -v '^navegador$' | tr '\n' ' ')"
    fi
  done
  return 0
}

instalar_pacotes() {
  local -a lista=()
  local -a grupos=()
  local g pkg

  while IFS= read -r g; do
    [ -n "$g" ] && grupos+=("$g")
  done < <(grupos_pedidos)

  info "grupos: ${grupos[*]}"

  validar_grupos

  for g in "${grupos[@]}"; do
    while IFS= read -r pkg; do
      [ -n "$pkg" ] && lista+=("$pkg")
    done < <(pacotes_para "$GER" "$g")
  done

  # Navegador: entra so o escolhido no perfil, nao os tres.
  if [ "$NAVEGADOR" != "nenhum" ] && [ -n "$NAVEGADOR" ]; then
    pkg="$(manifesto_valor "$NAVEGADOR" "$GER")"
    if [ -n "$pkg" ]; then
      lista+=("$pkg")
      info "navegador: $NAVEGADOR ($pkg)"
    else
      aviso "navegador '$NAVEGADOR' nao disponivel para $GER -- veja docs/"
    fi
  fi

  # O pacote de JDK pode ter saido do repositorio desde a ultima vez que o
  # manifesto foi atualizado (ver resolver_java acima). So mexe em quem bate
  # com o formato conhecido -- nunca troca um pacote que nao seja JDK.
  local i pacote_java
  for i in "${!lista[@]}"; do
    case "${lista[$i]}" in
      java-*-openjdk-devel|openjdk-*-jdk)
        pacote_java="$(resolver_java "$GER" "${lista[$i]}")"
        if [ -z "$pacote_java" ]; then
          aviso "nenhuma versao do OpenJDK disponivel -- pulando ${lista[$i]}"
          unset 'lista[i]'
        elif [ "$pacote_java" != "${lista[$i]}" ]; then
          aviso "${lista[$i]} nao existe mais no repositorio -- usando $pacote_java no lugar"
          lista[i]="$pacote_java"
        fi
        ;;
    esac
  done
  lista=("${lista[@]}")

  # Sem repetir: o mesmo pacote pode chegar por dois caminhos (o navegador
  # escolhido, um id multivalor) e "dnf install x x" e so ruido na tela.
  local -a unicos=()
  for pkg in ${lista[@]+"${lista[@]}"}; do
    case " ${unicos[*]-} " in *" $pkg "*) continue ;; esac
    unicos+=("$pkg")
  done
  lista=(${unicos[@]+"${unicos[@]}"})

  [ "${#lista[@]}" -eq 0 ] && { aviso "nada a instalar"; return 0; }

  info "${#lista[@]} pacotes: ${lista[*]}"

  if [ "$SIMULAR" = "1" ]; then
    info "[simular] sudo $GER install -y ${lista[*]}"
    return 0
  fi

  # Instalacao em bloco unico: muito mais rapido que um pacote por vez e o
  # gerenciador resolve as dependencias de uma vez so.
  if [ "$GER" = "dnf" ]; then
    sudo dnf install -y "${lista[@]}"
  else
    sudo apt-get install -y "${lista[@]}"
  fi
}

# ------------------------------------------------------ ferramentas avulsas --
# instalar_flatpak <id-flatpak> <rotulo>
#   Instala do Flathub o que nao existe no repositorio da distribuicao.
#   Ausencia de flatpak vira aviso, nao erro: e um programa a menos, nao um
#   motivo para abortar o resto do setup.
instalar_flatpak() {
  local app="$1" rotulo="$2"

  if ! command -v flatpak >/dev/null 2>&1; then
    aviso "flatpak indisponivel -- instale o $rotulo manualmente"
    return 0
  fi

  # O Flathub e um passo opcional e interativo do fedora-pos-instalacao.sh
  # (pergunta antes de habilitar). Quem pulou aquele script, ou respondeu
  # "nao" ali, chega aqui sem o remoto e toda instalacao por Flatpak falha
  # com "Nenhuma ref de remoto localizada para 'flathub'" -- as tres, uma
  # atras da outra, pelo mesmo motivo. Habilitar aqui e so registrar um
  # repositorio publico: nao e um passo que precise de confirmacao, ao
  # contrario dos do fedora-pos-instalacao.sh (que mexem em firmware/GPU).
  if ! flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    info "habilitando o Flathub (nao estava configurado)"
    flatpak remote-add --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null ||
      { aviso "nao consegui habilitar o Flathub -- instale o $rotulo manualmente"; return 0; }
  fi

  if flatpak list --app 2>/dev/null | grep -qi "$app"; then
    ok "$rotulo ja instalado"
    return 0
  fi

  info "instalando $rotulo via Flatpak"
  flatpak install -y flathub "$app" ||
    aviso "$rotulo falhou -- instale manualmente"
  return 0
}

# instalar_pacote_baixado <url> <rotulo>
#   Baixa um .rpm/.deb avulso e instala PELO gerenciador (nao por rpm -i /
#   dpkg -i), para que as dependencias sejam resolvidas junto. Devolve 1 em
#   caso de falha, sem abortar o setup: um programa a menos nao justifica
#   derrubar o resto.
instalar_pacote_baixado() {
  local url="$1" rotulo="$2" dir arq codigo=0

  dir="$(mktemp -d)"
  # A extensao importa: dnf e apt-get recusam um caminho local sem ela.
  arq="$dir/pacote.${url##*.}"

  info "baixando $rotulo"
  if ! curl -fSL --retry 2 -o "$arq" "$url"; then
    rm -rf "$dir"
    aviso "nao consegui baixar o $rotulo"
    return 1
  fi

  info "instalando $rotulo"
  if [ "$GER" = "dnf" ]; then
    sudo dnf install -y "$arq" || codigo=1
  else
    sudo apt-get install -y "$arq" || codigo=1
  fi

  rm -rf "$dir"
  [ "$codigo" -ne 0 ] && aviso "o $rotulo falhou ao instalar"
  return "$codigo"
}

# url_release_github <repo> <regex-do-arquivo>
#   Endereco do arquivo da release "latest" que casa com o regex. Serve para
#   nao fixar numero de versao no script: versao fixa envelhece calada e um
#   dia vira 404 -- foi o que o java-17-openjdk-devel fez aqui.
url_release_github() {
  local repo="$1" padrao="$2" api="https://api.github.com/repos/$1/releases/latest"

  if command -v jq >/dev/null 2>&1; then
    curl -fsSL "$api" 2>/dev/null |
      jq -r --arg re "$padrao" '.assets[].browser_download_url | select(test($re))' 2>/dev/null |
      head -1
  else
    # Sem jq (ele entra no stack base, mas este script pode rodar com --grupo
    # r numa maquina crua), o mesmo campo sai com grep.
    curl -fsSL "$api" 2>/dev/null |
      grep -oE '"browser_download_url": *"[^"]+"' |
      cut -d'"' -f4 |
      grep -E "$padrao" |
      head -1
  fi
}

# instalar_quarto_tarball -- Quarto em ~/.local, sem root.
#   Caminho para maquina onde nao se tem sudo (WSL corporativo, laboratorio,
#   servidor compartilhado). O Quarto e autocontido: basta descompactar e
#   apontar um link para o binario.
instalar_quarto_tarball() {
  local url="$1" dir destino="$HOME/.local/opt/quarto" bin="$HOME/.local/bin"

  dir="$(mktemp -d)"
  info "baixando Quarto CLI (tarball, sem root)"
  if ! curl -fSL --retry 2 -o "$dir/quarto.tar.gz" "$url"; then
    rm -rf "$dir"
    aviso "nao consegui baixar o Quarto"
    return 1
  fi

  mkdir -p "$destino" "$bin"
  # --strip-components=1 tira o diretorio "quarto-<versao>" de dentro do
  # tarball: sem isso o caminho final carregaria o numero da versao, e o
  # link quebraria na proxima atualizacao.
  rm -rf "${destino:?}"/*
  if ! tar -xzf "$dir/quarto.tar.gz" -C "$destino" --strip-components=1; then
    rm -rf "$dir"
    aviso "nao consegui descompactar o Quarto"
    return 1
  fi
  rm -rf "$dir"

  ln -sf "$destino/bin/quarto" "$bin/quarto"
  ok "Quarto CLI instalado em $destino"

  case ":$PATH:" in
    *":$bin:"*) ;;
    *) aviso "$bin nao esta no PATH -- abra um terminal novo ou rode ./install.sh" ;;
  esac
  return 0
}

# instalar_quarto -- Quarto CLI, sempre na release estavel mais recente.
#   Quem renderiza .qmd/.Rmd e este binario; o pacote R "quarto" so conversa
#   com ele. A Posit publica .rpm/.deb nas releases do GitHub, sem
#   repositorio, entao a versao vem da API em vez de estar escrita aqui.
instalar_quarto() {
  local padrao url url_tar

  if command -v quarto >/dev/null 2>&1; then
    ok "Quarto CLI ja instalado ($(quarto --version 2>/dev/null))"
    return 0
  fi

  case "$GER:$(uname -m)" in
    dnf:x86_64)  padrao='linux-x86_64\.rpm$' ;;
    dnf:aarch64) padrao='linux-aarch64\.rpm$' ;;
    apt:x86_64)  padrao='linux-amd64\.deb$' ;;
    apt:aarch64) padrao='linux-arm64\.deb$' ;;
    *)
      aviso "sem pacote de Quarto para $GER/$(uname -m) -- veja https://quarto.org/docs/get-started/"
      return 0
      ;;
  esac

  url="$(url_release_github quarto-dev/quarto-cli "$padrao")"
  if [ -z "$url" ]; then
    # A API do GitHub limita chamadas anonimas por hora; nao e motivo para
    # derrubar o setup.
    aviso "nao consegui descobrir a versao atual do Quarto -- instale manualmente: https://quarto.org/docs/get-started/"
    return 0
  fi

  # Pacote do sistema e o caminho preferido (entra no PATH de todo mundo e
  # sai pelo gerenciador). Sem root utilizavel, o tarball em ~/.local resolve
  # igual -- e melhor que terminar sem Quarto nenhum.
  if sudo -n true 2>/dev/null; then
    instalar_pacote_baixado "$url" "Quarto CLI" && return 0
    aviso "tentando o tarball em ~/.local no lugar"
  else
    info "sem sudo sem senha -- instalando o Quarto em ~/.local"
  fi

  case "$(uname -m)" in
    x86_64)  url_tar="$(url_release_github quarto-dev/quarto-cli 'linux-amd64\.tar\.gz$')" ;;
    aarch64) url_tar="$(url_release_github quarto-dev/quarto-cli 'linux-arm64\.tar\.gz$')" ;;
  esac

  if [ -z "${url_tar:-}" ]; then
    aviso "nao consegui descobrir o tarball do Quarto -- instale manualmente: https://quarto.org/docs/get-started/"
    return 0
  fi

  instalar_quarto_tarball "$url_tar" ||
    aviso "instale manualmente: https://quarto.org/docs/get-started/"
  return 0
}

# instalar_whatsapp -- ZapZap do Flathub, aparecendo como "WhatsApp".
#
#   A Meta nao publica cliente de desktop para Linux. O que existe no Flathub
#   sao wrappers de terceiros em volta do WhatsApp Web; o ZapZap e o mais
#   ativo deles. Isso esta dito aqui e no pacotes.yaml de proposito: instalar
#   um wrapper e confiar suas mensagens a um empacotador independente, e quem
#   ler este repo daqui a um ano merece saber disso sem ter que descobrir.
#
#   O atalho vem com o nome "ZapZap" e um icone cinza, o que faz ninguem
#   achar o programa procurando por "WhatsApp" no menu. A funcao escreve um
#   .desktop em ~/.local/share/applications, que tem precedencia sobre o do
#   Flatpak, so trocando nome e icone -- o Exec continua sendo o do ZapZap.
instalar_whatsapp() {
  local origem destino icone alvo_icone
  local app=com.rtosta.zapzap

  instalar_flatpak "$app" "WhatsApp (ZapZap)"

  # Se o Flatpak nao entrou, nao ha atalho para renomear.
  flatpak list --app --columns=application 2>/dev/null | grep -qx "$app" || return 0

  origem=""
  for d in /var/lib/flatpak/exports/share/applications \
           "$HOME/.local/share/flatpak/exports/share/applications"; do
    [ -f "$d/$app.desktop" ] && { origem="$d/$app.desktop"; break; }
  done
  [ -z "$origem" ] && return 0

  # Icone: procurado entre os temas ja instalados, nunca baixado. Se a maquina
  # nao tiver nenhum icone de WhatsApp, fica o do ZapZap mesmo -- melhor que
  # buscar logo de terceiro num endereco qualquer.
  icone="$(find /usr/share/icons "$HOME/.local/share/icons" \
                /var/lib/flatpak/exports/share/icons \
                -iname 'whatsapp.svg' -o -iname 'whatsapp.png' 2>/dev/null | head -1)"

  destino="$HOME/.local/share/applications/$app.desktop"
  mkdir -p "$(dirname "$destino")"

  if [ -n "$icone" ]; then
    # Copiado para hicolor porque e o tema que todo os outros herdam: assim o
    # icone aparece independente do tema que o usuario estiver usando.
    alvo_icone="$HOME/.local/share/icons/hicolor/scalable/apps/whatsapp-zapzap.${icone##*.}"
    mkdir -p "$(dirname "$alvo_icone")"
    cp -f "$icone" "$alvo_icone"
    # Name[xx]= traduzidos sao APAGADOS, nao convertidos: transformar cada um
    # em "Name=" produziria chave repetida, que torna o .desktop invalido.
    sed -e 's/^Name=.*/Name=WhatsApp/' \
        -e '/^Name\[/d' \
        -e 's/^Icon=.*/Icon=whatsapp-zapzap/' "$origem" > "$destino"
  else
    aviso "sem icone de WhatsApp nos temas instalados -- mantendo o do ZapZap"
    sed -e 's/^Name=.*/Name=WhatsApp/' -e '/^Name\[/d' "$origem" > "$destino"
  fi

  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
  command -v gtk-update-icon-cache >/dev/null 2>&1 &&
    gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null

  ok "WhatsApp (ZapZap) no menu como \"WhatsApp\""
  return 0
}

# avisar_jogos -- diz o que o Linux NAO vai rodar, antes de o usuario descobrir
#   sozinho no meio de uma partida.
#
#   Nao e pessimismo: a maioria esmagadora do catalogo roda por Proton, e em
#   GPU AMD costuma rodar bem. O que trava e uma coisa so -- anticheat que
#   exige modulo de kernel, e cujo fabricante escolheu nao permitir Linux. Nao
#   ha ajuste, driver ou Proton que resolva: e decisao do editor do jogo.
avisar_jogos() {
  echo
  aviso "jogos com anticheat de kernel NAO rodam no Linux, por decisao do editor:"
  echo "    Fortnite, Valorant, League of Legends, Roblox, GTA V e VI,"
  echo "    EA SPORTS FC, Apex Legends, Destiny 2, Rainbow Six Siege,"
  echo "    Call of Duty, PUBG, Rust, Delta Force."
  echo
  echo "    Rodam normalmente: Counter-Strike 2, Elden Ring, Overwatch 2,"
  echo "    Dead by Daylight, Marvel Rivals, Genshin Impact e a maior parte"
  echo "    do catalogo de um jogador so."
  echo
  echo "    Confira um titulo antes de comprar:"
  echo "      https://protondb.com          -- relatos de quem jogou"
  echo "      https://areweanticheatyet.com -- situacao do anticheat"
  echo
  echo "    No Steam: Configuracoes > Compatibilidade > ligar o Proton para"
  echo "    todos os titulos. Sem isso a loja esconde os jogos de Windows."
  return 0
}

# expor_pandoc -- deixa o pandoc do Quarto visivel no PATH.
#
#   O rmarkdown (.Rmd sem Quarto) chama o pandoc do sistema e para com
#   "pandoc version 2.8 or higher is required" quando nao acha. No Fedora
#   isso e garantido: a distribuicao nao empacota o pandoc solto, so as
#   bibliotecas Haskell. Mas o Quarto ja traz um pandoc completo dentro
#   dele, entao o certo e apontar para esse -- nao instalar um segundo.
#
#   Um link em ~/.local/bin resolve para o R, o RStudio e o terminal de uma
#   vez, sem mexer em .bashrc de ninguem.
expor_pandoc() {
  local quarto_bin raiz pandoc bin="$HOME/.local/bin"

  if command -v pandoc >/dev/null 2>&1; then
    ok "pandoc: $(command -v pandoc)"
    return 0
  fi

  quarto_bin="$(command -v quarto 2>/dev/null || echo "$HOME/.local/bin/quarto")"
  [ -x "$quarto_bin" ] || return 0

  # Resolve o link para chegar na arvore real do Quarto (~/.local/opt/quarto
  # ou /opt/quarto, conforme tenha vindo por tarball ou por pacote).
  quarto_bin="$(readlink -f "$quarto_bin")"
  raiz="$(dirname "$(dirname "$quarto_bin")")"

  # Procurado em vez de escrito: o caminho tem a arquitetura no meio
  # (bin/tools/x86_64/pandoc) e ja mudou de forma entre versoes do Quarto.
  pandoc="$(find "$raiz" -type f -name pandoc -perm -u+x 2>/dev/null | head -1)"
  if [ -z "$pandoc" ]; then
    aviso "nao achei o pandoc dentro do Quarto -- .Rmd em PDF pode falhar"
    return 0
  fi

  mkdir -p "$bin"
  ln -sf "$pandoc" "$bin/pandoc"
  ok "pandoc do Quarto exposto em $bin/pandoc ($("$pandoc" --version | head -1))"
  return 0
}

# garantir_latex -- LaTeX que se completa sozinho, para renderizar PDF.
#
#   Instala o TinyTeX MESMO quando ja existe LaTeX do sistema, e isso e
#   deliberado. Medido nesta maquina em 13/09/2026: com o texlive do Fedora
#   (263 pacotes instalados), "quarto render" de um .qmd com chunk de R
#   morria em "LaTeX Error: File `framed.sty' not found" -- e o tlmgr que
#   vem da distribuicao nao instala pacote sob demanda, porque quem manda
#   nos arquivos e o dnf. O caminho la seria caçar texlive-<pacote> um a um,
#   a cada documento novo.
#
#   O TinyTeX resolve pela raiz: no mesmo documento ele baixou framed,
#   selnolig e hyphen-portuguese sozinho, durante o render. Mora em
#   ~/.TinyTeX, nao precisa de root e nao conflita com o texlive do sistema.
garantir_latex() {
  local quarto_bin

  if [ -d "$HOME/.TinyTeX" ]; then
    ok "TinyTeX ja instalado"
    return 0
  fi

  # Pode ter acabado de ser instalado em ~/.local/bin, que ainda nao esta no
  # PATH deste shell.
  if command -v quarto >/dev/null 2>&1; then
    quarto_bin="quarto"
  elif [ -x "$HOME/.local/bin/quarto" ]; then
    quarto_bin="$HOME/.local/bin/quarto"
  else
    aviso "sem Quarto -- sem ele nao instalo o TinyTeX; PDF nao vai renderizar"
    return 0
  fi

  info "instalando TinyTeX (LaTeX para PDF, ~200 MB, sem root)"
  "$quarto_bin" install tinytex --no-prompt >/dev/null 2>&1 ||
    aviso "o TinyTeX falhou -- rode 'quarto install tinytex' manualmente"
  return 0
}

# instalar_rstudio -- baixa e instala o .rpm/.deb oficial da Posit.
#   O RStudio Desktop nao esta no dnf nem no apt (fica "-" no manifesto), a
#   Posit nao publica repositorio para Linux e ele tambem nao existe no
#   Flathub -- entao nem o caminho do DBeaver/Obsidian serve aqui. Sobra o
#   arquivo avulso do site, que e o que esta funcao faz.
#
#   Os enderecos "latest" abaixo redirecionam sempre para a versao estavel
#   atual, de proposito: numero de versao fixo aqui dentro envelheceria e
#   quebraria calado, como ja aconteceu com o java-17-openjdk-devel.
instalar_rstudio() {
  local url

  # Pergunta ao gerenciador alem do PATH: o pacote da Posit ja mudou de lugar
  # de binario entre versoes, e um "command -v" sozinho baixaria 500 MB de
  # novo a cada run se o link em /usr/bin mudasse de nome.
  if command -v rstudio >/dev/null 2>&1 ||
     { [ "$GER" = "dnf" ] && rpm -q rstudio >/dev/null 2>&1; } ||
     { [ "$GER" = "apt" ] && dpkg -s rstudio >/dev/null 2>&1; }; then
    ok "RStudio ja instalado"
    return 0
  fi

  # A Posit so publica RStudio Desktop para Linux em x86_64: em ARM nao ha
  # arquivo para baixar, e insistir so geraria um 404 confuso.
  if [ "$(uname -m)" != "x86_64" ]; then
    aviso "a Posit nao publica RStudio Desktop para $(uname -m) -- veja https://posit.co/download/rstudio-desktop/"
    return 0
  fi

  case "$GER" in
    dnf) url="https://rstudio.org/download/latest/stable/desktop/rhel9/rstudio-latest-x86_64.rpm" ;;
    apt) url="https://rstudio.org/download/latest/stable/desktop/jammy/rstudio-latest-amd64.deb" ;;
    *)   return 0 ;;
  esac

  instalar_pacote_baixado "$url" "RStudio Desktop (arquivo grande)" ||
    aviso "instale manualmente: https://posit.co/download/rstudio-desktop/"
  return 0
}

# Programas que nao vem em repositorio de distribuicao.
instalar_avulsos() {
  # Cada ferramenta so entra se o stack correspondente estiver ligado. Numa
  # maquina que pediu apenas "base", nada disto e instalado.
  local quer_python=0 quer_dados=0 quer_escritorio=0 quer_opcional=0 quer_editor=0 quer_r=0 quer_pessoal=0 quer_jogos=0
  if [ -n "$GRUPO" ]; then
    [ "$GRUPO" = "python" ]     && quer_python=1
    [ "$GRUPO" = "dados" ]      && quer_dados=1
    [ "$GRUPO" = "escritorio" ] && quer_escritorio=1
    [ "$GRUPO" = "opcional" ]   && quer_opcional=1
    [ "$GRUPO" = "editor" ]     && quer_editor=1
    [ "$GRUPO" = "r" ]          && quer_r=1
    [ "$GRUPO" = "pessoal" ]    && quer_pessoal=1
    [ "$GRUPO" = "jogos" ]      && quer_jogos=1
  else
    tem_stack python     && quer_python=1
    tem_stack dados      && quer_dados=1
    tem_stack escritorio && quer_escritorio=1
    tem_stack opcional   && quer_opcional=1
    tem_stack editor     && quer_editor=1
    tem_stack r          && quer_r=1
    tem_stack pessoal    && quer_pessoal=1
    tem_stack jogos      && quer_jogos=1
  fi

  if [ "$quer_python" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o uv"
    elif command -v uv >/dev/null 2>&1; then
      ok "uv ja instalado"
    else
      # Instalador oficial da Astral; vai para ~/.local/bin, sem sudo. Sob
      # set -e, um curl que falha (rede instavel, proxy corporativo)
      # abortaria o setup-linux.sh inteiro -- inclusive o que vem depois do
      # bloco de Python e nao tem nada a ver com ele (DuckDB, DBeaver,
      # ONLYOFFICE, Obsidian, Docker). Mesmo tratamento que essas ferramentas
      # ja recebem: falha de terceiro vira aviso, nao aborta o resto.
      info "instalando uv"
      curl -LsSf https://astral.sh/uv/install.sh | sh ||
        aviso "nao consegui instalar o uv -- sem rede ou astral.sh bloqueado. Rode de novo, ou instale manualmente: https://docs.astral.sh/uv/"
    fi
  fi

  # Spotify e WhatsApp nao existem no dnf/apt. O Spotify distribui pelo
  # Flathub; o WhatsApp nao tem cliente oficial para Linux nenhum (ver
  # instalar_whatsapp).
  if [ "$quer_pessoal" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o Spotify e o WhatsApp (ZapZap) via Flatpak"
    else
      instalar_flatpak com.spotify.Client "Spotify"
      instalar_whatsapp
    fi
  fi

  # Steam, Heroic e ProtonUp-Qt vem do Flathub. O Steam do dnf exigiria o RPM
  # Fusion nonfree; o Flatpak nao exige nada e traz o runtime de 32 bits que a
  # maioria dos jogos precisa. A Epic nao publica launcher para Linux -- quem
  # faz esse papel e o Heroic.
  if [ "$quer_jogos" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria Steam, Heroic e ProtonUp-Qt via Flatpak"
    else
      instalar_flatpak com.valvesoftware.Steam "Steam"
      instalar_flatpak com.heroicgameslauncher.hgl "Heroic (Epic, GOG, Amazon)"
      instalar_flatpak net.davidotek.pupgui2 "ProtonUp-Qt"
      avisar_jogos
    fi
  fi

  if [ "$quer_r" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o RStudio Desktop, o Quarto CLI e o TinyTeX"
    else
      instalar_rstudio
      instalar_quarto
      # Os dois dependem do Quarto ja estar no disco: um usa o pandoc que
      # vem dentro dele, o outro e instalado por ele.
      expor_pandoc
      garantir_latex
    fi
  fi

  if [ "$quer_dados" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o DuckDB CLI e o DBeaver"
    else
      # DuckDB CLI: binario unico, sem dependencia.
      if command -v duckdb >/dev/null 2>&1; then
        ok "duckdb ja instalado"
      else
        info "instalando DuckDB CLI"
        curl -fsSL https://install.duckdb.org | sh ||
          aviso "nao consegui instalar o DuckDB CLI -- instale manualmente: https://duckdb.org"
      fi

      # DBeaver via Flatpak: evita conflito de versao de JDK com o Spark.
      instalar_flatpak io.dbeaver.DBeaverCommunity "DBeaver"
    fi
  fi

  # ONLYOFFICE e Obsidian nao existem no dnf nem no apt (ficam "-" no
  # manifesto, e o pacotes_para pula em silencio). Sem isto, quem escolhe
  # "escritorio" ou "opcional" no configurar.sh -- que promete os dois pelo
  # nome -- nao recebe nem o programa nem um aviso.
  if [ "$quer_escritorio" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o ONLYOFFICE"
    else
      instalar_flatpak org.onlyoffice.desktopeditors "ONLYOFFICE"
    fi
  fi

  if [ "$quer_opcional" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o Obsidian"
    else
      instalar_flatpak md.obsidian.Obsidian "Obsidian"
    fi
  fi

  # O manifesto nao tem entrada de gerenciador que sirva para o Claude Code
  # (CLI): nao ha pacote no dnf/apt, e ainda nao foi confirmado se existe
  # formula/pacote no brew, winget ou scoop -- por isso o id "claude-code"
  # no pacotes.yaml fica com tudo "-", so para documentar que o kit cuida
  # dele, e o Linux e resolvido aqui, igual ao uv.
  if [ "$quer_editor" = "1" ]; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] instalaria o Claude Code (CLI)"
    elif command -v claude >/dev/null 2>&1; then
      ok "Claude Code (CLI) ja instalado"
    else
      # Instalador oficial da Anthropic; nao depende de npm/Node, embora o
      # stack "editor" ja traga os dois para a extensao do VS Code.
      info "instalando Claude Code (CLI)"
      curl -fsSL https://claude.ai/install.sh | bash ||
        aviso "nao consegui instalar o Claude Code -- instale manualmente: https://docs.claude.com/en/docs/claude-code/setup"
    fi
  fi

  [ "$quer_python" = "0" ] && [ "$quer_dados" = "0" ] &&
    [ "$quer_escritorio" = "0" ] && [ "$quer_opcional" = "0" ] &&
    [ "$quer_editor" = "0" ] && [ "$quer_r" = "0" ] &&
    [ "$quer_pessoal" = "0" ] && [ "$quer_jogos" = "0" ] &&
    ok "nenhuma ferramenta avulsa pedida"
  return 0
}

# --------------------------------------------------------------- pendencias --
# avisar_indisponiveis -- conta o que os grupos pedidos NAO trouxeram.
#   Pacote marcado "-" no manifesto e pulado em silencio por pacotes_para, e
#   foi assim que o RStudio sumiu de um setup do stack "r" sem uma linha
#   explicando por que. Aqui o silencio vira aviso, guiado pela chave "linux"
#   do manifesto: "avulso" ja foi tratado acima (e quem falha la avisa por si),
#   "nao" nao existe neste sistema, e a ausencia da chave e um esquecimento no
#   manifesto -- que passa a aparecer em vez de sumir.
avisar_indisponiveis() {
  local g id nome sem_linux=""

  while IFS= read -r g; do
    [ -z "$g" ] && continue
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      [ -n "$(manifesto_valor "$id" "$GER")" ] && continue
      nome="$(manifesto_valor "$id" nome)"
      nome="${nome:-$id}"
      case "$(manifesto_valor "$id" linux)" in
        avulso) ;;
        # Nesta linha entra so o nome, sem o parenteses explicativo do
        # manifesto ("Everything (busca instantanea...)"): sao varios juntos
        # e a linha inteira precisa caber na tela.
        nao)    sem_linux="${sem_linux:+$sem_linux, }${nome%% (*}" ;;
        *)      aviso "$nome nao tem pacote no $GER e ninguem mais o instala -- instale a mao (ou marque 'linux:' no pacotes.yaml)" ;;
      esac
    done < <(manifesto_ids "$g")
  done < <(grupos_pedidos)

  # Numa linha so: sao programas que nunca vao existir aqui (PowerToys,
  # Rtools, Microsoft 365...), entao um aviso por item viraria ruido em todo
  # run -- mas ficar calado deixa quem escolheu o grupo achando que falhou.
  [ -n "$sem_linux" ] &&
    aviso "sem equivalente no Linux, fora deste setup: $sem_linux"
  return 0
}

# ------------------------------------------------------------- pos-instalacao
# quer_pos <grupo> -- verdadeiro quando aquele grupo entrou neste run.
#   Mudar grupo de usuario e habilitar servico sao mudancas de sistema que
#   ninguem quer de surpresa: so acontecem para o que foi pedido.
quer_pos() {
  if [ -n "$GRUPO" ]; then
    [ "$GRUPO" = "$1" ]
  else
    tem_stack "$1"
  fi
}

pos_instalacao() {
  if quer_pos container; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] habilitaria o docker e adicionaria o usuario ao grupo"
    elif command -v docker >/dev/null 2>&1 && [ "$OS" = "linux" ]; then
      sudo systemctl enable --now docker 2>/dev/null ||
        aviso "nao consegui habilitar o servico docker"
      # Sem isso, todo comando docker exige sudo.
      if ! id -nG | tr ' ' '\n' | grep -qx docker; then
        sudo usermod -aG docker "$USER"
        aviso "adicionado ao grupo docker -- faca logout/login para valer"
      fi
    fi
  fi

  # GameMode sem o grupo instala e nao faz nada: a regra do polkit do Fedora
  # (/usr/share/polkit-1/rules.d/gamemode.rules) so libera os helpers de
  # governor e de GPU para quem esta no grupo "gamemode". Fora dele, o daemon
  # sobe, aceita o jogo e falha em silencio no pkexec -- o governor da CPU
  # continua em "schedutil" durante a partida, que e justamente o que o
  # GameMode existe para mudar.
  if quer_pos jogos; then
    if [ "$SIMULAR" = "1" ]; then
      info "[simular] adicionaria o usuario ao grupo gamemode"
    elif getent group gamemode >/dev/null 2>&1; then
      if ! id -nG | tr ' ' '\n' | grep -qx gamemode; then
        sudo usermod -aG gamemode "$USER" &&
          aviso "adicionado ao grupo gamemode -- faca logout/login para valer" ||
          aviso "nao consegui adicionar ao grupo gamemode; o GameMode nao vai mudar o governor"
      else
        ok "ja esta no grupo gamemode"
      fi
    fi
  fi
  return 0
}

# -------------------------------------------------------------------- fluxo --
configurar_repos
instalar_pacotes
instalar_avulsos
# Depois dos instaladores, para que o aviso fique no fim da tela em vez de
# rolar junto com a saida do dnf.
avisar_indisponiveis
pos_instalacao

echo
info "setup concluido. Proximos passos:"
echo "  1. ./install.sh --extensoes   aplica configuracoes e extensoes"

# As bibliotecas sao passo separado: o setup-linux.sh instala o interpretador
# e o uv, nunca os pacotes. Sem lembrar aqui, quem segue o terminal -- e nao o
# README -- termina com Python instalado e "No module named pandas".
passo=2
if [ -n "${LIBS_PY:-}" ]; then
  echo "  $passo. ./scripts/setup-python.sh   bibliotecas de Python (~/.venvs/lab)"
  passo=$(( passo + 1 ))
fi
if [ -n "${LIBS_R:-}" ]; then
  echo "  $passo. ./scripts/setup-r.sh        bibliotecas de R"
  passo=$(( passo + 1 ))
fi

echo "  $passo. gh auth login              reautentica o GitHub"
passo=$(( passo + 1 ))
echo "  $passo. ./scripts/cofre.sh abrir   restaura o cofre de segredos"

# O venv e invisivel para o python3 do sistema. E a duvida numero um depois
# de instalar: "instalou, mas o import falha".
if [ -n "${LIBS_PY:-}" ]; then
  echo
  echo "  As bibliotecas de Python vao para ~/.venvs/lab, nao para o Python"
  echo "  do sistema. Para usa-las: source ~/.venvs/lab/bin/activate"
fi
