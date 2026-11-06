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
/* =====================================================================
   02_degradacao.sas - degradação por pista (s por volta de idade do pneu)
   Mesmo modelo para os dois anos: 2024 vira a previsão, 2025 o "real"
   ===================================================================== */
%macro degradacao(s);                                     /* s = 24 ou 25 */
  data uso&s;                                             /* voltas usadas no modelo */
    set v&s;                                              /* voltas do ano */
    where usar2 = 1 and circuito ne 'Lusail';             /* só voltas limpas; Lusail fora (efeitos confundidos) */
    length rp $40;                                        /* chave corrida-piloto */
    rp = catx('_', session_key, driver_number);           /* um nível por piloto em cada corrida */
  run;                                                    /* executa */
  proc sort data=uso&s; by rp; run;                       /* ABSORB exige ordenação pela chave */

  ods exclude all;                                        /* não imprime a saída enorme do GLM */
  proc glm data=uso&s;                                    /* modelo linear de efeitos fixos */
    absorb rp;                                            /* efeito corrida-piloto (ritmo do carro/piloto) */
    class circuito compound;                              /* variáveis de classe */
    model lap_duration = circuito*lap_number              /* combustível e evolução da pista, por pista */
                         compound                         /* diferença de ritmo entre compostos */
                         circuito*tyre_age / solution;    /* degradação: inclinação da idade do pneu por pista */
    ods output ParameterEstimates=pe&s FitStatistics=fit&s;  /* guarda coeficientes e R² */
  run; quit;                                              /* executa */
  ods exclude none;                                       /* volta a imprimir */

  data deg&s;                                             /* uma linha por pista com a degradação */
    set pe&s;                                             /* coeficientes */
    where index(Parameter, 'tyre_age') > 0;               /* só os termos de idade do pneu */
    length circuito $40;                                  /* nome da pista */
    if index(Parameter, ' ') = 0 then delete;             /* segurança: ignora linhas sem nome de pista */
    circuito = strip(substr(Parameter, index(Parameter, ' ') + 1));  /* "circuito*tyre_age Yas Marina Circuit" -> nome da pista */
    deg = Estimate;                                       /* s perdidos por volta de idade do pneu */
    keep circuito deg StdErr;                             /* mantém só o necessário */
  run;                                                    /* executa */
%mend degradacao;                                         /* fim */

%degradacao(24)                                           /* 2024: base da previsão */
%degradacao(25)                                           /* 2025: o que de fato aconteceu */

proc print data=fit24 noobs; title 'Ajuste 2024'; run;    /* R² do modelo 2024 */
proc print data=deg24 noobs; title 'Degradação 2024 (s/volta)'; run;  /* conferência: Miami ~0,026 e Suzuka ~0,120 */
title;                                                    /* limpa o título */
