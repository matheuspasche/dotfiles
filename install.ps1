<#
.SYNOPSIS
    Aplica as configuracoes do kit nos caminhos do Windows.

.DESCRIPTION
    Equivalente Windows do install.sh. Liga (ou copia) gitconfig, settings do
    VS Code, gitignore global e Makevars.win para os lugares certos.

    Estrategia de ligacao, na ordem: junction (pasta, nao exige privilegio),
    symlink (exige admin ou Modo Desenvolvedor), copia (sempre funciona).
    Ver New-Ligacao em scripts/common.ps1.

    Idempotente. Qualquer arquivo pre-existente vira backup com timestamp.

.PARAMETER Extensoes
    Tambem instala as extensoes do VS Code listadas em
    config/vscode/extensions.txt.

.PARAMETER Simular
    Mostra o que seria feito sem escrever nada.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Extensoes
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Extensoes,
    [switch]$Simular
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\scripts\common.ps1"

if ($Simular) { Write-Aviso 'modo simulacao: nada sera escrito' }

$raiz = $script:DotfilesRaiz
$perfil = $env:USERPROFILE
Write-Info "kit:    $raiz"
Write-Info "perfil: $perfil"

# Envolve New-Ligacao para respeitar o -Simular deste script.
function Aplicar {
    param([string]$Origem, [string]$Destino, [string]$Rotulo)
    if ($Simular) {
        Write-Info "[simular] $Rotulo -> $Destino"
        return
    }
    New-Ligacao -Origem $Origem -Destino $Destino
}

# ---------------------------------------------------------------------------
# Git
# ---------------------------------------------------------------------------

Aplicar -Origem (Join-Path $raiz 'config\gitconfig') `
        -Destino (Join-Path $perfil '.gitconfig') `
        -Rotulo 'gitconfig'

Aplicar -Origem (Join-Path $raiz 'config\gitignore_global') `
        -Destino (Join-Path $perfil '.gitignore_global') `
        -Rotulo 'gitignore global'

# ~/.gitconfig.local guarda o que e especifico desta maquina e NAO vai para o
# repositorio. O gitconfig versionado faz include dele e quebraria sem o arquivo.
$local = Join-Path $perfil '.gitconfig.local'
if (-not (Test-Path -LiteralPath $local)) {
    if ($Simular) {
        Write-Info "[simular] criaria $local"
    } else {
        $conteudo = @"
# Configuracao Git especifica desta maquina. Nao versionada.
[core]
	# No Windows o checkout converte para CRLF e o commit volta para LF.
	autocrlf = true
[credential]
	helper = manager
"@
        Set-Content -LiteralPath $local -Value $conteudo -Encoding UTF8
        Write-Ok "criado: $local"
    }
} else {
    Write-Ok "ja existe: $local"
}

# ---------------------------------------------------------------------------
# VS Code
# ---------------------------------------------------------------------------

$vscodeUser = Join-Path $env:APPDATA 'Code\User'
Aplicar -Origem (Join-Path $raiz 'config\vscode\settings.json') `
        -Destino (Join-Path $vscodeUser 'settings.json') `
        -Rotulo 'VS Code settings.json'

$keybindings = Join-Path $raiz 'config\vscode\keybindings.json'
if (Test-Path -LiteralPath $keybindings) {
    Aplicar -Origem $keybindings `
            -Destino (Join-Path $vscodeUser 'keybindings.json') `
            -Rotulo 'VS Code keybindings.json'
}

# ---------------------------------------------------------------------------
# R / Rcpp
# ---------------------------------------------------------------------------

# No Windows o R procura Makevars.win em %USERPROFILE%\Documents\.R\, nao em
# ~/.R como no Linux. Diferenca que costuma custar uma tarde de depuracao.
$pastaR = Join-Path $perfil 'Documents\.R'
if (-not $Simular -and -not (Test-Path -LiteralPath $pastaR)) {
    New-Item -ItemType Directory -Path $pastaR -Force | Out-Null
}
Aplicar -Origem (Join-Path $raiz 'config\Makevars.win') `
        -Destino (Join-Path $pastaR 'Makevars.win') `
        -Rotulo 'Makevars.win'

# .Rprofile, se existir no kit.
$rprofile = Join-Path $raiz 'config\Rprofile'
if (Test-Path -LiteralPath $rprofile) {
    Aplicar -Origem $rprofile `
            -Destino (Join-Path $perfil 'Documents\.Rprofile') `
            -Rotulo '.Rprofile'
}

# ---------------------------------------------------------------------------
# Extensoes do VS Code
# ---------------------------------------------------------------------------

if ($Extensoes) {
    $lista = Join-Path $raiz 'config\vscode\extensions.txt'
    if (-not (Test-Comando 'code')) {
        Write-Aviso 'comando "code" nao esta no PATH -- pulando extensoes.'
        Write-Aviso 'Reabra o terminal apos instalar o VS Code e rode de novo.'
    } elseif (-not (Test-Path -LiteralPath $lista)) {
        Write-Aviso "lista nao encontrada: $lista"
    } else {
        foreach ($linha in (Get-Content -LiteralPath $lista)) {
            $ext = $linha.Trim()
            if ($ext -eq '' -or $ext.StartsWith('#')) { continue }
            if ($Simular) {
                Write-Info "[simular] code --install-extension $ext"
                continue
            }
            Write-Info "extensao: $ext"
            code --install-extension $ext --force 2>&1 | Out-Null
        }
        Write-Ok 'extensoes processadas'
    }
}

Write-Host ''
Write-Ok 'install concluido.'
Write-Host 'Confira com:  git config --global --list'
