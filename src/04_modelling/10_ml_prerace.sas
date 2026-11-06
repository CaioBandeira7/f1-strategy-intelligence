/* =====================================================================
   10_ml_prerace.sas - ML de tempo de volta SEM informação futura
   Tarefa (definida antes de modelar):
     "Antes da largada, prever o tempo de cada volta de corrida,
      relativo ao ritmo do piloto nos treinos livres do mesmo fim de semana."
   Alvo  : y = tempo da volta na corrida - ritmo mediano do piloto nas
           simulações de corrida dos treinos (conhecido antes da corrida)
   Entram: pista, composto, idade do pneu, progresso da corrida (voltas
           conhecidas no plano). Clima da corrida NÃO entra (não é conhecido antes).
   Ablação: B = sem idade do pneu | C = com idade do pneu | D = GLM igual ao C
   Incerteza: erro por corrida + bootstrap por corrida (1.000 reamostras)
   Pré-requisito: rodar 08 (cria lr24, lr25, real24, real25, v24, v25)
   ===================================================================== */
%include "~/f1/08_degradacao_treinos.sas";              /* refaz toda a base (inclui 01_02, 03 e 04) */

/* ---------- 1. referência pré-corrida: ritmo do piloto nos treinos ---------- */
%macro ref(s);
  proc means data=lr&s noprint nway;                    /* mediana das voltas boas das simulações de corrida */
    class race_session_key driver_number;               /* por corrida (fim de semana) e piloto */
    var lap_duration;
    output out=ref&s(drop=_type_ rename=(_freq_=n_ref race_session_key=session_key)) median=ritmo_treino;
  run;
%mend ref;
%ref(24)
%ref(25)

/* ---------- 2. base: voltas limpas da corrida + referência ---------- */
%macro base(s);
  proc sql;
    create table pr&s as
    select v.session_key, v.circuito, v.driver_number, v.lap_number, v.compound, v.tyre_age,
           v.lap_number / r.voltas_corrida as prog,     /* progresso da corrida (combustível) */
           v.lap_duration - f.ritmo_treino as y         /* alvo sem informação futura */
    from v&s v
         inner join ref&s f on v.session_key = f.session_key and v.driver_number = f.driver_number
         inner join (select distinct session_key, voltas_corrida from real&s) r on v.session_key = r.session_key
    where v.usar2 = 1 and v.compound in ('SOFT','MEDIUM','HARD')
          and f.n_ref >= 6;                             /* referência com pelo menos 6 voltas */
  quit;
%mend base;
%base(24)
%base(25)
proc sql;                                               /* teste justo: só pistas vistas no treino */
  create table pr25 as select * from pr25 where circuito in (select distinct circuito from pr24);
quit;
proc means data=pr24 noprint nway;                      /* referência A: média do alvo por pista em 2024 */
  class circuito; var y; output out=baseA(drop=_type_ _freq_) mean=yA;
run;

/* ---------- 3. modelos no CAS (treino 2024, teste 2025) ---------- */
cas mysess;
caslib _all_ assign;
proc casutil;
  load data=work.pr24 outcaslib="casuser" casout="pr24" replace;
  load data=work.pr25 outcaslib="casuser" casout="pr25" replace;
quit;

%macro floresta(nome, entradas);                        /* floresta com um conjunto de variáveis */
  proc forest data=casuser.pr24 ntrees=200 maxdepth=12 seed=2025;
    input &entradas / level=interval;
    input circuito compound / level=nominal;
    target y / level=interval;
    savestate rstore=casuser.&nome._st;
  run;
  proc astore;
    score data=casuser.pr25 rstore=casuser.&nome._st out=casuser.p_&nome copyvars=(_all_);
  run;
%mend floresta;
%floresta(B_sem_idade, prog)                            /* B: sem idade do pneu */
%floresta(C_com_idade, prog tyre_age)                   /* C: com idade do pneu */

proc regselect data=casuser.pr24;                       /* D: GLM com as mesmas variáveis do C */
  class circuito compound;
  model y = circuito compound circuito*prog compound*tyre_age circuito*tyre_age;
  selection method=none;
  code file="&pasta/glm_prerace.sas";
run;
data casuser.p_D_glm;
  set casuser.pr25;
  %include "&pasta/glm_prerace.sas";
run;

/* ---------- 4. erro por corrida de cada modelo ---------- */
%macro erro(tab, nome, pred);
  proc sql;
    create table e_&nome as
    select session_key, circuito, "&nome" as modelo length=14,
           mean(abs(y - &pred)) as mae, count(*) as voltas
    from &tab group by session_key, circuito;
  quit;
%mend erro;
proc sql;                                               /* referências */
  create table p_ref as select p.*, 0 as p0, coalesce(a.yA, 0) as pA
  from pr25 p left join baseA a on p.circuito = a.circuito;
quit;
%erro(p_ref, Ref_zero, p0)
%erro(p_ref, A_media_pista, pA)
%erro(casuser.p_B_sem_idade, B_sem_idade, P_y)
%erro(casuser.p_C_com_idade, C_com_idade, P_y)
%erro(casuser.p_D_glm, D_glm, P_y)
data erros;                                             /* uma linha por corrida e modelo */
  set e_Ref_zero e_A_media_pista e_B_sem_idade e_C_com_idade e_D_glm;
run;

/* ---------- 5. bootstrap por corrida (a corrida é a unidade, não a volta) ---------- */
proc sql;
  create table corridas as select distinct session_key from erros;
quit;
proc surveyselect data=corridas out=boot method=urs samprate=1 outhits reps=1000 seed=2025 noprint;
run;                                                    /* 1.000 reamostras de corridas com reposição */
proc sql;
  create table boot_mae as                              /* MAE médio por reamostra e modelo */
  select b.replicate, e.modelo, mean(e.mae) as mae
  from boot b inner join erros e on b.session_key = e.session_key
  group by b.replicate, e.modelo;
  create table boot_dif as                              /* diferenças pareadas na mesma reamostra */
  select a.replicate,
         a.mae - b.mae as ganho_idade,                  /* B - C: quanto a idade do pneu ajuda */
         c.mae - b.mae as ganho_vs_media,               /* A - C: ganho sobre a referência por pista */
         d.mae - b.mae as floresta_vs_glm               /* D - C: floresta vs GLM */
  from boot_mae a
       inner join boot_mae b on a.replicate = b.replicate and b.modelo = 'C_com_idade'
       inner join boot_mae c on a.replicate = c.replicate and c.modelo = 'A_media_pista'
       inner join boot_mae d on a.replicate = d.replicate and d.modelo = 'D_glm'
  where a.modelo = 'B_sem_idade';
quit;
proc univariate data=boot_mae noprint;                  /* intervalo de 95% de cada modelo */
  class modelo; var mae;
  output out=ic_mae mean=mae_medio pctlpts=2.5 97.5 pctlpre=p;
run;
proc univariate data=boot_dif noprint;                  /* intervalo de 95% das diferenças */
  var ganho_idade ganho_vs_media floresta_vs_glm;
  output out=ic_dif mean=m_idade m_media m_glm
         pctlpts=2.5 97.5 pctlpre=idade_ media_ glm_;
run;

proc sql;                                               /* tamanho da base */
  title 'Base pré-corrida';
  select '2024 (treino)' as base, count(*) as voltas, count(distinct session_key) as corridas from pr24
  union all select '2025 (teste)', count(*), count(distinct session_key) from pr25;
quit;
proc print data=ic_mae noobs; title 'MAE em 2025 por modelo (média por corrida, IC 95% bootstrap por corrida)'; run;
proc print data=ic_dif noobs; title 'Diferenças pareadas (positivo = o modelo C é melhor)'; run;
title;

/* ---------- 6. tabela para o Model Studio (Build Models) ---------- */
data prerace;                                           /* 2024 + 2025 empilhados com papel de partição */
  set pr24(in=t) pr25;
  ano = ifn(t, 2024, 2025);
  if not t then particao = 0;                           /* 0 = teste: 2025, nunca usado para treinar */
  else if mod(session_key, 5) = 0 then particao = 2;    /* 2 = validação: ~20% das corridas de 2024 (corrida inteira) */
  else particao = 1;                                    /* 1 = treino: restante de 2024 */
run;
proc casutil;                                           /* sobe e promove para o Model Studio enxergar */
  droptable casdata="F1_PRERACE" incaslib="casuser" quiet;
  load data=work.prerace outcaslib="casuser" casout="F1_PRERACE" promote;
quit;
proc freq data=prerace; tables ano*particao / nopercent norow nocol; title 'Partições para o Model Studio'; run;
title;
