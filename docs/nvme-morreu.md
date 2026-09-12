# O NVMe morreu

Procedimento para voltar a trabalhar em menos de uma hora quando o disco
principal (Linux) falha e so resta o SSD SATA com Windows.

Nao e um plano teorico: o NVMe ja morreu uma vez. Este documento existe para
que a segunda vez custe cinquenta minutos, nao um dia.

## Antes de mais nada

Se o NVMe falhou mas ainda aparece na BIOS, **nao tente reparticionar nem
formatar**. Disco SSD em falha as vezes responde por mais alguns minutos --
tempo suficiente para copiar o que nao estava versionado. Faca isso primeiro,
de um live USB, e so depois siga este documento.

## Premissas

- O Windows no SSD SATA liga e tem rede.
- O cofre (`segredos.age`) esta acessivel: Google Drive, pendrive ou os dois.
- A passphrase do cofre esta no gerenciador de senhas, **em outro aparelho**.
- Este repositorio esta no GitHub.

Se qualquer uma falhar, va para [Se faltar alguma peca](#se-faltar-alguma-peca).

---

## Linha do tempo

| Tempo | Etapa | Resultado |
|---|---|---|
| 0-5 min | Passo 1 | Git e o kit na maquina |
| 5-20 min | Passo 2 | Stack instalado (roda sozinho) |
| 20-25 min | Passo 3 | Credenciais restauradas |
| 25-35 min | Passo 4 | Configuracoes aplicadas, repositorios clonados |
| 35-50 min | Passo 5 | Ambiente por linguagem (R, Python) |
| 50-60 min | Passo 6 | Verificacao |

Os passos 2 e 5 sao os demorados e rodam praticamente sozinhos. Comece o 2 e
use a espera para o passo 3.

---

## Passo 1 -- Git e o kit (5 min)

Abra o **PowerShell como administrador** (botao direito no menu iniciar,
"Terminal (Admin)").

```powershell
winget install --id Git.Git --exact --silent --accept-package-agreements --accept-source-agreements
```

Feche e reabra o PowerShell -- o PATH so atualiza em terminal novo.

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/matheuspasche/dotfiles.git
cd dotfiles
```

O clone vai pedir login do GitHub pelo navegador. Aceite; e mais rapido que
restaurar o token agora.

## Passo 2 -- Stack (15 min, desatendido)

```powershell
.\scripts\setup-windows.ps1
```

Le `pacotes.yaml` e instala tudo pelo winget: VS Code, Python, uv, R, RStudio,
Rtools, Node, Java 17, DBeaver, DuckDB, Docker Desktop, age, ripgrep, jq.
Depois habilita o WSL2 com Ubuntu.

**Deixe rodando e va para o passo 3 em outra janela.**

Se pedir reinicializacao por causa do WSL, reinicie e rode de novo -- o script
e idempotente, pula o que ja instalou.

## Passo 3 -- Credenciais (5 min)

Com o cofre em maos (Drive ou pendrive):

```powershell
.\scripts\cofre.ps1 -Listar -Caminho 'G:\Meu Drive\cofre\segredos.age'
```

Confere o conteudo sem escrever nada. Se a lista fizer sentido:

```powershell
.\scripts\cofre.ps1 -Abrir -Caminho 'G:\Meu Drive\cofre\segredos.age'
```

Digite a passphrase quando o `age` pedir. Isso restaura chaves SSH, `gh`,
Docker, `.pypirc`, credenciais do Claude Code e o `.Renviron`.

> Se o `age` ainda nao estiver instalado porque o passo 2 nao terminou:
> `winget install FiloSottile.age`

## Passo 4 -- Configuracoes e codigo (10 min)

```powershell
.\install.ps1 -Extensoes
```

Aplica gitconfig, settings do VS Code, `Makevars.win` e instala as extensoes.

Clone o que estiver em uso:

```powershell
cd $env:USERPROFILE\Documents\GitHub
gh repo list matheuspasche --limit 100
gh repo clone matheuspasche/<projeto>
```

> **O que nao estava commitado, nao volta.** Este e o unico ponto do
> procedimento sem rede de seguranca. Se o NVMe ainda responde, e a hora de
> tentar recuperar aquele branch local.

## Passo 5 -- Ambientes de linguagem (15 min)

**Python** -- por projeto, nao global:

```powershell
cd <projeto>
uv sync
```

**R** -- reinstala do snapshot mais recente:

```powershell
$pkgs = Get-Content .\snapshots\windows-<data>\pacotes-r.txt |
        Select-Object -Skip 1 |
        ForEach-Object { ($_ -split '\s+')[0] }
Rscript -e "install.packages(commandArgs(TRUE))" @pkgs
```

Demora. Deixe rodando.

**Compilar Rcpp** exige o Rtools no PATH. Confira com:

```powershell
Rscript -e "pkgbuild::has_build_tools(debug = TRUE)"
```

**Docker** -- abra o Docker Desktop uma vez para ele terminar de configurar o
backend WSL2. Imagens nao voltam do snapshot, sao baixadas de novo:

```powershell
docker pull <imagem que voce usa>
```

**Spark** precisa do `JAVA_HOME`:

```powershell
[Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot', 'User')
```

Ajuste a versao para a pasta que existir em `C:\Program Files\Eclipse Adoptium\`.

## Passo 6 -- Verificacao (10 min)

```powershell
git config --global --list        # nome, email, aliases
gh auth status                    # GitHub autenticado
ssh -T git@github.com             # chave SSH funcionando
docker run --rm hello-world       # Docker de pe
Rscript -e "sessionInfo()"        # R responde
python -c "import sys; print(sys.version)"
wsl --list --verbose              # WSL2, nao WSL1
duckdb -c "select 42"             # DuckDB
```

Sete comandos. Se os sete passam, o ambiente esta viavel.

---

## Se faltar alguma peca

### O cofre sumiu

Nao ha recuperacao do cofre em si. Refaca as credenciais na mao:

1. `gh auth login` -- reautentica o GitHub pelo navegador, 30 segundos.
2. `ssh-keygen -t ed25519 -C "matheuspasche@gmail.com"` e depois
   `gh ssh-key add ~/.ssh/id_ed25519.pub`.
3. PyPI: gerar token novo em <https://pypi.org/manage/account/token/>.
4. Docker Hub: `docker login`.
5. Claude Code: `claude` pede login no primeiro uso.

Leva uns 20 minutos e revoga o que estava valendo antes -- o que e bom se o
disco perdido saiu da sua mao.

### Esqueci a passphrase

O cofre vira lixo. Nao existe recuperacao, e esse e o ponto do `age`. Siga o
roteiro acima de refazer credencial por credencial.

### O Windows nao tem rede

Confira `drivers-rede.txt` no snapshot mais recente: ele diz exatamente qual
e o adaptador. Baixe o driver de outra maquina, leve no pendrive.

### Preciso de Linux hoje

O WSL2 resolve para quase tudo que nao seja GPU ou driver:

```powershell
wsl --install --distribution Ubuntu
```

Dentro do Ubuntu:

```bash
git clone https://github.com/matheuspasche/dotfiles.git
cd dotfiles
./scripts/setup-linux.sh
./install.sh
```

O mesmo `pacotes.yaml` serve os dois lados.

---

## Manutencao deste plano

Um plano de recuperacao que nunca foi testado e uma suposicao. A cada seis
meses, ou depois de mudar o stack:

- [ ] `scripts\cofre.ps1 -Listar` -- o cofre ainda abre? A passphrase confere?
- [ ] O cofre esta em dois lugares (Drive **e** pendrive)?
- [ ] O snapshot mais recente tem menos de seis meses?
- [ ] Algum programa novo que nao esta em `pacotes.yaml`?
- [ ] Este documento ainda descreve a realidade?
