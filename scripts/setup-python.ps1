<#
.SYNOPSIS
    Configura o ambiente Python no Windows: uv, ambiente base, bibliotecas,
    kernel do Jupyter e variaveis do Spark.

.DESCRIPTION
    Quatro trabalhos:

      1. uv -- instala se faltar e garante ~\.local\bin no PATH.

      2. Ambiente base -- cria um venv em %USERPROFILE%\.venvs\lab para
         exploracao e notebooks. Projeto de verdade continua com o seu proprio
         .venv gerenciado por "uv sync"; este aqui e para a analise solta que
         nao merece um projeto.

      3. Bibliotecas -- instala os conjuntos de LIBS_PY no perfil.conf e
         registra o kernel do Jupyter, que e o que faz o VS Code enxergar o
         ambiente no seletor de notebook.

      4. Spark -- define JAVA_HOME e PYSPARK_PYTHON, e avisa sobre o
         winutils.exe, que o Hadoop exige no Windows.

.PARAMETER Conjuntos
    Sobrescreve LIBS_PY do perfil. Ex.: -Conjuntos 'py-core py-ml'

.PARAMETER Listar
    Mostra os conjuntos disponiveis e sai.

.PARAMETER Verificar
    So roda o diagnostico, sem instalar nada.

.PARAMETER Ambiente
    Nome do ambiente base. Padrao: lab

.PARAMETER EmPrimeiroPlano
    Instala prendendo o terminal.

.PARAMETER Simular
    Mostra o que faria sem executar.

.EXAMPLE
    .\scripts\setup-python.ps1 -Listar
    .\scripts\setup-python.ps1 -Conjuntos 'py-core py-viz py-notebook'
    .\scripts\setup-python.ps1 -Verificar
#>
[CmdletBinding()]
param(
    [string]$Conjuntos,
    [switch]$Listar,
    [switch]$Verificar,
    [string]$Ambiente = 'lab',
    [switch]$EmPrimeiroPlano,
    [switch]$Simular
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

$raiz = $script:DotfilesRaiz
$pastaVenvs = Join-Path $env:USERPROFILE '.venvs'
$venv = Join-Path $pastaVenvs $Ambiente
$pythonVenv = Join-Path $venv 'Scripts\python.exe'

# ---------------------------------------------------------------------------
# Listagem
# ---------------------------------------------------------------------------
if ($Listar) {
    Write-Info 'Conjuntos de bibliotecas Python disponiveis:'
    Write-Host ''
    foreach ($c in (Get-Conjuntos -Linguagem python)) {
        $dep = ''
        if ($c.requer) { $dep = "  (requer $($c.requer))" }
        Write-Host ("  {0,-13} {1,3} min  {2}{3}" -f $c.id, $c.minutos, $c.nome, $dep)
        Write-Host ("  {0,-13}          {1}" -f '', ($c.pacotes -join ' ')) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host 'Ligue os que quiser em LIBS_PY no perfil.conf.'
    exit 0
}

# ---------------------------------------------------------------------------
# 1. uv
# ---------------------------------------------------------------------------

if (-not (Test-Comando 'uv')) {
    if ($Simular) {
        Write-Info '[simular] instalaria o uv'
    } else {
        Write-Info 'instalando uv'
        $codigo = Invoke-Nativo -Comando 'winget' -Silencioso -Argumentos @(
            'install', '--id', 'astral-sh.uv', '--exact', '--silent',
            '--accept-package-agreements', '--accept-source-agreements')
        if ($codigo -ne 0) {
            Write-Erro 'nao consegui instalar o uv pelo winget'
            Write-Host 'Alternativa: irm https://astral.sh/uv/install.ps1 | iex'
            exit 1
        }
        # O winget nao atualiza o PATH da sessao em curso.
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
    }
}

if (Test-Comando 'uv') {
    Write-Ok "uv: $((uv --version) -join '')"
} elseif (-not $Simular) {
    Write-Aviso 'uv instalado mas ainda fora do PATH -- reabra o terminal e rode de novo'
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Ambiente base
# ---------------------------------------------------------------------------

if ($Simular) {
    Write-Info "[simular] criaria o ambiente $venv"
} elseif (Test-Path -LiteralPath $pythonVenv) {
    Write-Ok "ambiente ja existe: $venv"
} else {
    New-Item -ItemType Directory -Path $pastaVenvs -Force | Out-Null
    Write-Info "criando ambiente base em $venv"
    # --seed instala pip e setuptools: varias ferramentas ainda assumem pip.
    $codigo = Invoke-Nativo -Comando 'uv' -Silencioso -Argumentos @('venv', $venv, '--seed')
    if ($codigo -ne 0) { Write-Erro 'uv venv falhou'; exit 1 }
    Write-Ok "ambiente criado: $venv"
}

# ---------------------------------------------------------------------------
# Verificacao isolada
# ---------------------------------------------------------------------------

if ($Verificar) {
    $py = $pythonVenv
    if (-not (Test-Path -LiteralPath $py)) { $py = 'python' }
    Write-Host ''
    Write-Info 'diagnostico do ambiente Python'
    # Invoke-Nativo, nao "&" direto: qualquer linha em stderr do Python (um
    # DeprecationWarning de biblioteca, por exemplo) vira excecao fatal sob
    # $ErrorActionPreference = 'Stop' (ligado no topo deste script), mesmo
    # quando o diagnostico inteiro passou -- exatamente o que Invoke-Nativo
    # existe para evitar. Ja mordeu de verdade o mesmo bloco em setup-r.ps1.
    $codigo = Invoke-Nativo -Comando $py -Argumentos @((Join-Path $raiz 'scripts\py\verificar.py'))
    exit $codigo
}

# ---------------------------------------------------------------------------
# 3. Bibliotecas
# ---------------------------------------------------------------------------

$perfil = Get-Perfil
$escolha = $Conjuntos
if (-not $escolha) { $escolha = $perfil['LIBS_PY'] }

if (-not $escolha) {
    Write-Host ''
    Write-Aviso 'nenhum conjunto de bibliotecas Python escolhido.'
    Write-Host  'Defina LIBS_PY no perfil.conf, ou passe -Conjuntos.'
    Write-Host  'Veja as opcoes com: .\scripts\setup-python.ps1 -Listar'
    exit 0
}

$resolvidos = Resolve-Conjuntos -Linguagem python -Escolhidos $escolha
if ($resolvidos.Count -eq 0) { Write-Aviso 'nada a instalar'; exit 0 }

$pacotes = @()
$minutos = 0
$temNotebook = $false
$temSpark = $false
foreach ($c in $resolvidos) {
    $pacotes += $c.pacotes
    if ($c.minutos) { $minutos += [int]$c.minutos }
    if ($c.id -eq 'py-notebook') { $temNotebook = $true }
    if ($c.id -eq 'py-spark') { $temSpark = $true }
}
$pacotes = $pacotes | Select-Object -Unique

Write-Host ''
Write-Info "$($resolvidos.Count) conjunto(s), $($pacotes.Count) pacotes, ~$minutos min"
foreach ($c in $resolvidos) { Write-Host "    $($c.id) -- $($c.nome)" }

if ($Simular) {
    Write-Info "[simular] uv pip install --python $pythonVenv $($pacotes -join ' ')"
    if ($temNotebook) { Write-Info "[simular] registraria o kernel do Jupyter '$Ambiente'" }
    if ($temSpark) { Write-Info '[simular] configuraria JAVA_HOME e PYSPARK_PYTHON' }
    exit 0
}

$emSegundoPlano = ($perfil['LIBS_EM_SEGUNDO_PLANO'] -eq 'sim') -and (-not $EmPrimeiroPlano)

if ($emSegundoPlano) {
    $log = Join-Path $raiz "logs\python-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force | Out-Null
    $argumentos = @('pip', 'install', '--python', "`"$pythonVenv`"") + $pacotes
    Start-Process -FilePath 'uv' -ArgumentList $argumentos `
        -RedirectStandardOutput $log -RedirectStandardError "$log.erro" `
        -WindowStyle Hidden | Out-Null
    Write-Ok "instalacao rodando em segundo plano (~$minutos min)"
    Write-Host "    log:  $log"
    Write-Host "    siga: Get-Content '$log' -Wait -Tail 20"
} else {
    Write-Info 'instalando'
    $codigo = Invoke-Nativo -Comando 'uv' -Argumentos (@('pip', 'install', '--python', $pythonVenv) + $pacotes)
    if ($codigo -ne 0) { Write-Erro 'instalacao falhou'; exit 1 }
    Write-Ok 'bibliotecas instaladas'
}

# --- kernel do Jupyter ------------------------------------------------------
# Sem o kernel registrado, o ambiente nao aparece no seletor de notebook do
# VS Code -- o motivo mais comum de "o VS Code nao acha meu venv".
if ($temNotebook -and -not $emSegundoPlano) {
    Write-Info 'registrando kernel do Jupyter'
    $codigo = Invoke-Nativo -Comando $pythonVenv -Silencioso -Argumentos @(
        '-m', 'ipykernel', 'install', '--user', '--name', $Ambiente,
        '--display-name', "Python ($Ambiente)")
    if ($codigo -eq 0) {
        Write-Ok "kernel registrado: Python ($Ambiente)"
    } else {
        Write-Aviso 'nao consegui registrar o kernel'
    }
}

# ---------------------------------------------------------------------------
# 4. Spark
# ---------------------------------------------------------------------------

if ($temSpark) {
    Write-Host ''
    Write-Info 'configurando o Spark'

    # JAVA_HOME: procura o Temurin instalado pelo manifesto.
    $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    if (-not $javaHome -or -not (Test-Path -LiteralPath $javaHome)) {
        $candidatos = @()
        foreach ($base in @("$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Java")) {
            if (Test-Path -LiteralPath $base) {
                $candidatos += Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'jdk' }
            }
        }
        # Ordena por nome decrescente para pegar a versao mais nova disponivel.
        $escolhido = $candidatos | Sort-Object Name -Descending | Select-Object -First 1
        if ($escolhido) {
            [Environment]::SetEnvironmentVariable('JAVA_HOME', $escolhido.FullName, 'User')
            Write-Ok "JAVA_HOME definido: $($escolhido.FullName)"
            Write-Aviso 'reabra o terminal para a variavel valer'
        } else {
            Write-Aviso 'nenhum JDK encontrado -- o Spark nao sobe sem ele'
            Write-Host  'Instale com: winget install EclipseAdoptium.Temurin.17.JDK'
        }
    } else {
        Write-Ok "JAVA_HOME ja definido: $javaHome"
    }

    # PYSPARK_PYTHON: sem isso o Spark tenta usar o Python do sistema nos
    # workers e quebra com "Python worker failed to connect back".
    [Environment]::SetEnvironmentVariable('PYSPARK_PYTHON', $pythonVenv, 'User')
    [Environment]::SetEnvironmentVariable('PYSPARK_DRIVER_PYTHON', $pythonVenv, 'User')
    Write-Ok 'PYSPARK_PYTHON apontando para o ambiente base'

    $hadoopHome = [Environment]::GetEnvironmentVariable('HADOOP_HOME', 'User')
    if (-not $hadoopHome -or -not (Test-Path -LiteralPath (Join-Path $hadoopHome 'bin\winutils.exe'))) {
        Write-Aviso 'winutils.exe ausente (HADOOP_HOME)'
        Write-Host  '    Ler dados funciona; escrever em disco local costuma falhar.'
        Write-Host  '    O kit nao baixa esse binario automaticamente: ele e distribuido'
        Write-Host  '    por repositorios de terceiros e deve ser obtido com criterio.'
        Write-Host  '    Veja docs/spark-no-windows.md.'
    } else {
        Write-Ok "HADOOP_HOME: $hadoopHome"
    }
}

Write-Host ''
Write-Ok 'setup do Python concluido.'
Write-Host "    ambiente:  $venv"
Write-Host "    ativar:    & '$venv\Scripts\Activate.ps1'"
Write-Host "    conferir:  .\scripts\setup-python.ps1 -Verificar"
exit 0
