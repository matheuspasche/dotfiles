# dotfiles

Kit de configuracao e recuperacao de ambiente para Fedora KDE, Windows e
macOS. Um manifesto unico de programas, scripts idempotentes e um cofre
cifrado de credenciais.

Existe por um motivo pratico: formatar sem perder o dia seguinte, e voltar a
trabalhar em menos de uma hora quando um disco morre.

**Nada e instalado sem voce pedir.** O primeiro passo e um assistente que
pergunta o que voce usa; todo o resto obedece essa resposta. Uma maquina que
so precisa de navegador e compactador recebe navegador e compactador — nao R,
Python e Docker.

## Comeco rapido

### Linux (Fedora / Ubuntu)

```bash
sudo dnf install -y git    # ou: sudo apt-get install -y git
git clone https://github.com/matheuspasche/dotfiles.git ~/dotfiles
cd ~/dotfiles

./scripts/configurar.sh                # 1. o que voce usa (perguntas)
./scripts/fedora-pos-instalacao.sh     # 2. codecs, drivers, Flathub
./scripts/setup-linux.sh               # 3. instala o que voce escolheu
./install.sh --extensoes               # 4. gitconfig, VS Code, Makevars
./scripts/setup-python.sh              # 5. bibliotecas (segundo plano)
./scripts/setup-r.sh
```

Primeira vez no Fedora KDE? Leia
[docs/fedora-kde-primeiros-passos.md](docs/fedora-kde-primeiros-passos.md).

### Windows

```powershell
winget install --id Git.Git --exact --silent
# reabra o terminal
cd $env:USERPROFILE\Documents
git clone https://github.com/matheuspasche/dotfiles.git
cd dotfiles

.\scripts\configurar.ps1        # 1. o que voce usa (perguntas)
.\scripts\hardware.ps1          # 2. o que o seu hardware pede
.\scripts\setup-windows.ps1     # 3. instala o que voce escolheu
.\install.ps1 -Extensoes        # 4. gitconfig, VS Code, Makevars
.\scripts\setup-python.ps1      # 5. bibliotecas (segundo plano)
.\scripts\setup-r.ps1
```

Primeira vez no Windows? Leia
[docs/windows-primeiros-passos.md](docs/windows-primeiros-passos.md) --
WSL2/Docker exigem administrador e BIOS com virtualizacao ligada, entre
outras armadilhas ja verificadas.

### macOS

```bash
git clone https://github.com/matheuspasche/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/configurar.sh
./scripts/setup-macos.sh
./install.sh --extensoes
```

Todo script aceita `--simular` (ou `-Simular`) para mostrar o que faria sem
tocar em nada. Use na primeira vez.

E aceita `--sim` para nao perguntar nada e rodar do inicio ao fim -- util
quando voce ja respondeu tudo no `configurar.sh` e so quer que instale:

```bash
./scripts/fedora-pos-instalacao.sh --sim   # codecs e drivers
./scripts/setup-linux.sh --sim             # programas
```

A ordem importa no Fedora: o `fedora-pos-instalacao.sh` troca o ffmpeg da
distribuicao pelo do RPM Fusion, e e isso que permite instalar as
bibliotecas de 32 bits de que o Steam precisa. Rodar o setup antes dele
funciona, mas o Steam abre reclamando de bibliotecas ausentes.

## Stacks disponiveis

Escolha os que quiser no assistente. Cada um e independente.

| Stack | O que traz |
|---|---|
| `base` | curl e o terminal — o minimo de QUALQUER maquina |
| `pessoal` | Spotify, WhatsApp, VLC |
| `jogos` | Steam, Heroic (Epic/GOG), Lutris, Proton-GE, GameMode, MangoHud |
| `escritorio` | LibreOffice, OnlyOffice, Microsoft 365 |
| `produtividade` | utilitarios do KDE e captura de tela; PowerToys e Everything no Windows |
| `opcional` | Obsidian, Syncthing |
| `dev` | git, gh, ripgrep, fd, jq, age |
| `editor` | VS Code, Claude Code e Node |
| `python` | Python, uv, e os conjuntos de bibliotecas que voce marcar |
| `r` | R, RStudio, Quarto, TinyTeX e toolchain de compilacao |
| `dados` | DBeaver, DuckDB |
| `jvm` | JDK, requisito do Spark |
| `container` | Docker (e o WSL2 no Windows) |

O navegador fica **fora** da tabela de proposito: voce escolhe um em
`NAVEGADOR` no `perfil.conf` (Firefox, Chrome ou Brave) e o setup instala so
esse. Pedir `navegador` como stack instalaria os tres.

A suite de escritorio funciona igual, dentro do stack `escritorio`: voce
escolhe uma em `SUITE_ESCRITORIO` (`libreoffice`, `onlyoffice`,
`microsoft365` ou `tudo`), e nao as tres de uma vez. Vazio usa o padrao do
sistema -- LibreOffice em Linux/macOS, Microsoft 365 no Windows, que ja e a
suite nativa por la (exige assinatura; sem ela, escolha `libreoffice`).

A ordem da tabela e a ordem de necessidade. O criterio para decidir onde uma
coisa entra e: **"se eu fosse formatar o computador de alguem que nao
programa, isso entraria?"**

Por isso o `git` esta em `dev` e nao em `base`. Ele e prioritario para quem
programa e irrelevante para quem nao programa -- e `base` significa "todo
mundo", nao "todo programador". Da mesma forma, VS Code fica em `editor`.

Formatar uma maquina de uso comum, entao, e `base pessoal navegador
escritorio` -- sem nada de desenvolvimento.

**Jogos no Linux:** a maior parte do catalogo roda por Proton, e em GPU AMD
costuma rodar bem. O que nao roda e uma coisa so: jogo com **anticheat de
kernel** cujo editor escolheu bloquear Linux — Fortnite, Valorant, League of
Legends, Roblox, GTA V e VI, EA SPORTS FC, Apex Legends, Destiny 2, Rainbow
Six Siege, Call of Duty, PUBG, Rust, Delta Force. Nao ha driver, Proton ou
ajuste que resolva: e decisao do editor, nao limitacao tecnica do Linux.
Rodam normalmente Counter-Strike 2, Elden Ring, Overwatch 2, Dead by
Daylight, Marvel Rivals e Genshin Impact. Confira antes de comprar em
[protondb.com](https://protondb.com) e
[areweanticheatyet.com](https://areweanticheatyet.com).

A Epic nao publica launcher para Linux: quem faz esse papel e o **Heroic**,
que loga na sua conta Epic e baixa os jogos. O **EA app** tambem nao existe
para Linux — jogos da EA rodam por Proton, pelo Steam ou pelo Heroic. No
Windows e no macOS o Heroic nao entra: o app oficial da Epic (abaixo) ja
existe e funciona nativo, sem precisar de wrapper nenhum.

**Driver de GPU no Windows, so com o stack `jogos`:** nem AMD nem NVIDIA
publicam o instalador completo do driver no winget, entao o
`setup-windows.ps1` resolve por fora: baixa e abre o instalador oficial
("Adrenalin" da AMD, direto de `drivers.amd.com`) ou instala o app da NVIDIA
pela Microsoft Store. Nos dois casos e so quando o stack `jogos` foi
escolhido -- o `hardware.ps1` sozinho so detecta e sugere, nunca instala.
O instalador da AMD e grafico e pede elevacao (UAC); o resto do wizard e
manual.

**WhatsApp no Linux:** a Meta nao publica cliente de desktop para Linux. O
kit instala o [ZapZap](https://github.com/zapzap-linux/zapzap) do Flathub, um
wrapper de terceiro em volta do WhatsApp Web, e renomeia o atalho para
"WhatsApp". No macOS e no Windows nao ha wrapper nenhum: la o app e o oficial.

## Bibliotecas de R e Python

Conjuntos que voce liga ou desliga, com o tempo estimado de instalacao. Quem
so escreve Python nao espera o tidyverse compilar.

```bash
./scripts/setup-r.sh --listar
./scripts/setup-python.sh --listar
```

**R** — `r-core` (tidyverse, data.table, duckdb, arrow), `r-modelagem`
(tidymodels, xgboost), `r-rcpp`, `r-paralelo` (future), `r-shiny`,
`r-relatorio` (Quarto), `r-banco`, `r-dev`.

**Python** — `py-core` (numpy, pandas, polars, duckdb), `py-viz` (matplotlib,
seaborn, plotly), `py-ml` (scikit-learn, xgboost), `py-spark`, `py-notebook`,
`py-banco`, `py-dev`, `py-web`.

A instalacao vai para segundo plano com log, para nao prender o terminal.

### Usar so o modulo de R, numa maquina que nao e sua

O caso tipico: voce entrou numa empresa, a maquina ja vem configurada e voce
so precisa do ambiente de R -- sem trocar o `.gitconfig` de lugar, sem mexer
nas settings do VS Code da equipe e sem encher o sistema de repositorio que
ninguem pediu.

```bash
./scripts/setup-linux.sh --grupo r        # R, toolchain, RStudio, Quarto, TinyTeX
./install.sh --apenas r                   # so o ~/.R/Makevars e o ~/.Rprofile
./scripts/setup-r.sh --conjuntos "r-shiny r-relatorio"
./scripts/setup-r.sh --verificar          # renderiza HTML e PDF de verdade
```

O que esses comandos **nao** fazem:

- **nao adicionam repositorio de terceiro alheio.** Cada repositorio e
  declarado em `repo:` no `pacotes.yaml` e so entra se algum pacote daquele
  run precisar dele. `--grupo r` nao configura VS Code, Docker nem RPM Fusion.
- **nao sobrescrevem sua configuracao.** `--apenas r` aplica so o Makevars e o
  Rprofile. As areas sao `git`, `vscode` e `r`, combinaveis:
  `./install.sh --apenas "git r"`.
- **nao exigem `perfil.conf`.** `--grupo` e `--conjuntos` ignoram o perfil.

O `--apenas r` nao e opcional na pratica: sem o `Makevars` os pacotes de R
compilam com as flags erradas e varios simplesmente falham.

### O que o setup conserta sozinho

- **Rtools fora do PATH** — causa numero um de "Rcpp nao compila" no Windows.
  O `setup-r.ps1` escreve o caminho no `.Renviron`.
- **`MAKEFLAGS`** ajustado ao numero real de nucleos, deixando um livre.
- **Kernel do Jupyter registrado** — sem isso o VS Code nao lista o ambiente
  no seletor de notebook.
- **`JAVA_HOME` e `PYSPARK_PYTHON`** para o Spark subir de fato.

O diagnostico **compila C++ na hora** e **sobe uma sessao Spark de verdade**:
instalado nao e o mesmo que funcionando.

```bash
./scripts/setup-r.sh --verificar
./scripts/setup-python.sh --verificar
```

## Tema do KDE (opcional)

Fora do fluxo principal de proposito: aparencia e gosto pessoal, e nenhum
outro script chama este.

```bash
./scripts/tema-kde.sh --salvar     # grava o tema ATUAL em config/kde/tema.conf
./scripts/tema-kde.sh --aplicar    # aplica numa maquina nova
```

O `--salvar` le o estado real da sessao, nao os defaults do pacote de tema --
o que preserva os pontos em que voce desviou dele. O `--aplicar` baixa o tema
do GitHub do autor quando faltar (sempre o ramo atual, sem versao fixa) e
nunca passa `--resetLayout`: essa flag trocaria os seus paineis pelos do tema.

**Papel de parede por hora do dia.** Um timer do systemd sorteia uma imagem a
cada 15 minutos, de uma pasta por periodo: `dawn` 5-8h, `day` 8-17h, `dusk`
17-20h, `night` 20-5h, em `~/Pictures/wallpapers-dynamic/`.

As imagens **nao sao versionadas** -- sao dezenas de MB de licenca que nao e
nossa para redistribuir. Elas viajam no **cofre**, junto com as credenciais:
`./scripts/cofre.sh abrir` traz as imagens de volta numa maquina nova. Isso
faz o cofre passar de ~0,1 MB para ~30 MB; se incomodar, tire
`Pictures/wallpapers-dynamic` do `config/segredos.lista` e sincronize pelo
Syncthing, que ja esta no manifesto.

## Google Drive como pasta local (opcional)

Fora do fluxo principal de proposito: nenhum outro script chama este. Monta o
Google Drive no Dolphin via `rclone`, em vez do `kio-gdrive` nativo do KDE --
que usa uma credencial de API compartilhada por todo o KDE no mundo e quebra
com `Requested resource is forbidden` quando o Google a limita. Passo a passo
manual completo (instalacao, `rclone config`, mount e o servico systemd) em
`~/github/tutorial-google-drive-kde-fedora.md`.

```bash
./scripts/gdrive-mount.sh --instalar              # instala o rclone
./scripts/gdrive-mount.sh --configurar            # assistente rclone config
./scripts/gdrive-mount.sh --montar                # monta uma vez em ~/GoogleDrive
./scripts/gdrive-mount.sh --servico               # monta automaticamente no login (systemd)
./scripts/gdrive-mount.sh --status                # estado atual (configurado / montado / servico)
./scripts/gdrive-mount.sh --desmontar             # desmonta
```

Todos aceitam `[nome-do-remote] [pasta]` como argumentos posicionais (padrao:
`google_account` e `~/GoogleDrive`) e `--simular` para so mostrar o que
fariam. `--servico` grava um unit template
(`config/gdrive/gdrive-mount@.service`) em
`~/.config/systemd/user/gdrive-mount@.service`, entao a mesma unidade serve
para montar varias contas -- `gdrive-mount@trabalho.service`,
`gdrive-mount@pessoal.service`.

## Hardware

`scripts/hardware.{sh,ps1}` detecta CPU, GPU, placa-mae, rede, bluetooth e
disco, e diz o que aquele hardware pede — sem instalar nada.

No Fedora isso importa mais do que parece: a GPU AMD precisa de um `dnf swap`
(nao `install`) para ter aceleracao de video, a NVIDIA precisa do driver
proprietario, e fone Bluetooth sem os codecs cai no SBC.

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `perfil.conf` | **Suas escolhas**: identidade, stacks, bibliotecas, navegador. Nao versionado |
| `pacotes.yaml` | **Fonte unica** de programas: cada um com o id de dnf, apt, brew, winget e scoop |
| `bibliotecas.yaml` | **Fonte unica** de bibliotecas: conjuntos de R e Python |
| `scripts/configurar.{sh,ps1}` | Assistente que escreve o `perfil.conf` |
| `scripts/hardware.{sh,ps1}` | Detecta o hardware e diz o que ele pede |
| `scripts/setup-{linux,macos,windows}` | Instala o que o perfil pediu |
| `scripts/setup-{r,python}.{sh,ps1}` | Bibliotecas, PATH, Rtools, Jupyter, Spark |
| `scripts/fedora-pos-instalacao.sh` | Codecs, drivers e Flathub, seguindo as chaves `FEDORA_*` do perfil |
| `install.sh` / `install.ps1` | Aplica gitconfig, settings do VS Code, Makevars e atalhos do KDE -- so das areas que o perfil pediu |
| `scripts/snapshot-*.{sh,ps1}` | Fotografa a maquina antes de formatar |
| `scripts/cofre.{sh,ps1}` | Cofre cifrado de credenciais (`age`) |
| `scripts/tema-kde.sh` | Tema e papel de parede do KDE (opcional, fora do fluxo) |
| `scripts/gdrive-mount.sh` | Google Drive como pasta local via rclone (opcional, fora do fluxo) |
| `docs/fedora-kde-primeiros-passos.md` | Primeira vez no Fedora KDE |
| `docs/windows-primeiros-passos.md` | Primeira vez no Windows: WSL, drivers, winget |
| `docs/nvme-morreu.md` | Recuperacao de emergencia em menos de uma hora |
| `docs/spark-no-windows.md` | As tres armadilhas do PySpark no Windows |
| `docs/checklist-migracao.md` | Roteiro de formatacao planejada |
| `docs/segredos.md` | Como o cofre funciona |

## Adicionar um programa

Um lugar so — `pacotes.yaml`:

```yaml
  - id: bat
    nome: bat (cat com realce)
    grupo: base
    dnf: bat
    apt: bat
    brew: bat
    winget: sharkdp.bat
    scoop: bat
```

Use `"-"` onde o programa nao existir naquele gerenciador. Os scripts de setup
dos tres sistemas passam a instala-lo sem nenhuma outra edicao.

Biblioteca nova de R ou Python? Mesma ideia, em `bibliotecas.yaml`.

## Ambientes suportados

`scripts/common.sh` detecta **linux**, **macos**, **wsl**, **gitbash** e
**container**, e ajusta os caminhos. Dentro do WSL, por exemplo, a
configuracao do VS Code que vale e a do perfil Windows, porque o editor roda
do lado de la via Remote-WSL.

O `common.ps1` traz as mesmas funcoes para o PowerShell, com um parser proprio
do `pacotes.yaml` — sem depender de modulo externo, que nao existe numa
maquina recem-formatada.

## Segredos

Nenhuma credencial neste repositorio, cifrada ou nao.

Credenciais vivem em `segredos.age`: um blob cifrado com `age` e passphrase,
gerado por `scripts/cofre.sh` / `cofre.ps1`. Pode ficar em nuvem ou pendrive —
sem a passphrase e ruido. A passphrase fica no gerenciador de senhas, nunca
junto do cofre.

Detalhes e procedimento de revogacao em [docs/segredos.md](docs/segredos.md).

## Filosofia

1. **Uma verdade so.** Lista de pacotes existe em um arquivo, nao dentro de
   tres scripts.
2. **Nada sem escolha.** O assistente pergunta; o setup obedece. Sem perfil,
   instala o minimo e diz como escolher.
3. **Idempotencia.** Rodar de novo nao quebra nada — o que importa no dia da
   migracao, quando algo falha no meio.
4. **Segredo nunca em texto claro.** O snapshot registra o que estava
   instalado, jamais credencial.
5. **Degradar, nao quebrar.** Symlink vira junction, junction vira copia.
   Pacote ausente e pulado, nao aborta.

## Desenvolvimento

```bash
bash -n scripts/*.sh install.sh        # sintaxe dos scripts POSIX
```

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

Para testar numa maquina limpa sem formatar nada:

```bash
docker run --rm -v "$PWD:/kit-ro:ro" fedora:41 bash -c \
  'cp -r /kit-ro /kit && cd /kit && ./scripts/setup-linux.sh --simular'
```
