@{
    # ------------------------------------------------------------------------
    # Configuracao do PSScriptAnalyzer para este repositorio.
    #
    # Write-Host e proposital: estes sao scripts interativos de instalacao e a
    # cor no console faz parte da usabilidade. Nao ha consumidor de pipeline.
    # ------------------------------------------------------------------------
    ExcludeRules = @(
        # Write-Host e proposital: script interativo, cor faz parte da leitura.
        'PSAvoidUsingWriteHost',

        # Get-CaminhosExistentes devolve uma lista; o plural descreve melhor
        # o retorno do que o singular exigido pela regra.
        'PSUseSingularNouns',

        # Falso positivo em cofre.ps1: os switches -Fechar/-Abrir/-Listar sao
        # lidos no bloco de fluxo no fim do arquivo, fora de qualquer funcao.
        'PSReviewUnusedParameter',

        # Invoke-Expression aparece uma vez, no instalador oficial do scoop
        # (get.scoop.sh). Nao ha alternativa suportada.
        'PSAvoidUsingInvokeExpression'
    )
}
