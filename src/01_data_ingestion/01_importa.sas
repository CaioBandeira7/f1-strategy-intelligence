/* =====================================================================
   01_importa.sas - lê os CSVs de 2024 (treino) e 2025 (teste)
   ===================================================================== */
options locale=en_US validvarname=v7;              /* ponto = decimal na leitura; nomes de coluna válidos no SAS */
%let pasta = ~/f1;                                 /* pasta com os CSVs no Home */

%macro importa(arq, tab);                          /* macro: importa um CSV para a WORK */
  proc import datafile="&pasta/&arq"               /* arquivo de origem */
              out=&tab dbms=csv replace;           /* tabela de destino, sobrescreve se existir */
    guessingrows=max;                              /* olha todas as linhas para acertar tipo e tamanho */
  run;                                             /* executa */
%mend importa;                                     /* fim da macro */

%macro importa_ano(ano, s);                        /* importa todos os arquivos de um ano */
  %importa(f1_&ano._voltas_para_sas.csv,   v&s)    /* voltas com as marcações (usar2 etc.) */
  %importa(f1_&ano._perda_box_por_pista.csv, box&s)/* perda no box por pista */
  %importa(f1_&ano._estrategia_real.csv,   real&s) /* estratégia real de cada piloto */
  %importa(f1_&ano._stints.csv,            st&s)   /* stints brutos */
  %importa(f1_&ano._secas_voltas_clima.csv, cl&s)  /* voltas com clima (para o ML) */
%mend importa_ano;                                 /* fim da macro */

%importa_ano(2024, 24)                             /* 2024 = base do modelo */
%importa_ano(2025, 25)                             /* 2025 = temporada de teste */

proc sql;                                          /* conferência rápida */
  select '2024' as ano, count(*) as voltas, sum(usar2) as usadas,
         count(distinct circuito) as pistas from v24
  union all
  select '2025', count(*), sum(usar2), count(distinct circuito) from v25;
quit;                                              /* fim */
