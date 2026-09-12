#!/usr/bin/env bash
# ============================================================================
# fedora-pos-instalacao.sh -- o que todo Fedora KDE precisa depois de instalar
#
# Cada passo PERGUNTA antes de executar. Nada roda sozinho, exceto com --sim,
# que responde sim a tudo (util para reinstalar sem supervisao).
#
# Cobre o que o Fedora deliberadamente nao instala por questao de licenca ou
# patente, mais os ajustes que a maioria dos guias de pos-instalacao repete.
#
# Os passos podem ser desligados de antemao no perfil.conf:
#   FEDORA_RPMFUSION, FEDORA_CODECS, FEDORA_GPU, FEDORA_FIRMWARE,
#   FEDORA_FONTES_MS, FEDORA_DNF_RAPIDO
#
# Uso:
#   ./scripts/fedora-pos-instalacao.sh
#   ./scripts/fedora-pos-instalacao.sh --sim        sem perguntar
#   ./scripts/fedora-pos-instalacao.sh --simular    so mostra
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
carregar_perfil

SIMULAR=0
SIM_A_TUDO=0

while [ $# -gt 0 ]; do
  case "$1" in
    --sim)     SIM_A_TUDO=1; shift ;;
    --simular) SIMULAR=1; shift ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) morre "argumento desconhecido: $1" ;;
  esac
done

# Este script e so para Fedora: os nomes de pacote e o RPM Fusion nao existem
# em outras distribuicoes.
if [ ! -f /etc/fedora-release ]; then
  morre "este script e para Fedora. Detectado: $(detectar_os) / $(detectar_gerenciador)"
fi

VERSAO_FEDORA="$(rpm -E %fedora)"
info "Fedora $VERSAO_FEDORA detectado"
[ "$SIMULAR" = "1" ] && aviso "modo simulacao: nada sera executado"
[ "$SIM_A_TUDO" = "1" ] && aviso "modo --sim: executando sem perguntar"

# Detecta o hardware uma vez e reaproveita nas decisoes de driver.
# shellcheck disable=SC1090
eval "$("$DOTFILES_RAIZ/scripts/hardware.sh" --exportar)"
info "CPU: $HW_CPU_MODELO"
info "GPU: $HW_GPU_MODELO"
echo

# perguntar <texto> -- devolve 0 para sim. Respeita --sim e --simular.
perguntar() {
  [ "$SIM_A_TUDO" = "1" ] && return 0
  [ "$SIMULAR" = "1" ] && return 0
  printf '\n%s [S/n] ' "$1"
  read -r resposta
  case "$resposta" in
    [nN]*) return 1 ;;
    *)     return 0 ;;
  esac
}

# executar <comando...> -- roda ou so imprime, conforme --simular.
executar() {
  if [ "$SIMULAR" = "1" ]; then
    echo "    [simular] $*"
    return 0
  fi
  echo "    \$ $*"
  "$@"
}

# ============================================================================
# 1. DNF mais rapido
# ============================================================================
if [ "$FEDORA_DNF_RAPIDO" = "sim" ]; then
  info "1. Acelerar o DNF"
  echo "   Downloads em paralelo e escolha do espelho mais rapido."
  echo "   O padrao do Fedora e conservador: 3 downloads por vez."
  if perguntar "   Aplicar?"; then
    # config-manager setopt e o jeito suportado no dnf5 (Fedora 41+);
    # editar /etc/dnf/dnf.conf na mao ainda funciona, mas duplica chave
    # quando o script roda duas vezes.
    executar sudo dnf config-manager setopt max_parallel_downloads=10
    executar sudo dnf config-manager setopt fastestmirror=True
    ok "DNF ajustado"
  fi
fi

# ============================================================================
# 2. Atualizar o sistema
# ============================================================================
info "2. Atualizar o sistema"
echo "   A ISO tem semanas ou meses; ha correcao de seguranca e kernel novo."
if perguntar "   Atualizar agora?"; then
  executar sudo dnf upgrade --refresh -y
  ok "sistema atualizado"
  aviso "se o kernel mudou, reinicie antes de instalar driver de GPU"
fi

# ============================================================================
# 3. RPM Fusion
# ============================================================================
if [ "$FEDORA_RPMFUSION" = "sim" ]; then
  info "3. RPM Fusion"
  echo "   Repositorio com o que o Fedora nao distribui por patente ou licenca:"
  echo "   codecs de video, firmware e drivers."
  if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    ok "RPM Fusion ja instalado"
  elif perguntar "   Habilitar?"; then
    executar sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSAO_FEDORA}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${VERSAO_FEDORA}.noarch.rpm"
    # Sem o group update, os metadados do core nao passam a enxergar os
    # pacotes novos e o swap de codec falha logo depois.
    executar sudo dnf group update -y core
    ok "RPM Fusion habilitado"
  fi
fi

# ============================================================================
# 4. Codecs multimidia
# ============================================================================
if [ "$FEDORA_CODECS" = "sim" ]; then
  info "4. Codecs multimidia"
  echo "   Sem isto, o Fedora recem-instalado nao toca MP3, H.264, H.265 nem AAC."
  echo "   Vale para navegador, player e qualquer coisa que use GStreamer."
  if perguntar "   Instalar codecs?"; then
    # swap, nao install: o ffmpeg-free do Fedora sai sem os codecs
    # patenteados e ocupa o mesmo lugar do ffmpeg completo.
    executar sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    executar sudo dnf install -y \
      gstreamer1-plugins-good gstreamer1-plugins-bad-free \
      gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly \
      gstreamer1-plugin-libav gstreamer1-plugin-openh264
    executar sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
    ok "codecs instalados"
  fi
fi

# ============================================================================
# 5. Aceleracao de video por hardware
# ============================================================================
if [ "$FEDORA_GPU" = "sim" ]; then
  info "5. Aceleracao de video por hardware (GPU: $HW_GPU_FABRICANTE)"
  case "$HW_GPU_FABRICANTE" in
    amd)
      echo "   O driver amdgpu ja esta no kernel. Falta so o VA-API completo,"
      echo "   que no Fedora vem sem os codecs patenteados."
      if perguntar "   Trocar pelos drivers do RPM Fusion?"; then
        # swap e obrigatorio: os pacotes -freeworld CONFLITAM com os do
        # Fedora. Um "dnf install" simples falha por conflito de arquivo.
        executar sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
        executar sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
        executar sudo dnf install -y libva-utils vulkan-tools mesa-vulkan-drivers
        ok "VA-API e Vulkan prontos -- confira com: vainfo"
      fi
      ;;
    nvidia)
      echo "   GPU NVIDIA precisa do driver proprietario."
      aviso "   o modulo e compilado na hora (uns 5 min) e exige reboot"
      if perguntar "   Instalar akmod-nvidia?"; then
        executar sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
        aviso "espere o modulo terminar antes de reiniciar:"
        echo "      modinfo -F version nvidia"
      fi
      ;;
    intel)
      echo "   GPU Intel usa o driver do kernel; falta o decodificador."
      if perguntar "   Instalar intel-media-driver?"; then
        executar sudo dnf install -y intel-media-driver libva-utils
        ok "confira com: vainfo"
      fi
      ;;
    *)
      aviso "GPU nao identificada -- pulando"
      ;;
  esac
fi

# ============================================================================
# 6. Flathub
# ============================================================================
info "6. Flathub"
echo "   Os spins do Fedora (KDE incluso) NAO recebem a pergunta de repositorio"
echo "   de terceiros na primeira inicializacao -- so a edicao Workstation."
echo "   Sem isto, metade do catalogo de aplicativos nao aparece."
if flatpak remotes 2>/dev/null | grep -q flathub; then
  ok "Flathub ja configurado"
elif perguntar "   Habilitar o Flathub?"; then
  executar flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  ok "Flathub habilitado"
fi

# ============================================================================
# 7. Compactadores
# ============================================================================
info "7. Formatos de arquivo compactado"
echo "   RAR e 7z nao vem por padrao; o Ark do KDE fica sem saber abrir."
if perguntar "   Instalar unrar, p7zip e afins?"; then
  executar sudo dnf install -y unzip unrar p7zip p7zip-plugins
  ok "compactadores instalados"
fi

# ============================================================================
# 8. Codecs de audio Bluetooth
# ============================================================================
info "8. Codecs de audio Bluetooth (LDAC, AptX, AAC)"
echo "   Sem eles, fone Bluetooth cai no SBC e o audio fica visivelmente pior."
echo "   Vale para Galaxy Buds, Sony, Anker, Edifier e afins."

# LDAC e AAC estao no repositorio do Fedora; o AptX so existe no RPM Fusion
# (patente). Instalar em duas etapas evita que a falta do AptX derrube as
# outras duas.
CODECS_BT="libldac fdk-aac-free"
if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  CODECS_BT="$CODECS_BT libfreeaptx"
else
  aviso "   sem RPM Fusion: AptX ficara de fora (LDAC e AAC funcionam)"
fi

if perguntar "   Instalar?"; then
  # shellcheck disable=SC2086
  executar sudo dnf install -y $CODECS_BT
  aviso "reinicie o pipewire depois: systemctl --user restart pipewire pipewire-pulse"
fi

# ============================================================================
# 9. Firmware
# ============================================================================
if [ "$FEDORA_FIRMWARE" = "sim" ]; then
  info "9. Atualizacao de firmware (fwupd)"
  echo "   Atualiza BIOS, SSD e outros dispositivos pelo proprio Linux."
  if perguntar "   Procurar atualizacoes de firmware?"; then
    executar sudo fwupdmgr refresh --force
    executar fwupdmgr get-updates || true
    aviso "para aplicar: sudo fwupdmgr update   (pode reiniciar a maquina)"
  fi
fi

# ============================================================================
# 10. Fontes
# ============================================================================
info "10. Fontes"
echo "   Noto cobre praticamente todo alfabeto e emoji."
if perguntar "   Instalar o conjunto Noto?"; then
  executar sudo dnf install -y google-noto-fonts-common google-noto-sans-fonts \
    google-noto-serif-fonts google-noto-emoji-fonts
  ok "fontes instaladas"
fi

if [ "$FEDORA_FONTES_MS" = "sim" ]; then
  echo
  echo "   Fontes da Microsoft (Arial, Times New Roman, Calibri)."
  echo "   Uteis quando se abre documento do trabalho e o layout precisa bater."
  if perguntar "   Instalar as fontes da Microsoft?"; then
    executar sudo dnf install -y mscore-fonts-all
    ok "fontes da Microsoft instaladas"
  fi
fi

# ============================================================================
# 11. TRIM
# ============================================================================
if [ "$HW_NVME" = "sim" ] || [ "$SIM_A_TUDO" = "1" ]; then
  info "11. TRIM semanal (SSD/NVMe)"
  echo "   Mantem a velocidade de escrita do SSD ao longo do tempo."
  if perguntar "   Habilitar fstrim.timer?"; then
    executar sudo systemctl enable --now fstrim.timer
    ok "TRIM semanal habilitado"
  fi
fi

# ============================================================================
# 12. Impressora e scanner
# ============================================================================
info "12. Impressora e scanner"
echo "   O KDE nao instala o suporte completo por padrao."
if perguntar "   Instalar CUPS e drivers de scanner?"; then
  executar sudo dnf install -y cups system-config-printer sane-airscan simple-scan
  executar sudo systemctl enable --now cups
  ok "impressao e digitalizacao prontas"
fi

# ============================================================================
echo
ok "pos-instalacao concluida."
echo
info "Confira o resultado:"
echo "    vainfo                          aceleracao de video"
echo "    vulkaninfo --summary            Vulkan"
echo "    flatpak remotes                 Flathub habilitado"
echo "    systemctl status fstrim.timer   TRIM"
echo "    fastfetch                       resumo do sistema"
echo
info "Proximo passo: ./scripts/setup-linux.sh"
