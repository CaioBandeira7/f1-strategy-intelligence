/* roda a base (sem imprimir) e depois o 08 */
ods exclude all;                                        /* não imprime as saídas antigas */
%include "~/f1/01_02_importa_degradacao.sas";            /* importa e estima a degradação */
%include "~/f1/03_simulador_previsao.sas";               /* simulador v1 e macros */
%include "~/f1/04_avaliacao.sas";                        /* gabaritos e avaliação */
ods exclude none;                                       /* volta a imprimir */
/* =====================================================================
   08_degradacao_treinos.sas - degradação estimada nos TREINOS LIVRES
   (informação que existe antes da corrida) e escolha da entrada do
   simulador usando só a 1ª metade de 2025 (validação).
   Pré-requisito: rodar 01_02, 03 e 04 antes (macros e tabelas).
   ===================================================================== */

data deg24_orig; set deg24; run;                        /* guarda a degradação de corrida de 2024 */

/* ---------- 1. importa as voltas dos treinos ---------- */
%importa(f1_2024_treinos_voltas.csv, fp24)              /* treinos 2024 */
%importa(f1_2025_treinos_voltas.csv, fp25)              /* treinos 2025 */

/* ---------- 2. separa as simulações de corrida (stints longos) ---------- */
%macro longos(s);                                       /* s = 24 ou 25 */
  data lr&s;                                            /* voltas candidatas */
    set fp&s;
    where compound in ('SOFT','MEDIUM','HARD')          /* pneu de pista seca */
          and volta_no_stint > 0 and ultima_do_stint = 0   /* sem volta de saída e sem volta de entrada */
          and is_pit_out_lap = 0 and lap_duration > 0;  /* sem saída do box e com tempo */
    length id_stint $60;                                /* identifica cada stint de treino */
    id_stint = catx('_', session_key, driver_number, stint_number);
  run;
  proc means data=lr&s noprint nway;                    /* tempo mediano de cada stint */
    class id_stint; var lap_duration;
    output out=lrmed&s(drop=_type_ _freq_) median=med_stint;
  run;
  proc sort data=lr&s; by id_stint; run;
  data lr&s;                                            /* tira voltas lentas (tráfego, volta de resfriamento) */
    merge lr&s lrmed&s; by id_stint;
    if lap_duration <= 1.03 * med_stint;                /* até 3% acima da mediana do stint */
  run;
  proc sql;                                             /* só stints com 6+ voltas boas = simulação de corrida */
    create table lr&s as select * from lr&s
    group by id_stint having count(*) >= 6
    order by id_stint;
  quit;
  ods exclude all;
  proc glm data=lr&s;                                   /* inclinação da idade do pneu por pista, dentro de cada stint */
    absorb id_stint;                                    /* nível de cada stint (carro, piloto, combustível do início) */
    class circuito;
    model lap_duration = circuito*tyre_age / solution;  /* inclinação = desgaste + queima de combustível */
    ods output ParameterEstimates=pefp&s;
  run; quit;
  ods exclude none;
  data fpdeg&s;                                         /* uma linha por pista */
    set pefp&s;
    where index(Parameter, 'tyre_age') > 0 and index(Parameter, ' ') > 0;
    length circuito $40;
    circuito = strip(substr(Parameter, index(Parameter, ' ') + 1));
    fp_slope = Estimate;                                /* inclinação nos treinos (s/volta) */
    keep circuito fp_slope;
  run;
%mend longos;
%longos(24)
%longos(25)

/* ---------- 3. calibração em 2024: degradação de corrida = a + b x inclinação do treino ---------- */
proc sql;
  create table calib24 as                               /* pares (treino 2024, corrida 2024) */
  select f.circuito, f.fp_slope, d.deg
  from fpdeg24 f inner join deg24_orig d on f.circuito = d.circuito;
quit;
proc reg data=calib24 outest=coef_calib noprint;        /* regressão simples */
  model deg = fp_slope;
run; quit;
data _null_;                                            /* guarda a e b em macro variáveis */
  set coef_calib;
  call symputx('ca', Intercept);
  call symputx('cb', fp_slope);
run;
proc corr data=calib24 noprob outp=corr_calib noprint; var deg fp_slope; run;  /* correlação treino x corrida */
%put NOTE: calibração deg = &ca + &cb * fp_slope;

/* ---------- 4. três candidatas de entrada para 2025 ---------- */
proc sql;
  create table cand as                                  /* uma linha por pista */
  select d.circuito,
         d.deg as deg_2024,                             /* A: repetir a degradação de 2024 */
         &ca + &cb * f.fp_slope as deg_treino,          /* B: degradação prevista pelos treinos de 2025 */
         calculated deg_treino * 0.5 + d.deg * 0.5 as deg_media   /* C: média de A e B */
  from deg24_orig d inner join fpdeg25 f on d.circuito = f.circuito;
quit;

/* ---------- 5. divide 2025 em validação (1ª metade) e teste (2ª metade) ---------- */
proc sql;
  create table ordem25 as                               /* corridas avaliáveis em ordem de data */
  select distinct r.circuito, r.session_key
  from real25 r inner join cand c on r.circuito = c.circuito
  order by r.session_key;
quit;
data metade25;                                          /* 1ª metade = validação, 2ª = teste */
  set ordem25 nobs=n;
  length grupo $10;
  grupo = ifc(_n_ <= ceil(n / 2), 'validacao', 'teste');
run;

/* ---------- 6. roda o simulador com cada entrada e avalia ---------- */
%macro roda(var, nome);                                 /* var = coluna de degradação usada */
  data deg24;                                           /* o simulador lê a tabela deg24 */
    set cand(rename=(&var = deg));
    deg = max(deg, 0.005);                              /* segurança: degradação mínima */
    keep circuito deg;
  run;
  ods exclude all;
  %simula(25)                                           /* simulador */
  %avalia(25)                                           /* avaliação piloto a piloto */
  ods exclude none;
  proc sql;
    create table res_&nome as                           /* resumo por metade */
    select "&nome" as entrada length=12, m.grupo,
           count(*) as corridas,
           mean(a.acertou_paradas) as acerto_paradas format=percent8.0,
           mean(a.mae_modelo) as mae_janela format=5.2
    from aval_pista25 a inner join metade25 m on a.circuito = m.circuito
    group by m.grupo;
    create table prev25_&nome as select * from prev25;  /* guarda a previsão */
  quit;
%mend roda;
%roda(deg_2024,   A_2024)
%roda(deg_treino, B_treinos)
%roda(deg_media,  C_media)
data deg24; set deg24_orig; run;                        /* restaura a degradação oficial de 2024 */

data comparacao_entrada;
  set res_A_2024 res_B_treinos res_C_media;
run;
proc sort data=comparacao_entrada; by grupo entrada; run;
proc print data=corr_calib noobs; title 'Correlação treino x corrida (2024)'; run;
proc print data=cand noobs; title 'Degradação: 2024 x prevista pelos treinos 2025'; run;
proc print data=comparacao_entrada noobs; title 'Escolha da entrada (decidir SÓ pela validação)'; run;
title;
