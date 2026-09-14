<#
.SYNOPSIS
    Configura o ambiente R no Windows: PATH do Rtools, Makevars e bibliotecas.

.DESCRIPTION
    Tres trabalhos, nesta ordem:

      1. PATH -- poe o Rtools no ~/.Renviron. Instalar o Rtools nao basta:
         o R so acha o "make" se o caminho estiver no PATH da sessao do R, e
         o instalador nem sempre cuida disso. Esse e o motivo numero um de
         "Rcpp nao compila" numa maquina recem-formatada.

      2. Makevars.win -- ajusta o -j do MAKEFLAGS ao numero real de nucleos.

      3. Bibliotecas -- instala os conjuntos escolhidos em LIBS_R no
         perfil.conf. Opcionalmente em segundo plano, com log.

.PARAMETER Conjuntos
    Sobrescreve LIBS_R do perfil. Ex.: -Conjuntos 'r-core r-rcpp'

.PARAMETER Listar
    Mostra os conjuntos disponiveis e sai.

.PARAMETER Verificar
    So roda o diagnostico (scripts/r/verificar.R), sem instalar nada.

.PARAMETER EmPrimeiroPlano
    Instala prendendo o terminal, em vez de mandar para segundo plano.

.PARAMETER Simular
    Mostra o que faria sem executar.

.EXAMPLE
    .\scripts\setup-r.ps1 -Listar
    .\scripts\setup-r.ps1 -Conjuntos 'r-core r-rcpp r-paralelo'
    .\scripts\setup-r.ps1 -Verificar
#>
[CmdletBinding()]
param(
    [string]$Conjuntos,
    [switch]$Listar,
    [switch]$Verificar,
    [switch]$EmPrimeiroPlano,
    [switch]$Simular
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

$raiz = $script:DotfilesRaiz

# ---------------------------------------------------------------------------
# Listagem
# ---------------------------------------------------------------------------
if ($Listar) {
    Write-Info 'Conjuntos de bibliotecas R disponiveis:'
    Write-Host ''
    foreach ($c in (Get-Conjuntos -Linguagem r)) {
        $dep = ''
        if ($c.requer) { $dep = "  (requer $($c.requer))" }
        Write-Host ("  {0,-13} {1,3} min  {2}{3}" -f $c.id, $c.minutos, $c.nome, $dep)
        Write-Host ("  {0,-13}          {1}" -f '', ($c.pacotes -join ' ')) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host 'Ligue os que quiser em LIBS_R no perfil.conf.'
    exit 0
}

# ---------------------------------------------------------------------------
# R precisa existir
# ---------------------------------------------------------------------------

# Procura o Rscript no PATH e, se nao achar, nas instalacoes padrao. O R nao
# se adiciona ao PATH do usuario por padrao no Windows.
function Find-Rscript {
    if (Test-Comando 'Rscript') { return (Get-Command Rscript).Source }

    $candidatos = Get-ChildItem 'C:\Program Files\R' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($dir in $candidatos) {
        $exe = Join-Path $dir.FullName 'bin\x64\Rscript.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
        $exe = Join-Path $dir.FullName 'bin\Rscript.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

$rscript = Find-Rscript
if (-not $rscript) {
    Write-Erro 'R nao encontrado.'
    Write-Host 'Instale com: winget install RProject.R'
    Write-Host 'Ou rode: .\scripts\setup-windows.ps1 -Grupo r'
    exit 1
}
Write-Ok "Rscript: $rscript"

# O diretorio bin do R no PATH do usuario deixa "R" e "Rscript" chamaveis de
# qualquer terminal -- conveniencia que o instalador do R nao configura.
$binR = Split-Path -Parent $rscript
$pathUsuario = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($pathUsuario -notlike "*$binR*") {
    if ($Simular) {
        Write-Info "[simular] adicionaria ao PATH do usuario: $binR"
    } else {
        [Environment]::SetEnvironmentVariable('Path', "$pathUsuario;$binR", 'User')
        Write-Ok "PATH do usuario recebeu: $binR"
        Write-Aviso 'reabra o terminal para o PATH valer nesta sessao'
    }
} else {
    Write-Ok 'R ja esta no PATH do usuario'
}

# ---------------------------------------------------------------------------
# 1. Rtools no .Renviron
# ---------------------------------------------------------------------------

# Localiza o Rtools pelo registro (onde o instalador grava) e, se falhar,
# pelos caminhos conhecidos das versoes recentes.
function Find-Rtools {
    $chaves = @('HKLM:\SOFTWARE\R-core\Rtools\*', 'HKCU:\SOFTWARE\R-core\Rtools\*')
    foreach ($chave in $chaves) {
        $itens = Get-ItemProperty $chave -ErrorAction SilentlyContinue
        foreach ($item in $itens) {
            if ($item.PSObject.Properties.Name -contains 'InstallPath') {
                if ($item.InstallPath -and (Test-Path -LiteralPath $item.InstallPath)) {
                    return $item.InstallPath
                }
            }
        }
    }
    foreach ($p in @('C:\rtools45', 'C:\rtools44', 'C:\rtools43', 'C:\rtools42',
                     'C:\rtools40', 'C:\RBuildTools\4.0')) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

$rtools = Find-Rtools
if (-not $rtools) {
    Write-Aviso 'Rtools nao encontrado -- Rcpp nao vai compilar.'
    Write-Host  'Instale com: winget install RProject.Rtools'
} else {
    Write-Ok "Rtools: $rtools"

    $usrBin = Join-Path $rtools 'usr\bin'
    # O R le ~/.Renviron na inicializacao. No Windows, ~ e a pasta Documentos.
    $renviron = Join-Path ([Environment]::GetFolderPath('MyDocuments')) '.Renviron'

    # Barra normal no .Renviron: o R interpreta a contrabarra como escape e
    # o caminho chega truncado se for gravado no formato do Windows.
    $usrBinR = $usrBin -replace '\\', '/'
    $linha = 'PATH="' + $usrBinR + ';${PATH}"'

    $atual = ''
    if (Test-Path -LiteralPath $renviron) {
        $atual = Get-Content -LiteralPath $renviron -Raw
    }

    if ($atual -match [regex]::Escape($usrBinR)) {
        Write-Ok '.Renviron ja aponta para o Rtools'
    } elseif ($Simular) {
        Write-Info "[simular] acrescentaria ao $renviron :"
        Write-Host  "          $linha"
    } else {
        # Acrescenta, nunca sobrescreve: o .Renviron costuma guardar tambem
        # variaveis de API (GITHUB_PAT e afins) que nao podem se perder.
        $prefixo = ''
        if ($atual -and -not $atual.EndsWith("`n")) { $prefixo = "`r`n" }
        $bloco = "$prefixo`r`n# Rtools no PATH do R -- acrescentado por scripts/setup-r.ps1`r`n$linha`r`n"
        # "-Encoding UTF8" no Windows PowerShell 5.1 sempre grava BOM, mesmo
        # num arquivo novo -- e o parser de .Renviron do R nao reconhece o
        # BOM como parte da primeira linha, e avisa "contains invalid
        # line(s)" toda vez que roda (inofensivo, mas polui a saida). UTF8
        # sem BOM via .NET funciona igual em PowerShell 5.1 e 7+.
        $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($renviron, $bloco, $utf8SemBom)
        Write-Ok "Rtools acrescentado ao $renviron"
    }
}

# ---------------------------------------------------------------------------
# 2. Makevars.win com o -j certo
# ---------------------------------------------------------------------------

$nucleos = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
if (-not $nucleos -or $nucleos -lt 1) { $nucleos = 2 }
# Deixa um nucleo livre: compilar com todos trava a maquina por 20 minutos.
$j = [math]::Max(1, $nucleos - 1)

# Mesma pasta "Documentos" especial usada acima para o .Renviron -- NAO
# "$env:USERPROFILE\Documents" no caminho literal, que diverge dela quando o
# OneDrive redireciona Documentos (comum no Windows 11). As duas secoes
# gravando em lugares diferentes e o tipo de bug que some sem erro nenhum:
# o script relata sucesso, mas ajusta um Makevars.win que o R nunca le.
$pastaR = Join-Path ([Environment]::GetFolderPath('MyDocuments')) '.R'
$makevars = Join-Path $pastaR 'Makevars.win'

if ($Simular) {
    Write-Info "[simular] ajustaria MAKEFLAGS=-j$j em $makevars"
} elseif (Test-Path -LiteralPath $makevars) {
    $conteudo = Get-Content -LiteralPath $makevars -Raw
    $novo = $conteudo -replace 'MAKEFLAGS\s*=\s*-j\d+', "MAKEFLAGS = -j$j"
    if ($novo -ne $conteudo) {
        # UTF8 sem BOM (ver comentario na secao do .Renviron acima): make
        # nao espera BOM num Makevars e pode nem reportar o motivo do erro.
        $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($makevars, $novo, $utf8SemBom)
        Write-Ok "MAKEFLAGS ajustado para -j$j ($nucleos nucleos fisicos)"
    } else {
        Write-Ok "MAKEFLAGS ja esta em -j$j"
    }
} else {
    Write-Aviso "Makevars.win nao encontrado -- rode .\install.ps1 antes"
}

# ---------------------------------------------------------------------------
# 3. Bibliotecas
# ---------------------------------------------------------------------------

if ($Verificar) {
    Write-Host ''
    Write-Info 'diagnostico do ambiente R'
    # Invoke-Nativo, nao "&" direto: o R escreve aviso rotineiro em stderr (o
    # BOM do .Renviron, por exemplo), e sob $ErrorActionPreference = 'Stop'
    # (ligado no topo deste script) isso vira excecao fatal mesmo quando o
    # diagnostico inteiro passou -- exatamente o que Invoke-Nativo existe
    # para evitar.
    $codigo = Invoke-Nativo -Comando $rscript -Argumentos @((Join-Path $raiz 'scripts\r\verificar.R'))
    exit $codigo
}

$perfil = Get-Perfil
$escolha = $Conjuntos
if (-not $escolha) { $escolha = $perfil['LIBS_R'] }

if (-not $escolha) {
    Write-Host ''
    Write-Aviso 'nenhum conjunto de bibliotecas R escolhido.'
    Write-Host  'Defina LIBS_R no perfil.conf, ou passe -Conjuntos.'
    Write-Host  'Veja as opcoes com: .\scripts\setup-r.ps1 -Listar'
    exit 0
}

$resolvidos = Resolve-Conjuntos -Linguagem r -Escolhidos $escolha
if ($resolvidos.Count -eq 0) { Write-Aviso 'nada a instalar'; exit 0 }

$pacotes = @()
$minutos = 0
foreach ($c in $resolvidos) {
    $pacotes += $c.pacotes
    if ($c.minutos) { $minutos += [int]$c.minutos }
}
$pacotes = $pacotes | Select-Object -Unique

Write-Host ''
Write-Info "$($resolvidos.Count) conjunto(s), $($pacotes.Count) pacotes, ~$minutos min"
foreach ($c in $resolvidos) { Write-Host "    $($c.id) -- $($c.nome)" }

if ($Simular) {
    Write-Info "[simular] Rscript instalar.R $($pacotes -join ' ')"
    exit 0
}

$instalador = Join-Path $raiz 'scripts\r\instalar.R'
$emSegundoPlano = ($perfil['LIBS_EM_SEGUNDO_PLANO'] -eq 'sim') -and (-not $EmPrimeiroPlano)

if ($emSegundoPlano) {
    $log = Join-Path $raiz "logs\r-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force | Out-Null

    # Start-Process com redirecionamento: o R continua compilando depois que
    # este terminal fechar, que e o ponto de instalar em segundo plano.
    $argumentos = @("`"$instalador`"") + $pacotes
    Start-Process -FilePath $rscript -ArgumentList $argumentos `
        -RedirectStandardOutput $log -RedirectStandardError "$log.erro" `
        -WindowStyle Hidden | Out-Null

    Write-Host ''
    Write-Ok "instalacao rodando em segundo plano (~$minutos min)"
    Write-Host "    log:  $log"
    Write-Host "    siga: Get-Content '$log' -Wait -Tail 20"
    Write-Host "    depois: .\scripts\setup-r.ps1 -Verificar"
    exit 0
} else {
    # Invoke-Nativo, nao "&" direto -- ver o comentario no bloco -Verificar
    # acima sobre stderr de R virando excecao fatal sob ErrorActionPreference
    # 'Stop'.
    $codigo = Invoke-Nativo -Comando $rscript -Argumentos (@($instalador) + $pacotes)
    Write-Host ''
    if ($codigo -eq 0) {
        Write-Ok 'bibliotecas instaladas'
        Invoke-Nativo -Comando $rscript -Argumentos @((Join-Path $raiz 'scripts\r\verificar.R')) | Out-Null
    } else {
        Write-Aviso 'alguns pacotes falharam -- veja a saida acima'
        exit $codigo
    }
}
exit 0
