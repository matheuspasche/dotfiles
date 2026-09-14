# ============================================================================
# common.ps1 -- biblioteca compartilhada dos scripts PowerShell do kit
#
# Equivalente Windows de scripts/common.sh. Fornece log, deteccao de
# ambiente, leitura do manifesto pacotes.yaml e criacao de links.
#
# Uso:  . "$PSScriptRoot\common.ps1"
#
# Compativel com Windows PowerShell 5.1 e PowerShell 7+. Nao usa operador
# ternario, ?? nem ?. -- ausentes no 5.1.
# ============================================================================

# Nota: StrictMode NAO e ligado aqui de proposito. Este arquivo e carregado
# com dot-source e o modo vazaria para a sessao de quem o carrega. Cada script
# de entrada liga o seu proprio.

# ---------------------------------------------------------------- caminhos --
# Raiz do repositorio, resolvida a partir da pasta deste arquivo.
$script:DotfilesRaiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:Manifesto    = Join-Path $script:DotfilesRaiz 'pacotes.yaml'

# ------------------------------------------------------------------- log ----
function Write-Info  { param([string]$Mensagem) Write-Host "==> $Mensagem" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Mensagem) Write-Host " ok  $Mensagem" -ForegroundColor Green }
function Write-Aviso { param([string]$Mensagem) Write-Host "aviso $Mensagem" -ForegroundColor Yellow }
function Write-Erro  { param([string]$Mensagem) Write-Host "erro  $Mensagem" -ForegroundColor Red }

# -------------------------------------------------------------------- GPU ---
# Devolve o modelo (Name do WMI) e o fabricante ('amd' | 'nvidia' | 'intel' |
# 'desconhecido') da GPU principal. Le Win32_VideoController, que e
# informacao de hardware (PCI vendor/device ID) -- funciona mesmo sem o
# driver do fabricante instalado, so com o driver generico do Windows.
#
# Usado por hardware.ps1 (so relatorio) e setup-windows.ps1 (instala o
# driver quando o stack "jogos" for pedido) -- uma fonte so para os dois nao
# divergirem sobre qual e a GPU.
function Get-InfoGpu {
    $gpus = @(Get-CimInstance Win32_VideoController)
    $principal = $gpus | Select-Object -First 1

    $modelo = 'desconhecido'
    $fabricante = 'desconhecido'
    if ($principal) {
        $modelo = $principal.Name
        if ($modelo -match 'AMD|Radeon') { $fabricante = 'amd' }
        if ($modelo -match 'NVIDIA')     { $fabricante = 'nvidia' }
        if ($modelo -match 'Intel')      { $fabricante = 'intel' }
    }

    return [pscustomobject]@{ Modelo = $modelo; Fabricante = $fabricante }
}

# --------------------------------------------------------------- ambiente ---
# Verdadeiro quando o processo atual tem privilegio de administrador.
function Test-Admin {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal  = New-Object Security.Principal.WindowsPrincipal($identidade)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Verdadeiro quando o comando existe no PATH.
function Test-Comando {
    param([Parameter(Mandatory)][string]$Nome)
    $cmd = Get-Command $Nome -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

# --------------------------------------------------------------- manifesto --
# Le pacotes.yaml e devolve um array de hashtables, uma por pacote.
#
# Parser proprio do mesmo subconjunto restrito de YAML lido pelo awk em
# common.sh -- evita depender de modulo externo (powershell-yaml), que nao
# vem instalado numa maquina recem-formatada.
function Get-Manifesto {
    param([string]$Caminho = $script:Manifesto)

    if (-not (Test-Path $Caminho)) {
        throw "manifesto nao encontrado: $Caminho"
    }

    $pacotes = New-Object System.Collections.ArrayList
    $atual   = $null

    foreach ($linha in (Get-Content -LiteralPath $Caminho -Encoding UTF8)) {
        # Ignora comentarios e linhas em branco.
        if ($linha -match '^\s*#' -or $linha -match '^\s*$') { continue }

        # Inicio de um novo item: "  - id: <slug>"
        if ($linha -match '^\s*-\s*id:\s*(.+?)\s*$') {
            if ($null -ne $atual) { [void]$pacotes.Add($atual) }
            $atual = @{ id = $Matches[1].Trim('"') }
            continue
        }

        # Demais chaves do item corrente: "    chave: valor"
        if ($null -ne $atual -and $linha -match '^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$') {
            $chave = $Matches[1]
            $valor = $Matches[2].Trim('"')
            # "-" marca pacote indisponivel naquele gerenciador.
            if ($valor -eq '-') { $valor = '' }
            $atual[$chave] = $valor
        }
    }
    if ($null -ne $atual) { [void]$pacotes.Add($atual) }

    return $pacotes.ToArray()
}

# Devolve os identificadores nativos de um gerenciador (winget, scoop, ...).
# -Grupo filtra pelo campo grupo do manifesto.
function Get-PacotesPara {
    param(
        [Parameter(Mandatory)][string]$Gerenciador,
        [string]$Grupo
    )

    $saida = New-Object System.Collections.ArrayList
    foreach ($p in (Get-Manifesto)) {
        if ($Grupo -and $p['grupo'] -ne $Grupo) { continue }
        if (-not $p.ContainsKey($Gerenciador)) { continue }
        $valor = $p[$Gerenciador]
        if ([string]::IsNullOrWhiteSpace($valor)) { continue }
        # winget_fonte nomeia a fonte alternativa do winget (hoje so 'msstore').
        # Vazio = fonte padrao, que e o caso de quase todo pacote.
        $fonte = ''
        if ($Gerenciador -eq 'winget' -and $p.ContainsKey('winget_fonte')) {
            $fonte = $p['winget_fonte']
        }
        [void]$saida.Add([pscustomobject]@{
            id    = $p['id']
            nome  = $p['nome']
            grupo = $p['grupo']
            pkg   = $valor
            fonte = $fonte
        })
    }
    return $saida.ToArray()
}

# ------------------------------------------------------------------ links ---
# Liga <Destino> a <Origem>. Estrategia, em ordem de preferencia:
#   1. junction  -- para diretorios; nao exige privilegio
#   2. symlink   -- exige admin ou Modo Desenvolvedor ligado
#   3. copia     -- fallback que sempre funciona
#
# Qualquer arquivo pre-existente em Destino vira backup com timestamp.
function New-Ligacao {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Origem,
        [Parameter(Mandatory)][string]$Destino
    )

    if (-not (Test-Path -LiteralPath $Origem)) {
        Write-Aviso "origem inexistente, pulando: $Origem"
        return
    }

    $pastaDestino = Split-Path -Parent $Destino
    if ($pastaDestino -and -not (Test-Path -LiteralPath $pastaDestino)) {
        New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
    }

    # Ja aponta para o lugar certo: nada a fazer.
    if (Test-Path -LiteralPath $Destino) {
        $item = Get-Item -LiteralPath $Destino -Force
        if ($item.LinkType -and $item.Target -contains (Resolve-Path $Origem).Path) {
            Write-Ok "ja ligado: $Destino"
            return
        }
        $carimbo = Get-Date -Format 'yyyyMMddHHmmss'
        $backup  = "$Destino.backup.$carimbo"
        Move-Item -LiteralPath $Destino -Destination $backup -Force
        Write-Aviso "backup do arquivo anterior: $backup"
    }

    if (-not $PSCmdlet.ShouldProcess($Destino, "ligar a $Origem")) { return }

    $ehPasta = (Get-Item -LiteralPath $Origem).PSIsContainer

    if ($ehPasta) {
        try {
            New-Item -ItemType Junction -Path $Destino -Target $Origem -ErrorAction Stop | Out-Null
            Write-Ok "junction: $Destino -> $Origem"
            return
        } catch {
            Write-Aviso "junction falhou, tentando symlink: $Destino"
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Destino -Target $Origem -ErrorAction Stop | Out-Null
        Write-Ok "symlink: $Destino -> $Origem"
        return
    } catch {
        # Sem admin e sem Modo Desenvolvedor o symlink e negado -- copia resolve,
        # ao custo de o arquivo nao acompanhar mais o repositorio.
        Copy-Item -LiteralPath $Origem -Destination $Destino -Recurse -Force
        Write-Aviso "symlink indisponivel, copiado: $Destino"
    }
}

# --------------------------------------------------------------- perfil -----
# Le perfil.conf (formato CHAVE="valor") e devolve uma hashtable.
#
# O arquivo e deliberadamente simples para nao exigir parser: o bash faz
# source e aqui basta uma expressao regular. Linha fora do formato e recusada
# em vez de ignorada -- um perfil editado a mao com um comando dentro nao deve
# passar despercebido.
function Get-Perfil {
    param([string]$Caminho = (Join-Path $script:DotfilesRaiz 'perfil.conf'))

    # Padroes conservadores: o kit funciona recem-clonado, sem perfil.
    $perfil = @{
        GIT_NOME = ''; GIT_EMAIL = ''; GIT_ASSINAR = 'nao'
        STACKS = 'base'
        LIBS_R = ''; LIBS_PY = ''
        LIBS_EM_SEGUNDO_PLANO = 'sim'
        NAVEGADOR = 'nenhum'
        # Vazio = padrao do sistema (ver Initialize-Pacotes em setup-windows.ps1).
        SUITE_ESCRITORIO = ''
        VSCODE_EXTENSOES = 'base'
        FEDORA_RPMFUSION = 'sim'; FEDORA_CODECS = 'sim'; FEDORA_GPU = 'sim'
        FEDORA_FIRMWARE = 'sim'; FEDORA_FONTES_MS = 'nao'; FEDORA_DNF_RAPIDO = 'sim'
        COFRE_DESTINO = ''; SNAPSHOT_DESTINO = ''
        _CARREGADO = $false
    }

    if (-not (Test-Path -LiteralPath $Caminho)) { return $perfil }

    $numero = 0
    foreach ($linha in (Get-Content -LiteralPath $Caminho)) {
        $numero++
        if ($linha -match '^\s*(#.*)?$') { continue }
        if ($linha -match '^([A-Z_][A-Z0-9_]*)="([^"$`]*)"\s*(#.*)?$') {
            $perfil[$Matches[1]] = $Matches[2]
        } else {
            throw "perfil.conf linha ${numero}: fora do formato CHAVE=`"valor`". Rode scripts\configurar.ps1"
        }
    }
    $perfil['_CARREGADO'] = $true
    return $perfil
}

# Verdadeiro quando o stack esta ligado no perfil.
function Test-Stack {
    param(
        [Parameter(Mandatory)][hashtable]$Perfil,
        [Parameter(Mandatory)][string]$Nome
    )
    $lista = $Perfil['STACKS'] -split '\s+' | Where-Object { $_ }
    return ($lista -contains $Nome)
}

# ---------------------------------------------------- bibliotecas -----------
# Conjuntos de bibliotecas de uma linguagem (r | python), lidos do
# bibliotecas.yaml -- mesmo formato e mesmo parser do pacotes.yaml.
function Get-Conjuntos {
    param([Parameter(Mandatory)][ValidateSet('r', 'python')][string]$Linguagem)

    $arquivo = Join-Path $script:DotfilesRaiz 'bibliotecas.yaml'
    $saida = New-Object System.Collections.ArrayList
    foreach ($c in (Get-Manifesto -Caminho $arquivo)) {
        if ($c['linguagem'] -ne $Linguagem) { continue }
        [void]$saida.Add([pscustomobject]@{
            id      = $c['id']
            nome    = $c['nome']
            minutos = $c['minutos']
            requer  = $(if ($c.ContainsKey('requer')) { $c['requer'] } else { '' })
            pacotes = ($c['pacotes'] -split '\s+' | Where-Object { $_ })
        })
    }
    return $saida.ToArray()
}

# Expande a lista de ids escolhida pelo usuario, puxando as dependencias
# declaradas em "requer" e preservando a ordem de instalacao.
function Resolve-Conjuntos {
    param(
        [Parameter(Mandatory)][ValidateSet('r', 'python')][string]$Linguagem,
        [string]$Escolhidos
    )

    $todos = Get-Conjuntos -Linguagem $Linguagem
    $pedidos = $Escolhidos -split '\s+' | Where-Object { $_ }
    $final = New-Object System.Collections.ArrayList

    foreach ($id in $pedidos) {
        $c = $todos | Where-Object { $_.id -eq $id }
        if (-not $c) {
            Write-Aviso "conjunto desconhecido, ignorado: $id"
            continue
        }
        # A dependencia entra antes, e so uma vez.
        if ($c.requer) {
            $dep = $todos | Where-Object { $_.id -eq $c.requer }
            if ($dep -and -not ($final | Where-Object { $_.id -eq $dep.id })) {
                [void]$final.Add($dep)
            }
        }
        if (-not ($final | Where-Object { $_.id -eq $c.id })) { [void]$final.Add($c) }
    }
    return $final.ToArray()
}

# ---------------------------------------------------------------- nativo ----
# Executa um programa externo sem que a saida de erro dele derrube o script.
#
# Motivo: no Windows PowerShell 5.1, redirecionar stderr de executavel nativo
# (2>&1) embrulha cada linha num ErrorRecord. Com $ErrorActionPreference =
# 'Stop', isso vira erro terminal mesmo quando o programa devolveu 0 -- e
# winget, uv e git escrevem progresso em stderr o tempo todo.
#
# Devolve o codigo de saida. Nunca lanca excecao.
function Invoke-Nativo {
    param(
        [Parameter(Mandatory)][string]$Comando,
        [string[]]$Argumentos = @(),
        [switch]$Silencioso
    )

    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Silencioso) {
            & $Comando @Argumentos 2>&1 | Out-Null
        } else {
            # ForEach-Object converte o ErrorRecord em texto antes de exibir.
            & $Comando @Argumentos 2>&1 | ForEach-Object { Write-Host "$_" }
        }
        if ($null -eq $LASTEXITCODE) { return 0 }
        return $LASTEXITCODE
    } catch {
        Write-Aviso "falha ao executar ${Comando}: $($_.Exception.Message)"
        return 1
    } finally {
        $ErrorActionPreference = $anterior
    }
}
