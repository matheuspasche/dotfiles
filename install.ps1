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

$conf = Get-Perfil

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
        $linhas = New-Object System.Collections.ArrayList
        [void]$linhas.Add('# Configuracao Git especifica desta maquina. Nao versionada.')
        [void]$linhas.Add('# Gerado por install.ps1 a partir do perfil.conf.')

        # Identidade so entra se o perfil declarou. Sem isso o git pergunta no
        # primeiro commit -- melhor do que assinar com o nome de outra pessoa.
        if ($conf['GIT_NOME'] -or $conf['GIT_EMAIL']) {
            [void]$linhas.Add('[user]')
            if ($conf['GIT_NOME'])  { [void]$linhas.Add("`tname = $($conf['GIT_NOME'])") }
            if ($conf['GIT_EMAIL']) { [void]$linhas.Add("`temail = $($conf['GIT_EMAIL'])") }
        }

        [void]$linhas.Add('[core]')
        [void]$linhas.Add("`t# No Windows o checkout converte para CRLF e o commit volta para LF.")
        [void]$linhas.Add("`tautocrlf = true")
        [void]$linhas.Add('[credential]')
        [void]$linhas.Add("`thelper = manager")

        Set-Content -LiteralPath $local -Value ($linhas -join "`r`n") -Encoding UTF8
        Write-Ok "criado: $local"
        if (-not $conf['GIT_NOME'] -and -not $conf['GIT_EMAIL']) {
            Write-Aviso 'identidade do git nao definida -- preencha GIT_NOME e GIT_EMAIL no perfil.conf'
            Write-Aviso 'ou rode: .\scripts\configurar.ps1'
        }
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
        # A lista e dividida em secoes "[grupo]": instala so os grupos que o
        # perfil pediu em VSCODE_EXTENSOES.
        $grupos = $conf['VSCODE_EXTENSOES'] -split '\s+' | Where-Object { $_ }
        $instalarEste = $false

        foreach ($linha in (Get-Content -LiteralPath $lista)) {
            $ext = $linha.Trim()
            if ($ext -eq '' -or $ext.StartsWith('#')) { continue }

            if ($ext -match '^\[(.+)\]$') {
                $grupo = $Matches[1]
                $instalarEste = ($grupos -contains $grupo)
                if ($instalarEste) { Write-Info "grupo: $grupo" }
                continue
            }

            if (-not $instalarEste) { continue }

            if ($Simular) {
                Write-Info "[simular] code --install-extension $ext"
                continue
            }
            Write-Info "extensao: $ext"
            Invoke-Nativo -Comando 'code' -Silencioso -Argumentos @('--install-extension', $ext, '--force') | Out-Null
        }
        Write-Ok 'extensoes processadas'
    }
}

Write-Host ''
Write-Ok 'install concluido.'
Write-Host 'Confira com:  git config --global --list'
