# Spark no Windows

O PySpark roda no Windows, mas tem tres armadilhas que nao existem no Linux.
O `setup-python.ps1` resolve duas sozinho; a terceira precisa de uma decisao
sua.

## 1. JAVA_HOME

O Spark e uma aplicacao JVM. Sem `JAVA_HOME` apontando para um JDK, a sessao
nem sobe.

```powershell
winget install EclipseAdoptium.Temurin.17.JDK
```

O `setup-python.ps1` procura o JDK instalado e define a variavel. Para
conferir:

```powershell
$env:JAVA_HOME
java -version
```

**Use JDK 17.** O Spark 3.x nao roda em JDK 21 ou mais novo sem flags extras
de modulo, e o erro que aparece (`InaccessibleObjectException`) nao diz isso.

## 2. PYSPARK_PYTHON

O Spark sobe processos de trabalho separados. Sem esta variavel, ele tenta
usar o Python do PATH do sistema em vez do seu ambiente virtual — e falha com
`Python worker failed to connect back`, que nao sugere a causa.

O `setup-python.ps1` define `PYSPARK_PYTHON` e `PYSPARK_DRIVER_PYTHON`
apontando para o ambiente base.

## 3. winutils.exe — a decisao que e sua

O Spark usa as bibliotecas do Hadoop para acessar o sistema de arquivos.
No Windows, o Hadoop precisa de dois binarios nativos, `winutils.exe` e
`hadoop.dll`, que **nao vem no pacote pip do PySpark**.

Sintomas sem eles:

- ler `.csv` e `.parquet` do disco local: **funciona**
- `df.write.parquet(...)` em disco local: falha com `UnsatisfiedLinkError` ou
  `NullPointerException` no `NativeIO`
- `spark.sql("...").show()` sobre dado em memoria: funciona

Ou seja, quem so le dado nao percebe o problema por semanas.

**O kit nao baixa esses binarios automaticamente, de proposito.** Eles sao
distribuidos por repositorios pessoais no GitHub, nao pelo projeto Hadoop, e
sao executaveis nativos que vao rodar com a sua permissao de usuario. Baixar
binario de terceiro sem o usuario decidir nao e coisa que um script de setup
deva fazer sozinho.

### Se voce precisa de escrita local

Escolha uma das tres, em ordem de preferencia:

**A. Use o WSL2.** O caminho mais limpo: dentro do Ubuntu nao existe problema
de winutils, porque la o Hadoop tem os binarios nativos de Linux. O kit
instala o WSL2 quando o perfil pede `container` ou `python`.

```bash
# dentro do WSL
./scripts/setup-python.sh --conjuntos "py-core py-spark"
```

**B. Nao escreva com o Spark.** Em analise de dado que cabe numa maquina,
converta para pandas ou polars e escreva com eles:

```python
df.toPandas().to_parquet("saida.parquet")
```

Para os volumes em que o Spark faz sentido numa maquina so, isso costuma ser
suficiente — e mais rapido.

**C. Instale o winutils conscientemente.** Se escolher este caminho:

1. Pegue a versao que corresponde ao Hadoop empacotado no seu PySpark:
   ```python
   import pyspark
   print(pyspark.__version__)   # ex.: 3.5.x -> Hadoop 3.3
   ```
2. Baixe de uma fonte que voce avaliou, confira o hash publicado, e
   coloque em `C:\hadoop\bin\`.
3. Defina as variaveis:
   ```powershell
   [Environment]::SetEnvironmentVariable('HADOOP_HOME', 'C:\hadoop', 'User')
   [Environment]::SetEnvironmentVariable('Path', "$env:Path;C:\hadoop\bin", 'User')
   ```
4. Reabra o terminal e confira com `.\scripts\setup-python.ps1 -Verificar`.

## Conferir tudo

```powershell
.\scripts\setup-python.ps1 -Verificar
```

O diagnostico sobe uma sessao Spark de verdade e conta linhas — importar o
`pyspark` sem erro nao prova que a JVM funciona.

## Configuracao util para maquina unica

```python
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("local")
    .master("local[*]")                        # todos os nucleos
    .config("spark.driver.memory", "8g")       # ajuste a sua RAM
    .config("spark.sql.shuffle.partitions", "8")   # o padrao 200 e absurdo aqui
    .getOrCreate()
)
```

`spark.sql.shuffle.partitions` vale 200 por padrao, numero pensado para
cluster. Numa maquina so, isso cria 200 tarefas minusculas e o tempo vai todo
em coordenacao. Deixe perto do numero de nucleos.
