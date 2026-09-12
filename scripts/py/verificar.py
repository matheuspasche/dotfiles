"""Diagnostico do ambiente Python.

Responde o que costuma falhar em silencio depois de formatar:
  1. o interpretador e o esperado, e o ambiente virtual esta ativo?
  2. as bibliotecas principais importam?
  3. o PySpark acha o Java e consegue subir uma sessao de verdade?
  4. o kernel do Jupyter esta registrado para o VS Code enxergar?

Uso:  python verificar.py
Sai com status 1 quando algo essencial nao passa.
"""

from __future__ import annotations

import importlib
import os
import shutil
import subprocess
import sys

falhou = False


def cabecalho(texto: str) -> None:
    print(f"\n== {texto} ==")


def ok(texto: str) -> None:
    print(f"  ok    {texto}")


def falha(texto: str) -> None:
    global falhou
    falhou = True
    print(f"  FALHA {texto}")


def aviso(texto: str) -> None:
    print(f"  aviso {texto}")


# --- interpretador ----------------------------------------------------------
cabecalho("Interpretador")
print(f"  versao      {sys.version.split()[0]}")
print(f"  executavel  {sys.executable}")

# sys.prefix != sys.base_prefix e o teste confiavel de "estou num venv".
# VIRTUAL_ENV sozinho mente quando alguem exporta a variavel na mao.
em_venv = sys.prefix != sys.base_prefix
if em_venv:
    ok(f"ambiente virtual ativo: {sys.prefix}")
else:
    aviso("rodando no Python do sistema, fora de ambiente virtual")

if sys.version_info < (3, 10):
    falha(f"Python {sys.version_info.major}.{sys.version_info.minor} e antigo demais para varias bibliotecas")
else:
    ok(f"Python {sys.version_info.major}.{sys.version_info.minor}")


# --- bibliotecas ------------------------------------------------------------
cabecalho("Bibliotecas")

# Nome do modulo difere do nome do pacote em varios casos (scikit-learn ->
# sklearn), por isso o mapeamento explicito.
BIBLIOTECAS = [
    ("numpy", "numpy"),
    ("pandas", "pandas"),
    ("polars", "polars"),
    ("pyarrow", "pyarrow"),
    ("duckdb", "duckdb"),
    ("matplotlib", "matplotlib"),
    ("seaborn", "seaborn"),
    ("sklearn", "scikit-learn"),
    ("scipy", "scipy"),
]

presentes = 0
for modulo, pacote in BIBLIOTECAS:
    try:
        m = importlib.import_module(modulo)
        versao = getattr(m, "__version__", "?")
        print(f"  ok    {pacote:<14} {versao}")
        presentes += 1
    except ImportError:
        print(f"  --    {pacote:<14} nao instalado")

if presentes == 0:
    aviso("nenhuma biblioteca do conjunto py-core encontrada")


# --- PySpark ----------------------------------------------------------------
cabecalho("PySpark")

try:
    import pyspark  # noqa: F401

    ok(f"pyspark {pyspark.__version__}")

    java_home = os.environ.get("JAVA_HOME", "")
    java_exe = shutil.which("java")

    if java_home and os.path.isdir(java_home):
        ok(f"JAVA_HOME: {java_home}")
    elif java_exe:
        aviso(f"JAVA_HOME nao definido, mas java esta no PATH: {java_exe}")
    else:
        falha("Java nao encontrado -- o Spark nao sobe sem JDK 17")
        print("        Instale com: dnf install java-17-openjdk-devel")
        print("                     winget install EclipseAdoptium.Temurin.17.JDK")

    if java_exe or java_home:
        # A versao importa: Spark 3.x nao roda em JDK 21+ sem flags extras.
        try:
            saida = subprocess.run(
                ["java", "-version"], capture_output=True, text=True, timeout=30
            )
            linha = (saida.stderr or saida.stdout).splitlines()
            if linha:
                print(f"  {linha[0].strip()}")
        except Exception:
            pass

    # No Windows, o Spark precisa de winutils.exe para o Hadoop achar o
    # sistema de arquivos local. Sem isso a sessao sobe e falha ao escrever.
    if sys.platform == "win32":
        hadoop_home = os.environ.get("HADOOP_HOME", "")
        if hadoop_home and os.path.isfile(os.path.join(hadoop_home, "bin", "winutils.exe")):
            ok(f"HADOOP_HOME com winutils.exe: {hadoop_home}")
        else:
            aviso("HADOOP_HOME/winutils.exe ausente")
            print("        Leitura funciona; escrita em disco local costuma falhar.")
            print("        Veja docs/spark-no-windows.md.")

    # O teste real: subir uma sessao e contar linhas. Importar o pyspark nao
    # prova nada -- a JVM so e exercitada aqui.
    if java_exe or java_home:
        try:
            from pyspark.sql import SparkSession

            spark = (
                SparkSession.builder.appName("verificar")
                .master("local[1]")
                .config("spark.ui.enabled", "false")
                .config("spark.driver.memory", "1g")
                .getOrCreate()
            )
            spark.sparkContext.setLogLevel("ERROR")
            n = spark.createDataFrame([(1,), (2,), (3,)], ["x"]).count()
            spark.stop()
            if n == 3:
                ok("sessao Spark subiu e executou uma query")
            else:
                falha(f"sessao Spark subiu mas retornou {n} em vez de 3")
        except Exception as e:
            falha(f"nao consegui subir a sessao Spark: {type(e).__name__}")
            print(f"        {str(e).splitlines()[0][:160]}")

except ImportError:
    aviso("pyspark nao instalado (conjunto py-spark)")


# --- Jupyter ----------------------------------------------------------------
cabecalho("Jupyter")

try:
    import ipykernel  # noqa: F401

    ok(f"ipykernel {ipykernel.__version__}")

    try:
        from jupyter_client.kernelspec import KernelSpecManager

        kernels = KernelSpecManager().find_kernel_specs()
        if kernels:
            ok(f"{len(kernels)} kernel(s) registrado(s)")
            for nome in sorted(kernels):
                print(f"        {nome}")
        else:
            # Sem kernel registrado, o VS Code nao lista o ambiente no seletor
            # de notebook -- e o sintoma classico de "o VS Code nao ve meu venv".
            falha("nenhum kernel registrado -- o VS Code nao vai listar este ambiente")
            print("        Registre com: python -m ipykernel install --user --name <nome>")
    except ImportError:
        aviso("jupyter_client indisponivel -- nao da para listar kernels")

except ImportError:
    aviso("ipykernel nao instalado (conjunto py-notebook)")


# --- resultado --------------------------------------------------------------
print()
if falhou:
    print("== alguma checagem essencial falhou ==")
    sys.exit(1)
print("== ambiente Python funcional ==")
sys.exit(0)
