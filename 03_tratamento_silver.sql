--Objetivo

--Padronizar os dados e preparar as informações para análise.

--Regras aplicadas
--Remoção de registros sem ano.
--Padronização de nomes.
--Conversão de valores numéricos.
--Filtro para período comum entre as fontes.
--Criação da camada Silver


CREATE SCHEMA IF NOT EXISTS silver;


CREATE OR REPLACE TABLE silver.comex_exportacoes AS
SELECT
CAST(ano AS INT) AS ano,
UPPER(pais) AS pais,
ncm,
CAST(valor_usd AS DOUBLE) AS valor_usd,
uf
FROM bronze.comex_exportacoes
WHERE ano IS NOT NULL;


CREATE OR REPLACE TABLE silver.cfem AS
SELECT
CAST(ano AS INT) AS ano,
municipio,
substancia,
CAST(valor_cfem AS DOUBLE) AS valor_cfem
FROM bronze.cfem
WHERE ano BETWEEN 2002 AND 2023;

--Resultado esperado
--Dados padronizados.
--Períodos compatíveis entre as bases.
--Dados preparados para agregação.