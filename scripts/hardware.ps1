<#
.SYNOPSIS
    Identifica o hardware no Windows e diz o que instalar por causa dele.

.DESCRIPTION
    Gemeo do hardware.sh. Nao instala nada: detecta CPU, GPU, placa-mae,
    rede, bluetooth, disco e virtualizacao, e imprime o que aquele hardware
    especifico pede.

.PARAMETER Exportar
    Imprime CHAVE=valor em vez do relatorio, para outro script consumir.

.EXAMPLE
    .\scripts\hardware.ps1
    .\scripts\hardware.ps1 -Exportar
#>
[CmdletBinding()]
param([switch]$Exportar)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot\common.ps1"

# --------------------------------------------------------------------- CPU ---
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuModelo = $cpu.Name.Trim()
$cpuNucleos = $cpu.NumberOfCores
$cpuThreads = $cpu.NumberOfLogicalProcessors
$cpuFabricante = 'desconhecido'
if ($cpuModelo -match 'AMD')   { $cpuFabricante = 'amd' }
if ($cpuModelo -match 'Intel') { $cpuFabricante = 'intel' }

# VirtualizationFirmwareEnabled diz se a BIOS liberou; sem isso nao ha
# WSL2 nem Docker Desktop, e o erro que o usuario ve nao aponta para a BIOS.
$virtualizacao = 'nao'
if ($cpu.PSObject.Properties.Name -contains 'VirtualizationFirmwareEnabled') {
    if ($cpu.VirtualizationFirmwareEnabled) { $virtualizacao = 'sim' }
}
# Num host que ja roda Hyper-V, o campo acima vem falso mesmo com tudo ligado.
$hyperv = Get-CimInstance Win32_ComputerSystem
if ($hyperv.HypervisorPresent) { $virtualizacao = 'sim' }

# --------------------------------------------------------------------- GPU ---
$infoGpu = Get-InfoGpu
$gpuModelo = $infoGpu.Modelo
$gpuFabricante = $infoGpu.Fabricante

# ---------------------------------------------------------------- placa-mae --
$placa = Get-CimInstance Win32_BaseBoard
$placaModelo = "$($placa.Manufacturer) $($placa.Product)".Trim()

# --------------------------------------------------------------- memoria -----
$memoriaGB = [math]::Round($hyperv.TotalPhysicalMemory / 1GB, 0)

# ----------------------------------------------------------- rede/bluetooth --
$rede = @(Get-CimInstance Win32_NetworkAdapter |
    Where-Object { $_.PhysicalAdapter -and $_.Name } |
    Select-Object -ExpandProperty Name -First 3)

$bluetooth = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Bluetooth' -and $_.Status -eq 'OK' } |
    Select-Object -ExpandProperty FriendlyName -First 1)

# -------------------------------------------------------------------- disco --
$discos = @(Get-CimInstance Win32_DiskDrive)
$temNVMe = 'nao'
foreach ($d in $discos) {
    if ($d.Model -match 'NVMe' -or $d.PNPDeviceID -match 'NVME') { $temNVMe = 'sim' }
}

# ----------------------------------------------------------------- exportar --
if ($Exportar) {
    "HW_CPU_FABRICANTE=`"$cpuFabricante`""
    "HW_CPU_MODELO=`"$cpuModelo`""
    "HW_CPU_NUCLEOS=`"$cpuNucleos`""
    "HW_CPU_THREADS=`"$cpuThreads`""
    "HW_VIRTUALIZACAO=`"$virtualizacao`""
    "HW_GPU_FABRICANTE=`"$gpuFabricante`""
    "HW_GPU_MODELO=`"$gpuModelo`""
    "HW_PLACA=`"$placaModelo`""
    "HW_NVME=`"$temNVMe`""
    "HW_MEMORIA_GB=`"$memoriaGB`""
    exit 0
}

# ---------------------------------------------------------------- relatorio --
Write-Host ''
Write-Info 'Hardware detectado'
Write-Host ''
Write-Host ("  CPU         {0}" -f $cpuModelo)
Write-Host ("              {0} nucleos / {1} threads" -f $cpuNucleos, $cpuThreads)
Write-Host ("  GPU         {0}" -f $gpuModelo)
Write-Host ("  Placa-mae   {0}" -f $placaModelo)
Write-Host ("  Memoria     {0} GB" -f $memoriaGB)
foreach ($r in $rede) { Write-Host ("  Rede        {0}" -f $r) }
if ($bluetooth.Count -gt 0) { Write-Host ("  Bluetooth   {0}" -f $bluetooth[0]) }
Write-Host ("  NVMe        {0}" -f $temNVMe)

Write-Host ''
Write-Info 'O que este hardware pede'
Write-Host ''

# --- virtualizacao ---
if ($virtualizacao -eq 'sim') {
    Write-Ok 'virtualizacao habilitada (WSL2 e Docker Desktop funcionam)'
} else {
    Write-Aviso 'virtualizacao NAO habilitada'
    Write-Host  '      Ligue na BIOS: SVM Mode (AMD) ou Intel VT-x.'
    Write-Host  '      E habilite no Windows:'
    Write-Host  '        dism /online /enable-feature /featurename:VirtualMachinePlatform /all'
}

# --- GPU ---
Write-Host ''
switch ($gpuFabricante) {
    'amd' {
        Write-Ok 'GPU AMD'
        Write-Host '      O Windows Update entrega um driver basico. Para jogos e'
        Write-Host '      aceleracao completa, use o driver Adrenalin -- a AMD nao'
        Write-Host '      publica esse instalador no winget, so no site oficial:'
        Write-Host '        https://www.amd.com/pt/support (autodetectar hardware)'
        Write-Host '      Ou peca o stack "jogos": .\scripts\setup-windows.ps1 -Grupo jogos'
        Write-Host '      baixa e abre esse instalador sozinho.'
    }
    'nvidia' {
        Write-Ok 'GPU NVIDIA'
        Write-Host '      NVIDIA app (driver + overlay + DLSS), pela Microsoft Store:'
        Write-Host '        winget install XP8CLZL93F5Z4P --source msstore'
        Write-Host '      (o stack "jogos" ja faz isso sozinho)'
        Write-Host '      Para CUDA (treino de modelo na GPU):'
        Write-Host '        winget install Nvidia.CUDA'
    }
    'intel' {
        Write-Ok 'GPU Intel'
        Write-Host '        winget install Intel.IntelDriverAndSupportAssistant'
    }
    default { Write-Aviso 'GPU nao identificada' }
}

# --- placa-mae ---
Write-Host ''
Write-Host '  Chipset e BIOS:'
if ($placaModelo -match 'Gigabyte') {
    Write-Host '      Gigabyte: use o App Center ou baixe o BIOS da pagina do modelo.'
    Write-Host "      Modelo detectado: $($placa.Product)"
} elseif ($placaModelo -match 'ASUS') {
    Write-Host '      ASUS: MyASUS ou Armoury Crate para driver e BIOS.'
} elseif ($placaModelo -match 'MSI') {
    Write-Host '      MSI: MSI Center.'
}
if ($cpuFabricante -eq 'amd') {
    # Nem "AMD.ChipsetSoftware" nem nenhum outro pacote de chipset AMD existe
    # no winget (conferido: "No package found matching input criteria."). O
    # instalador universal da AMD so esta no site oficial, e detecta sozinho
    # qual chipset (B450, X570...) esta na placa.
    Write-Host '      Chipset AMD (necessario para o gerenciamento de energia correto):'
    Write-Host '        https://www.amd.com/pt/support/download/drivers.html (chipset)'
}

# --- bluetooth ---
if ($bluetooth.Count -gt 0) {
    Write-Host ''
    Write-Host '  Bluetooth:'
    if ($bluetooth[0] -match 'Intel') {
        Write-Ok '    adaptador Intel -- driver vem pelo Windows Update'
        Write-Host '      Se o audio falhar depois de suspender, atualize por:'
        Write-Host '        winget install Intel.IntelDriverAndSupportAssistant'
    } else {
        Write-Host "      $($bluetooth[0])"
    }
}

# --- disco ---
Write-Host ''
Write-Host '  Disco:'
Write-Host '      O Windows ja faz TRIM em SSD por padrao. Conferir:'
Write-Host '        fsutil behavior query DisableDeleteNotify'
Write-Host '      Resposta 0 significa TRIM ativo.'

Write-Host ''
Write-Info 'Nada acima foi executado -- sao sugestoes para este hardware.'
exit 0
