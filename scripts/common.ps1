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
        [void]$saida.Add([pscustomobject]@{
            id    = $p['id']
            nome  = $p['nome']
            grupo = $p['grupo']
            pkg   = $valor
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
