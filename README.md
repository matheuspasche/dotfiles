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

## Stacks disponiveis

Escolha os que quiser no assistente. Cada um e independente.

| Stack | O que traz |
|---|---|
| `base` | git, gh, curl, ripgrep, fd, jq, age — o minimo de qualquer maquina |
| `editor` | VS Code e Node |
| `python` | Python, uv, e os conjuntos de bibliotecas que voce marcar |
| `r` | R, RStudio, toolchain de compilacao (Rtools no Windows) |
| `dados` | DBeaver, DuckDB |
| `jvm` | JDK 17, requisito do Spark |
| `container` | Docker (e o WSL2 no Windows) |
| `escritorio` | LibreOffice, OnlyOffice, Microsoft 365 |
| `produtividade` | PowerToys e Everything no Windows; utilitarios do KDE no Linux |
| `navegador` | Firefox, Chrome ou Brave — so o que voce escolher |
| `opcional` | VLC, Obsidian, Syncthing |

Editor de codigo fica em `editor`, e nao em `base`, de proposito: um
computador de uso comum nao precisa de VS Code.

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
| `scripts/fedora-pos-instalacao.sh` | Codecs, drivers e Flathub, perguntando a cada passo |
| `install.sh` / `install.ps1` | Aplica gitconfig, settings do VS Code e Makevars |
| `scripts/snapshot-*.{sh,ps1}` | Fotografa a maquina antes de formatar |
| `scripts/cofre.{sh,ps1}` | Cofre cifrado de credenciais (`age`) |
| `docs/fedora-kde-primeiros-passos.md` | Primeira vez no Fedora KDE |
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
