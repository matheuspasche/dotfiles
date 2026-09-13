# ============================================================================
# verificar.R -- diagnostico do ambiente R
#
# Responde tres perguntas que costumam falhar em silencio depois de formatar:
#   1. o compilador C++ funciona? (Rcpp de verdade, nao so instalado)
#   2. a paralelizacao funciona? (nucleos visiveis e um future executado)
#   3. o BLAS e o de referencia ou um otimizado?
#
# Uso:  Rscript verificar.R
# Sai com status 1 quando algo essencial nao passa.
# ============================================================================

falhou <- FALSE

cabecalho <- function(texto) cat(sprintf("\n== %s ==\n", texto))
ok        <- function(texto) cat(sprintf("  ok    %s\n", texto))
falha     <- function(texto) { cat(sprintf("  FALHA %s\n", texto)); falhou <<- TRUE }
aviso     <- function(texto) cat(sprintf("  aviso %s\n", texto))

# --- ambiente ---------------------------------------------------------------
cabecalho("Ambiente")
cat(sprintf("  R           %s\n", getRversion()))
cat(sprintf("  plataforma  %s\n", R.version$platform))
cat(sprintf("  biblioteca  %s\n", .libPaths()[1]))

# A biblioteca do usuario precisa existir e ser gravavel, senao todo
# install.packages cai para a biblioteca do sistema e pede sudo.
if (file.access(.libPaths()[1], mode = 2) == 0) {
  ok("biblioteca de pacotes gravavel")
} else {
  falha(sprintf("biblioteca nao gravavel: %s", .libPaths()[1]))
}

# --- toolchain de compilacao ------------------------------------------------
cabecalho("Compilacao (Rcpp)")

make <- Sys.which("make")
if (nzchar(make)) {
  ok(sprintf("make encontrado: %s", make))
} else {
  falha("make nao esta no PATH")
  if (.Platform$OS.type == "windows") {
    cat("        No Windows isso quase sempre e o Rtools fora do PATH.\n")
    cat("        Instale com: winget install RProject.Rtools\n")
  } else {
    cat("        Instale o toolchain: dnf install gcc-c++ | apt install build-essential\n")
  }
}

if (requireNamespace("pkgbuild", quietly = TRUE)) {
  if (isTRUE(pkgbuild::has_build_tools(debug = FALSE))) {
    ok("pkgbuild reconhece o toolchain")
  } else {
    falha("pkgbuild nao encontrou ferramentas de compilacao")
  }
} else {
  aviso("pkgbuild nao instalado (conjunto r-rcpp) -- pulando esta checagem")
}

# O teste real: compilar C++ na hora. Instalar o Rcpp nao prova nada; muita
# instalacao quebrada so aparece quando alguem tenta compilar de fato.
if (requireNamespace("Rcpp", quietly = TRUE)) {
  resultado <- tryCatch({
    Rcpp::cppFunction("double somaQuadrados(int n) {
      double total = 0;
      for (int i = 1; i <= n; i++) total += (double)i * i;
      return total;
    }")
    esperado <- sum((1:100)^2)
    obtido <- somaQuadrados(100L)
    isTRUE(all.equal(esperado, obtido))
  }, error = function(e) {
    cat(sprintf("        %s\n", conditionMessage(e)))
    FALSE
  })
  if (isTRUE(resultado)) {
    ok("Rcpp compilou e executou C++ corretamente")
  } else {
    falha("Rcpp nao conseguiu compilar")
  }
} else {
  aviso("Rcpp nao instalado (conjunto r-rcpp) -- pulando o teste de compilacao")
}

# --- paralelizacao ----------------------------------------------------------
cabecalho("Paralelizacao")

cat(sprintf("  detectCores fisicos  %s\n", parallel::detectCores(logical = FALSE)))
cat(sprintf("  detectCores logicos  %s\n", parallel::detectCores(logical = TRUE)))

if (requireNamespace("parallelly", quietly = TRUE)) {
  disponiveis <- parallelly::availableCores()
  cat(sprintf("  availableCores       %s\n", disponiveis))
  # availableCores respeita limite de container e de cgroup; detectCores nao.
  # Num container com limite de CPU, so o primeiro numero e confiavel.
  if (disponiveis > 1) {
    ok(sprintf("%d nucleos disponiveis para o R", disponiveis))
  } else {
    aviso("apenas 1 nucleo disponivel -- paralelizacao nao vai ajudar")
  }
} else {
  aviso("parallelly nao instalado (conjunto r-paralelo)")
}

if (requireNamespace("future", quietly = TRUE)) {
  resultado <- tryCatch({
    # multisession funciona nos tres sistemas. multicore seria mais rapido no
    # Linux, mas nao existe no Windows e e instavel dentro do RStudio.
    future::plan(future::multisession, workers = 2)
    on.exit(future::plan(future::sequential), add = TRUE)
    f <- future::future({ Sys.getpid() })
    pid <- future::value(f)
    pid != Sys.getpid()
  }, error = function(e) {
    cat(sprintf("        %s\n", conditionMessage(e)))
    FALSE
  })
  if (isTRUE(resultado)) {
    ok("future executou em processo separado")
  } else {
    falha("future nao conseguiu paralelizar")
  }
} else {
  aviso("future nao instalado (conjunto r-paralelo)")
}

# --- BLAS -------------------------------------------------------------------
cabecalho("Algebra linear (BLAS)")

blas <- tryCatch(sessionInfo()$BLAS, error = function(e) NULL)
if (is.null(blas) || !nzchar(blas)) {
  aviso("BLAS nao identificado")
} else {
  cat(sprintf("  %s\n", blas))
  # O BLAS de referencia do R e correto, mas varias vezes mais lento que
  # OpenBLAS em multiplicacao de matriz -- o que aparece em qualquer modelo.
  if (grepl("openblas|mkl|accelerate|atlas", blas, ignore.case = TRUE)) {
    ok("BLAS otimizado em uso")
  } else {
    aviso("BLAS de referencia (nao otimizado)")
    if (.Platform$OS.type != "windows") {
      cat("        Fedora:  sudo dnf install openblas-threads\n")
      cat("        Ubuntu:  sudo apt install libopenblas-dev\n")
    }
  }
}

# Uma multiplicacao pequena, so para confirmar que o BLAS esta funcional.
tempo <- tryCatch({
  m <- matrix(runif(600 * 600), 600)
  system.time(m %*% m)[["elapsed"]]
}, error = function(e) NA_real_)

if (!is.na(tempo)) {
  cat(sprintf("  multiplicacao 600x600: %.2fs\n", tempo))
}

# --- renderizacao (Quarto, pandoc, LaTeX) -----------------------------------
# Checagem de ponta a ponta em vez de "o binario existe": o que quebra aqui
# nao e a ausencia do Quarto, e um .sty faltando no meio do LaTeX -- coisa
# que so aparece renderizando de verdade. O documento abaixo usa chunk de R,
# grafico, tabela e acentuacao, que e onde os problemas moram.
cat("\n== Renderizacao (HTML e PDF) ==\n")

quarto_bin <- Sys.which("quarto")
if (!nzchar(quarto_bin)) {
  quarto_bin <- path.expand("~/.local/bin/quarto")
  if (!file.exists(quarto_bin)) quarto_bin <- ""
}

if (!nzchar(quarto_bin)) {
  aviso("Quarto nao encontrado -- .qmd nao renderiza")
  cat("        rode: ./scripts/setup-linux.sh --grupo r\n")
} else {
  ok(sprintf("Quarto: %s", system2(quarto_bin, "--version", stdout = TRUE)[1]))

  pandoc <- Sys.which("pandoc")
  if (nzchar(pandoc)) {
    ok(sprintf("pandoc: %s", pandoc))
  } else {
    aviso("pandoc fora do PATH -- .Rmd em PDF vai falhar")
  }

  dir_teste <- file.path(tempdir(), "verificar-render")
  dir.create(dir_teste, showWarnings = FALSE, recursive = TRUE)
  qmd <- file.path(dir_teste, "teste.qmd")

  writeLines(c(
    "---", "title: \"Verificacao\"", "lang: pt",
    "format:", "  html: default", "  pdf: default", "---", "",
    "```{r}", "#| warning: false", "#| fig-cap: \"grafico\"",
    "plot(mtcars$wt, mtcars$mpg)", "```", "",
    "```{r}", "knitr::kable(head(mtcars[, 1:3]))", "```", "",
    "Acentuacao: acao, coracao. Matematica: $\\frac{1}{3}$."
  ), qmd)

  for (formato in c("html", "pdf")) {
    saida <- sub("qmd$", formato, qmd)
    # A primeira renderizacao em PDF pode baixar pacotes LaTeX sob demanda
    # (e para isso que o TinyTeX esta ali), entao demora mais que o resto.
    res <- tryCatch(
      system2(quarto_bin, c("render", shQuote(qmd), "--to", formato),
              stdout = FALSE, stderr = FALSE),
      error = function(e) 1L
    )
    if (identical(as.integer(res), 0L) && file.exists(saida)) {
      ok(sprintf("%s renderizado (%.0f KB)", toupper(formato),
                 file.size(saida) / 1024))
    } else {
      aviso(sprintf("falhou ao renderizar %s", toupper(formato)))
      if (formato == "pdf") {
        cat("        LaTeX incompleto? rode: quarto install tinytex\n")
      }
    }
  }
}

# --- resultado --------------------------------------------------------------
cat("\n")
if (falhou) {
  cat("== alguma checagem essencial falhou ==\n")
  quit(status = 1)
}
cat("== ambiente R funcional ==\n")
quit(status = 0)
