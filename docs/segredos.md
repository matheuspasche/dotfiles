# Segredos

Como credenciais atravessam uma formatacao sem virar um vazamento.

## O problema

Reconfigurar GitHub, PyPI, Docker, chaves SSH e Claude Code depois de formatar
custa quase uma hora. A tentacao e jogar tudo num repositorio privado, ou numa
pasta sincronizada, e acabar com isso.

Nao faca. Motivos concretos:

- **Repositorio privado nao e privado o suficiente.** Vira publico por
  acidente -- um toggle errado, um fork, um colaborador novo, um backup
  automatico. Token do GitHub dentro de um repositorio do GitHub e escalada
  total: quem le o token le todos os repositorios.
- **Git nao esquece.** `git rm` depois nao remove o segredo; ele fica no
  packfile, no reflog e em todo clone que alguem ja fez. Limpar exige reescrever
  o historico, e mesmo assim os clones antigos continuam com a copia.
- **Pasta de nuvem sincroniza para a nuvem.** Um `.env` no Google Drive e um
  `.env` nos servidores do Google, indexado, versionado e retido depois de
  apagado.
- **O cenario de fallback piora.** Se o disco principal morreu e o que restou
  foi o disco com segredos em texto claro, um disco perdido ou roubado entrega
  tudo de uma vez.

## A solucao

Um blob cifrado com [age](https://age-encryption.org/), passphrase forte.

```
arquivos de credencial  ->  tar  ->  age --passphrase  ->  segredos.age
```

O `segredos.age` pode ficar em qualquer lugar: Google Drive, pendrive,
repositorio, anexo de e-mail. Sem a passphrase e ruido.

A passphrase fica **so no gerenciador de senhas**, em outro aparelho. Nunca
junto do cofre. Um cofre com a senha ao lado e uma pasta comum com passos
extras.

### Por que age e nao GPG

O GPG resolve o mesmo problema com trinta anos de opcoes acumuladas, chaveiro
proprio e mensagens de erro dificeis. O `age` faz uma coisa: cifra um arquivo
com uma passphrase, com padroes modernos e sem configuracao. Para este uso, e
exatamente o que se precisa -- e no dia em que o disco morreu, "sem
configuracao" vale mais que flexibilidade.

## Uso

### Criar o cofre

```powershell
.\scripts\cofre.ps1 -Fechar -Caminho 'G:\Meu Drive\cofre'
```

```bash
./scripts/cofre.sh fechar ~/Drive/cofre
```

Le `config/segredos.lista`, pega o que existe nesta maquina, empacota e cifra.
O `age` pede a passphrase duas vezes.

### Conferir sem restaurar

```powershell
.\scripts\cofre.ps1 -Listar
```

Lista o conteudo sem escrever nada em disco. **Rode isso a cada seis meses.**
Um cofre que nunca foi aberto e uma suposicao, nao um backup.

### Restaurar

```powershell
.\scripts\cofre.ps1 -Abrir -Caminho 'G:\Meu Drive\cofre\segredos.age'
```

```bash
./scripts/cofre.sh abrir ~/Drive/cofre/segredos.age
```

Extrai no HOME, sobrescrevendo o que tiver o mesmo nome, e conserta as
permissoes de `~/.ssh` e `~/.gnupg` -- o `ssh` recusa chave privada legivel
por outros usuarios.

## O que entra

Definido em [`config/segredos.lista`](../config/segredos.lista): chaves SSH,
GnuPG, `gh`, `.pypirc`, `.docker/config.json`, credenciais do Claude Code,
`.Renviron`, credenciais de AWS e gcloud, `.pgpass`, conexoes do DBeaver.

O arquivo lista **nomes**, nunca conteudo. Ele e versionado; o cofre gerado a
partir dele nao e.

## Cuidados do script

- O conteudo em texto claro nunca e gravado em disco no Linux/macOS: o `tar`
  escreve num pipe e o `age` le dali.
- No Windows o `tar` do sistema nao lida bem com pipe binario no PowerShell
  5.1, entao existe um arquivo intermediario na pasta temporaria. Ele e
  sobrescrito com zeros antes de ser apagado, inclusive quando o `age` falha.
- A passphrase nunca passa por parametro de linha de comando -- ficaria no
  historico do shell e na lista de processos. Ela vai direto para o prompt do
  `age`.
- O cofre nasce com permissao `600`.
- `.gitignore` bloqueia `cofre/`, `*.age` e uma lista de padroes de credencial
  (`*.pem`, `.env`, `id_rsa*`) como segunda camada.

## O que fazer se vazar

Se o cofre **e** a passphrase cairem na mao de alguem, trate como
comprometimento total e revogue na ordem:

1. **GitHub** -- <https://github.com/settings/tokens> revoga todos os tokens;
   <https://github.com/settings/keys> remove as chaves SSH. Depois
   `gh auth login` e `ssh-keygen` para gerar novas.
2. **PyPI** -- <https://pypi.org/manage/account/token/>, revogar e recriar.
3. **Docker Hub** -- revogar o access token nas configuracoes de seguranca.
4. **AWS / gcloud** -- rotacionar as chaves de acesso. Prioridade maxima:
   sao as que custam dinheiro.
5. **Claude Code** -- `claude logout` e login de novo.
6. **Bancos** -- trocar as senhas que estavam em `.pgpass` e no DBeaver.

Depois: gerar cofre novo com passphrase nova, apagar o antigo de toda copia.

## Manutencao

A cada seis meses, ou depois de trocar alguma credencial:

- [ ] `cofre.ps1 -Listar` -- o cofre abre? A passphrase confere?
- [ ] Esta em dois lugares (Drive **e** pendrive)?
- [ ] Credencial nova que nao esta em `segredos.lista`?
- [ ] Credencial que nao uso mais e podia ser revogada?
