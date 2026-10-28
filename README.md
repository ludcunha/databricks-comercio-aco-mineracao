# Comércio Exterior de Aço e Mineração no Databricks

Projeto de portfólio de engenharia e análise de dados. Ele junta duas bases públicas:

- **Exportações brasileiras** (Comex Stat, do Ministério do Desenvolvimento, Indústria, Comércio e Serviços - MDIC)
- **Arrecadação da CFEM** (Agência Nacional de Mineração - ANM). A CFEM é a taxa que as mineradoras pagam pela exploração mineral.

Os dados passam por três camadas no Databricks (bronze, silver e gold), viram um modelo dimensional e alimentam análises em SQL e um dashboard. Um job do Databricks executa todo o processo.

O foco é **minério de ferro e aço**, no período de **2003 a 2023**.

## Perguntas que o projeto responde

1. Quais países mais compram minério de ferro e aço do Brasil?
2. Como o preço médio por tonelada (US$/t) mudou ao longo do tempo?
3. Quais estados mais exportam?
4. Quais municípios mais arrecadam CFEM? A arrecadação acompanha o preço do minério?

## Principais resultados

| Pergunta | Resposta |
|---|---|
| Quem compra | A **China** comprou 64% do minério de ferro exportado entre 2019 e 2023. Os **Estados Unidos** compraram 40% do aço. |
| Preço | O minério foi de US$ 20/t (2003) para o pico de US$ 126/t (2011), caiu para US$ 36/t (2016) e voltou a US$ 125/t (2021). |
| Estados | **Minas Gerais** e **Pará** somam cerca de 65% do valor exportado de minério e aço entre 2003 e 2023. |
| Municípios | **Parauapebas (PA)** é quem mais arrecada CFEM: R$ 12 bilhões entre 2003 e 2023, 98% vindos do ferro. |
| CFEM x preço | Correlação de **0,58**: a CFEM do ferro tende a subir com o preço do minério, mas também depende do câmbio, do volume e da mudança de alíquota de 2017. |

## Fontes de dados

| Arquivo | Fonte | Conteúdo | Link |
|---|---|---|---|
| `Comex_Stat/BRASIL_EXP_COMPLETO.csv` | Comex Stat (MDIC), via Kaggle | Exportações por produto (NCM), país, estado e via, de 1997 a 2023 | [Kaggle](https://www.kaggle.com/datasets/yousefmoterassed/importaoexportao-do-brasil-desde-1996-a-2023) |
| `Comex_Stat/PAIS.csv` | Comex Stat (MDIC), via Kaggle | Nome dos países (o arquivo de exportações traz só o código) | mesmo link |
| `Arquivos_CFEM/CFEM_Arrecadacao.csv` | ANM (dados abertos) | Pagamentos de CFEM por município, substância e empresa, de 2002 a 2026 | [dados.gov.br](https://dados.gov.br/dados/conjuntos-dados/sistema-arrecadacao) |

O dataset do Kaggle também pode ser baixado com Python:

```python
import kagglehub

path = kagglehub.dataset_download("yousefmoterassed/importaoexportao-do-brasil-desde-1996-a-2023")
print("Arquivos em:", path)
```

> Os CSVs não estão no repositório porque são grandes (~2,8 GB). Eles estão listados no `.gitignore`.

## Como o projeto foi feito (passo a passo)

### Passo 1 - Enviar os dados para o Databricks

Criei no Unity Catalog o catálogo `comercio_aco_mineracao`, o schema `bronze` e um Volume chamado `raw`. Os CSVs foram enviados para:

- `/Volumes/comercio_aco_mineracao/bronze/raw/Comex_Stat/`
- `/Volumes/comercio_aco_mineracao/bronze/raw/Arquivos_CFEM/`

### Passo 2 - Explorar os arquivos ([01_analise_exploratoria.sql](01_analise_exploratoria.sql))

Antes de criar tabelas, li os CSVs direto do Volume para entender o formato e a qualidade dos dados. Descobertas:

| O que encontrei | O que fiz |
|---|---|
| Os arquivos usam a codificação Latin-1 (ISO-8859-1), não UTF-8 | Leitura com `encoding => 'ISO-8859-1'`, para os acentos saírem certos |
| O Comex separa colunas com `;` | Leitura com `sep => ';'` |
| O CFEM usa vírgula nos decimais (`"206,41"`) | Troca da vírgula por ponto antes de converter para número |
| `CFEM_Arrecadacao.csv` é exatamente a soma dos arquivos por faixa de anos (2002-2006 ... 2022-2026) | Carregar só o arquivo completo. Carregar todos dobraria os dados |
| O CFEM tem cerca de 143 mil linhas repetidas, idênticas em todas as colunas (~6%). A maior parte do valor está em pagamentos de ferro de fev/2024 | Remover as repetidas na camada silver |
| O ferro aparece no CFEM com dois nomes: `FERRO` e `MINÉRIO DE FERRO` | Tratar os dois como ferro |
| 2002 no CFEM tem um único registro, repetido 10 vezes | Começar a análise em 2003 |
| O Comex vai só até 2023 e traz apenas exportações | Terminar a análise em 2023; sem balança comercial |

### Passo 3 - Camada bronze ([02_ingestao_bronze.sql](02_ingestao_bronze.sql))

Os CSVs viram tabelas Delta **sem nenhuma alteração**: todas as colunas como texto e com os nomes originais. Cada linha ganha duas colunas de controle: o arquivo de origem e a data da carga.

| Tabela | Linhas |
|---|---|
| `bronze.comex_exportacoes` | 26,9 milhões |
| `bronze.comex_pais` | 282 |
| `bronze.cfem_arrecadacao` | 2,43 milhões |

### Passo 4 - Camada silver ([03_tratamento_silver.sql](03_tratamento_silver.sql))

Limpeza e padronização:

- Converte os tipos (ano e mês como número inteiro, valores como número decimal) e passa os nomes das colunas para snake_case.
- **Comex:** mantém só os produtos do projeto:
  - NCM 2601: minério de ferro
  - capítulo 72: ferro fundido, ferro e aço
  - capítulo 73: obras de ferro ou aço
- **CFEM:** remove as linhas repetidas, converte a vírgula decimal e marca o que é ferro (coluna `eh_minerio_ferro`). Todas as substâncias são mantidas.
- A silver guarda todos os anos. O recorte de período fica para a gold.

Resultado: 1,83 milhão de linhas de exportação e 2,29 milhões de linhas de CFEM.

### Passo 5 - Camada gold ([04_modelagem_gold.sql](04_modelagem_gold.sql))

Modelo dimensional (estrela) no **período de 2003 a 2023**. O período é definido num lugar só, a tabela `dim_tempo`; fatos e dimensões são montados a partir dela.

```
            dim_tempo          dim_pais
                 \               /
   dim_produto -- fato_exportacao -- (UF, via)

            dim_tempo      dim_municipio
                 \           /
                   fato_cfem -- (substância)
```

| Tabela | O que guarda |
|---|---|
| `dim_tempo` | Meses de 2003 a 2023 |
| `dim_pais` | Países de destino |
| `dim_produto` | NCMs com categoria e descrição (ex.: "7207 - Semimanufaturados de ferro ou aço não ligado") |
| `dim_municipio` | Municípios que pagam CFEM |
| `fato_exportacao` | Valor (US$) e toneladas por mês, país, NCM, estado e via |
| `fato_cfem` | CFEM (R$) por mês, município e substância |
| `indicadores_periodo_comum` | Uma linha por ano com os indicadores que cruzam as duas bases: preço do minério, CFEM do ferro e variações |
| `resumo_bases` | O que tem em cada base (período, produtos e quantidade de linhas em cada camada). Usada no dashboard |
| `log_validacao` | Histórico da validação de qualidade (Passo 8) |

### Passo 6 - Análises ([05_analises.sql](05_analises.sql))

Consultas que respondem às perguntas do projeto. Usam joins, CTEs e funções de janela (`RANK`, `LAG`, `CORR`).

### Passo 7 - Dashboard ([dashboard/comercio_aco_mineracao.lvdash.json](dashboard/comercio_aco_mineracao.lvdash.json))

Dashboard AI/BI do Databricks que lê a camada gold.

| Página | Conteúdo |
|---|---|
| O que tem em cada base | Período, produtos e quantidade de linhas de cada base; produtos exportados; substâncias do CFEM; notas sobre o tratamento |
| Exportações | Valor por ano, preço por tonelada, países compradores e estados exportadores |
| CFEM | Municípios que mais arrecadam e arrecadação por ano, separando o ferro das outras substâncias |
| Exportação x CFEM | CFEM do ferro e preço do minério no mesmo gráfico, correlações e tabela anual |
| Filtros | Filtro de anos que vale para todas as páginas |

### Passo 8 - Validação de qualidade ([06_validacao_qualidade.sql](06_validacao_qualidade.sql))

Depois da carga, um script confere as três camadas. Se alguma regra falhar, ele gera um erro: o job para e o dashboard **não** é atualizado com dados ruins.

| Camada | Regras |
|---|---|
| Bronze | As tabelas não podem estar vazias. O número de linhas não pode cair mais de 10% em relação à última carga aprovada (isso pega um arquivo cortado ou incompleto). |
| Silver | Nenhum valor nulo ou negativo nas colunas principais. Nenhum produto fora dos NCMs do projeto. Nenhuma linha duplicada no CFEM. |
| Gold | Todos os 21 anos (2003 a 2023) presentes. Nenhuma linha dos fatos sem a dimensão correspondente. Ferro com CFEM em todos os anos. Totais da gold iguais aos da silver no mesmo período. |

O resultado de cada regra fica guardado na tabela `gold.log_validacao`, com o histórico de todas as execuções. Se a validação falhar, dá para voltar as tabelas à versão anterior com o histórico do Delta (`DESCRIBE HISTORY` e `RESTORE TABLE`). O passo a passo está no comentário do script.

### Passo 9 - Job ([jobs/pipeline_medalhao.json](jobs/pipeline_medalhao.json))

Um job do Databricks executa a carga completa **sob demanda**, ou seja, quando alguém clica em "Executar":

```
bronze (02) → silver (03) → gold (04) → validação (06) → atualiza o dashboard
```

- Cada etapa só começa se a anterior terminar sem erro.
- Em caso de falha, inclusive na validação, o job envia um e-mail.
- Os scripts 01 (exploração) e 05 (análises) ficam fora do job porque não fazem parte da carga.
- A execução completa leva cerca de 3 minutos.

## Estrutura do repositório

```
├── 01_analise_exploratoria.sql   # exploração dos CSVs
├── 02_ingestao_bronze.sql        # camada bronze
├── 03_tratamento_silver.sql      # camada silver
├── 04_modelagem_gold.sql         # camada gold (modelo dimensional)
├── 05_analises.sql               # respostas às perguntas
├── 06_validacao_qualidade.sql    # validação de qualidade (falha o job se algo estiver errado)
├── dashboard/
│   └── comercio_aco_mineracao.lvdash.json   # definição do dashboard
├── jobs/
│   └── pipeline_medalhao.json    # definição do job
└── README.md
```

## Como reproduzir

Pré-requisitos: um workspace Databricks com Unity Catalog, um SQL Warehouse e o [Databricks CLI](https://docs.databricks.com/dev-tools/cli/) instalado.

1. **Conectar o CLI ao workspace:** faça o login (abre o navegador para autenticar) e confira se a conexão funcionou.

   ```bash
   databricks auth login --host https://<seu-workspace>.cloud.databricks.com
   databricks current-user me
   ```

   O segundo comando deve mostrar o seu usuário.

2. **Dados:** baixe os arquivos das fontes acima.
3. **Catálogo e Volume:** crie o catálogo `comercio_aco_mineracao`, o schema `bronze` e o Volume `raw`. Envie os CSVs para as pastas mostradas em "Passo 1 - Enviar os dados para o Databricks".
4. **Primeira carga:** rode os scripts 01 a 06, nessa ordem, no editor SQL do Databricks.
5. **Dashboard:** em *Dashboards > Importar*, escolha o arquivo `dashboard/comercio_aco_mineracao.lvdash.json`. Ele lê as tabelas de `comercio_aco_mineracao.gold`. Anote o ID do dashboard (fica na URL).
6. **Job (opcional, para as próximas cargas):**
   1. No `jobs/pipeline_medalhao.json`, troque os marcadores pelos seus valores: `<SEU_USUARIO>` e `<SEU_EMAIL>` (seu usuário do Databricks), `<WAREHOUSE_ID>` (ID do SQL Warehouse) e `<DASHBOARD_ID>` (ID anotado no passo 5).
   2. Envie os scripts do job para o workspace, crie o job e execute:

   ```bash
   databricks workspace import /Users/<SEU_USUARIO>/comercio_aco_mineracao/sql/02_ingestao_bronze.sql \
     --file 02_ingestao_bronze.sql --format RAW --overwrite
   # repita para 03_tratamento_silver.sql, 04_modelagem_gold.sql e 06_validacao_qualidade.sql

   databricks jobs create --json @jobs/pipeline_medalhao.json
   databricks jobs run-now <job_id>
   ```

> **Atenção:** o job roda as cópias dos scripts que estão no workspace. Sempre que alterar um `.sql` aqui, envie a nova versão com o `databricks workspace import` antes de rodar o job.

## Decisões e limitações

- **Período de 2003 a 2023:** é o período que as duas bases têm em comum. Bronze e silver guardam o histórico completo; só a gold é recortada.
- **Sem balança comercial:** o dataset do Comex traz apenas exportações.
- **CFEM em reais (R$) sem correção pela inflação, e preço em dólares (US$):** a comparação entre os dois também é afetada pelo câmbio e pelo aumento da alíquota do ferro de 2% para 3,5% em 2017 (Lei 13.540/2017).
- **Carga completa a cada execução:** o job recria todas as tabelas. É simples e, para este volume de dados, rápido.
- **Exportações com peso zero:** cerca de 270 mil linhas do Comex têm peso igual a zero. Elas somam 0,01% do valor, então quase não afetam o preço por tonelada.

## Tecnologias

Databricks (Unity Catalog, Volumes, SQL Warehouse serverless, Jobs, dashboards AI/BI), Delta Lake, SQL, Databricks CLI, Git/GitHub.

## Autora

Ludmila Cunha
