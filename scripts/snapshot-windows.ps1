<#
.SYNOPSIS
    Fotografa o estado desta maquina Windows antes de formatar.

.DESCRIPTION
    Equivalente Windows do snapshot-sistema.sh. Gera, em snapshots/windows-<data>/:

      programas-winget.txt   tudo que o winget ve instalado
      programas-scoop.txt    idem para o scoop, quando existir
      extensoes-vscode.txt   extensoes do VS Code, prontas para reinstalar
      pacotes-r.txt          pacotes R instalados (nome e versao)
      pacotes-python.txt     pip freeze do Python do PATH
      wsl-distros.txt        distribuicoes WSL e versao
      docker-imagens.txt     imagens Docker locais
      drivers-rede.txt       adaptadores de rede -- util se o Wi-Fi nao subir
      discos.txt             layout de discos e volumes
      variaveis-path.txt     PATH de usuario e de maquina
      resumo.md              indice legivel de tudo acima

    NAO coleta segredo nenhum. Credenciais sao responsabilidade do
    scripts/cofre.ps1, que cifra antes de gravar.

.PARAMETER Destino
    Pasta onde gravar. Padrao: <raiz do kit>\snapshots

.EXAMPLE
    .\scripts\snapshot-windows.ps1
    .\scripts\snapshot-windows.ps1 -Destino 'G:\Meu Drive\backup-formatacao'
#>
[CmdletBinding()]
param(
    [string]$Destino
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot\common.ps1"

if (-not $Destino) { $Destino = Join-Path $script:DotfilesRaiz 'snapshots' }

$carimbo = Get-Date -Format 'yyyy-MM-dd'
$pasta   = Join-Path $Destino "windows-$carimbo"
New-Item -ItemType Directory -Path $pasta -Force | Out-Null
Write-Info "gravando em: $pasta"

# Executa um bloco e grava a saida num arquivo, sem abortar o snapshot inteiro
# quando a ferramenta nao existe nesta maquina.
function Coletar {
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [Parameter(Mandatory)][string]$Rotulo,
        [Parameter(Mandatory)][scriptblock]$Bloco
    )
    $caminho = Join-Path $pasta $Arquivo
    try {
        $saida = & $Bloco 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($saida)) {
            Set-Content -LiteralPath $caminho -Value '(vazio)' -Encoding UTF8
            Write-Aviso "$Rotulo -- sem dados"
        } else {
            Set-Content -LiteralPath $caminho -Value $saida -Encoding UTF8
            Write-Ok "$Rotulo -> $Arquivo"
        }
    } catch {
        Set-Content -LiteralPath $caminho -Value "(falhou: $($_.Exception.Message))" -Encoding UTF8
        Write-Aviso "$Rotulo falhou: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------- programas --

Coletar -Arquivo 'programas-winget.txt' -Rotulo 'programas (winget)' -Bloco {
    if (Test-Comando 'winget') { winget list --accept-source-agreements }
    else { 'winget indisponivel' }
}

Coletar -Arquivo 'programas-scoop.txt' -Rotulo 'programas (scoop)' -Bloco {
    if (Test-Comando 'scoop') { scoop list } else { 'scoop nao instalado' }
}

# Lista tambem o que foi instalado fora de gerenciador -- e o que da trabalho
# de lembrar depois de formatar.
Coletar -Arquivo 'programas-instalados.txt' -Rotulo 'programas (registro)' -Bloco {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $chaves -ErrorAction SilentlyContinue |
        # Com StrictMode, acessar propriedade ausente lanca erro -- por isso o
        # teste e feito sobre a lista de propriedades, nao sobre o valor.
        Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' } |
        Select-Object DisplayName, DisplayVersion, Publisher |
        Sort-Object DisplayName -Unique |
        Format-Table -AutoSize
}

# ---------------------------------------------------------------- VS Code ---

Coletar -Arquivo 'extensoes-vscode.txt' -Rotulo 'extensoes do VS Code' -Bloco {
    if (Test-Comando 'code') { code --list-extensions }
    else { 'comando code indisponivel' }
}

# --------------------------------------------------------------------- R ----

Coletar -Arquivo 'pacotes-r.txt' -Rotulo 'pacotes R' -Bloco {
    if (Test-Comando 'Rscript') {
        # So os instalados pelo usuario; ignora os que vem com o R.
        $expr = 'ip <- installed.packages(); ip <- ip[is.na(ip[,"Priority"]), c("Package","Version")]; write.table(ip, quote=FALSE, row.names=FALSE)'
        Rscript -e $expr
    } else { 'Rscript indisponivel' }
}

# ---------------------------------------------------------------- Python ----

Coletar -Arquivo 'pacotes-python.txt' -Rotulo 'pacotes Python' -Bloco {
    if (Test-Comando 'python') { python -m pip freeze }
    else { 'python indisponivel' }
}

Coletar -Arquivo 'ferramentas-uv.txt' -Rotulo 'ferramentas uv' -Bloco {
    if (Test-Comando 'uv') { uv tool list } else { 'uv indisponivel' }
}

# ------------------------------------------------------------------- WSL ----

Coletar -Arquivo 'wsl-distros.txt' -Rotulo 'distribuicoes WSL' -Bloco {
    if (Test-Comando 'wsl') { wsl --list --verbose } else { 'WSL indisponivel' }
}

# ---------------------------------------------------------------- Docker ----

Coletar -Arquivo 'docker-imagens.txt' -Rotulo 'imagens Docker' -Bloco {
    if (Test-Comando 'docker') { docker image ls } else { 'docker indisponivel' }
}

Coletar -Arquivo 'docker-volumes.txt' -Rotulo 'volumes Docker' -Bloco {
    if (Test-Comando 'docker') { docker volume ls } else { 'docker indisponivel' }
}

# ------------------------------------------------------------- hardware -----

# Adaptador de rede: se o Windows novo subir sem driver de Wi-Fi, esta lista
# diz exatamente qual driver baixar de outra maquina.
Coletar -Arquivo 'drivers-rede.txt' -Rotulo 'adaptadores de rede' -Bloco {
    Get-CimInstance Win32_NetworkAdapter |
        Where-Object { $_.PhysicalAdapter } |
        Select-Object Name, Manufacturer, MACAddress |
        Format-Table -AutoSize
}

Coletar -Arquivo 'discos.txt' -Rotulo 'discos e volumes' -Bloco {
    Get-CimInstance Win32_DiskDrive |
        Select-Object Model, InterfaceType,
                      @{n='TamanhoGB';e={[math]::Round($_.Size/1GB,1)}} |
        Format-Table -AutoSize
    Get-CimInstance Win32_LogicalDisk |
        Select-Object DeviceID, VolumeName, FileSystem,
                      @{n='TamanhoGB';e={[math]::Round($_.Size/1GB,1)}},
                      @{n='LivreGB';e={[math]::Round($_.FreeSpace/1GB,1)}} |
        Format-Table -AutoSize
}

Coletar -Arquivo 'variaveis-path.txt' -Rotulo 'PATH' -Bloco {
    '== PATH do usuario =='
    [Environment]::GetEnvironmentVariable('Path','User') -split ';'
    ''
    '== PATH da maquina =='
    [Environment]::GetEnvironmentVariable('Path','Machine') -split ';'
}

# ------------------------------------------------------------------ resumo --

$sistema = (Get-CimInstance Win32_OperatingSystem).Caption
$agora   = Get-Date -Format 'yyyy-MM-dd HH:mm'

$resumo = @"
# Snapshot do Windows -- $carimbo

Maquina: $env:COMPUTERNAME
Usuario: $env:USERNAME
Sistema: $sistema
Gerado : $agora

## Arquivos

| Arquivo | Conteudo |
|---|---|
| programas-winget.txt | tudo que o winget enxerga instalado |
| programas-scoop.txt | idem para o scoop |
| programas-instalados.txt | inclui o que foi instalado fora de gerenciador |
| extensoes-vscode.txt | lista pronta para reinstalar com code --install-extension |
| pacotes-r.txt | pacotes R do usuario, nome e versao |
| pacotes-python.txt | pip freeze |
| ferramentas-uv.txt | ferramentas instaladas com uv tool |
| wsl-distros.txt | distribuicoes WSL e versao |
| docker-imagens.txt | imagens Docker locais |
| docker-volumes.txt | volumes Docker -- confira antes de formatar |
| drivers-rede.txt | adaptadores de rede, para baixar driver se o Wi-Fi nao subir |
| discos.txt | layout de discos |
| variaveis-path.txt | PATH de usuario e de maquina |

## O que este snapshot NAO contem

Segredo nenhum. Token, senha e credencial ficam no cofre cifrado --
ver scripts/cofre.ps1 e docs/segredos.md.

## Antes de formatar

- [ ] Copiar esta pasta para fora do disco que sera formatado
- [ ] Gerar o cofre: scripts\cofre.ps1 -Fechar
- [ ] Conferir docker-volumes.txt -- volume com dado local nao volta sozinho
- [ ] git status em todo repositorio com trabalho nao commitado
"@

Set-Content -LiteralPath (Join-Path $pasta 'resumo.md') -Value $resumo -Encoding UTF8
Write-Ok 'resumo.md'

Write-Host ''
Write-Ok "snapshot completo: $pasta"
Write-Aviso 'copie esta pasta para fora do disco antes de formatar.'
