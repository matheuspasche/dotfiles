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

# --- o que falta ------------------------------------------------------------
instalados <- rownames(installed.packages())
faltando <- setdiff(args, instalados)

if (length(faltando) == 0) {
  cat("==> todos os pacotes ja estao instalados\n")
  quit(status = 0)
}

cat(sprintf("==> %d de %d pacotes a instalar: %s\n",
            length(faltando), length(args), paste(faltando, collapse = " ")))

# --- instalacao -------------------------------------------------------------
# Um pacote que falha nao deve derrubar os outros: o tryCatch por pacote troca
# "nada instalou" por "faltou um", que e muito mais facil de resolver depois.
falhas <- character(0)

for (pacote in faltando) {
  cat(sprintf("\n--- %s ---\n", pacote))
  resultado <- tryCatch({
    install.packages(pacote, quiet = FALSE)
    # install.packages nao devolve erro quando falha; a unica verificacao
    # confiavel e perguntar depois se o pacote pode ser carregado.
    if (!requireNamespace(pacote, quietly = TRUE)) stop("nao carregou apos instalar")
    TRUE
  }, error = function(e) {
    cat(sprintf("erro em %s: %s\n", pacote, conditionMessage(e)))
    FALSE
  }, warning = function(w) {
    cat(sprintf("aviso em %s: %s\n", pacote, conditionMessage(w)))
    requireNamespace(pacote, quietly = TRUE)
  })
  if (!isTRUE(resultado)) falhas <- c(falhas, pacote)
}

# --- resumo -----------------------------------------------------------------
cat("\n")
if (length(falhas) > 0) {
  cat(sprintf("==> %d pacote(s) falharam: %s\n",
              length(falhas), paste(falhas, collapse = " ")))
  cat("    Causa comum no Linux: falta a biblioteca de desenvolvimento do sistema.\n")
  cat("    Ex.: curl precisa de libcurl-devel, xml2 precisa de libxml2-devel.\n")
  quit(status = 1)
}

cat(sprintf("==> %d pacote(s) instalados com sucesso\n", length(faltando)))
quit(status = 0)
