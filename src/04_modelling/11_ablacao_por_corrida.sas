/* =====================================================================
   11_ablacao_por_corrida.sas - teste decisivo da idade do pneu
   Reproduz as 2 regressões lineares do Model Studio (mesma tabela, mesma
   partição, mesmas variáveis, interações de 2 fatores, stepwise) e compara
   o erro POR CORRIDA no teste de 2025, com bootstrap pareado por corrida.
   ===================================================================== */
cas mysess;                                             /* abre a sessão CAS */
caslib _all_ assign;                                    /* cria os libnames das caslibs */
%let tab = casuser.F1_2024_PARA_MODEL_STUDIO;           /* a MESMA tabela usada no Model Studio */

/* ---------- 1. as duas regressões (iguais às do Model Studio) ---------- */
%macro reglin(nome, efeitos);                           /* nome do modelo e lista de efeitos */
  proc regselect data=&tab;
    partition role=particao(train='1' validate='2' test='0');   /* 1 treino, 2 validação, 0 teste */
    class circuito compound;                            /* pista e composto são categorias */
    model y = &efeitos;                                 /* efeitos principais + interações de 2 fatores */
    selection method=stepwise(select=sbc choose=sbc);   /* stepwise, padrão do nó Linear Regression */
    output out=casuser.p_&nome copyvars=(session_key circuito particao y) pred=p_y;   /* previsões */
  run;
%mend reglin;
/* "Two-factor interactions" do Model Studio cruza só variáveis de classe (pista x composto) */
%reglin(com_idade, circuito compound prog tyre_age circuito*compound)   /* C: com idade do pneu */
%reglin(sem_idade, circuito compound prog circuito*compound)            /* B: sem idade (única diferença) */

/* ---------- 2. métricas por partição, em segundos (MAE e RMSE) ---------- */
%macro metricas(nome);
  proc sql;
    create table m_&nome as
    select "&nome" as modelo length=10,
           case particao when 1 then '1 treino 2024' when 2 then '2 validacao 2024'
                else '3 teste 2025' end as particao length=16,
           count(*) as voltas,                          /* confere que as bases são iguais */
           mean(abs(y - p_y)) as mae_s format=6.3,      /* erro absoluto médio (s) */
           sqrt(mean((y - p_y)**2)) as rmse_s format=6.3   /* raiz do erro quadrático médio (s) */
    from casuser.p_&nome group by 2;
  quit;
%mend metricas;
%metricas(com_idade)
%metricas(sem_idade)
data metricas; set m_com_idade m_sem_idade; run;        /* tabela única */

/* ---------- 3. MAE por corrida no teste (a corrida é a unidade) ---------- */
%macro por_corrida(nome);
  proc sql;
    create table c_&nome as
    select session_key, circuito, count(*) as voltas,
           mean(abs(y - p_y)) as mae_&nome
    from casuser.p_&nome where particao = 0             /* só o teste de 2025 */
    group by session_key, circuito;
  quit;
%mend por_corrida;
%por_corrida(com_idade)
%por_corrida(sem_idade)
proc sql;
  create table corrida as                               /* uma linha por corrida */
  select a.session_key, a.circuito, a.voltas,
         a.mae_com_idade, b.mae_sem_idade,
         b.mae_sem_idade - a.mae_com_idade as ganho format=6.3   /* positivo = idade do pneu ajuda */
  from c_com_idade a inner join c_sem_idade b on a.session_key = b.session_key
  order by ganho desc;
quit;

/* ---------- 4. bootstrap pareado por corrida (1.000 reamostras) ---------- */
proc surveyselect data=corrida out=boot method=urs samprate=1 outhits reps=1000 seed=2025 noprint;
run;                                                    /* sorteia corridas com reposição */
proc means data=boot noprint nway;                      /* ganho médio em cada reamostra */
  class replicate; var ganho;
  output out=boot_m mean=ganho;
run;
proc univariate data=boot_m noprint;                    /* intervalo de 95% */
  var ganho;
  output out=ic mean=ganho_medio pctlpts=2.5 97.5 pctlpre=ic_;
run;
proc sql noprint;                                       /* em quantas corridas a idade ajuda */
  select sum(ganho > 0), count(*) into :n_melhor trimmed, :n_total trimmed from corrida;
quit;

/* ---------- 5. resultados ---------- */
proc print data=metricas noobs; title 'MAE e RMSE (segundos) por partição'; run;
proc print data=corrida noobs; title 'MAE por corrida no teste 2025 (ganho = sem - com)'; run;
proc print data=ic noobs;
  title "Ganho da idade do pneu: média por corrida e IC 95% bootstrap (melhor em &n_melhor de &n_total corridas)";
run;
title;
