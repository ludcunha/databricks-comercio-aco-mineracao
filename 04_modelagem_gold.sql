
--Objetivo

--Construir indicadores de negócio relacionados à mineração e comércio exterior.

--Indicador 1 - Exportações por ano
--SQL
CREATE OR REPLACE TABLE gold.exportacoes_anuais AS
SELECT
ano,
SUM(valor_usd) AS total_exportado
FROM silver.comex_exportacoes
GROUP BY ano;
Indicador 2 - CFEM por ano

CREATE OR REPLACE TABLE gold.cfem_anual AS
SELECT
ano,
SUM(valor_cfem) AS total_cfem
FROM silver.cfem
GROUP BY ano;
Indicador 3 - Top municípios arrecadadores


CREATE OR REPLACE TABLE gold.top_municipios_cfem AS
SELECT
municipio,
SUM(valor_cfem) AS total_cfem
FROM silver.cfem
GROUP BY municipio
ORDER BY total_cfem DESC;

--Resultado esperado

--A camada Gold disponibiliza informações consolidadas para:

--Dashboards gerenciais.
--Análises de mercado.
--Estudos da cadeia de mineração.
--Comparação entre exportações e arrecadação mineral.