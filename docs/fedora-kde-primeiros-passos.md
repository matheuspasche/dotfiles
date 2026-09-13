# Fedora KDE: primeiros passos

O que fazer numa instalacao nova para o sistema ficar liso. Escrito para quem
esta chegando ao Fedora, e ao KDE, pela primeira vez.

A maior parte esta automatizada em
[`scripts/fedora-pos-instalacao.sh`](../scripts/fedora-pos-instalacao.sh), que
**obedece as chaves `FEDORA_*` do seu `perfil.conf`** -- as mesmas que o
`configurar.sh` perguntou. Sem perfil, ele pergunta passo a passo. Este
documento explica o porque de cada um: util quando algo nao funciona e voce
precisa entender o que o script fez.

```bash
./scripts/hardware.sh                  # o que o seu hardware pede
./scripts/fedora-pos-instalacao.sh     # aplica o que o perfil pediu
```

Duas opcoes para o resto dos casos:

```bash
./scripts/fedora-pos-instalacao.sh --perguntar   # confirmar passo a passo
./scripts/fedora-pos-instalacao.sh --sim         # sem perguntar nada
```

---

## O que o Fedora deliberadamente nao instala

Essa e a chave para entender quase todo problema de Fedora recem-instalado.

O Fedora e patrocinado pela Red Hat, uma empresa americana, e por isso nao
distribui software com patente de software ativa nos Estados Unidos nem
codigo de licenca proprietaria. Isso deixa de fora, de fabrica:

- decodificacao de **H.264, H.265 e AAC** — video da web, arquivo do celular
- **aceleracao de video por hardware** completa na GPU
- drivers proprietarios da **NVIDIA**
- fontes da **Microsoft**
- **AptX** para audio Bluetooth

Nada disso e defeito, e politica. O conserto se chama **RPM Fusion**: um
repositorio comunitario que empacota exatamente o que o Fedora nao pode.

```bash
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf group update core
```

O `group update core` no fim nao e opcional: sem ele, os metadados nao passam
a enxergar os pacotes novos e o passo seguinte falha.

---

## A armadilha do `install` contra o `swap`

Este e o erro que mais aparece em guia desatualizado da internet.

Os pacotes do RPM Fusion que trazem os codecs **substituem** os do Fedora --
eles ocupam o mesmo lugar. Um `dnf install` simples falha com conflito de
arquivo. O comando certo e `swap`:

```bash
# Codecs: troca o ffmpeg capado pelo completo
sudo dnf swap ffmpeg-free ffmpeg --allowerasing

# Aceleracao de video AMD: troca os drivers VA-API
sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld
sudo dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
```

Confira depois com `vainfo`. Se listar perfis de H264 e HEVC, funcionou.

---

## O que e especifico do KDE

O Fedora KDE e um **spin**, nao a edicao Workstation. Duas consequencias
praticas que pegam todo mundo:

**1. Nao existe a pergunta de "repositorios de terceiros" na primeira
inicializacao.** Ela e exclusiva da Workstation. No KDE voce precisa habilitar
o Flathub na mao, senao metade do catalogo de aplicativos simplesmente nao
aparece na loja:

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

**2. O suporte a impressora e scanner nao vem completo.** Instale se for usar:

```bash
sudo dnf install cups system-config-printer sane-airscan simple-scan
sudo systemctl enable --now cups
```

### Equivalentes de PowerToys no KDE

Quem vem do Windows procura o PowerToys. O KDE ja traz a maior parte:

| PowerToys | KDE |
|---|---|
| FancyZones | KWin faz tiling nativo — atalho <kbd>Meta</kbd>+<kbd>T</kbd> em versoes recentes |
| PowerToys Run | KRunner — <kbd>Alt</kbd>+<kbd>Espaco</kbd> |
| PowerRename | Ferramenta de renomear em lote do Dolphin — <kbd>F2</kbd> com varios arquivos |
| Color Picker | Spectacle e o seletor de cor do KDE |
| Always on Top | Clique direito na barra de titulo > Mais acoes |

O que vale instalar a mais:

```bash
sudo dnf install kate spectacle filelight kcalc
```

`filelight` responde "quem comeu meu disco" melhor que qualquer coisa
equivalente no Windows.

---

## Audio Bluetooth

Sem os codecs, todo fone Bluetooth cai no **SBC** e o audio fica visivelmente
pior. LDAC e AAC estao no repositorio do Fedora; AptX so no RPM Fusion:

```bash
sudo dnf install libldac fdk-aac-free   # Fedora
sudo dnf install libfreeaptx            # requer RPM Fusion
systemctl --user restart pipewire pipewire-pulse
```

Confira o codec em uso nas configuracoes de som do KDE, no dispositivo
conectado. Galaxy Buds e a maioria dos fones Android usam AAC; Sony usa LDAC.

---

## DNF mais rapido

O padrao do Fedora e conservador: tres downloads em paralelo.

```bash
sudo dnf config-manager setopt max_parallel_downloads=10
sudo dnf config-manager setopt fastestmirror=True
```

`config-manager setopt` e a forma suportada no dnf5 (Fedora 41 em diante).
Editar `/etc/dnf/dnf.conf` na mao ainda funciona, mas duplica a chave se voce
rodar duas vezes.

> `fastestmirror=True` ajuda em banda larga comum. Em VPN ou proxy corporativo
> pode piorar, porque a sondagem dos espelhos vira latencia extra.

---

## Notas por hardware

Rode `./scripts/hardware.sh` — ele detecta e diz o que se aplica. O resumo:

### GPU AMD

Nada a instalar de driver: o **amdgpu ja esta no kernel**, e para placas RDNA
isso costuma funcionar melhor que a alternativa proprietaria. So falta o
VA-API completo (o `swap` acima) e o Vulkan:

```bash
sudo dnf install vulkan-tools mesa-vulkan-drivers libva-utils
vulkaninfo --summary
```

### GPU NVIDIA

Precisa do driver proprietario:

```bash
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
```

**Espere o modulo compilar antes de reiniciar** — leva uns 5 minutos. Confira
com `modinfo -F version nvidia`. Reiniciar no meio da compilacao entrega uma
tela preta.

### CPU AMD

```bash
sudo dnf install amd-gpu-firmware linux-firmware
```

O governador `amd_pstate` melhora consumo e resposta de frequencia em Zen 2 e
mais recente. Veja se ja esta ativo:

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
```

Se responder `acpi-cpufreq` em vez de `amd-pstate-epp`, o kernel nao ativou
sozinho. Ativar exige parametro de boot — nao e obrigatorio, e o ganho e
modesto num desktop ligado na tomada.

### Rede Realtek

Os chips Realtek Gigabit comuns (`r8169`) funcionam com o driver do kernel.
Modelos mais novos (RTL8125 2.5G, Wi-Fi RTL8852) as vezes precisam do RPM
Fusion:

```bash
sudo dnf install akmod-realtek-rtw89
```

### Bluetooth Intel

Funciona sem ajuste: o firmware vem no `linux-firmware`, que ja esta instalado.

---

## Outras coisas que todo mundo instala

```bash
# Compactadores -- RAR e 7z nao vem, e o Ark fica sem saber abrir
sudo dnf install unzip unrar p7zip p7zip-plugins

# Fontes
sudo dnf install google-noto-sans-fonts google-noto-serif-fonts google-noto-emoji-fonts
sudo dnf install mscore-fonts-all    # Arial, Times New Roman -- requer RPM Fusion

# TRIM semanal no SSD
sudo systemctl enable --now fstrim.timer

# Firmware (BIOS, SSD) pelo proprio Linux
sudo fwupdmgr refresh --force && fwupdmgr get-updates
```

---

## Conferir se deu certo

```bash
vainfo                          # aceleracao de video: deve listar H264 e HEVC
vulkaninfo --summary            # Vulkan
flatpak remotes                 # flathub deve aparecer
systemctl status fstrim.timer   # TRIM ativo
inxi -Fxz                       # resumo geral do sistema
```

---

## Vindo do Windows: o que mais estranha

- **Nao instale programa baixando do site.** O caminho normal e `dnf` ou a
  loja de aplicativos. Baixar `.rpm` avulso funciona, mas voce perde a
  atualizacao automatica.
- **`sudo dnf upgrade` atualiza tudo** — sistema, aplicativos, drivers, de uma
  vez. Nao existe a separacao entre Windows Update e atualizar cada programa.
- **O Fedora troca de versao a cada 6 meses.** A atualizacao e suportada e
  funciona (`sudo dnf system-upgrade`), mas nao e automatica.
- **SELinux esta ligado.** Se um programa se recusar a acessar um arquivo sem
  motivo aparente, olhe `sudo ausearch -m AVC -ts recent` antes de culpar a
  permissao do arquivo. Nao desligue o SELinux — quase sempre a correcao certa
  e um rotulo, com `restorecon`.
- **Sua pasta pessoal e `/home/<usuario>`**, e nada de configuracao mora
  dentro de `/`. Por isso o kit consegue restaurar tudo com symlink.

## Fontes

Este documento foi conferido contra guias de pos-instalacao atuais e contra os
pacotes realmente disponiveis no Fedora — o que corrigiu, por exemplo, o
`install` que deveria ser `swap` nos drivers da AMD.

- [Things to Do After Installing Fedora 44 — OSTechNix](https://ostechnix.com/things-to-do-after-installing-fedora-44/)
- [Things to Do After Installing Fedora 42 — ComputingForGeeks](https://computingforgeeks.com/things-to-do-after-installing-fedora/)
- [How to Increase DNF Speed on Fedora — LinuxCapable](https://linuxcapable.com/increase-dnf-speed-on-fedora-linux/)
