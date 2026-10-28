-- =====================================================================
-- 06 - VALIDAÇÃO DE QUALIDADE
-- =====================================================================
-- Objetivo
--   Conferir as três camadas depois da carga e FALHAR o job se algo
--   estiver errado, para o dashboard não ser atualizado com dado ruim
--   (o job só atualiza o dashboard se esta etapa passar).
--
-- Como funciona
--   1. Cada regra é calculada e gravada em gold.log_validacao
--      (histórico de todas as execuções, aprovadas ou não).
--   2. Se alguma regra da execução atual falhar, raise_error() interrompe
--      o script com a lista do que falhou -> a tarefa e o job falham e o
--      e-mail de falha é enviado.
--
-- Se a validação falhar
--   As tabelas já foram recriadas com o dado novo. Para voltar à versão
--   anterior, use o histórico do Delta, por exemplo:
--     DESCRIBE HISTORY comercio_aco_mineracao.gold.fato_cfem;
--     RESTORE TABLE comercio_aco_mineracao.gold.fato_cfem TO VERSION AS OF <versão>;
-- =====================================================================

USE CATALOG comercio_aco_mineracao;

CREATE TABLE IF NOT EXISTS gold.log_validacao (
  data_execucao     TIMESTAMP COMMENT 'Momento da validação',
  camada            STRING    COMMENT 'bronze, silver ou gold',
  regra             STRING    COMMENT 'O que foi verificado',
  valor_encontrado  DOUBLE    COMMENT 'Valor medido',
  esperado          STRING    COMMENT 'Valor ou faixa aceitos',
  aprovado          BOOLEAN   COMMENT 'true = regra atendida'
)
COMMENT 'Histórico das validações de qualidade do pipeline';

-- Calcula todas as regras e grava no histórico ------------------------------
INSERT INTO gold.log_validacao
WITH
-- última contagem aprovada de cada tabela bronze (para detectar queda de volume)
anterior AS (
  SELECT regra, MAX_BY(valor_encontrado, data_execucao) AS valor
  FROM gold.log_validacao
  WHERE aprovado AND regra LIKE 'Linhas em bronze.%'
  GROUP BY regra
),
contagem_bronze AS (
  SELECT 'Linhas em bronze.comex_exportacoes' AS regra, COUNT(*) AS valor FROM bronze.comex_exportacoes
  UNION ALL
  SELECT 'Linhas em bronze.comex_pais', COUNT(*) FROM bronze.comex_pais
  UNION ALL
  SELECT 'Linhas em bronze.cfem_arrecadacao', COUNT(*) FROM bronze.cfem_arrecadacao
),
regras AS (
  -- BRONZE: não pode estar vazia nem cair mais de 10% em relação à última validação aprovada
  SELECT 'bronze' AS camada, b.regra, b.valor,
         CASE WHEN a.valor IS NULL THEN '> 0'
              ELSE CONCAT('>= ', CAST(FLOOR(a.valor * 0.9) AS STRING), ' (90% da última carga aprovada)') END AS esperado,
         b.valor > 0 AND (a.valor IS NULL OR b.valor >= a.valor * 0.9) AS aprovado
  FROM contagem_bronze b
  LEFT JOIN anterior a ON a.regra = b.regra

  -- SILVER: exportações
  UNION ALL
  SELECT 'silver', 'Exportações com ano, mês, NCM, país ou valor nulo',
         COUNT_IF(ano IS NULL OR mes IS NULL OR ncm IS NULL OR co_pais IS NULL OR valor_fob_usd IS NULL), '0', NULL
  FROM silver.comex_exportacoes
  UNION ALL
  SELECT 'silver', 'Exportações com valor ou peso negativo',
         COUNT_IF(valor_fob_usd < 0 OR kg_liquido < 0), '0', NULL
  FROM silver.comex_exportacoes
  UNION ALL
  SELECT 'silver', 'Exportações fora dos NCMs do projeto (2601, 72, 73)',
         COUNT_IF(NOT (ncm LIKE '2601%' OR LEFT(ncm, 2) IN ('72', '73'))), '0', NULL
  FROM silver.comex_exportacoes

  -- SILVER: CFEM
  UNION ALL
  SELECT 'silver', 'CFEM com ano, mês, município, substância ou valor nulo',
         COUNT_IF(ano IS NULL OR mes IS NULL OR codigo_municipio IS NULL OR substancia IS NULL OR valor_recolhido_brl IS NULL), '0', NULL
  FROM silver.cfem_arrecadacao
  UNION ALL
  SELECT 'silver', 'CFEM com valor negativo', COUNT_IF(valor_recolhido_brl < 0), '0', NULL
  FROM silver.cfem_arrecadacao
  UNION ALL
  SELECT 'silver', 'CFEM com linhas duplicadas',
         COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM silver.cfem_arrecadacao)), '0', NULL
  FROM silver.cfem_arrecadacao

  -- GOLD: período 2003-2023 completo nos dois fatos
  UNION ALL
  SELECT 'gold', 'Anos distintos em fato_exportacao (2003-2023)', COUNT(DISTINCT t.ano), '21', NULL
  FROM gold.fato_exportacao f JOIN gold.dim_tempo t USING (sk_tempo)
  UNION ALL
  SELECT 'gold', 'Anos distintos em fato_cfem (2003-2023)', COUNT(DISTINCT t.ano), '21', NULL
  FROM gold.fato_cfem f JOIN gold.dim_tempo t USING (sk_tempo)
  UNION ALL
  SELECT 'gold', 'Anos fora de 2003-2023 na dim_tempo', COUNT_IF(ano NOT BETWEEN 2003 AND 2023), '0', NULL
  FROM gold.dim_tempo

  -- GOLD: chaves sem dimensão
  UNION ALL
  SELECT 'gold', 'fato_exportacao sem país na dim_pais', COUNT(*), '0', NULL
  FROM gold.fato_exportacao f LEFT ANTI JOIN gold.dim_pais d USING (co_pais)
  UNION ALL
  SELECT 'gold', 'fato_exportacao sem produto na dim_produto', COUNT(*), '0', NULL
  FROM gold.fato_exportacao f LEFT ANTI JOIN gold.dim_produto d USING (ncm)
  UNION ALL
  SELECT 'gold', 'fato_cfem sem município na dim_municipio', COUNT(*), '0', NULL
  FROM gold.fato_cfem f LEFT ANTI JOIN gold.dim_municipio d USING (codigo_municipio)

  -- GOLD: indicadores do período comum
  UNION ALL
  SELECT 'gold', 'Anos em indicadores_periodo_comum', COUNT(*), '21', NULL
  FROM gold.indicadores_periodo_comum
  UNION ALL
  SELECT 'gold', 'Anos sem CFEM do ferro ou sem preço do minério',
         COUNT_IF(COALESCE(cfem_ferro_brl, 0) <= 0 OR preco_minerio_usd_t IS NULL), '0', NULL
  FROM gold.indicadores_periodo_comum

  -- GOLD x SILVER: o total da Gold precisa bater com a Silver no mesmo período
  UNION ALL
  SELECT 'gold', 'Diferença de valor FOB entre gold e silver (US$)',
         ABS((SELECT SUM(valor_fob_usd) FROM gold.fato_exportacao)
           - (SELECT SUM(valor_fob_usd) FROM silver.comex_exportacoes WHERE ano BETWEEN 2003 AND 2023)), '0', NULL
  UNION ALL
  SELECT 'gold', 'Diferença de CFEM entre gold e silver (R$)',
         ROUND(ABS((SELECT SUM(valor_recolhido_brl) FROM gold.fato_cfem)
           - (SELECT SUM(valor_recolhido_brl) FROM silver.cfem_arrecadacao WHERE ano BETWEEN 2003 AND 2023)), 2), '0', NULL
)
SELECT
  current_timestamp()                       AS data_execucao,
  camada,
  regra,
  CAST(valor AS DOUBLE)                     AS valor_encontrado,
  esperado,
  -- regras sem aprovação própria: aprovadas quando o valor é igual ao esperado
  COALESCE(aprovado, CAST(valor AS DOUBLE) = CAST(esperado AS DOUBLE)) AS aprovado
FROM regras;

-- Resultado desta execução --------------------------------------------------------
SELECT camada, regra, valor_encontrado, esperado, aprovado
FROM gold.log_validacao
WHERE data_execucao = (SELECT MAX(data_execucao) FROM gold.log_validacao)
ORDER BY aprovado, camada, regra;

-- Falha a tarefa se alguma regra não passou ------------------------------------------
-- O CASE garante que raise_error só é chamado quando existe falha.
SELECT CASE
         WHEN qtd_falhas > 0 THEN raise_error(CONCAT(
           'Validação de qualidade falhou em ', CAST(qtd_falhas AS STRING), ' regra(s): ', detalhes))
         ELSE 'Validação aprovada: todas as regras passaram'
       END AS resultado
FROM (
  SELECT COUNT(*) AS qtd_falhas,
         ARRAY_JOIN(COLLECT_LIST(CONCAT('[', camada, '] ', regra,
                                        ' = ', CAST(valor_encontrado AS STRING),
                                        ' (esperado ', esperado, ')')), '; ') AS detalhes
  FROM gold.log_validacao
  WHERE data_execucao = (SELECT MAX(data_execucao) FROM gold.log_validacao)
    AND NOT aprovado
);
