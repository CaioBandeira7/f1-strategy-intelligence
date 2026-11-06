/* =====================================================================
   18_validacao_temporal.sas - "mesma pista, temporada seguinte"
   E1 (desenvolvimento): treina em 2023 -> avalia em 2024.
       2024 já foi usado para comparar alternativas (V2, CA): NÃO é teste intocado.
   E2 (histórico): treina em 2023+2024 -> avalia em 2025 (2025 já examinado).
   Regras:
     - parâmetros globais (limites de q da referência CA, modelos, médias)
       são ajustados SÓ nos anos de treino;
     - informação pré-corrida do fim de semana avaliado (melhor volta, q_fds)
       pode ser usada, porque existe antes da largada;
     - entrada no box = registro de parada OU última volta de um stint que não é o último
       (a OpenF1 não tem paradas nas 6 primeiras corridas de 2023);
     - escopo do teste: pistas presentes no treino; combinações pista x
       composto não vistas são marcadas e avaliadas à parte.
   Não altera V1, V2 nem benchmarks. Saída: ~/f1/temporal.
   Pré-requisito: sessão com os programas 14 e 17 (macros e tabelas de 2023-2025).
   ===================================================================== */
options locale=en_US validvarname=v7;
%let pasta = ~/f1;
%let home  = %sysget(HOME);
%let criou = %sysfunc(dcreate(temporal, &home/f1));
libname tmp "&home/f1/temporal";
%let ef_com = circuito compound prog tyre_age circuito*compound;
%let ef_sem = circuito compound prog circuito*compound;

/* ---------- 0. 2023 com as mesmas etapas da V2 ---------- */
%prepara(23)                                            /* melhor volta, sprint, q da referência A */
%macro voltas_ano(s, eqtab);                            /* igual ao %voltas do programa 14, com a tabela de equipes */
  proc sql;
    create table vt&s as
    select v.session_key, v.circuito, v.driver_number, v.lap_number, v.compound, v.tyre_age, v.lap_duration,
           v.lap_number / r.voltas_corrida as prog, e.team_name, coalesce(sp.sprint, 0) as sprint
    from v&s v
         inner join (select distinct session_key, voltas_corrida from real&s) r on v.session_key = r.session_key
         left join &eqtab e on v.session_key = e.session_key and v.driver_number = e.driver_number
         left join sprint&s sp on v.session_key = sp.session_key
         left join fim&s z on v.session_key = z.session_key and v.driver_number = z.driver_number
                          and v.lap_number = z.lap_number
    where v.usar2 = 1 and v.compound in ('SOFT','MEDIUM','HARD')
          and missing(z.lap_number);                    /* regra temporal: fim de stint (não o último) = entrada no box */
    create table ult&s as select session_key, driver_number, max(lap_number) as ultima from v&s group by 1, 2;
    create table amar&s as select distinct circuito, lap_number from rc&s
      where upcase(flag) in ('YELLOW', 'DOUBLE YELLOW') and not missing(lap_number);
    create table inc&s as select distinct circuito, lap_number, message from rc&s
      where (index(upcase(message), 'INCIDENT') > 0 or index(upcase(message), 'PENALTY') > 0) and not missing(lap_number);
    create table medp&s as select session_key, driver_number, median(lap_duration) as med_piloto from vt&s group by 1, 2;
    create table incl&s as select l.session_key, l.driver_number, l.lap_number,
           max(index(upcase(i.message), catx(' ', 'CAR', l.driver_number, '(')) > 0) as incidente
      from vt&s l inner join inc&s i on l.circuito = i.circuito and l.lap_number = i.lap_number group by 1, 2, 3;
    create table ft&s as
    select l.session_key, l.driver_number, l.lap_number,
           (l.lap_number = u.ultima and coalesce(t.terminou, 1) = 0) as volta_pre_abandono,
           (not missing(a.lap_number)) as bandeira_amarela, coalesce(n.incidente, 0) as incidente,
           (l.lap_duration > 1.10 * m.med_piloto) as volta_lenta_110
    from vt&s l
         left join ult&s u on l.session_key = u.session_key and l.driver_number = u.driver_number
         left join (select session_key, driver_number, terminou from real&s) t
              on l.session_key = t.session_key and l.driver_number = t.driver_number
         left join amar&s a on l.circuito = a.circuito and l.lap_number = a.lap_number
         left join incl&s n on l.session_key = n.session_key and l.driver_number = n.driver_number and l.lap_number = n.lap_number
         left join medp&s m on l.session_key = m.session_key and l.driver_number = m.driver_number;
  quit;
%mend voltas_ano;
%voltas_ano(23, eq23)                                   /* 2023 */
%voltas_ano(24, eq)                                     /* 2024 com a mesma regra */
%voltas_ano(25, eq)                                     /* 2025 com a mesma regra */

%macro limites_t(tab, pref);                            /* limites de q a partir de qualquer tabela de treino */
  proc univariate data=&tab noprint; var q_a; output out=_lim q1=q1 q3=q3 n=n; run;
  data _null_; set _lim;
    call symputx("&pref._inf", q1 - 3 * (q3 - q1), 'G');
    call symputx("&pref._sup", q3 + 3 * (q3 - q1), 'G');
    call symputx("&pref._n", n, 'G');
  run;
%mend limites_t;

%macro alvo(s, inf, sup, saida);                        /* voltas do ano s com referência CA (limites dados) */
  %constroi_ca(&s, &inf, &sup, _ca&s)
  proc sql;
    create table &saida as
    select l.*, 2000 + &s as ano, c.ref_ca, coalesce(c.ref_estimada, 0) as ref_estimada,
           c.qualidade_referencia, l.lap_duration - c.ref_ca as y,
           max(f.volta_pre_abandono, f.bandeira_amarela, f.incidente, f.volta_lenta_110) as atipica
    from vt&s l
         inner join _ca&s c on l.session_key = c.session_key and l.driver_number = c.driver_number
         left join ft&s f on l.session_key = f.session_key and l.driver_number = f.driver_number
                           and l.lap_number = f.lap_number
    where not missing(c.ref_ca);
  quit;
%mend alvo;

/* ---------- 1. experimento genérico ---------- */
%macro experimento(nome, treino, teste);
  data _all;                                            /* treino + teste; teste só em pistas vistas no treino */
    set &treino(in=a) &teste;
    length papel papel_b $1;
    papel = ifc(a, 'T', 'S');
    papel_b = ifc(a and ref_estimada = 1, 'X', papel);  /* variante B: treina só com referências observadas */
  run;
  proc sql;
    create table _vistas as select distinct circuito from _all where papel = 'T';
    create table _combos as select distinct circuito, compound from _all where papel = 'T';
    create table _allc as
    select a.*, (not missing(c.compound)) as combo_visto
    from _all a left join _combos c on a.circuito = c.circuito and a.compound = c.compound
    where a.papel = 'T' or a.circuito in (select circuito from _vistas);
  quit;
  data _all; set _allc; run;
  data _tr _te; set _all; if papel = 'T' then output _tr; else output _te; run;
  proc casutil;
    load data=work._all outcaslib="casuser" casout="tall" replace;
    load data=work._tr  outcaslib="casuser" casout="ttr"  replace;
    load data=work._te  outcaslib="casuser" casout="tte"  replace;
  quit;
  proc datasets lib=work nolist; delete pred_&nome; quit;
  %macro reg(mod, papelvar, efeitos);
    proc regselect data=casuser.tall;
      partition role=&papelvar(train='T' test='S');
      class circuito compound;
      model y = &efeitos;
      selection method=stepwise(select=sbc choose=sbc);
      output out=casuser.to copyvars=(session_key driver_number lap_number y papel) pred=p;
    run;
    data _p; length modelo $8; set casuser.to; where papel = 'S'; modelo = "&mod"; keep modelo session_key driver_number lap_number y p; run;
    proc append base=pred_&nome data=_p force; run;
  %mend reg;
  %reg(com,  papel,   &ef_com)
  %reg(sem,  papel,   &ef_sem)
  %reg(comB, papel_b, &ef_com)
  %reg(semB, papel_b, &ef_sem)
  proc forest data=casuser.ttr ntrees=100 seed=2025;
    input prog tyre_age / level=interval;
    input circuito compound / level=nominal;
    target y / level=interval;
    savestate rstore=casuser.tf_st;
  run;
  proc astore;
    score data=casuser.tte rstore=casuser.tf_st out=casuser.tfo copyvars=(session_key driver_number lap_number y);
  run;
  data _p; length modelo $8; set casuser.tfo; modelo = 'forest'; p = P_y; keep modelo session_key driver_number lap_number y p; run;
  proc append base=pred_&nome data=_p force; run;
  proc sql;                                             /* baselines: zero e média pista x composto do treino */
    create table _m1 as select circuito, compound, mean(y) as m1 from _tr group by 1, 2;
    create table _m2 as select circuito, mean(y) as m2 from _tr group by 1;
    create table _p as
    select 'zero' as modelo length=8, t.session_key, t.driver_number, t.lap_number, t.y, 0 as p from _te t
    union all
    select 'media_pc', t.session_key, t.driver_number, t.lap_number, t.y, coalesce(a.m1, b.m2, 0)
    from _te t left join _m1 a on t.circuito = a.circuito and t.compound = a.compound
               left join _m2 b on t.circuito = b.circuito;
  quit;
  proc append base=pred_&nome data=_p force; run;
  proc sql;                                             /* atributos do teste */
    create table pred_&nome._x as
    select p.*, t.circuito, t.compound, t.tyre_age, t.ref_estimada, t.atipica, t.combo_visto, t.sprint
    from pred_&nome p inner join _te t
         on p.session_key = t.session_key and p.driver_number = t.driver_number and p.lap_number = t.lap_number;
  quit;
  data pred_&nome; set pred_&nome._x; run;
  data tmp.pred_&nome; set pred_&nome; run;
%mend experimento;

%macro resumo(nome);                                    /* métricas, ganho pareado, bootstrap e LORO */
  proc sql;
    create table r_&nome._geral as
    select "&nome" as exp length=4, modelo, count(*) as voltas, count(distinct session_key) as corridas,
           mean(abs(y - p)) as mae format=6.3, sqrt(mean((y - p)**2)) as rmse format=6.3
    from pred_&nome group by modelo;
    create table r_&nome._grupo as
    select "&nome" as exp length=4, modelo, ref_estimada, atipica, combo_visto, count(*) as voltas,
           mean(abs(y - p)) as mae format=6.3
    from pred_&nome where modelo in ('com', 'comB', 'sem', 'forest', 'media_pc')
    group by modelo, ref_estimada, atipica, combo_visto;
    create table r_&nome._corr as
    select session_key, circuito, modelo, count(*) as voltas, mean(abs(y - p)) as mae
    from pred_&nome group by 1, 2, 3;
  quit;
  proc datasets lib=work nolist; delete boot_res; quit;
  %macro par(a, b, rot);                                /* ganho = MAE(b) - MAE(a), positivo = a é melhor */
    proc sql;
      create table _g as
      select x.session_key, x.circuito, x.voltas, y.mae - x.mae as ganho
      from r_&nome._corr x inner join r_&nome._corr y on x.session_key = y.session_key
      where x.modelo = "&a" and y.modelo = "&b";
    quit;
    %boot(_g, 0, &rot peso igual)
    %boot(_g, 1, &rot peso por voltas)
    proc sql;                                           /* LORO: tira uma corrida por vez (sensibilidade) */
      create table _l as select a.circuito, mean(b.ganho) as g from _g a inner join _g b
      on a.session_key ne b.session_key group by a.circuito;
      create table _l2 as select "&rot" as analise length=40, min(g) as loro_min format=6.3,
             max(g) as loro_max format=6.3, sum(g <= 0) as loro_nao_positivo from _l;
    quit;
    proc append base=loro_&nome data=_l2 force; run;
  %mend par;
  proc datasets lib=work nolist; delete loro_&nome; quit;
  %par(com,  sem,      idade do pneu (todas as refs))
  %par(comB, semB,     idade do pneu (só observadas))
  %par(com,  forest,   regressão vs forest)
  %par(com,  media_pc, regressão vs média pista x composto)
  %par(com,  zero,     regressão vs zero)
  data boot_&nome; set boot_res; run;
  data tmp.boot_&nome; set boot_&nome; run;
%mend resumo;

/* ---------- 2. E1: treino 2023 -> avaliação 2024 ---------- */
%limites_t(qa23, e1)                                    /* limites de q aprendidos SÓ em 2023 */
%alvo(23, &e1_inf, &e1_sup, tr_e1)
%alvo(24, &e1_inf, &e1_sup, te_e1)                      /* 2024: limites de 2023 + informação do fds de 2024 */
ods exclude all;
%experimento(E1, tr_e1, te_e1)
ods exclude none;
%resumo(E1)

/* ---------- 3. E2: treino 2023+2024 -> avaliação histórica 2025 ---------- */
data qa2324; set qa23 qa24; run;
%limites_t(qa2324, e2)                                  /* limites de q aprendidos em 2023+2024 */
%alvo(23, &e2_inf, &e2_sup, tr_e2a)
%alvo(24, &e2_inf, &e2_sup, tr_e2b)
data tr_e2; set tr_e2a tr_e2b; run;
%alvo(25, &e2_inf, &e2_sup, te_e2)
ods exclude all;
%experimento(E2, tr_e2, te_e2)
ods exclude none;
%resumo(E2)

/* ---------- 4. resultados ---------- */
proc sql;
  title "V1. Parâmetros: limites de q E1 (2023, n=&e1_n): &e1_inf a &e1_sup | E2 (2023+2024, n=&e2_n): &e2_inf a &e2_sup";
  select 'E1 treino 2023' as base, count(*) as voltas, count(distinct session_key) as corridas, sum(ref_estimada) as voltas_ref_est from tr_e1
  union all select 'E1 teste 2024', count(*), count(distinct session_key), sum(ref_estimada) from te_e1
  union all select 'E2 treino 2023+2024', count(*), count(distinct session_key), sum(ref_estimada) from tr_e2
  union all select 'E2 teste 2025', count(*), count(distinct session_key), sum(ref_estimada) from te_e2;
quit;
proc print data=r_E1_geral noobs; title 'V2. E1 (2023 -> 2024): MAE/RMSE por modelo (2024 é validação de desenvolvimento, não teste intocado)'; run;
proc print data=boot_E1 noobs; title 'V3. E1: comparações pareadas por corrida e IC 95% bootstrap'; run;
proc print data=loro_E1 noobs; title 'V4. E1: sensibilidade retirando uma corrida por vez'; run;
proc print data=r_E1_grupo noobs; title 'V5. E1: por tipo de referência, voltas atípicas e combinação pista x composto vista no treino'; run;
proc print data=r_E2_geral noobs; title 'V6. E2 (2023+2024 -> 2025, ano já examinado): MAE/RMSE por modelo'; run;
proc print data=boot_E2 noobs; title 'V7. E2: comparações pareadas por corrida e IC 95% bootstrap'; run;
proc print data=loro_E2 noobs; title 'V8. E2: sensibilidade retirando uma corrida por vez'; run;
proc print data=r_E2_grupo noobs; title 'V9. E2: por tipo de referência, atípicas e combinação vista'; run;
proc sql;
  title 'V10. E1: MAE por corrida (regressão com idade, sem idade, forest, média pista x composto)';
  select circuito, max(case when modelo = 'com' then mae end) as com format=6.3,
         max(case when modelo = 'sem' then mae end) as sem format=6.3,
         max(case when modelo = 'forest' then mae end) as forest format=6.3,
         max(case when modelo = 'media_pc' then mae end) as media_pc format=6.3
  from r_E1_corr group by circuito order by circuito;
quit;
title;
