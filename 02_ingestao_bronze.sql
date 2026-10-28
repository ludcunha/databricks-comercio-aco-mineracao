-- =====================================================================
-- 02 - INGESTÃO BRONZE
-- =====================================================================
-- Objetivo
--   Ingerir os arquivos brutos do Volume como tabelas Delta, preservando
--   as informações originais (todas as colunas como STRING, nomes originais).
--
-- Fontes (Volume /Volumes/comercio_aco_mineracao/bronze/raw/)
--   Comex_Stat/BRASIL_EXP_COMPLETO.csv  -> exportações por NCM, país, UF e via (MDIC)
--   Comex_Stat/PAIS.csv                 -> tabela de países do Comex Stat
--   Arquivos_CFEM/CFEM_Arrecadacao.csv  -> arrecadação de CFEM (ANM)
--
-- Particularidades dos arquivos (ver 01_analise_exploratoria.sql)
--   * Encoding ISO-8859-1 (Latin-1), não UTF-8.
--   * Comex usa ';' como separador; CFEM usa ','.
--   * CFEM usa vírgula decimal ("206,41") -> conversão feita na Silver.
--   * Os arquivos CFEM_Arrecadacao_AAAA_AAAA.csv são recortes do arquivo
--     completo, por isso são ignorados (evita duplicar os dados).
--
-- Colunas técnicas adicionadas
--   _arquivo_origem : caminho do arquivo lido (rastreabilidade)
--   _data_ingestao  : momento da carga
-- =====================================================================

USE CATALOG comercio_aco_mineracao;

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE VOLUME IF NOT EXISTS bronze.raw;

-- Exportações (Comex Stat) ---------------------------------------------
CREATE OR REPLACE TABLE bronze.comex_exportacoes
COMMENT 'Exportações brasileiras (Comex Stat/MDIC) 1997-2023, dado bruto'
AS
SELECT
  * EXCEPT (_rescued_data),
  _metadata.file_path  AS _arquivo_origem,
  current_timestamp()  AS _data_ingestao
FROM read_files(
  '/Volumes/comercio_aco_mineracao/bronze/raw/Comex_Stat/BRASIL_EXP_COMPLETO.csv',
  format           => 'csv',
  header           => true,
  sep              => ';',
  encoding         => 'ISO-8859-1',
  inferColumnTypes => false
);

-- Países (Comex Stat) --------------------------------------------------
CREATE OR REPLACE TABLE bronze.comex_pais
COMMENT 'Tabela de países do Comex Stat, dado bruto'
AS
SELECT
  * EXCEPT (_rescued_data),
  _metadata.file_path  AS _arquivo_origem,
  current_timestamp()  AS _data_ingestao
FROM read_files(
  '/Volumes/comercio_aco_mineracao/bronze/raw/Comex_Stat/PAIS.csv',
  format           => 'csv',
  header           => true,
  sep              => ';',
  encoding         => 'ISO-8859-1',
  inferColumnTypes => false
);

-- Arrecadação CFEM (ANM) -----------------------------------------------
CREATE OR REPLACE TABLE bronze.cfem_arrecadacao
COMMENT 'Arrecadação de CFEM (ANM) 2002-2026, dado bruto (contém linhas duplicadas da origem)'
AS
SELECT
  * EXCEPT (_rescued_data),
  _metadata.file_path  AS _arquivo_origem,
  current_timestamp()  AS _data_ingestao
FROM read_files(
  '/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/CFEM_Arrecadacao.csv',
  format           => 'csv',
  header           => true,
  sep              => ',',
  encoding         => 'ISO-8859-1',
  inferColumnTypes => false
);

-- Conferência da carga ---------------------------------------------------
SELECT 'comex_exportacoes' AS tabela, COUNT(*) AS qtd_registros FROM bronze.comex_exportacoes
UNION ALL
SELECT 'comex_pais', COUNT(*) FROM bronze.comex_pais
UNION ALL
SELECT 'cfem_arrecadacao', COUNT(*) FROM bronze.cfem_arrecadacao;
