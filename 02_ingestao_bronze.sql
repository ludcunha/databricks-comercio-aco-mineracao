--Objetivo

--Realizar a ingestão dos dados brutos preservando as informações originais disponibilizadas pelas fontes oficiais.

--Fontes de dados
--Fonte	DescriçãoComex Stat (MDIC)	Exportações e importações do Brasil
--ANM	Arrecadação de CFEM
--Criação das tabelas Bronze


CREATE SCHEMA IF NOT EXISTS bronze;
--SQL
CREATE OR REPLACE TABLE bronze.comex_exportacoes
USING CSV
OPTIONS (
header = 'true'
)
LOCATION '/Volumes/comercio_aco_mineracao/bronze/comex/';
SQL
CREATE OR REPLACE TABLE bronze.cfem
USING CSV
OPTIONS (
header = 'true'
)
LOCATION '/Volumes/comercio_aco_mineracao/bronze/cfem/';

--Resultado esperado
--Dados armazenados sem transformações.
--Preservação da rastreabilidade.
--Camada utilizada como fonte oficial do projeto.