# Checklist de migracao

Roteiro para formatar uma maquina sem perder nada e sem passar a semana
seguinte lembrando de configuracao que faltou.

Para o caso de **falha inesperada** do disco, o documento e outro:
[nvme-morreu.md](nvme-morreu.md).

---

## Antes de formatar

### Fotografar a maquina

```powershell
# Windows
.\scripts\snapshot-windows.ps1 -Destino 'G:\Meu Drive\backup-formatacao'
```

```bash
# Linux / macOS
./scripts/snapshot-sistema.sh ~/Drive/backup-formatacao
```

Gera a lista de programas, extensoes, pacotes R e Python, imagens Docker,
adaptadores de rede e layout de discos. **Grave fora do disco que sera
formatado.**

### Fechar o cofre de credenciais

```powershell
.\scripts\cofre.ps1 -Fechar -Caminho 'G:\Meu Drive\cofre'
```

```bash
./scripts/cofre.sh fechar ~/Drive/cofre
```

- [ ] Cofre gerado
- [ ] Passphrase guardada no gerenciador de senhas, em **outro aparelho**
- [ ] Cofre copiado para um segundo lugar (pendrive)
- [ ] `cofre.ps1 -Listar` confirma que o arquivo abre

### Codigo

- [ ] `git status` limpo em todo repositorio
- [ ] `git push` em toda branch que importa
- [ ] Branch local sem remoto: empurrar ou aceitar perder
- [ ] Stash antigo revisado (`git stash list`)

### Dados que nao estao em repositorio

- [ ] Volumes Docker com banco local (confira `docker-volumes.txt`)
- [ ] Arquivos `.duckdb` e `.parquet` fora de projeto
- [ ] Conexoes do DBeaver -- ja entram no cofre, confira que estavam listadas
- [ ] Downloads, Documentos, Area de Trabalho
- [ ] Configuracao de VPN, certificado do trabalho

### Sistema

- [ ] Chave do Windows anotada, se for OEM:
      `wmic path softwarelicensingservice get OA3xOriginalProductKey`
- [ ] Licenca de programa pago (RStudio Pro, JetBrains, etc.)
- [ ] Pendrive de instalacao pronto e testado (boot funciona)
- [ ] Driver de rede baixado, se o snapshot indicar hardware incomum

---

## Depois de formatar

### 1. Base

```powershell
winget install --id Git.Git --exact --silent
```

Reabra o terminal.

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/matheuspasche/dotfiles.git
cd dotfiles
```

### 2. Stack

```powershell
.\scripts\setup-windows.ps1           # Windows
```

```bash
./scripts/setup-linux.sh              # Fedora / Ubuntu
./scripts/setup-macos.sh              # macOS
```

Tudo vem de `pacotes.yaml`. Programa que faltar, adicione la -- e nao no
script.

### 3. Credenciais

```powershell
.\scripts\cofre.ps1 -Abrir -Caminho 'G:\Meu Drive\cofre\segredos.age'
```

```bash
./scripts/cofre.sh abrir ~/Drive/cofre/segredos.age
```

### 4. Configuracoes

```powershell
.\install.ps1 -Extensoes
```

```bash
./install.sh --extensoes
```

### 5. Ambientes

- [ ] `uv sync` em cada projeto Python
- [ ] Pacotes R a partir de `pacotes-r.txt` do snapshot
- [ ] `docker pull` das imagens em uso
- [ ] `JAVA_HOME` apontando para o JDK 17 (Spark)
- [ ] Rtools no PATH: `Rscript -e "pkgbuild::has_build_tools(debug=TRUE)"`

### 6. Verificacao

```bash
git config --global --list
gh auth status
ssh -T git@github.com
docker run --rm hello-world
Rscript -e "sessionInfo()"
python -c "import sys; print(sys.version)"
duckdb -c "select 42"
```

---

## Filosofia do kit

Quatro regras, que explicam por que o repositorio tem esse formato.

**1. Uma verdade so.** Programa se declara em `pacotes.yaml`, com o
identificador de cada gerenciador lado a lado. Os scripts de setup leem dali.
Nao existe lista de pacotes dentro de script -- porque duas listas divergem,
sempre.

**2. Idempotencia.** Todo script pode rodar de novo sem estragar nada. Isso
vale mais do que parece no dia da migracao, quando algo falha no meio e voce
precisa retomar sem saber exatamente onde parou.

**3. Segredo nunca em texto claro.** Snapshot registra o que estava
instalado, nunca credencial. Credencial vive no cofre `age`, cifrada com
passphrase, e o cofre pode ficar em qualquer lugar -- inclusive numa nuvem
que voce nao controla -- porque sem a passphrase e ruido. O `.gitignore` tem
uma segunda camada de padroes (`*.pem`, `.env`, `id_rsa*`) como rede contra
um `git add .` distraido.

**4. Degradar, nao quebrar.** Symlink vira junction, junction vira copia.
Pacote que nao existe num gerenciador e pulado, nao aborta a instalacao.
Ferramenta ausente no snapshot vira aviso, nao erro. A maquina recem-formatada
e justamente onde nada esta no lugar -- o script tem que sobreviver a isso.

---

## Estrutura

```
dotfiles/
├── pacotes.yaml              fonte unica: programas x gerenciador
├── install.sh                aplica configuracoes (Linux/macOS/WSL/Git Bash)
├── install.ps1               aplica configuracoes (Windows)
├── config/
│   ├── gitconfig             comum a todas as maquinas
│   ├── gitignore_global
│   ├── Makevars              flags de Rcpp (Linux/macOS)
│   ├── Makevars.win          flags de Rcpp (Windows/Rtools)
│   ├── segredos.lista        o que entra no cofre
│   └── vscode/
│       ├── settings.json     chaves .windows/.linux/.osx no mesmo arquivo
│       └── extensions.txt
├── scripts/
│   ├── common.sh             biblioteca POSIX (detecta linux/macos/wsl/gitbash)
│   ├── common.ps1            biblioteca PowerShell
│   ├── setup-linux.sh
│   ├── setup-macos.sh
│   ├── setup-windows.ps1
│   ├── snapshot-sistema.sh
│   ├── snapshot-windows.ps1
│   ├── cofre.sh              cofre cifrado (age)
│   └── cofre.ps1
└── docs/
    ├── checklist-migracao.md este arquivo
    ├── nvme-morreu.md        recuperacao de emergencia
    └── segredos.md           como o cofre funciona
```

---

## Adicionar um programa novo

Um lugar so:

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

Sem identificador num gerenciador, use `"-"`. O setup daquele sistema pula.
