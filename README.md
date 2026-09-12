# dotfiles

Kit de configuracao e recuperacao de ambiente para Fedora KDE, Windows 11 e
macOS. Um manifesto unico de programas, scripts idempotentes de instalacao e
um cofre cifrado de credenciais.

Existe por um motivo pratico: formatar sem perder o dia seguinte, e voltar a
trabalhar em menos de uma hora quando um disco morre.

## Comeco rapido

### Windows

```powershell
winget install --id Git.Git --exact --silent
# reabra o terminal
cd $env:USERPROFILE\Documents
git clone https://github.com/matheuspasche/dotfiles.git
cd dotfiles
.\scripts\setup-windows.ps1     # instala o stack e configura o WSL2
.\install.ps1 -Extensoes        # aplica gitconfig, VS Code e Makevars
```

### Linux (Fedora / Ubuntu)

```bash
sudo dnf install -y git    # ou: sudo apt-get install -y git
git clone https://github.com/matheuspasche/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/setup-linux.sh
./install.sh --extensoes
```

### macOS

```bash
git clone https://github.com/matheuspasche/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/setup-macos.sh
./install.sh --extensoes
```

Todo script aceita `--simular` (ou `-Simular`) para mostrar o que faria sem
tocar em nada. Use na primeira vez.

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `pacotes.yaml` | **Fonte unica**: cada programa com o identificador de dnf, apt, brew, winget e scoop |
| `install.sh` / `install.ps1` | Aplica gitconfig, settings do VS Code e Makevars nos caminhos certos |
| `scripts/setup-*.{sh,ps1}` | Instala o stack lendo o manifesto |
| `scripts/snapshot-*.{sh,ps1}` | Fotografa a maquina antes de formatar |
| `scripts/cofre.{sh,ps1}` | Cofre cifrado de credenciais (`age`) |
| `docs/checklist-migracao.md` | Roteiro de formatacao planejada |
| `docs/nvme-morreu.md` | Recuperacao de emergencia em menos de uma hora |
| `docs/segredos.md` | Como o cofre funciona e por que nao ha segredo em texto claro |

## Stack coberto

R (com Rcpp compilando), Python via `uv`, VS Code, Claude Code, Docker, Spark
(JDK 17), DBeaver, DuckDB, Node, Git e GitHub CLI.

## Adicionar um programa

Um lugar so -- `pacotes.yaml`:

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

## Ambientes suportados

`scripts/common.sh` detecta **linux**, **macos**, **wsl** e **gitbash**, e
ajusta os caminhos: dentro do WSL, por exemplo, a configuracao do VS Code que
vale e a do perfil Windows, porque o editor roda do lado de la via Remote-WSL.

O `common.ps1` traz as mesmas funcoes para o PowerShell, com um parser proprio
do `pacotes.yaml` -- sem depender de modulo externo, que nao existe numa
maquina recem-formatada.

## Segredos

Nenhuma credencial neste repositorio, cifrada ou nao.

Credenciais vivem em `segredos.age`: um blob cifrado com `age` e passphrase,
gerado por `scripts/cofre.sh` / `cofre.ps1`. Pode ficar no Google Drive ou num
pendrive -- sem a passphrase e ruido. A passphrase fica no gerenciador de
senhas, nunca junto do cofre.

Detalhes, cuidados e procedimento de revogacao em
[docs/segredos.md](docs/segredos.md).

## Filosofia

1. **Uma verdade so.** Lista de pacotes existe em um arquivo, nao dentro de
   tres scripts.
2. **Idempotencia.** Rodar de novo nao quebra nada -- o que importa no dia da
   migracao, quando algo falha no meio.
3. **Segredo nunca em texto claro.** Snapshot registra o que estava instalado,
   jamais credencial.
4. **Degradar, nao quebrar.** Symlink vira junction, junction vira copia.
   Pacote ausente e pulado, nao aborta.

## Desenvolvimento

```bash
bash -n scripts/*.sh install.sh        # sintaxe dos scripts POSIX
```

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```
