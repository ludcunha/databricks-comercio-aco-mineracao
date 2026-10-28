-- =====================================================================
-- 01 - ANÁLISE EXPLORATÓRIA (arquivos brutos no Volume)
-- =====================================================================
-- Objetivo
--   Explorar os CSVs antes da ingestão para entender volume, colunas,
--   formato e qualidade, e assim definir as regras da Bronze e da Silver.
--   As consultas leem direto do Volume com read_files(), então este
--   script pode rodar antes de existir qualquer tabela.
-- =====================================================================

USE CATALOG comercio_aco_mineracao;

-- Arquivos disponíveis no Volume
LIST '/Volumes/comercio_aco_mineracao/bronze/raw/Comex_Stat/';
LIST '/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/';

-- ---------------------------------------------------------------------
-- Comex Stat - exportações
-- Formato: separador ';', encoding ISO-8859-1
-- Colunas: CO_ANO, CO_MES, CO_NCM, CO_UNID, CO_PAIS, SG_UF_NCM, CO_VIA,
--          CO_URF, QT_ESTAT, KG_LIQUIDO, VL_FOB
-- ---------------------------------------------------------------------

-- Amostra
SELECT *
FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Comex_Stat/BRASIL_EXP_COMPLETO.csv',
                format => 'csv', header => true, sep => ';', encoding => 'ISO-8859-1')
LIMIT 10;

-- Volume, período, dimensões e recorte de aço/minério
SELECT
  COUNT(*)                                        AS qtd_registros,
  MIN(CO_ANO)                                     AS menor_ano,
  MAX(CO_ANO)                                     AS maior_ano,
  COUNT(DISTINCT CO_PAIS)                         AS qtd_paises,
  COUNT(DISTINCT CO_NCM)                          AS qtd_ncm,
  COUNT_IF(CO_NCM LIKE '2601%')                   AS registros_minerio_ferro,
  COUNT_IF(LEFT(CO_NCM, 2) IN ('72', '73'))       AS registros_aco,
  COUNT_IF(CO_PAIS IS NULL OR CO_NCM IS NULL OR VL_FOB IS NULL) AS registros_com_nulos
FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Comex_Stat/BRASIL_EXP_COMPLETO.csv',
                format => 'csv', header => true, sep => ';', encoding => 'ISO-8859-1',
                inferColumnTypes => false);

-- ---------------------------------------------------------------------
-- CFEM - arrecadação
-- Formato: separador ',', encoding ISO-8859-1, vírgula decimal ("206,41")
-- ---------------------------------------------------------------------

-- Amostra
SELECT *
FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/CFEM_Arrecadacao.csv',
                format => 'csv', header => true, encoding => 'ISO-8859-1', inferColumnTypes => false)
LIMIT 10;

-- Período e volume do arquivo completo
SELECT
  COUNT(*)  AS qtd_registros,
  MIN(Ano)  AS menor_ano,
  MAX(Ano)  AS maior_ano
FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/CFEM_Arrecadacao.csv',
                format => 'csv', header => true, encoding => 'ISO-8859-1', inferColumnTypes => false);

-- Os arquivos por faixa de anos somam o mesmo que o arquivo completo?
SELECT
  REGEXP_EXTRACT(_metadata.file_name, 'CFEM_Arrecadacao(.*)\\.csv', 1) AS arquivo,
  COUNT(*) AS qtd_registros
FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/',
                format => 'csv', header => true, encoding => 'ISO-8859-1', inferColumnTypes => false,
                pathGlobFilter => 'CFEM_Arrecadacao*.csv')
GROUP BY 1
ORDER BY 1;

-- Linhas 100% duplicadas
WITH agrupado AS (
  SELECT * EXCEPT (_rescued_data), COUNT(*) AS ocorrencias
  FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/CFEM_Arrecadacao.csv',
                  format => 'csv', header => true, encoding => 'ISO-8859-1', inferColumnTypes => false)
  GROUP BY ALL
)
SELECT
  SUM(ocorrencias)       AS qtd_registros,
  COUNT(*)               AS qtd_distintos,
  SUM(ocorrencias - 1)   AS qtd_duplicados
FROM agrupado;

-- Substâncias ligadas ao ferro
SELECT `Substância` AS substancia, COUNT(*) AS qtd_registros
FROM read_files('/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/CFEM_Arrecadacao.csv',
                format => 'csv', header => true, encoding => 'ISO-8859-1', inferColumnTypes => false)
WHERE UPPER(`Substância`) LIKE '%FERR%'
GROUP BY 1
ORDER BY 2 DESC;

-- =====================================================================
-- Conclusões
--   * Exportações (Comex): 26,9 milhões de registros, 1997 a 2023.
--     ~1,8 milhão são de minério de ferro (NCM 2601) e aço (cap. 72 e 73).
--     O campo de país é um código (CO_PAIS); o nome vem de PAIS.csv.
--   * CFEM: 2,43 milhões de registros, 2002 a 2026 (2026 parcial).
--   * Os arquivos CFEM_Arrecadacao_AAAA_AAAA.csv são recortes do arquivo
--     completo -> a Bronze usa apenas CFEM_Arrecadacao.csv.
--   * O CFEM tem ~143 mil linhas idênticas (~6%) -> removidas na Silver.
--   * Ferro aparece no CFEM como 'FERRO' e 'MINÉRIO DE FERRO'.
--   * Os arquivos estão em ISO-8859-1 e o CFEM usa vírgula decimal:
--     tratado na leitura (Bronze) e na conversão de tipos (Silver).
--   * O dataset do Comex contém só exportações (sem importações).
--   * 2002 no CFEM tem um único registro (basalto, RS) repetido 10 vezes,
--     de processo de 2007 cadastrado em 2013: não representa o ano.
--   * Decisão: o período comum de análise é 2003 a 2023, aplicado na Gold.
-- =====================================================================
