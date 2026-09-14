# ============================================================================
# instalar.R -- instala pacotes R, em paralelo, pulando o que ja existe
#
# Chamado pelos wrappers setup-r.sh e setup-r.ps1. Implementacao unica para
# os tres sistemas: o que muda entre eles (caminho, toolchain) fica nos
# wrappers; a logica de instalacao fica aqui.
#
# Uso:  Rscript instalar.R <pacote> [<pacote> ...]
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("nada a instalar\n")
  quit(status = 0)
}

# --- espelho ----------------------------------------------------------------
# Sem repos definido, install.packages abre um menu interativo e trava um
# script desatendido. O espelho da RStudio/Posit e global e rapido.
repositorio <- getOption("repos")
if (is.null(repositorio[["CRAN"]]) || repositorio[["CRAN"]] == "@CRAN@") {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

# --- paralelismo ------------------------------------------------------------
# Ncpus acelera muito a instalacao: cada pacote compila num processo. Deixa um
# nucleo livre para a maquina continuar usavel durante os 20 minutos de build.
nucleos <- tryCatch(
  max(1L, parallel::detectCores(logical = FALSE) - 1L),
  error = function(e) 2L
)
options(Ncpus = nucleos)
cat(sprintf("==> compilando com %d nucleo(s)\n", nucleos))

# --- libv8 estatico ---------------------------------------------------------
# O pacote V8 (dependencia do gt, e portanto do gtsummary) procura a libv8 do
# sistema e para com "fatal error: v8.h". No Fedora nao existe um "v8-devel"
# para instalar: os nomes vem versionados (v8-13.6-devel), e o numero muda a
# cada release -- o mesmo tipo de alvo movel que ja quebrou o JDK aqui.
#
# Esta variavel e a saida recomendada pelo proprio pacote: ele baixa um build
# estatico da libv8 e compila contra ele, sem root e sem nome de versao.
if (.Platform$OS.type == "unix") {
  Sys.setenv(DOWNLOAD_STATIC_LIBV8 = "1")
}

# --- o que falta ------------------------------------------------------------
instalados <- rownames(installed.packages())
faltando <- setdiff(args, instalados)

if (length(faltando) == 0) {
  cat("==> todos os pacotes ja estao instalados\n")
  quit(status = 0)
}

# Pacote arquivado no CRAN falha com "package 'x' is not available for this
# version of R" -- mensagem que costuma ser lida como erro de compilacao, e
# manda o usuario procurar biblioteca de sistema que nao tem nada a ver. Vale
# mais dizer na cara, e antes de comecar, que aquele nome nao existe mais.
indisponiveis <- tryCatch({
  setdiff(faltando, rownames(available.packages()))
}, error = function(e) character(0))

if (length(indisponiveis) > 0) {
  cat(sprintf(paste0("==> %d pacote(s) nao existem no CRAN para o R %s",
                     " (arquivados ou removidos): %s\n"),
              length(indisponiveis), getRversion(),
              paste(indisponiveis, collapse = " ")))
  cat("    Nao adianta insistir: tire do bibliotecas.yaml ou troque por outro.\n")
  faltando <- setdiff(faltando, indisponiveis)
}

if (length(faltando) == 0) {
  quit(status = 1)
}

cat(sprintf("==> %d de %d pacotes a instalar: %s\n",
            length(faltando), length(args), paste(faltando, collapse = " ")))

# --- instalacao -------------------------------------------------------------
# Um pacote que falha nao deve derrubar os outros: o tryCatch por pacote troca
# "nada instalou" por "faltou um", que e muito mais facil de resolver depois.
#
# A verificacao NAO usa requireNamespace(): isso carregaria a DLL do pacote
# nesta mesma sessao de R, que fica viva ate o fim do loop inteiro. No
# Windows uma DLL carregada nao pode ser substituida -- e como varios
# pacotes da lista dependem de glue/Rcpp, o primeiro requireNamespace(glue)
# trava a versao carregada, e todo pacote seguinte que pede reinstalar/
# atualizar glue ou Rcpp falha com "nao foi possivel remover a instalacao
# previa", derrubando em cascata tudo que depende deles (aconteceu de
# verdade: 16 pacotes por causa so de glue e Rcpp). installed.packages() so
# le o cadastro em disco, sem carregar nada -- verifica que a instalacao
# aconteceu sem esse efeito colateral.
esta_instalado <- function(pacote) {
  pacote %in% rownames(installed.packages(lib.loc = .libPaths()[1]))
}

falhas <- character(0)

for (pacote in faltando) {
  cat(sprintf("\n--- %s ---\n", pacote))
  resultado <- tryCatch({
    install.packages(pacote, quiet = FALSE)
    if (!esta_instalado(pacote)) stop("nao apareceu no cadastro de pacotes apos instalar")
    TRUE
  }, error = function(e) {
    cat(sprintf("erro em %s: %s\n", pacote, conditionMessage(e)))
    FALSE
  }, warning = function(w) {
    cat(sprintf("aviso em %s: %s\n", pacote, conditionMessage(w)))
    esta_instalado(pacote)
  })
  if (!isTRUE(resultado)) falhas <- c(falhas, pacote)
}

# --- resumo -----------------------------------------------------------------
cat("\n")
if (length(falhas) > 0 || length(indisponiveis) > 0) {
  if (length(falhas) > 0) {
    cat(sprintf("==> %d pacote(s) falharam ao compilar: %s\n",
                length(falhas), paste(falhas, collapse = " ")))
    cat("    Causa comum no Linux: falta a biblioteca de desenvolvimento do\n")
    cat("    sistema. Procure no log a linha 'fatal error: <arquivo>.h' -- o\n")
    cat("    nome do header diz qual -devel falta (uv.h -> libuv-devel).\n")
    cat("    Declare a biblioteca no bibliotecas.yaml, em sistema_dnf/apt.\n")
  }
  if (length(indisponiveis) > 0) {
    cat(sprintf("==> %d pacote(s) nao existem mais no CRAN: %s\n",
                length(indisponiveis), paste(indisponiveis, collapse = " ")))
  }
  quit(status = 1)
}

cat(sprintf("==> %d pacote(s) instalados com sucesso\n", length(faltando)))
quit(status = 0)
