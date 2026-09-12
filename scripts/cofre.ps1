<#
.SYNOPSIS
    Cofre cifrado de credenciais (versao Windows).

.DESCRIPTION
    Empacota os arquivos listados em config/segredos.lista e cifra com age
    usando passphrase. O resultado (segredos.age) pode ser guardado em
    qualquer lugar -- Google Drive, pendrive, repositorio -- porque sem a
    passphrase e ruido.

    A passphrase e digitada por voce, direto no prompt do age. Nao passa por
    parametro, nao entra no historico do PowerShell e nao e gravada em lugar
    nenhum. Passphrase perdida = cofre irrecuperavel. Guarde no gerenciador
    de senhas.

.PARAMETER Fechar
    Cria o cofre a partir dos arquivos existentes nesta maquina.

.PARAMETER Abrir
    Restaura os arquivos do cofre no perfil do usuario.

.PARAMETER Listar
    Mostra o que ha dentro do cofre sem escrever nada em disco.

.PARAMETER Caminho
    Pasta de destino (com -Fechar) ou arquivo .age (com -Abrir/-Listar).
    Padrao: <raiz do kit>\cofre

.EXAMPLE
    .\scripts\cofre.ps1 -Fechar -Caminho 'G:\Meu Drive\cofre'
    .\scripts\cofre.ps1 -Abrir  -Caminho 'G:\Meu Drive\cofre\segredos.age'
#>
[CmdletBinding(DefaultParameterSetName = 'Fechar')]
param(
    [Parameter(ParameterSetName = 'Fechar')][switch]$Fechar,
    [Parameter(ParameterSetName = 'Abrir')][switch]$Abrir,
    [Parameter(ParameterSetName = 'Listar')][switch]$Listar,
    [string]$Caminho
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

$lista         = Join-Path $script:DotfilesRaiz 'config\segredos.lista'
$padraoDestino = Join-Path $script:DotfilesRaiz 'cofre'
$perfil        = $env:USERPROFILE

if (-not (Test-Comando 'age')) {
    Write-Erro 'age nao encontrado.'
    Write-Host 'Instale com: winget install FiloSottile.age'
    exit 1
}

# O tar do Windows 10/11 (bsdtar) serve; sem ele nao da para empacotar.
if (-not (Test-Comando 'tar')) {
    Write-Erro 'tar nao encontrado (esperado em C:\Windows\System32\tar.exe).'
    exit 1
}

# Le config/segredos.lista e devolve os caminhos que existem de fato.
function Get-CaminhosExistentes {
    if (-not (Test-Path -LiteralPath $lista)) {
        throw "lista nao encontrada: $lista"
    }
    $saida = New-Object System.Collections.ArrayList
    foreach ($linha in (Get-Content -LiteralPath $lista)) {
        $c = $linha.Trim()
        if ($c -eq '' -or $c.StartsWith('#')) { continue }
        if (Test-Path -LiteralPath (Join-Path $perfil $c)) {
            [void]$saida.Add($c)
        }
    }
    return $saida.ToArray()
}

# ----------------------------------------------------------------- fechar ---
function Invoke-Fechar {
    $destino = $Caminho
    if (-not $destino) { $destino = $padraoDestino }
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    $saida = Join-Path $destino 'segredos.age'

    $itens = Get-CaminhosExistentes
    if ($itens.Count -eq 0) {
        Write-Erro 'nenhum dos caminhos de segredos.lista existe nesta maquina'
        exit 1
    }

    Write-Info "$($itens.Count) itens encontrados:"
    $itens | ForEach-Object { Write-Host "    $_" }

    if (Test-Path -LiteralPath $saida) {
        $backup = "$saida.anterior"
        Move-Item -LiteralPath $saida -Destination $backup -Force
        Write-Aviso "cofre anterior renomeado: $backup"
    }

    Write-Host ''
    Write-Info 'o age vai pedir uma passphrase. Use uma forte e guarde no gerenciador de senhas.'
    Write-Aviso 'passphrase perdida = cofre irrecuperavel.'
    Write-Host ''

    # O tar do Windows nao lida bem com pipe binario no PowerShell 5.1, entao
    # o arquivo intermediario e inevitavel. Ele vai para a pasta temporaria e
    # e apagado logo depois -- inclusive se o age falhar (bloco finally).
    $temporario = Join-Path ([System.IO.Path]::GetTempPath()) ("cofre-" + [guid]::NewGuid().ToString() + ".tar")
    try {
        & tar -C $perfil -cf $temporario @itens
        if ($LASTEXITCODE -ne 0) { throw "tar falhou (codigo $LASTEXITCODE)" }

        & age --passphrase --output $saida $temporario
        if ($LASTEXITCODE -ne 0) { throw "age falhou (codigo $LASTEXITCODE)" }
    } finally {
        if (Test-Path -LiteralPath $temporario) {
            # Sobrescreve antes de apagar: remocao simples deixa o conteudo
            # recuperavel no disco.
            $tamanho = (Get-Item -LiteralPath $temporario).Length
            $zeros = New-Object byte[] ([math]::Min($tamanho, 1MB))
            $fs = [System.IO.File]::OpenWrite($temporario)
            try {
                $escrito = 0
                while ($escrito -lt $tamanho) {
                    $bloco = [math]::Min($zeros.Length, $tamanho - $escrito)
                    $fs.Write($zeros, 0, $bloco)
                    $escrito += $bloco
                }
            } finally { $fs.Close() }
            Remove-Item -LiteralPath $temporario -Force
        }
    }

    Write-Ok "cofre criado: $saida"
    $kb = [math]::Round((Get-Item -LiteralPath $saida).Length / 1KB, 1)
    Write-Host "    tamanho: $kb KB"
    Write-Host ''
    Write-Info 'guarde uma copia em pelo menos dois lugares separados, por exemplo:'
    Write-Host  '    - Google Drive'
    Write-Host  '    - pendrive guardado fisicamente'
    Write-Aviso 'a passphrase NAO deve ficar junto do cofre.'
}

# ------------------------------------------------------------------ abrir ---
function Invoke-Abrir {
    $arquivo = $Caminho
    if (-not $arquivo) { $arquivo = Join-Path $padraoDestino 'segredos.age' }
    if (-not (Test-Path -LiteralPath $arquivo)) {
        Write-Erro "cofre nao encontrado: $arquivo"
        exit 1
    }

    Write-Info "restaurando de: $arquivo"
    Write-Aviso 'arquivos existentes no perfil com o mesmo nome serao sobrescritos.'
    Write-Host ''
    Write-Info 'digite a passphrase do cofre:'

    $temporario = Join-Path ([System.IO.Path]::GetTempPath()) ("cofre-" + [guid]::NewGuid().ToString() + ".tar")
    try {
        & age --decrypt --output $temporario $arquivo
        if ($LASTEXITCODE -ne 0) { throw "age falhou (codigo $LASTEXITCODE)" }

        & tar -C $perfil -xf $temporario
        if ($LASTEXITCODE -ne 0) { throw "tar falhou (codigo $LASTEXITCODE)" }
    } finally {
        if (Test-Path -LiteralPath $temporario) {
            Remove-Item -LiteralPath $temporario -Force
        }
    }

    Write-Ok 'cofre restaurado no perfil do usuario'
    Write-Host ''
    Write-Info 'confira:'
    Write-Host  '    gh auth status'
    Write-Host  '    ssh -T git@github.com'
}

# ----------------------------------------------------------------- listar ---
function Invoke-Listar {
    $arquivo = $Caminho
    if (-not $arquivo) { $arquivo = Join-Path $padraoDestino 'segredos.age' }
    if (-not (Test-Path -LiteralPath $arquivo)) {
        Write-Erro "cofre nao encontrado: $arquivo"
        exit 1
    }
    Write-Info "conteudo de $arquivo"
    $temporario = Join-Path ([System.IO.Path]::GetTempPath()) ("cofre-" + [guid]::NewGuid().ToString() + ".tar")
    try {
        & age --decrypt --output $temporario $arquivo
        if ($LASTEXITCODE -ne 0) { throw "age falhou (codigo $LASTEXITCODE)" }
        & tar -tf $temporario
    } finally {
        if (Test-Path -LiteralPath $temporario) {
            Remove-Item -LiteralPath $temporario -Force
        }
    }
}

# ------------------------------------------------------------------ fluxo ---
if     ($Fechar) { Invoke-Fechar }
elseif ($Abrir)  { Invoke-Abrir }
elseif ($Listar) { Invoke-Listar }
else {
    Write-Host 'Use um dos modos:'
    Write-Host '  .\scripts\cofre.ps1 -Fechar [-Caminho <pasta>]'
    Write-Host '  .\scripts\cofre.ps1 -Abrir  [-Caminho <arquivo.age>]'
    Write-Host '  .\scripts\cofre.ps1 -Listar [-Caminho <arquivo.age>]'
    exit 1
}
