-- =====================================================================
-- 04 - MODELAGEM GOLD (modelo dimensional)
-- =====================================================================
-- Objetivo
--   Construir um modelo estrela para análise de exportações de minério de
--   ferro/aço e arrecadação de CFEM.
--
--   Dimensões : dim_tempo, dim_pais, dim_produto, dim_municipio
--   Fatos     : fato_exportacao (grão: mês x país x NCM x UF x via)
--               fato_cfem       (grão: mês x município x substância)
--   Analítica : indicadores_periodo_comum (grão: ano)
--   Apoio     : resumo_bases (o que tem em cada base, para o dashboard)
--
-- Período de análise: 2003 a 2023
--   É o período comum às duas bases (Comex vai até 2023; o CFEM de 2002
--   tem um único registro inválido, então a série começa em 2003).
--   O período é definido em UM lugar só: a dim_tempo. Fatos e dimensões
--   são montados com JOIN nela, então tudo na Gold fica em 2003-2023.
--   Bronze e Silver continuam com o histórico completo.
-- =====================================================================

USE CATALOG comercio_aco_mineracao;

CREATE SCHEMA IF NOT EXISTS gold;

-- Dimensão tempo (mensal) - DEFINE O PERÍODO DA GOLD: 2003 a 2023 -----------
CREATE OR REPLACE TABLE gold.dim_tempo
COMMENT 'Calendário mensal do período de análise (2003-2023)'
AS
SELECT
  YEAR(d) * 100 + MONTH(d)          AS sk_tempo,
  d                                  AS data_mes,
  YEAR(d)                            AS ano,
  MONTH(d)                           AS mes,
  QUARTER(d)                         AS trimestre,
  CASE WHEN MONTH(d) <= 6 THEN 1 ELSE 2 END AS semestre,
  DATE_FORMAT(d, 'MMM/yyyy')         AS mes_ano
FROM (
  SELECT EXPLODE(SEQUENCE(DATE'2003-01-01', DATE'2023-12-01', INTERVAL 1 MONTH)) AS d
);

-- Dimensão país -------------------------------------------------------------
CREATE OR REPLACE TABLE gold.dim_pais
COMMENT 'Países de destino das exportações'
AS
SELECT co_pais, iso3, nome_pais, nome_pais_ingles
FROM silver.pais;

-- Dimensão produto (NCM) ------------------------------------------------------
CREATE OR REPLACE TABLE gold.dim_produto
COMMENT 'NCMs de minério de ferro e aço presentes nas exportações'
AS
WITH descricao_posicao (posicao_ncm, descricao_posicao) AS (
  VALUES
    ('2601', 'Minérios de ferro e seus concentrados'),
    ('7201', 'Ferro fundido bruto (ferro-gusa)'),
    ('7202', 'Ferroligas'),
    ('7203', 'Produtos ferrosos de redução direta'),
    ('7204', 'Desperdícios e sucata de ferro ou aço'),
    ('7205', 'Granalhas e pós de ferro ou aço'),
    ('7206', 'Ferro e aço não ligado em lingotes'),
    ('7207', 'Semimanufaturados de ferro ou aço não ligado'),
    ('7208', 'Laminados planos a quente (largura >= 600 mm)'),
    ('7209', 'Laminados planos a frio (largura >= 600 mm)'),
    ('7210', 'Laminados planos revestidos (largura >= 600 mm)'),
    ('7211', 'Laminados planos (largura < 600 mm)'),
    ('7212', 'Laminados planos revestidos (largura < 600 mm)'),
    ('7213', 'Fio-máquina de ferro ou aço não ligado'),
    ('7214', 'Barras de ferro ou aço não ligado'),
    ('7215', 'Outras barras de ferro ou aço não ligado'),
    ('7216', 'Perfis de ferro ou aço não ligado'),
    ('7217', 'Fios de ferro ou aço não ligado'),
    ('7218', 'Aço inoxidável em lingotes e semimanufaturados'),
    ('7219', 'Laminados planos de aço inox (largura >= 600 mm)'),
    ('7220', 'Laminados planos de aço inox (largura < 600 mm)'),
    ('7221', 'Fio-máquina de aço inox'),
    ('7222', 'Barras e perfis de aço inox'),
    ('7223', 'Fios de aço inox'),
    ('7224', 'Outras ligas de aço em lingotes e semimanufaturados'),
    ('7225', 'Laminados planos de outras ligas (largura >= 600 mm)'),
    ('7226', 'Laminados planos de outras ligas (largura < 600 mm)'),
    ('7227', 'Fio-máquina de outras ligas de aço'),
    ('7228', 'Barras e perfis de outras ligas de aço'),
    ('7229', 'Fios de outras ligas de aço'),
    ('7301', 'Estacas-pranchas'),
    ('7302', 'Elementos de vias férreas'),
    ('7303', 'Tubos de ferro fundido'),
    ('7304', 'Tubos sem costura'),
    ('7305', 'Tubos de grande diâmetro (> 406,4 mm)'),
    ('7306', 'Outros tubos e perfis ocos'),
    ('7307', 'Acessórios para tubos'),
    ('7308', 'Construções e estruturas'),
    ('7309', 'Reservatórios (> 300 l)'),
    ('7310', 'Reservatórios e latas (<= 300 l)'),
    ('7311', 'Recipientes para gases comprimidos'),
    ('7312', 'Cordas e cabos'),
    ('7313', 'Arame farpado'),
    ('7314', 'Telas e grades'),
    ('7315', 'Correntes'),
    ('7316', 'Âncoras'),
    ('7317', 'Pregos e tachas'),
    ('7318', 'Parafusos, porcas e arruelas'),
    ('7319', 'Agulhas e alfinetes'),
    ('7320', 'Molas'),
    ('7321', 'Fogões e aquecedores'),
    ('7322', 'Radiadores'),
    ('7323', 'Artigos de uso doméstico'),
    ('7324', 'Artigos de higiene'),
    ('7325', 'Outras obras moldadas'),
    ('7326', 'Outras obras de ferro ou aço')
),
ncms AS (
  SELECT DISTINCT s.ncm, s.categoria_produto
  FROM silver.comex_exportacoes s
  JOIN gold.dim_tempo t ON t.sk_tempo = s.ano * 100 + s.mes
)
SELECT
  n.ncm,
  LEFT(n.ncm, 2)                                    AS capitulo_ncm,
  LEFT(n.ncm, 4)                                    AS posicao_ncm,
  COALESCE(d.descricao_posicao, 'Não descrito')     AS descricao_posicao,
  n.categoria_produto
FROM ncms n
LEFT JOIN descricao_posicao d ON LEFT(n.ncm, 4) = d.posicao_ncm;

-- Dimensão município ----------------------------------------------------------
CREATE OR REPLACE TABLE gold.dim_municipio
COMMENT 'Municípios com arrecadação de CFEM'
AS
SELECT
  s.codigo_municipio,
  MAX_BY(s.municipio, s.ano) AS municipio,   -- nome mais recente
  MAX_BY(s.uf, s.ano)        AS uf
FROM silver.cfem_arrecadacao s
JOIN gold.dim_tempo t ON t.sk_tempo = s.ano * 100 + s.mes
GROUP BY s.codigo_municipio;

-- Fato exportação -------------------------------------------------------------
CREATE OR REPLACE TABLE gold.fato_exportacao
COMMENT 'Exportações de minério de ferro e aço agregadas por mês, país, NCM, UF e via'
AS
SELECT
  t.sk_tempo,
  s.co_pais,
  s.ncm,
  s.uf,
  s.co_via,
  SUM(s.valor_fob_usd)         AS valor_fob_usd,
  SUM(s.kg_liquido)            AS kg_liquido,
  SUM(s.kg_liquido) / 1000.0   AS toneladas
FROM silver.comex_exportacoes s
JOIN gold.dim_tempo t ON t.sk_tempo = s.ano * 100 + s.mes   -- recorte 2003-2023
GROUP BY ALL;

-- Fato CFEM -------------------------------------------------------------------
CREATE OR REPLACE TABLE gold.fato_cfem
COMMENT 'Arrecadação de CFEM agregada por mês, município e substância'
AS
SELECT
  t.sk_tempo,
  s.codigo_municipio,
  s.substancia,
  s.eh_minerio_ferro,
  SUM(s.valor_recolhido_brl)            AS valor_recolhido_brl,
  SUM(CASE WHEN s.unidade_medida = 't' THEN s.quantidade_comercializada END) AS toneladas_comercializadas,
  COUNT(*)                              AS qtd_recolhimentos
FROM silver.cfem_arrecadacao s
JOIN gold.dim_tempo t ON t.sk_tempo = s.ano * 100 + s.mes   -- recorte 2003-2023
GROUP BY ALL;

-- Tabela analítica: período comum ----------------------------------------------
-- Indicadores anuais que dependem das duas bases (Comex + CFEM).
-- O período (2003-2023) já vem dos fatos, via dim_tempo.
CREATE OR REPLACE TABLE gold.indicadores_periodo_comum
COMMENT 'Exportações de minério/aço x CFEM por ano, período comum 2003-2023'
AS
WITH exportacao AS (
  SELECT
    t.ano,
    SUM(CASE WHEN p.categoria_produto = 'Minério de ferro' THEN f.valor_fob_usd END)  AS exp_minerio_fob_usd,
    SUM(CASE WHEN p.categoria_produto = 'Minério de ferro' THEN f.toneladas END)      AS exp_minerio_toneladas,
    SUM(CASE WHEN p.categoria_produto <> 'Minério de ferro' THEN f.valor_fob_usd END) AS exp_aco_fob_usd
  FROM gold.fato_exportacao f
  JOIN gold.dim_tempo   t ON f.sk_tempo = t.sk_tempo
  JOIN gold.dim_produto p ON f.ncm      = p.ncm
  GROUP BY t.ano
),
cfem AS (
  SELECT
    t.ano,
    SUM(f.valor_recolhido_brl)                                              AS cfem_total_brl,
    SUM(CASE WHEN f.eh_minerio_ferro THEN f.valor_recolhido_brl ELSE 0 END) AS cfem_ferro_brl
  FROM gold.fato_cfem f
  JOIN gold.dim_tempo t ON f.sk_tempo = t.sk_tempo
  GROUP BY t.ano
),
anual AS (
  SELECT
    e.ano,
    e.exp_minerio_fob_usd,
    e.exp_minerio_toneladas,
    e.exp_minerio_fob_usd / NULLIF(e.exp_minerio_toneladas, 0) AS preco_minerio_usd_t,
    e.exp_aco_fob_usd,
    c.cfem_total_brl,
    c.cfem_ferro_brl
  FROM exportacao e
  JOIN cfem       c ON e.ano = c.ano
)
SELECT
  *,
  -- variação % sobre o ano anterior
  (preco_minerio_usd_t / NULLIF(LAG(preco_minerio_usd_t) OVER (ORDER BY ano), 0) - 1) * 100 AS var_preco_minerio_pct,
  (cfem_ferro_brl      / NULLIF(LAG(cfem_ferro_brl)      OVER (ORDER BY ano), 0) - 1) * 100 AS var_cfem_ferro_pct
FROM anual;

-- Tabela de apoio: o que tem em cada base ------------------------------------
-- Documenta, para o dashboard, período, recorte e volume de cada base em
-- cada camada (origem/bronze -> silver -> gold).
CREATE OR REPLACE TABLE gold.resumo_bases
COMMENT 'Período, produtos e volume de registros de cada base, por camada'
AS
SELECT
  1                                                              AS ordem,
  'Exportações (Comex Stat / MDIC)'                              AS base,
  '1997 a 2023'                                                  AS periodo_origem,
  '2003 a 2023'                                                  AS periodo_analise,
  'Minério de ferro (NCM 2601), ferro e aço (cap. 72) e obras de ferro ou aço (cap. 73)' AS produtos_incluidos,
  (SELECT COUNT(*) FROM gold.dim_produto)                        AS qtd_produtos,
  'NCMs'                                                         AS tipo_produto,
  (SELECT COUNT(*) FROM bronze.comex_exportacoes)                AS registros_origem,
  (SELECT COUNT(*) FROM silver.comex_exportacoes)                AS registros_silver,
  (SELECT COUNT(*) FROM gold.fato_exportacao)                    AS registros_gold,
  'A origem tem todas as exportações do Brasil; só os NCMs de minério e aço seguem para a Silver. Não há importações.' AS observacao
UNION ALL
SELECT
  2,
  'Arrecadação de CFEM (ANM)',
  '2002 a 2026 (2026 parcial)',
  '2003 a 2023',
  'Todas as substâncias minerais. Ferro = FERRO + MINÉRIO DE FERRO',
  (SELECT COUNT(DISTINCT substancia) FROM gold.fato_cfem),
  'substâncias',
  (SELECT COUNT(*) FROM bronze.cfem_arrecadacao),
  (SELECT COUNT(*) FROM silver.cfem_arrecadacao),
  (SELECT COUNT(*) FROM gold.fato_cfem),
  'Usado só o arquivo completo (os arquivos por faixa de anos são recortes dele). Linhas 100% idênticas removidas na Silver. 2002 tem um único registro inválido.';

-- A conferência da Gold (período, chaves e totais) fica no 06_validacao_qualidade.sql.
