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

.PARAMETER Apenas
    Aplica so as areas listadas (entre aspas se for mais de uma), ignorando
    o que o perfil.conf pediria. Areas: git, vscode, r.
    Ex.: -Apenas r          -Apenas "git r"

.PARAMETER Simular
    Mostra o que seria feito sem escrever nada.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Extensoes
    .\install.ps1 -Apenas r
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Extensoes,
    [string]$Apenas,
    [switch]$Simular
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\scripts\common.ps1"

$conf = Get-Perfil

# Areas de configuracao aplicaveis. Sem -Apenas, seguem o perfil: nao ha por
# que escrever um ~/.gitconfig numa maquina que nao pediu o stack "dev", nem
# settings do VS Code sem o stack "editor", nem Makevars sem o stack "r".
# Sem perfil nenhum, aplica todas -- quem roda o install.ps1 cru esta pedindo
# o kit inteiro. Mesma logica do install.sh (sem a area "kde", que nao existe
# no Windows).
$areasValidas = @('git', 'vscode', 'r')
$areas = New-Object System.Collections.Generic.List[string]

if ($Apenas) {
    foreach ($a in ($Apenas -split '\s+' | Where-Object { $_ })) {
        if ($areasValidas -notcontains $a) {
            throw "area desconhecida: $a (validas: $($areasValidas -join ' '))"
        }
        $areas.Add($a)
    }
} elseif ($conf['_CARREGADO']) {
    $stacksPerfil = $conf['STACKS'] -split '\s+' | Where-Object { $_ }
    if ($stacksPerfil -contains 'dev')    { $areas.Add('git') }
    if ($stacksPerfil -contains 'editor') { $areas.Add('vscode') }
    if ($stacksPerfil -contains 'r')      { $areas.Add('r') }
} else {
    $areas.AddRange([string[]]$areasValidas)
}

# Test-Area <nome> -- verdadeiro quando aquela area deve ser aplicada.
function Test-Area {
    param([Parameter(Mandatory)][string]$Nome)
    return $areas.Contains($Nome)
}

if ($Simular) { Write-Aviso 'modo simulacao: nada sera escrito' }

$raiz = $script:DotfilesRaiz
$perfil = $env:USERPROFILE
Write-Info "kit:    $raiz"
Write-Info "perfil: $perfil"
Write-Info "areas:  $(if ($areas.Count) { $areas -join ' ' } else { '(nenhuma)' })"

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

if (Test-Area 'git') {

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

}  # Test-Area git

# ---------------------------------------------------------------------------
# VS Code
# ---------------------------------------------------------------------------

if (Test-Area 'vscode') {

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

}  # Test-Area vscode

# ---------------------------------------------------------------------------
# R / Rcpp
# ---------------------------------------------------------------------------

if (Test-Area 'r') {

# No Windows o R procura Makevars.win em Documentos\.R\, nao em ~/.R como no
# Linux. E "Documentos" aqui e a pasta especial do Windows (a mesma que
# setup-r.ps1 usa para o .Renviron do Rtools) -- NAO necessariamente
# "%USERPROFILE%\Documents" no caminho literal: com o OneDrive fazendo
# "Backup de Pastas Conhecidas" (padrao em varias instalacoes do Windows 11),
# a pasta real vira "%USERPROFILE%\OneDrive\Documentos" (ou "Documents",
# dependendo do idioma). Gravar no caminho fixo escreve num lugar que o R
# nunca olha, e o Rcpp acaba compilando com as flags erradas sem aviso nenhum.
$documentos = [Environment]::GetFolderPath('MyDocuments')
$pastaR = Join-Path $documentos '.R'
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
            -Destino (Join-Path $documentos '.Rprofile') `
            -Rotulo '.Rprofile'
}

}  # Test-Area r

# ---------------------------------------------------------------------------
# Extensoes do VS Code
# ---------------------------------------------------------------------------

if ($Extensoes -and (Test-Area 'vscode')) {
    $lista = Join-Path $raiz 'config\vscode\extensions.txt'

    # O winget nao atualiza o PATH da sessao em curso -- se o VS Code acabou
    # de ser instalado (mesmo terminal, mesmo setup-windows.ps1), "code" so
    # aparece juntando o PATH de Machine+User de novo, sem precisar reabrir.
    if (-not (Test-Comando 'code')) {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
    }

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
if ($areas.Count -eq 0) {
    Write-Ok 'install concluido -- nenhuma area a aplicar para os stacks deste perfil.'
    exit 0
}
Write-Ok "install concluido (areas: $($areas -join ' '))."
if (Test-Area 'git')    { Write-Host 'Confira com:  git config --global --list' }
if (Test-Area 'r')      { Write-Host 'Confira com:  R CMD config CFLAGS' }
if (Test-Area 'vscode') { Write-Host 'Confira com:  code --list-extensions' }
exit 0
