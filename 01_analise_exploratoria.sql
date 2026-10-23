--Objetivo

--Realizar a exploração inicial dos datasets de comércio exterior e arrecadação mineral para compreender
-- volume de dados, colunas disponíveis e qualidade das informações.

--Passos executados
--Verificação de quantidade de registros.
--Análise de valores nulos.
--Identificação das principais dimensões.
--Validação dos períodos históricos.
--Consultas

-- Quantidade de registros

SELECT COUNT(*) AS qtd_registros
FROM bronze.comex_exportacoes;

-- Período disponível

SELECT
MIN(ano) AS menor_ano,
MAX(ano) AS maior_ano
FROM bronze.comex_exportacoes;

-- Quantidade de países

SELECT COUNT(DISTINCT pais) AS qtd_paises
FROM bronze.comex_exportacoes;

-- Quantidade de NCMs

SELECT COUNT(DISTINCT ncm) AS qtd_ncm
FROM bronze.comex_exportacoes;

-- Período do CFEM

SELECT
MIN(ano) AS menor_ano,
MAX(ano) AS maior_ano
FROM bronze.cfem;

--Conclusões:

--Exportações disponíveis entre 1997 e 2023.
--Dados de CFEM disponíveis entre 2002 e 2026.
--Os arquivos com faixas de anos representam recortes do dataset completo.
--Será utilizado o dataset completo na camada Bronze.