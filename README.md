# databricks-comercio-aco-mineracao


# Comércio Exterior de Aço e Mineração no Databricks

Projeto de portfólio de análise de dados: pipeline completo (bronze, silver e gold), modelo dimensional e análises em SQL sobre o comércio exterior brasileiro de minério de ferro e aço, combinado com a arrecadação de CFEM da mineração.

## Objetivo

Construir, no Databricks, um data warehouse dimensional a partir de dados públicos e responder perguntas de negócio usando SQL (joins, agregações, CTEs e funções janela).

## Perguntas de negócio

- Quais países mais compram minério de ferro e aço do Brasil?
- Como o preço médio por tonelada (US$/t) evoluiu ao longo do tempo?
- Quais estados lideram as exportações? Qual a balança comercial por UF?
- Quais municípios mais arrecadam CFEM e a arrecadação acompanha o preço do minério?

## Fontes de dados

Nome do Arquivo | Fonte | Conteúdo | Link |
|---|---|---|
Comex_Stat| Comex Stat (MDIC) - Kaggle | Exportações e importações por NCM, país, UF e via | https://www.kaggle.com/datasets/yousefmoterassed/importaoexportao-do-brasil-desde-1996-a-2023 |

ou
import kagglehub

# Download latest version
path = kagglehub.dataset_download("yousefmoterassed/importaoexportao-do-brasil-desde-1996-a-2023")

print("Path to dataset files:", path)

Arquivo_CFEM | ANM (dados abertos) | Arrecadação de CFEM por município, substância e empresa | https://dados.gov.br/dados/conjuntos-dados/sistema-arrecadacao |




**Período analisado:** [ex.: 2020 a 2024]
**Filtros aplicados:** NCM capítulos 72 e 73 (ferro, aço e obras) e 2601 (minério de ferro).

> Os arquivos CSV não estão no repositório por causa do tamanho. Para reproduzir, baixe-os nas fontes acima e envie para um Volume no Databricks.




## Tecnologias

Databricks, Delta Lake, SQL, PySpark, Git/GitHub.

## Como reproduzir

1. Baixe os arquivos nas fontes acima.
2. Crie um schema e um Volume no Databricks e envie os CSVs.
3. Execute os notebooks na ordem: `01_bronze`, `02_silver`, `03_gold`, `04_analises`.

## Autor

Ludmila Cuha