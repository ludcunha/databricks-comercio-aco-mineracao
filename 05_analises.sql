-- =====================================================================
-- 05 - ANÁLISES DE NEGÓCIO
-- =====================================================================
-- Responde às perguntas do projeto usando o modelo Gold
-- (joins, agregações, CTEs e funções janela).
-- A Gold já está recortada no período 2003-2023 (ver 04_modelagem_gold.sql).
-- =====================================================================

USE CATALOG comercio_aco_mineracao;

-- ---------------------------------------------------------------------
-- 1. Quais países mais compram minério de ferro e aço do Brasil?
--    Top 5 países por categoria, com participação %.
--    Usa os últimos 5 anos (2019-2023) para mostrar o cenário atual.
-- ---------------------------------------------------------------------
WITH por_pais AS (
  SELECT
    p.categoria_produto,
    d.nome_pais,
    SUM(f.valor_fob_usd) AS valor_fob_usd
  FROM gold.fato_exportacao f
  JOIN gold.dim_tempo   t ON f.sk_tempo = t.sk_tempo
  JOIN gold.dim_pais    d ON f.co_pais  = d.co_pais
  JOIN gold.dim_produto p ON f.ncm      = p.ncm
  WHERE t.ano BETWEEN 2019 AND 2023
  GROUP BY ALL
),
ranking AS (
  SELECT
    *,
    RANK() OVER (PARTITION BY categoria_produto ORDER BY valor_fob_usd DESC)          AS posicao,
    valor_fob_usd / SUM(valor_fob_usd) OVER (PARTITION BY categoria_produto) * 100     AS participacao_pct
  FROM por_pais
)
SELECT
  categoria_produto,
  posicao,
  nome_pais,
  ROUND(valor_fob_usd / 1e9, 2) AS fob_usd_bilhoes,
  ROUND(participacao_pct, 1)    AS participacao_pct
FROM ranking
WHERE posicao <= 5
ORDER BY categoria_produto, posicao;

-- ---------------------------------------------------------------------
-- 2. Como o preço médio por tonelada (US$/t) evoluiu ao longo do tempo?
--    Preço = valor FOB / toneladas, com variação % sobre o ano anterior.
-- ---------------------------------------------------------------------
WITH preco_anual AS (
  SELECT
    t.ano,
    p.categoria_produto,
    SUM(f.valor_fob_usd)                         AS valor_fob_usd,
    SUM(f.toneladas)                             AS toneladas,
    SUM(f.valor_fob_usd) / NULLIF(SUM(f.toneladas), 0) AS preco_usd_t
  FROM gold.fato_exportacao f
  JOIN gold.dim_tempo   t ON f.sk_tempo = t.sk_tempo
  JOIN gold.dim_produto p ON f.ncm      = p.ncm
  GROUP BY ALL
)
SELECT
  ano,
  categoria_produto,
  ROUND(toneladas / 1e6, 1)  AS milhoes_toneladas,
  ROUND(preco_usd_t, 2)      AS preco_usd_t,
  ROUND((preco_usd_t / LAG(preco_usd_t) OVER (PARTITION BY categoria_produto ORDER BY ano) - 1) * 100, 1)
                             AS variacao_preco_pct
FROM preco_anual
ORDER BY categoria_produto, ano;

-- ---------------------------------------------------------------------
-- 3. Quais estados lideram as exportações?
--    Ranking de UFs por ano (top 5) e participação no total do ano.
--    Obs.: a balança comercial por UF não é calculada porque o dataset
--    utilizado contém apenas exportações.
-- ---------------------------------------------------------------------
WITH uf_ano AS (
  SELECT t.ano, f.uf, SUM(f.valor_fob_usd) AS valor_fob_usd
  FROM gold.fato_exportacao f
  JOIN gold.dim_tempo t ON f.sk_tempo = t.sk_tempo
  GROUP BY ALL
)
SELECT
  ano,
  posicao,
  uf,
  ROUND(valor_fob_usd / 1e9, 2)  AS fob_usd_bilhoes,
  ROUND(participacao_pct, 1)     AS participacao_pct
FROM (
  SELECT
    *,
    RANK() OVER (PARTITION BY ano ORDER BY valor_fob_usd DESC)          AS posicao,
    valor_fob_usd / SUM(valor_fob_usd) OVER (PARTITION BY ano) * 100     AS participacao_pct
  FROM uf_ano
)
WHERE posicao <= 5 AND ano >= 2019
ORDER BY ano, posicao;

-- ---------------------------------------------------------------------
-- 4a. Quais municípios mais arrecadam CFEM? (total 2003-2023, todas as substâncias)
-- ---------------------------------------------------------------------
SELECT
  RANK() OVER (ORDER BY SUM(f.valor_recolhido_brl) DESC)        AS posicao,
  m.municipio,
  m.uf,
  ROUND(SUM(f.valor_recolhido_brl) / 1e9, 2)                     AS cfem_brl_bilhoes,
  ROUND(SUM(CASE WHEN f.eh_minerio_ferro THEN f.valor_recolhido_brl ELSE 0 END)
        / SUM(f.valor_recolhido_brl) * 100, 1)                   AS pct_minerio_ferro
FROM gold.fato_cfem f
JOIN gold.dim_municipio m ON f.codigo_municipio = m.codigo_municipio
GROUP BY m.municipio, m.uf
ORDER BY posicao
LIMIT 10;

-- ---------------------------------------------------------------------
-- 4b. A arrecadação de CFEM do ferro acompanha o preço do minério?
--     Compara, ano a ano (período comum 2003-2023), o preço US$/t do
--     minério exportado com a CFEM do ferro, e calcula a correlação.
--     Usa a tabela gold.indicadores_periodo_comum.
--     Obs.: a CFEM está em R$ nominais e a alíquota do ferro subiu de 2%
--     para 3,5% em 2017 (Lei 13.540/2017), o que também explica o salto
--     da arrecadação a partir de 2018, além de câmbio e volume.
-- ---------------------------------------------------------------------
SELECT
  ano,
  ROUND(preco_minerio_usd_t, 2)       AS preco_minerio_usd_t,
  ROUND(cfem_ferro_brl / 1e9, 2)      AS cfem_ferro_brl_bilhoes,
  ROUND(var_preco_minerio_pct, 1)     AS var_preco_pct,
  ROUND(var_cfem_ferro_pct, 1)        AS var_cfem_ferro_pct,
  ROUND(CORR(preco_minerio_usd_t, cfem_ferro_brl) OVER (), 2) AS correlacao_periodo
FROM gold.indicadores_periodo_comum
ORDER BY ano;
