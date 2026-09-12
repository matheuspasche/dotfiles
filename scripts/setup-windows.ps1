<#
.SYNOPSIS
    Instala o stack de desenvolvimento no Windows e configura o WSL2.

.DESCRIPTION
    Le pacotes.yaml (fonte unica da verdade) e instala via winget, com scoop
    como alternativa para o que o winget nao cobre bem. Depois habilita e
    configura o WSL2 com Ubuntu.

    Idempotente: rodar duas vezes nao quebra nada, apenas pula o que ja existe.

.PARAMETER Grupo
    Instala so um grupo do manifesto (base, python, r, dados, jvm, container,
    opcional). Sem o parametro, instala tudo menos "opcional".

.PARAMETER PularWsl
    Nao mexe no WSL. Util quando so se quer atualizar programas.

.PARAMETER Simular
    Mostra o que seria feito sem instalar nada.

.EXAMPLE
    .\scripts\setup-windows.ps1 -Simular
    .\scripts\setup-windows.ps1 -Grupo r
#>
[CmdletBinding()]
param(
    [string]$Grupo,
    [switch]$PularWsl,
    [switch]$Simular
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

# ---------------------------------------------------------------------------
# Pre-requisitos
# ---------------------------------------------------------------------------

if (-not (Test-Comando 'winget')) {
    Write-Erro 'winget nao encontrado.'
    Write-Host  'Instale o "Instalador de Aplicativo" pela Microsoft Store e rode de novo.'
    exit 1
}

if (-not (Test-Admin)) {
    Write-Aviso 'rodando sem privilegio de administrador.'
    Write-Aviso 'Docker Desktop e o WSL exigem admin -- esses passos vao falhar.'
    Write-Aviso 'Recomendado: fechar e reabrir o terminal como administrador.'
}

# ---------------------------------------------------------------------------
# Instalacao via winget
# ---------------------------------------------------------------------------

# Verifica se um pacote winget ja consta como instalado.
function Test-WingetInstalado {
    param([Parameter(Mandatory)][string]$Id)
    $saida = winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String
    return ($saida -match [regex]::Escape($Id))
}

function Install-ViaWinget {
    param([Parameter(Mandatory)][pscustomobject]$Pacote)

    if (Test-WingetInstalado -Id $Pacote.pkg) {
        Write-Ok "ja instalado: $($Pacote.nome)"
        return $true
    }

    if ($Simular) {
        Write-Info "[simular] winget install $($Pacote.pkg)"
        return $true
    }

    Write-Info "instalando $($Pacote.nome) ($($Pacote.pkg))"
    # --silent evita janelas de instalador travando o script sem supervisao.
    winget install --id $Pacote.pkg --exact --silent `
        --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "instalado: $($Pacote.nome)"
        return $true
    }

    # 0x8A15002B = "no applicable upgrade / ja instalado" -- nao e falha real.
    if ($LASTEXITCODE -eq -1978335189) {
        Write-Ok "ja atualizado: $($Pacote.nome)"
        return $true
    }

    Write-Aviso "winget falhou para $($Pacote.nome) (codigo $LASTEXITCODE)"
    return $false
}

# ---------------------------------------------------------------------------
# scoop -- alternativa para o que o winget nao cobre
# ---------------------------------------------------------------------------

function Install-Scoop {
    if (Test-Comando 'scoop') {
        Write-Ok 'scoop ja instalado'
        return $true
    }
    if ($Simular) {
        Write-Info '[simular] instalaria o scoop'
        return $true
    }

    Write-Info 'instalando scoop'
    try {
        # scoop instala no perfil do usuario, sem exigir admin.
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        # Invoke-Expression aqui e o metodo oficial de instalacao do scoop
        # (get.scoop.sh). O PSScriptAnalyzer sinaliza, e esperado.
        $instalador = Invoke-RestMethod -Uri 'https://get.scoop.sh'
        Invoke-Expression $instalador
        Write-Ok 'scoop instalado'
        return $true
    } catch {
        Write-Aviso "scoop falhou: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# WSL2 + Ubuntu
# ---------------------------------------------------------------------------

function Initialize-Wsl {
    if ($Simular) {
        Write-Info '[simular] habilitaria WSL2 e instalaria Ubuntu'
        return
    }
    if (-not (Test-Admin)) {
        Write-Aviso 'WSL exige administrador -- pulando.'
        return
    }

    Write-Info 'configurando WSL2'

    # Em Windows 10 2004+ e Windows 11, "wsl --install" ja habilita os
    # recursos opcionais e instala o kernel. Distribuicao explicita para nao
    # depender do padrao mudar entre versoes.
    $distros = wsl --list --quiet 2>$null | Out-String

    if ($distros -match 'Ubuntu') {
        Write-Ok 'Ubuntu ja instalado no WSL'
    } else {
        Write-Info 'instalando Ubuntu no WSL (pode pedir reinicializacao)'
        wsl --install --distribution Ubuntu --no-launch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Aviso "wsl --install retornou $LASTEXITCODE -- pode exigir reboot antes de repetir"
            return
        }
    }

    # Garante WSL2 como padrao (WSL1 nao roda Docker nem systemd).
    wsl --set-default-version 2 2>&1 | Out-Null
    Write-Ok 'WSL2 configurado. Abra "Ubuntu" no menu iniciar para criar o usuario.'
}

# ---------------------------------------------------------------------------
# Fluxo principal
# ---------------------------------------------------------------------------

Write-Info "raiz do kit: $script:DotfilesRaiz"
if ($Simular) { Write-Aviso 'modo simulacao: nada sera instalado' }

# Sem -Grupo, instala todos os grupos exceto "opcional".
$pacotes = Get-PacotesPara -Gerenciador winget -Grupo $Grupo
if (-not $Grupo) {
    $pacotes = $pacotes | Where-Object { $_.grupo -ne 'opcional' }
}

Write-Info "$($pacotes.Count) pacotes a processar"

$falhas = New-Object System.Collections.ArrayList
foreach ($p in $pacotes) {
    if (-not (Install-ViaWinget -Pacote $p)) {
        [void]$falhas.Add($p)
    }
}

# O que o winget nao conseguiu, tenta pelo scoop quando houver equivalente.
if ($falhas.Count -gt 0) {
    Write-Info "tentando $($falhas.Count) pacote(s) restante(s) pelo scoop"
    if (Install-Scoop) {
        foreach ($p in $falhas) {
            $alt = (Get-Manifesto) | Where-Object { $_.id -eq $p.id }
            if ($alt -and $alt['scoop']) {
                if ($Simular) {
                    Write-Info "[simular] scoop install $($alt['scoop'])"
                } else {
                    scoop install $alt['scoop'] 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Ok "instalado via scoop: $($p.nome)" }
                    else { Write-Erro "falhou nos dois gerenciadores: $($p.nome)" }
                }
            } else {
                Write-Erro "sem alternativa scoop: $($p.nome)"
            }
        }
    }
}

if (-not $PularWsl) { Initialize-Wsl }

Write-Host ''
Write-Info 'setup concluido. Proximos passos:'
Write-Host  '  1. feche e reabra o terminal (PATH mudou)'
Write-Host  '  2. .\install.ps1            -- aplica gitconfig, VS Code e Makevars'
Write-Host  '  3. gh auth login            -- reautentica o GitHub'
Write-Host  '  4. scripts\cofre.ps1 -Abrir -- restaura o cofre de segredos'
