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

$conf = Get-Perfil

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
    Write-Aviso 'O WSL (e o backend do Docker Desktop) exige admin -- esse passo vai ser pulado.'
    Write-Aviso 'O resto do setup (winget, driver de GPU) nao precisa e roda normal.'
    Write-Host  '    Para o WSL: feche este terminal, abra "Windows PowerShell" como'
    Write-Host  '    administrador (botao direito -> Executar como administrador) e rode'
    Write-Host  '    de novo -- o script e idempotente, o que ja foi instalado so e pulado.'
    Write-Host  '    Confira antes se a virtualizacao esta ligada na BIOS:'
    Write-Host  '        .\scripts\hardware.ps1'
    Write-Host  '    (SVM Mode na AMD, Intel VT-x na Intel -- sem isso o WSL2 nao sobe'
    Write-Host  '    nem rodando como administrador.)'
}

# ---------------------------------------------------------------------------
# Instalacao via winget
# ---------------------------------------------------------------------------

# Verifica se um pacote winget ja consta como instalado.
# -Fonte restringe a busca a uma fonte alternativa (hoje so 'msstore'), porque
# um id de produto da Store nao existe na fonte padrao do winget.
function Test-WingetInstalado {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Fonte
    )
    $args = @('list', '--id', $Id, '--exact', '--accept-source-agreements')
    if ($Fonte) { $args += @('--source', $Fonte) }
    $saida = winget @args 2>$null | Out-String
    return ($saida -match [regex]::Escape($Id))
}

function Install-ViaWinget {
    param([Parameter(Mandatory)][pscustomobject]$Pacote)

    $fonte = ''
    if ($Pacote.PSObject.Properties.Name -contains 'fonte') { $fonte = $Pacote.fonte }

    if (Test-WingetInstalado -Id $Pacote.pkg -Fonte $fonte) {
        Write-Ok "ja instalado: $($Pacote.nome)"
        return $true
    }

    if ($Simular) {
        $de = if ($fonte) { " (fonte $fonte)" } else { '' }
        Write-Info "[simular] winget install $($Pacote.pkg)$de"
        return $true
    }

    Write-Info "instalando $($Pacote.nome) ($($Pacote.pkg))"
    # --silent evita janelas de instalador travando o script sem supervisao.
    $argumentos = @(
        'install', '--id', $Pacote.pkg, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements')
    # Sem --source, o winget so procura na fonte padrao e responde "nenhum
    # pacote encontrado" para um id que so existe na Microsoft Store.
    if ($fonte) { $argumentos += @('--source', $fonte) }

    $codigo = Invoke-Nativo -Comando 'winget' -Silencioso -Argumentos $argumentos

    if ($codigo -eq 0) {
        Write-Ok "instalado: $($Pacote.nome)"
        return $true
    }

    # 0x8A15002B = "no applicable upgrade / ja instalado" -- nao e falha real.
    if ($codigo -eq -1978335189) {
        Write-Ok "ja atualizado: $($Pacote.nome)"
        return $true
    }

    Write-Aviso "winget falhou para $($Pacote.nome) (codigo $codigo)"
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

        # Baixa para um arquivo e executa como script, em vez de
        # Invoke-Expression numa string em memoria (o metodo que o proprio
        # get.scoop.sh recomenda). Antivirus/EDR costuma bloquear IEX de
        # conteudo baixado na hora -- padrao comum de malware -- com
        # "System.Security.SecurityException: Erro de seguranca", mesmo com a
        # ExecutionPolicy liberada. Um .ps1 de verdade passa pelo AMSI normal
        # e nao esbarra nisso.
        $instalador = Join-Path $env:TEMP 'scoop-install.ps1'
        Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $instalador
        & $instalador
        Remove-Item -LiteralPath $instalador -Force -ErrorAction SilentlyContinue

        Write-Ok 'scoop instalado'
        return $true
    } catch {
        Write-Aviso "scoop falhou: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Driver de GPU -- so quando o stack "jogos" for pedido
# ---------------------------------------------------------------------------

# Nem AMD nem NVIDIA publicam o instalador completo do driver no winget
# (conferido: "No package found matching input criteria." para
# AMD.AMDSoftwareAdrenalinEdition, AMD.ChipsetSoftware e
# Nvidia.GeForceExperience). Por isso cada fabricante recebe um caminho
# proprio abaixo, em vez de um id de winget que nao existe.
function Install-DriverGpu {
    $info = Get-InfoGpu
    Write-Info "GPU detectada: $($info.Modelo)"

    switch ($info.Fabricante) {
        'nvidia' {
            # O "NVIDIA app" (substituiu o GeForce Experience) e distribuido
            # pela Microsoft Store, e esse id e real.
            if ($Simular) {
                Write-Info '[simular] winget install XP8CLZL93F5Z4P --source msstore'
                return
            }
            $codigo = Invoke-Nativo -Comando 'winget' -Silencioso -Argumentos @(
                'install', '--id', 'XP8CLZL93F5Z4P', '--source', 'msstore',
                '--accept-package-agreements', '--accept-source-agreements')
            if ($codigo -eq 0) { Write-Ok 'NVIDIA app instalado' }
            else { Write-Aviso "NVIDIA app falhou (codigo $codigo)" }
        }
        'amd' {
            # Sem pacote no winget: baixa o instalador "auto-detect" direto do
            # site oficial da AMD e abre. E um instalador grafico -- pede
            # elevacao e passos manuais, nao tem como automatizar mais que
            # isso sem contornar o instalador oficial do fabricante.
            if ($Simular) {
                Write-Info '[simular] baixaria e abriria o instalador Adrenalin da AMD'
                return
            }
            $paginaSuporte = 'https://www.amd.com/en/support/download/drivers.html'
            try {
                Write-Info 'procurando o instalador atual da AMD (drivers.amd.com)'
                $pagina = Invoke-WebRequest -Uri $paginaSuporte -UseBasicParsing -TimeoutSec 30
                $link = $pagina.Links |
                    Where-Object { $_.href -match '^https://drivers\.amd\.com/.*\.exe$' } |
                    Select-Object -First 1 -ExpandProperty href

                if (-not $link) {
                    Write-Aviso 'nao achei o link do instalador na pagina da AMD'
                    Write-Host  "    Baixe manualmente: $paginaSuporte"
                    return
                }

                # drivers.amd.com rejeita o download sem Referer/User-Agent de
                # navegador -- sem isso devolve uma pagina HTML de erro
                # ("Download Not Complete") em vez do .exe, com o mesmo
                # tamanho de qualquer download que desse certo, entao o erro
                # so aparece quando o instalador roda.
                $destino = Join-Path $env:TEMP (Split-Path -Leaf $link)
                Write-Info "baixando $link"
                Invoke-WebRequest -Uri $link -OutFile $destino -UseBasicParsing -TimeoutSec 300 `
                    -Headers @{ 'Referer' = $paginaSuporte } `
                    -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'
                Write-Ok "baixado: $destino"
                Write-Info 'abrindo o instalador -- ele pede elevacao (UAC) e conduz o resto'
                Start-Process -FilePath $destino
            } catch {
                Write-Aviso "nao consegui baixar/abrir o instalador da AMD: $($_.Exception.Message)"
                Write-Host  "    Baixe manualmente: $paginaSuporte"
            }
        }
        'intel' {
            if ($Simular) {
                Write-Info '[simular] winget install Intel.IntelDriverAndSupportAssistant'
                return
            }
            $codigo = Invoke-Nativo -Comando 'winget' -Silencioso -Argumentos @(
                'install', '--id', 'Intel.IntelDriverAndSupportAssistant', '--exact', '--silent',
                '--accept-package-agreements', '--accept-source-agreements')
            if ($codigo -eq 0) { Write-Ok 'Intel Driver & Support Assistant instalado' }
            else { Write-Aviso "instalacao falhou (codigo $codigo)" }
        }
        default {
            Write-Aviso 'GPU nao identificada -- pulando driver'
        }
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
        Write-Host  '    Rode este script de novo numa janela "Executar como administrador".'
        Write-Host  '    E idempotente: so instala o que ainda falta, o resto e pulado.'
        Write-Host  '    Antes, confira a virtualizacao na BIOS com: .\scripts\hardware.ps1'
        Write-Host  '    (sem SVM Mode/Intel VT-x ligado, o WSL2 nao sobe nem como admin.)'
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
        $codigo = Invoke-Nativo -Comando 'wsl' -Silencioso -Argumentos @(
            '--install', '--distribution', 'Ubuntu', '--no-launch')
        if ($codigo -ne 0) {
            Write-Aviso "wsl --install retornou $codigo -- pode exigir reboot antes de repetir"
            return
        }
    }

    # Garante WSL2 como padrao (WSL1 nao roda Docker nem systemd).
    Invoke-Nativo -Comando 'wsl' -Silencioso -Argumentos @('--set-default-version', '2') | Out-Null
    Write-Ok 'WSL2 configurado. Abra "Ubuntu" no menu iniciar para criar o usuario.'
}

# ---------------------------------------------------------------------------
# Fluxo principal
# ---------------------------------------------------------------------------

Write-Info "raiz do kit: $script:DotfilesRaiz"
if ($Simular) { Write-Aviso 'modo simulacao: nada sera instalado' }

# O que instalar vem de STACKS no perfil.conf -- NUNCA "tudo". Instalar R,
# Python e Docker numa maquina que so precisa de navegador nao serve a
# ninguem. -Grupo sobrescreve o perfil para um uso pontual.
$pacotes = @()

if ($Grupo) {
    $pacotes = Get-PacotesPara -Gerenciador winget -Grupo $Grupo
    Write-Info "grupo: $Grupo"
} else {
    if (-not $conf['_CARREGADO']) {
        Write-Host ''
        Write-Aviso 'nenhum perfil.conf encontrado.'
        Write-Host  "   Sem ele, so o stack 'base' sera instalado."
        Write-Host  '   Para escolher o que instalar:  .\scripts\configurar.ps1'
        Write-Host  ''
        if (-not $Simular) {
            $resposta = Read-Host '   Continuar so com o basico? [S/n]'
            if ($resposta -match '^[nN]') {
                Write-Info 'rode .\scripts\configurar.ps1 e tente de novo'
                exit 0
            }
        }
    }

    $stacks = $conf['STACKS'] -split '\s+' | Where-Object { $_ }
    Write-Info "grupos: $($stacks -join ' ')"
    foreach ($g in $stacks) {
        $pacotes += Get-PacotesPara -Gerenciador winget -Grupo $g
    }

    # Navegador: entra so o escolhido, nao os tres do manifesto.
    if ($conf['NAVEGADOR'] -and $conf['NAVEGADOR'] -ne 'nenhum') {
        $nav = (Get-PacotesPara -Gerenciador winget -Grupo 'navegador') |
               Where-Object { $_.id -eq $conf['NAVEGADOR'] }
        if ($nav) {
            $pacotes += $nav
            Write-Info "navegador: $($conf['NAVEGADOR'])"
        } else {
            Write-Aviso "navegador '$($conf['NAVEGADOR'])' nao encontrado no manifesto"
        }
    }

    # Suite de escritorio: mesma logica do navegador -- so entra quando o
    # stack "escritorio" foi pedido, e so a(s) escolhida(s) em
    # SUITE_ESCRITORIO. Sem escolha no perfil, o padrao do Windows e o
    # Microsoft 365, que ja e a suite nativa por aqui.
    if ($stacks -contains 'escritorio') {
        $todasSuites = Get-PacotesPara -Gerenciador winget -Grupo 'suite-escritorio'
        $escolha = $conf['SUITE_ESCRITORIO']
        if (-not $escolha) { $escolha = 'microsoft365' }
        $idsEscolhidos = if ($escolha -eq 'tudo') { $todasSuites.id } else { $escolha -split '\s+' | Where-Object { $_ } }
        foreach ($id in $idsEscolhidos) {
            $suite = $todasSuites | Where-Object { $_.id -eq $id }
            if ($suite) {
                $pacotes += $suite
                Write-Info "suite de escritorio: $id"
            } else {
                Write-Aviso "suite de escritorio '$id' nao encontrada no manifesto"
            }
        }
    }
}

if ($pacotes.Count -eq 0) {
    Write-Aviso 'nada a instalar'
    exit 0
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
                    $codigo = Invoke-Nativo -Comando 'scoop' -Silencioso -Argumentos @('install', $alt['scoop'])
                    if ($codigo -eq 0) { Write-Ok "instalado via scoop: $($p.nome)" }
                    else { Write-Erro "falhou nos dois gerenciadores: $($p.nome)" }
                }
            } else {
                Write-Erro "sem alternativa scoop: $($p.nome)"
            }
        }
    }
}

# O WSL e uma mudanca grande de sistema (recurso do Windows, reboot, 1 GB de
# disco). So entra quando faz sentido para o que o usuario pediu.
$querWsl = $false
if ($Grupo) {
    $querWsl = ($Grupo -eq 'container')
} else {
    $stacksWsl = $conf['STACKS'] -split '\s+' | Where-Object { $_ }
    $querWsl = ($stacksWsl -contains 'container') -or ($stacksWsl -contains 'python')
}

if (-not $PularWsl -and $querWsl) {
    Initialize-Wsl
} elseif (-not $PularWsl) {
    Write-Ok 'WSL nao solicitado pelo perfil -- pulando'
}

# Driver de GPU: mesma logica de "so entra se fizer sentido para o pedido".
$querDriverGpu = $false
if ($Grupo) {
    $querDriverGpu = ($Grupo -eq 'jogos')
} else {
    $stacksJogos = $conf['STACKS'] -split '\s+' | Where-Object { $_ }
    $querDriverGpu = ($stacksJogos -contains 'jogos')
}
if ($querDriverGpu) { Install-DriverGpu }

Write-Host ''
Write-Info 'setup concluido. Proximos passos:'
Write-Host  '  1. feche e reabra o terminal (PATH mudou)'
Write-Host  '  2. .\install.ps1            -- aplica gitconfig, VS Code e Makevars'
Write-Host  '  3. gh auth login            -- reautentica o GitHub'
Write-Host  '  4. scripts\cofre.ps1 -Abrir -- restaura o cofre de segredos'

# Sem isso, o codigo de saida do script e o $LASTEXITCODE do ultimo comando
# nativo chamado (winget/wsl) -- que pode ser diferente de zero mesmo num
# setup bem-sucedido, e derruba quem encadeia este script com "if ($?)" ou "&&".
exit 0
