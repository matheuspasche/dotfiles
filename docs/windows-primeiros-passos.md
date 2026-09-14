# Windows: primeiros passos

O que costuma travar numa instalacao nova, verificado numa maquina real
(nao copiado de guia antigo). Leia antes de reportar bug no kit -- boa parte
do que aparece aqui **nao e falha do script**, e comportamento do proprio
Windows/winget que so aparece na hora.

```powershell
.\scripts\configurar.ps1        # 1. o que voce usa (perguntas)
.\scripts\hardware.ps1          # 2. o que o seu hardware pede
.\scripts\setup-windows.ps1     # 3. instala o que voce escolheu
.\install.ps1 -Extensoes        # 4. gitconfig, VS Code, Makevars
```

---

## WSL2 e Docker Desktop exigem administrador -- e a BIOS

Duas travas separadas, nesta ordem:

**1. Administrador.** `wsl --install` habilita recursos opcionais do Windows
(Virtual Machine Platform, WSL), e isso exige uma sessao elevada. O
`setup-windows.ps1` detecta isso (`Test-Admin`) e **pula o WSL sem tentar**
quando nao esta elevado -- ele nao falha feio, so avisa. O resto do setup
(winget, driver de GPU) funciona normal sem admin.

**2. Virtualizacao na BIOS.** Mesmo como administrador, o WSL2 nao sobe se a
BIOS nao liberou virtualizacao (`SVM Mode` na AMD, `Intel VT-x` na Intel).
Confira com:

```powershell
.\scripts\hardware.ps1
```

Se aparecer "virtualizacao NAO habilitada": reinicie, entre na BIOS (`Del`
ou `F2` no boot, varia por placa), ligue `SVM Mode`/`Intel VT-x`, salve.

**Para resolver de vez**, depois de acertar a BIOS:

```powershell
# Feche este terminal, abra um novo com botao direito -> "Executar como administrador"
cd C:\Users\<voce>\Documents\dotfiles
.\scripts\setup-windows.ps1
```

O script e idempotente: roda de novo sem admin nao quebra nada, e rodar como
admin so instala o que ainda faltava (WSL/Docker) -- nao reinstala o resto.

---

## Nem todo id de winget sugerido existe de verdade

`winget install <id>` falha em silencio quando o id esta errado: a mensagem
e so "No package found matching input criteria." -- facil de confundir com
"o pacote nao existe para Windows". Ja apareceram dois casos reais no
manifesto deste kit (`btop.btop`, `dbeaver.dbeaver` -- os corretos eram
`aristocratos.btop4win` e `DBeaver.DBeaver.Community`).

Antes de assumir que um pacote so falta empacotar, confira:

```powershell
winget show --id <id> --exact --accept-source-agreements
```

"No package found" quer dizer id errado (ou realmente ausente do winget) --
nunca falta de rede ou de permissao, que dao outro erro.

### Nem AMD nem NVIDIA publicam o instalador completo do driver no winget

`AMD.AMDSoftwareAdrenalinEdition`, `AMD.ChipsetSoftware` e
`Nvidia.GeForceExperience` **nao existem** no winget -- nenhum dos dois
fabricantes publica esses instaladores la. O `hardware.ps1` so aponta o
caminho certo (site oficial da AMD; app da NVIDIA pela Microsoft Store, id
real `XP8CLZL93F5Z4P`). O stack `jogos` do `setup-windows.ps1` automatiza os
dois: baixa e abre o instalador da AMD, ou instala o app da NVIDIA via
winget/msstore.

Um detalhe do download da AMD: `drivers.amd.com` recusa o arquivo sem um
cabecalho `Referer` e `User-Agent` de navegador -- sem eles, devolve uma
pagina HTML de erro ("Download Not Complete") do mesmo tamanho que um
`.exe` pequeno, e o problema so aparece quando o "instalador" nao abre. O
`setup-windows.ps1` ja manda os dois cabecalhos.

---

## scoop: "Erro de seguranca" ao instalar

O instalador oficial do scoop (`get.scoop.sh`) sugere `Invoke-Expression`
numa string baixada na hora. Antivirus/EDR (inclusive o Defender, dependendo
da configuracao) costuma bloquear exatamente esse padrao -- e a tecnica mais
comum de entrega de malware via PowerShell -- mesmo com a
`ExecutionPolicy` liberada:

```
System.Security.SecurityException: Erro de seguranca.
```

O `setup-windows.ps1` ja evita isso: baixa o instalador para um arquivo
`.ps1` de verdade e executa como script, em vez de `Invoke-Expression` em
memoria. Um `.ps1` de verdade passa pelo AMSI normal e nao esbarra nisso.

---

## Instalador GUI "cancelado" sem voce ter clicado em nada

Se um pacote (LibreOffice, Microsoft 365...) pede elevacao (UAC) durante o
`setup-windows.ps1`, o popup aparece na sua tela de verdade -- **nao** e
automatico, e clicar "Nao"/fechar a janela conta como cancelamento
(`Installer failed with exit code: 1602`). Isso e voce decidindo, nao bug do
kit. Se quiser aquele pacote, rode o setup nesse grupo de novo e aprove o
UAC dessa vez.

## "Installer hash does not match" no Microsoft 365

Falha do proprio catalogo do winget: o binario que a Microsoft serve no CDN
muda sem o hash do manifesto do winget acompanhar. Nao e nada que o kit
cause nem consiga corrigir -- tentar de novo mais tarde as vezes resolve, ou
baixe direto de [office.com](https://www.office.com).

---

## Detectando GPU sem o driver do fabricante instalado

`hardware.ps1` identifica AMD/NVIDIA/Intel **antes** de qualquer driver ser
instalado, porque le `Win32_VideoController` -- informacao de hardware (PCI
vendor/device ID), nao do driver. Mesmo com o driver generico
"Microsoft Basic Display Adapter", o Windows ja sabe o fabricante e modelo.

## Fontes

Verificado nesta sessao contra o winget e os sites dos fabricantes
diretamente (`winget show`, `winget search`, download real testado) -- nao
copiado de guia desatualizado.
