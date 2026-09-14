<#
.SYNOPSIS
    Assistente que escreve o perfil.conf (versao Windows).

.DESCRIPTION
    Gemeo do configurar.sh. Faz perguntas e grava as respostas em
    perfil.conf, que nao e versionado. Os valores atuais viram o padrao de
    cada pergunta, entao reconfigurar e apertar Enter no que nao muda.

.EXAMPLE
    .\scripts\configurar.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

$conf = Get-Perfil
$destino = Join-Path $script:DotfilesRaiz 'perfil.conf'

Write-Host ''
Write-Info 'Assistente de configuracao do kit'
Write-Host '   As respostas vao para perfil.conf, que nao e versionado.'
Write-Host '   Enter aceita o valor entre colchetes.'
Write-Host ''

function Read-Texto {
    param([string]$Rotulo, [string]$Atual)
    $mostrar = $Atual
    if (-not $mostrar) { $mostrar = 'vazio' }
    $resposta = Read-Host "$Rotulo [$mostrar]"
    if ([string]::IsNullOrWhiteSpace($resposta)) { return $Atual }
    return $resposta.Trim()
}

function Read-SimNao {
    param([string]$Rotulo, [string]$Atual)
    $padrao = 's/N'
    if ($Atual -eq 'sim') { $padrao = 'S/n' }
    $resposta = Read-Host "$Rotulo [$padrao]"
    if ($resposta -match '^[sS]') { return 'sim' }
    if ($resposta -match '^[nN]') { return 'nao' }
    return $Atual
}

# Multipla escolha por numero. Devolve os ids escolhidos separados por espaco.
function Read-Lista {
    param(
        [string]$Rotulo,
        [string]$Atuais,
        [Parameter(Mandatory)][array]$Opcoes   # de {id, desc}
    )

    Write-Host ''
    Write-Host $Rotulo
    $marcados = $Atuais -split '\s+' | Where-Object { $_ }
    for ($i = 0; $i -lt $Opcoes.Count; $i++) {
        $marca = ' '
        if ($marcados -contains $Opcoes[$i].id) { $marca = 'x' }
        Write-Host ("  [{0}] {1}) {2,-14} {3}" -f $marca, ($i + 1), $Opcoes[$i].id, $Opcoes[$i].desc)
    }
    $escolha = Read-Host 'Numeros separados por espaco (Enter mantem o marcado)'
    if ([string]::IsNullOrWhiteSpace($escolha)) { return $Atuais }

    $saida = New-Object System.Collections.ArrayList
    foreach ($n in ($escolha -split '\s+')) {
        # Entrada invalida e ignorada em vez de derrubar o assistente.
        $numero = 0
        if (-not [int]::TryParse($n, [ref]$numero)) { continue }
        if ($numero -lt 1 -or $numero -gt $Opcoes.Count) { continue }
        [void]$saida.Add($Opcoes[$numero - 1].id)
    }
    return ($saida -join ' ')
}

# --------------------------------------------------------------- identidade --
Write-Info '1. Identidade do Git'
Write-Host '   Usada para assinar seus commits.'
$gitNome = Read-Texto '   Seu nome' $conf['GIT_NOME']
Write-Host ''
Write-Host '   Dica: no GitHub, Settings > Emails > Keep my email addresses private'
Write-Host '   da um endereco <id>+<usuario>@users.noreply.github.com. Usando ele,'
Write-Host '   seu e-mail real nao aparece em commit publico nenhum.'
$gitEmail = Read-Texto '   Seu e-mail' $conf['GIT_EMAIL']

# ------------------------------------------------------------------ stacks ---
$stacks = Read-Lista '2. Que stacks voce usa?' $conf['STACKS'] @(
    @{ id = 'base';          desc = 'curl e o terminal -- o minimo de QUALQUER maquina' }
    @{ id = 'pessoal';       desc = 'Spotify, WhatsApp, VLC' }
    @{ id = 'jogos';         desc = 'Steam, Heroic (Epic/GOG), Epic, EA app' }
    @{ id = 'escritorio';    desc = 'LibreOffice, OnlyOffice, Microsoft 365' }
    @{ id = 'produtividade'; desc = 'PowerToys, Everything, Flameshot' }
    @{ id = 'opcional';      desc = 'Obsidian, Syncthing' }
    @{ id = 'dev';           desc = 'git, gh, ripgrep, fd, jq, age' }
    @{ id = 'editor';        desc = 'VS Code, Claude Code e Node' }
    @{ id = 'python';        desc = 'Python e uv' }
    @{ id = 'r';             desc = 'R, RStudio, Quarto e toolchain de compilacao' }
    @{ id = 'dados';         desc = 'DBeaver, DuckDB' }
    @{ id = 'jvm';           desc = 'JDK 17 (requisito do Spark)' }
    @{ id = 'container';     desc = 'Docker Desktop (e WSL2)' }
)
$listaStacks = $stacks -split '\s+' | Where-Object { $_ }

# ------------------------------------------------------------- bibliotecas ---
$libsR = ''
if ($listaStacks -contains 'r') {
    $opcoes = @()
    foreach ($c in (Get-Conjuntos -Linguagem r)) {
        $opcoes += @{ id = $c.id; desc = "$($c.nome) (~$($c.minutos) min)" }
    }
    $libsR = Read-Lista '3. Bibliotecas de R' $conf['LIBS_R'] $opcoes
} else {
    Write-Info '3. Bibliotecas de R -- pulado (stack r nao selecionado)'
}

$libsPy = ''
if ($listaStacks -contains 'python') {
    $opcoes = @()
    foreach ($c in (Get-Conjuntos -Linguagem python)) {
        $opcoes += @{ id = $c.id; desc = "$($c.nome) (~$($c.minutos) min)" }
    }
    $libsPy = Read-Lista '4. Bibliotecas de Python' $conf['LIBS_PY'] $opcoes
} else {
    Write-Info '4. Bibliotecas de Python -- pulado (stack python nao selecionado)'
}

Write-Host ''
$segundoPlano = Read-SimNao '   Instalar bibliotecas em segundo plano (com log)?' $conf['LIBS_EM_SEGUNDO_PLANO']

# --------------------------------------------------------------- navegador ---
Write-Host ''
Write-Info '5. Navegador'
Write-Host '   1) firefox   2) chrome   3) brave   4) nenhum'
$navegador = Read-Texto '   Escolha (nome ou numero)' $conf['NAVEGADOR']
switch ($navegador) {
    '1' { $navegador = 'firefox' }
    '2' { $navegador = 'chrome' }
    '3' { $navegador = 'brave' }
    '4' { $navegador = 'nenhum' }
}

# ------------------------------------------------------- suite de escritorio -
# So pergunta para quem marcou o stack "escritorio" -- mesma logica da
# identidade e das extensoes: perguntar isso de quem nao vai usar so confunde.
$suiteEscritorio = $conf['SUITE_ESCRITORIO']
if ($listaStacks -contains 'escritorio') {
    Write-Host ''
    Write-Info '5b. Suite de escritorio'
    Write-Host '   1) libreoffice    de graca, ja no repositorio'
    Write-Host '   2) onlyoffice     melhor fidelidade a .docx/.xlsx'
    Write-Host '   3) microsoft365   exige assinatura (padrao no Windows)'
    Write-Host '   4) tudo           instala as tres'
    $padraoSuite = $suiteEscritorio
    if (-not $padraoSuite) { $padraoSuite = 'microsoft365' }
    $suiteEscritorio = Read-Texto '   Escolha (nome ou numero)' $padraoSuite
    switch ($suiteEscritorio) {
        '1' { $suiteEscritorio = 'libreoffice' }
        '2' { $suiteEscritorio = 'onlyoffice' }
        '3' { $suiteEscritorio = 'microsoft365' }
        '4' { $suiteEscritorio = 'tudo' }
    }
} else {
    $suiteEscritorio = ''
}

# --------------------------------------------------------------- extensoes ---
$vscode = Read-Lista '6. Extensoes do VS Code' $conf['VSCODE_EXTENSOES'] @(
    @{ id = 'base';      desc = 'Claude Code, GitLens, EditorConfig' }
    @{ id = 'python';    desc = 'Pylance, Jupyter, Ruff' }
    @{ id = 'r';         desc = 'extensao do R e depurador' }
    @{ id = 'dados';     desc = 'SQLTools, CSV, visualizador de planilha' }
    @{ id = 'container'; desc = 'Docker, Remote-WSL, Dev Containers' }
    @{ id = 'escrita';   desc = 'Markdown, Quarto' }
)

# --------------------------------------------------------------- caminhos ----
Write-Host ''
Write-Info '7. Caminhos'
Write-Host '   Onde guardar o cofre de credenciais e os snapshots.'
Write-Host '   Vazio usa a propria pasta do kit.'
$cofre = Read-Texto '   Pasta do cofre' $conf['COFRE_DESTINO']
$snapshot = Read-Texto '   Pasta dos snapshots' $conf['SNAPSHOT_DESTINO']

# ----------------------------------------------------------------- gravar ----
if (Test-Path -LiteralPath $destino) {
    Copy-Item -LiteralPath $destino -Destination "$destino.anterior" -Force
    Write-Aviso 'perfil anterior salvo em perfil.conf.anterior'
}

$agora = Get-Date -Format 'yyyy-MM-dd HH:mm'
$texto = @"
# ============================================================================
# perfil.conf -- gerado por scripts/configurar.ps1 em $agora
#
# Pode editar a mao. Formato: CHAVE="valor", sem comando nem variavel.
# Rode o assistente de novo para regerar.
# ============================================================================

# --- identidade ---
GIT_NOME="$gitNome"
GIT_EMAIL="$gitEmail"
GIT_ASSINAR="$($conf['GIT_ASSINAR'])"

# --- stacks ---
STACKS="$stacks"

# --- bibliotecas ---
LIBS_R="$libsR"
LIBS_PY="$libsPy"
LIBS_EM_SEGUNDO_PLANO="$segundoPlano"

# --- navegador ---
NAVEGADOR="$navegador"

# --- escritorio ---
SUITE_ESCRITORIO="$suiteEscritorio"

# --- editor ---
VSCODE_EXTENSOES="$vscode"

# --- Fedora: pos-instalacao (sem efeito no Windows) ---
FEDORA_RPMFUSION="$($conf['FEDORA_RPMFUSION'])"
FEDORA_CODECS="$($conf['FEDORA_CODECS'])"
FEDORA_GPU="$($conf['FEDORA_GPU'])"
FEDORA_FIRMWARE="$($conf['FEDORA_FIRMWARE'])"
FEDORA_FONTES_MS="$($conf['FEDORA_FONTES_MS'])"
FEDORA_DNF_RAPIDO="$($conf['FEDORA_DNF_RAPIDO'])"

# --- caminhos ---
COFRE_DESTINO="$cofre"
SNAPSHOT_DESTINO="$snapshot"
"@

Set-Content -LiteralPath $destino -Value $texto -Encoding UTF8
Write-Host ''
Write-Ok "perfil gravado: $destino"

# Estimativa de tempo: o unico numero que o usuario quer antes de comecar.
$minutos = 0
foreach ($id in (($libsR + ' ' + $libsPy) -split '\s+' | Where-Object { $_ })) {
    $linguagem = 'python'
    if ($id.StartsWith('r-')) { $linguagem = 'r' }
    $c = (Get-Conjuntos -Linguagem $linguagem) | Where-Object { $_.id -eq $id }
    if ($c -and $c.minutos) { $minutos += [int]$c.minutos }
}

Write-Host ''
Write-Info 'Resumo'
Write-Host "    stacks       $stacks"
$mostrarR = $libsR; if (-not $mostrarR) { $mostrarR = 'nenhum' }
$mostrarPy = $libsPy; if (-not $mostrarPy) { $mostrarPy = 'nenhum' }
Write-Host "    R            $mostrarR"
Write-Host "    Python       $mostrarPy"
Write-Host "    navegador    $navegador"
if ($suiteEscritorio) { Write-Host "    escritorio   $suiteEscritorio" }
if ($minutos -gt 0) { Write-Host "    bibliotecas  ~$minutos min de instalacao" }

Write-Host ''
Write-Info 'Proximos passos'
Write-Host '    1. .\scripts\hardware.ps1        o que o seu hardware pede'
Write-Host '    2. .\scripts\setup-windows.ps1   programas do manifesto e WSL2'
Write-Host '    3. .\install.ps1 -Extensoes      configuracoes e extensoes'
if ($libsR)  { Write-Host '    4. .\scripts\setup-r.ps1         bibliotecas de R' }
if ($libsPy) { Write-Host '    5. .\scripts\setup-python.ps1    bibliotecas de Python' }
exit 0
