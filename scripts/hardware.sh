#!/usr/bin/env bash
# ============================================================================
# hardware.sh -- identifica o hardware e diz o que instalar por causa dele
#
# Nao instala nada. Detecta CPU, GPU, rede, bluetooth e disco, e imprime os
# pacotes e ajustes que aquele hardware especifico pede. O
# fedora-pos-instalacao.sh consome esta deteccao.
#
# Uso:
#   ./scripts/hardware.sh            relatorio legivel
#   ./scripts/hardware.sh --exportar imprime CHAVE=valor, para outro script
# ============================================================================

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

EXPORTAR=0
[ "${1:-}" = "--exportar" ] && EXPORTAR=1

OS="$(detectar_os)"

# ---------------------------------------------------------------------- CPU --
CPU_MODELO="desconhecido"
CPU_FABRICANTE="desconhecido"
CPU_NUCLEOS=""
CPU_THREADS=""
CPU_VIRTUALIZACAO="nao"

if [ -r /proc/cpuinfo ]; then
  CPU_MODELO="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
  CPU_THREADS="$(grep -c '^processor' /proc/cpuinfo)"
  CPU_NUCLEOS="$(awk -F': ' '/cpu cores/ {print $2; exit}' /proc/cpuinfo)"
  # svm = AMD-V, vmx = Intel VT-x. Sem isso nao ha Docker com maquina virtual
  # nem WSL2 -- e costuma estar desligado na BIOS de fabrica.
  if grep -qE '^flags.*\b(svm|vmx)\b' /proc/cpuinfo; then
    CPU_VIRTUALIZACAO="sim"
  fi
  case "$CPU_MODELO" in
    *AMD*)   CPU_FABRICANTE="amd" ;;
    *Intel*) CPU_FABRICANTE="intel" ;;
  esac
elif [ "$OS" = "macos" ]; then
  CPU_MODELO="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  CPU_NUCLEOS="$(sysctl -n hw.physicalcpu 2>/dev/null)"
  CPU_THREADS="$(sysctl -n hw.logicalcpu 2>/dev/null)"
  case "$CPU_MODELO" in
    *Apple*) CPU_FABRICANTE="apple" ;;
    *Intel*) CPU_FABRICANTE="intel" ;;
  esac
fi

# ---------------------------------------------------------------------- GPU --
GPU_MODELO="desconhecido"
GPU_FABRICANTE="desconhecido"

if command -v lspci >/dev/null 2>&1; then
  # A classe VGA cobre a placa principal; 3D controller pega GPU secundaria.
  GPU_LINHA="$(lspci | grep -iE 'vga|3d controller' | head -1)"
  GPU_MODELO="${GPU_LINHA#*: }"
  case "$GPU_LINHA" in
    *AMD*|*ATI*|*Radeon*) GPU_FABRICANTE="amd" ;;
    *NVIDIA*)             GPU_FABRICANTE="nvidia" ;;
    *Intel*)              GPU_FABRICANTE="intel" ;;
  esac
elif [ "$OS" = "macos" ]; then
  GPU_MODELO="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/ {print $2; exit}')"
  GPU_FABRICANTE="apple"
fi

# ----------------------------------------------------------- rede/bluetooth --
REDE_MODELO=""
BLUETOOTH_MODELO=""

if command -v lspci >/dev/null 2>&1; then
  REDE_MODELO="$(lspci | grep -iE 'network|ethernet' | head -2 | sed 's/^[^:]*: //' | paste -sd '; ' -)"
fi
if command -v lsusb >/dev/null 2>&1; then
  BLUETOOTH_MODELO="$(lsusb | grep -i bluetooth | sed 's/.*: //' | head -1)"
fi
if [ -z "$BLUETOOTH_MODELO" ] && command -v lspci >/dev/null 2>&1; then
  BLUETOOTH_MODELO="$(lspci | grep -i bluetooth | sed 's/^[^:]*: //' | head -1)"
fi

# -------------------------------------------------------------------- disco --
DISCO_NVME="nao"
DISCO_SSD="nao"
if command -v lsblk >/dev/null 2>&1; then
  lsblk -d -o NAME 2>/dev/null | grep -q '^nvme' && DISCO_NVME="sim"
  # ROTA=0 significa disco nao rotacional, ou seja SSD.
  lsblk -d -o ROTA 2>/dev/null | grep -q '^ *0' && DISCO_SSD="sim"
fi

# ------------------------------------------------------------------ memoria --
MEMORIA_GB=""
if [ -r /proc/meminfo ]; then
  MEMORIA_GB="$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)"
elif [ "$OS" = "macos" ]; then
  MEMORIA_GB="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"
fi

# ---------------------------------------------------------------- exportar ---
if [ "$EXPORTAR" = "1" ]; then
  printf 'HW_CPU_FABRICANTE="%s"\n' "$CPU_FABRICANTE"
  printf 'HW_CPU_MODELO="%s"\n'     "$CPU_MODELO"
  printf 'HW_CPU_NUCLEOS="%s"\n'    "$CPU_NUCLEOS"
  printf 'HW_CPU_THREADS="%s"\n'    "$CPU_THREADS"
  printf 'HW_VIRTUALIZACAO="%s"\n'  "$CPU_VIRTUALIZACAO"
  printf 'HW_GPU_FABRICANTE="%s"\n' "$GPU_FABRICANTE"
  printf 'HW_GPU_MODELO="%s"\n'     "$GPU_MODELO"
  printf 'HW_NVME="%s"\n'           "$DISCO_NVME"
  printf 'HW_MEMORIA_GB="%s"\n'     "$MEMORIA_GB"
  exit 0
fi

# --------------------------------------------------------------- relatorio ---
echo
info "Hardware detectado"
echo
printf '  CPU         %s\n' "${CPU_MODELO:-desconhecido}"
[ -n "$CPU_NUCLEOS" ] && printf '              %s nucleos / %s threads\n' "$CPU_NUCLEOS" "$CPU_THREADS"
printf '  GPU         %s\n' "${GPU_MODELO:-desconhecido}"
[ -n "$MEMORIA_GB" ] && printf '  Memoria     %s GB\n' "$MEMORIA_GB"
[ -n "$REDE_MODELO" ] && printf '  Rede        %s\n' "$REDE_MODELO"
[ -n "$BLUETOOTH_MODELO" ] && printf '  Bluetooth   %s\n' "$BLUETOOTH_MODELO"
printf '  NVMe        %s\n' "$DISCO_NVME"

echo
info "O que este hardware pede"
echo

# --- virtualizacao ---
if eh_container; then
  # Dentro de container as flags da CPU chegam filtradas pelo hipervisor: o
  # teste daria falso negativo e mandaria o usuario mexer na BIOS a toa.
  ok "rodando em container -- checagem de virtualizacao nao se aplica"
elif [ "$CPU_VIRTUALIZACAO" = "sim" ]; then
  ok "virtualizacao habilitada (Docker e maquinas virtuais funcionam)"
else
  aviso "virtualizacao NAO habilitada na CPU"
  echo "      Ligue na BIOS: SVM Mode (AMD) ou Intel VT-x."
  echo "      Sem isso, Docker e WSL2 nao sobem."
fi

# --- GPU ---
case "$GPU_FABRICANTE" in
  amd)
    ok "GPU AMD -- o driver amdgpu ja vem no kernel, nada a instalar"
    echo "      Para decodificacao de video por hardware (VA-API):"
    echo "        sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld"
    echo "        sudo dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld"
    echo "      E swap, nao install: os pacotes -freeworld do RPM Fusion"
    echo "      CONFLITAM com os do Fedora, que saem sem os codecs patenteados"
    echo "      (H.264, HEVC). Um install simples falha por conflito."
    echo "      Vulkan:"
    echo "        sudo dnf install vulkan-tools mesa-vulkan-drivers"
    echo "      Conferir depois: vainfo   e   vulkaninfo --summary"
    ;;
  nvidia)
    aviso "GPU NVIDIA -- exige driver proprietario para desempenho decente"
    echo "        sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda"
    echo "      Espere o modulo compilar (uns 5 min) antes de reiniciar:"
    echo "        modinfo -F version nvidia"
    ;;
  intel)
    ok "GPU Intel -- driver no kernel"
    echo "        sudo dnf install intel-media-driver libva-intel-driver"
    ;;
  *)
    aviso "GPU nao identificada -- nenhuma recomendacao especifica"
    ;;
esac

echo

# --- CPU ---
case "$CPU_FABRICANTE" in
  amd)
    echo "  CPU AMD:"
    echo "        sudo dnf install amd-gpu-firmware linux-firmware"
    # O amd_pstate melhora consumo e frequencia em Zen 2 e mais novos, mas
    # nao e padrao em todo kernel -- por isso e sugestao, nao automacao.
    echo "      Governador moderno de frequencia (Zen 2+), opcional:"
    echo "        cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
    echo "        se nao disser amd-pstate, veja docs/fedora-kde-primeiros-passos.md"
    ;;
  intel)
    echo "  CPU Intel:"
    echo "        sudo dnf install microcode_ctl"
    ;;
esac

echo

# --- rede e bluetooth ---
if [ -n "$BLUETOOTH_MODELO" ]; then
  case "$BLUETOOTH_MODELO" in
    *Intel*)
      ok "Bluetooth Intel -- firmware ja vem em linux-firmware, funciona sem ajuste"
      ;;
    *Realtek*)
      aviso "Bluetooth Realtek -- alguns modelos precisam de firmware extra"
      echo "        sudo dnf install linux-firmware"
      ;;
    *)
      echo "  Bluetooth: $BLUETOOTH_MODELO"
      echo "        se nao funcionar: sudo dnf install linux-firmware bluez bluez-tools"
      ;;
  esac
fi

if printf '%s' "$REDE_MODELO" | grep -qi realtek; then
  aviso "rede Realtek -- alguns modelos (RTL8125, RTL8852) pedem driver do RPM Fusion"
  echo "        sudo dnf install akmod-realtek-rtw89   # conforme o modelo"
fi

# --- disco ---
echo
if [ "$DISCO_SSD" = "sim" ]; then
  echo "  SSD detectado:"
  echo "        systemctl enable --now fstrim.timer   # TRIM semanal"
fi

echo
info "Nada acima foi executado. Para aplicar com confirmacao passo a passo:"
echo "    ./scripts/fedora-pos-instalacao.sh"
