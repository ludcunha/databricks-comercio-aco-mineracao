-- =====================================================================
-- 03 - TRATAMENTO SILVER
-- =====================================================================
-- Objetivo
--   Padronizar, tipar e filtrar os dados da Bronze para análise.
--
-- Regras aplicadas
--   Comex
--     * Filtro de produtos: NCM 2601 (minério de ferro), capítulo 72
--       (ferro fundido, ferro e aço) e capítulo 73 (obras de ferro ou aço).
--     * Conversão de tipos (ano/mês INT, valores BIGINT) e nomes em snake_case.
--     * Classificação do produto em categoria.
--   Países
--     * Nomes padronizados em maiúsculas.
--   CFEM
--     * Remoção de linhas 100% idênticas (~143 mil, ~6% da origem).
--     * Conversão da vírgula decimal ("206,41" -> 206.41).
--     * Padronização de textos (TRIM/UPPER) e flag de minério de ferro.
--   A Silver mantém todos os anos. O recorte do período comum entre as
--   fontes (2003-2023) é feito na Gold, pela dim_tempo.
-- =====================================================================

USE CATALOG comercio_aco_mineracao;

CREATE SCHEMA IF NOT EXISTS silver;

-- Exportações de minério de ferro e aço ----------------------------------
CREATE OR REPLACE TABLE silver.comex_exportacoes
COMMENT 'Exportações de minério de ferro (NCM 2601) e aço (cap. 72 e 73), tipadas'
AS
SELECT
  CAST(CO_ANO AS INT)         AS ano,
  CAST(CO_MES AS INT)         AS mes,
  CO_NCM                      AS ncm,
  CASE
    WHEN CO_NCM LIKE '2601%' THEN 'Minério de ferro'
    WHEN CO_NCM LIKE '72%'   THEN 'Ferro e aço'
    WHEN CO_NCM LIKE '73%'   THEN 'Obras de ferro ou aço'
  END                         AS categoria_produto,
  CO_PAIS                     AS co_pais,
  SG_UF_NCM                   AS uf,
  CO_VIA                      AS co_via,
  CO_URF                      AS co_urf,
  CO_UNID                     AS co_unidade,
  CAST(QT_ESTAT   AS BIGINT)  AS qtd_estatistica,
  CAST(KG_LIQUIDO AS BIGINT)  AS kg_liquido,
  CAST(VL_FOB     AS BIGINT)  AS valor_fob_usd
FROM bronze.comex_exportacoes
WHERE CO_ANO IS NOT NULL
  AND (CO_NCM LIKE '2601%' OR LEFT(CO_NCM, 2) IN ('72', '73'));

-- Países ----------------------------------------------------------------
CREATE OR REPLACE TABLE silver.pais
COMMENT 'Países do Comex Stat'
AS
SELECT
  CO_PAIS                 AS co_pais,
  CO_PAIS_ISOA3           AS iso3,
  UPPER(TRIM(NO_PAIS))    AS nome_pais,
  UPPER(TRIM(NO_PAIS_ING)) AS nome_pais_ingles
FROM bronze.comex_pais;

-- Arrecadação CFEM ------------------------------------------------------
CREATE OR REPLACE TABLE silver.cfem_arrecadacao
COMMENT 'Arrecadação de CFEM sem duplicatas, valores numéricos (R$)'
AS
WITH sem_duplicatas AS (
  SELECT DISTINCT * EXCEPT (_arquivo_origem, _data_ingestao)
  FROM bronze.cfem_arrecadacao
)
SELECT
  CAST(Ano AS INT)                                              AS ano,
  CAST(`Mês` AS INT)                                            AS mes,
  Processo                                                      AS processo,
  CAST(AnoDoProcesso AS INT)                                    AS ano_processo,
  Tipo_PF_PJ                                                    AS tipo_pessoa,
  CPF_CNPJ                                                      AS cpf_cnpj,
  UPPER(TRIM(`Substância`))                                     AS substancia,
  UPPER(TRIM(`Substância`)) IN ('FERRO', 'MINÉRIO DE FERRO')    AS eh_minerio_ferro,
  UF                                                            AS uf,
  CodigoMunicipio                                               AS codigo_municipio,
  UPPER(TRIM(`Município`))                                      AS municipio,
  CAST(REPLACE(QuantidadeComercializada, ',', '.') AS DOUBLE)   AS quantidade_comercializada,
  TRIM(UnidadeDeMedida)                                         AS unidade_medida,
  CAST(REPLACE(ValorRecolhido, ',', '.') AS DOUBLE)             AS valor_recolhido_brl,
  CAST(DataCriacao AS TIMESTAMP)                                AS data_criacao
FROM sem_duplicatas
WHERE Ano IS NOT NULL;

-- Conferência -------------------------------------------------------------
SELECT categoria_produto, COUNT(*) AS registros, MIN(ano) AS de, MAX(ano) AS ate,
       ROUND(SUM(valor_fob_usd) / 1e9, 1) AS fob_usd_bilhoes
FROM silver.comex_exportacoes
GROUP BY categoria_produto;

SELECT COUNT(*) AS registros, MIN(ano) AS de, MAX(ano) AS ate,
       COUNT_IF(valor_recolhido_brl IS NULL) AS valores_nulos,
       ROUND(SUM(valor_recolhido_brl) / 1e9, 1) AS cfem_brl_bilhoes
FROM silver.cfem_arrecadacao;
