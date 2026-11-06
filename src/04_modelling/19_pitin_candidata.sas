/* =====================================================================
   19_pitin_candidata.sas - correção final da identificação de pit-in
   e versão candidata definitiva (V3c). Não altera V1, V2 nem ~/f1/temporal.
   Regra única para 2023, 2024 e 2025. Uma volta é entrada no box se:
     B) a OpenF1 registra a parada (is_in_lap), OU
     C) a volta seguinte do mesmo piloto é volta de saída do box (is_pit_out_lap,
        campo do endpoint de voltas, independente do registro de paradas), OU
     A) é a última volta de um stint que não é o último do piloto,
   EXCETO quando a troca de stint ocorre sob bandeira vermelha (pneus trocados
   no grid, sem passagem pelo box) ou quando é a última volta registrada
   (abandono: o stint seguinte não tem voltas) e não há B nem C.
   Pré-requisito: sessão dos programas 14, 17 e 18 (mk&s, rc&s, v&s, real&s, eq*, macros).
   ===================================================================== */
%let home = %sysget(HOME);
%let criou = %sysfunc(dcreate(candidata, &home/f1));    /* pasta nova da versão candidata */
libname cand "&home/f1/candidata";

/* ---------- 1. classificação de cada fronteira de stint ---------- */
%macro pitin(s);
  proc sql;
    create table _mk as                                 /* todas as voltas marcadas, com sinais B e C */
    select m.session_key, m.circuito, m.driver_number, m.lap_number, m.stint_number,
           (upcase(cats(m.is_in_lap)) in ('TRUE', '1')) as sinal_b,
           (upcase(cats(m.usar2)) in ('TRUE', '1')) as limpa_v2,
           (upcase(cats(n.is_pit_out_lap)) in ('TRUE', '1')) as sinal_c
    from mk&s m left join mk&s n
         on m.session_key = n.session_key and m.driver_number = n.driver_number
        and n.lap_number = m.lap_number + 1;
    create table _st as                                 /* fim de cada stint e último stint do piloto */
    select session_key, driver_number, stint_number, max(lap_number) as fim_stint
    from _mk group by 1, 2, 3;
    create table _ul as                                 /* último stint e última volta do piloto */
    select session_key, driver_number, max(stint_number) as ult_stint, max(fim_stint) as ult_volta
    from _st group by 1, 2;
    create table _rv as                                 /* voltas de bandeira vermelha (volta do líder) */
    select distinct circuito, lap_number as volta_vermelha from rc&s
    where upcase(flag) = 'RED' and not missing(lap_number);
    create table _p1 as                                 /* sinal A (fronteira de stint) e abandono */
    select 20&s as ano, m.session_key, m.circuito, m.driver_number, m.lap_number, m.limpa_v2,
           m.sinal_b, m.sinal_c,
           (not missing(t.fim_stint) and t.stint_number < u.ult_stint) as sinal_a,
           (calculated sinal_a and m.lap_number = u.ult_volta) as abandono
    from _mk m
         left join _st t on m.session_key = t.session_key and m.driver_number = t.driver_number
                        and m.stint_number = t.stint_number and m.lap_number = t.fim_stint
         left join _ul u on m.session_key = u.session_key and m.driver_number = u.driver_number;
    create table _p2 as                                 /* fronteira a até 1 volta da bandeira vermelha */
    select p.session_key, p.driver_number, p.lap_number, max(not missing(r.volta_vermelha)) as perto_vermelha
    from _p1 p left join _rv r on p.circuito = r.circuito
         and p.lap_number between r.volta_vermelha - 1 and r.volta_vermelha + 1
    where p.sinal_a = 1 group by 1, 2, 3;
    create table pin&s as                               /* regra final */
    select p.*, (p.sinal_a and coalesce(v.perto_vermelha, 0) = 1) as troca_vermelha,
           (p.sinal_b or p.sinal_c or
            (p.sinal_a and not p.abandono and not calculated troca_vermelha)) as pit_in
    from _p1 p left join _p2 v on p.session_key = v.session_key and p.driver_number = v.driver_number
         and p.lap_number = v.lap_number;
    create table cmp&s as                               /* comparação com a regra provisória do programa 18 */
    select p.*, (not missing(f.lap_number)) as regra18
    from pin&s p left join fim&s f
         on p.session_key = f.session_key and p.driver_number = f.driver_number and p.lap_number = f.lap_number;
  quit;
  data cand.pitin_20&s; set cmp&s; run;               /* auditoria salva por volta */
%mend pitin;
%pitin(23)
%pitin(24)
%pitin(25)
data pin_all; set cmp23 cmp24 cmp25; run;

/* ---------- 2. versão candidata: voltas de V2 sem as entradas no box ---------- */
%macro voltas_c(s, eqtab);                              /* igual ao %voltas_ano do 18, com a regra final */
  data fim&s._v18; set fim&s; run;                      /* guarda a regra provisória */
  proc sql;
    create table fim&s as select session_key, driver_number, lap_number
    from pin&s where pit_in = 1;
  quit;
  %voltas_ano(&s, &eqtab)
%mend voltas_c;
%voltas_c(23, eq23)
%voltas_c(24, eq)
%voltas_c(25, eq)

/* ---------- 3. reexecução só dos modelos selecionados ---------- */
%macro exp_final(nome, treino, teste);
  data _all;
    set &treino(in=a) &teste;
    length papel_b $1;
    papel_b = ifc(a, ifc(ref_estimada = 1, 'X', 'T'), 'S');   /* V2-B: treino só com referências observadas */
  run;
  proc sql;                                             /* teste só em pistas vistas no treino (como no 18) */
    create table _vistas as select distinct circuito from _all where papel_b ne 'S';
    create table _all2 as select * from _all where papel_b ne 'S' or circuito in (select circuito from _vistas);
  quit;
  proc casutil; load data=work._all2 outcaslib="casuser" casout="tall" replace; quit;
  proc datasets lib=work nolist; delete pred_&nome; quit;
  %macro reg(mod, efeitos);
    proc regselect data=casuser.tall;
      partition role=papel_b(train='T' test='S');
      class circuito compound;
      model y = &efeitos;
      selection method=stepwise(select=sbc choose=sbc);
      output out=casuser.to copyvars=(session_key circuito driver_number lap_number y papel_b ref_estimada) pred=p;
    run;
    data _p; length modelo $8; set casuser.to; where papel_b = 'S'; modelo = "&mod"; run;
    proc append base=pred_&nome data=_p force; run;
  %mend reg;
  %reg(comB, &ef_com)                                   /* regressão com idade do pneu (V2-B) */
  %reg(semB, &ef_sem)                                   /* regressão sem idade, mesmo treino */
  data _p; set pred_&nome; where modelo = 'comB'; modelo = 'zero'; p = 0; run;   /* baseline zero */
  proc append base=pred_&nome data=_p force; run;
  data cand.pred_&nome; set pred_&nome; run;
  proc sql;
    create table r_&nome as
    select "&nome" as exp length=4, modelo, count(*) as voltas, count(distinct session_key) as corridas,
           mean(abs(y - p)) as mae format=6.3, sqrt(mean((y - p)**2)) as rmse format=6.3,
           mean(case when ref_estimada = 0 then abs(y - p) end) as mae_obs format=6.3
    from pred_&nome group by modelo;
    create table r_&nome._corr as
    select session_key, circuito, modelo, count(*) as voltas, mean(abs(y - p)) as mae
    from pred_&nome group by 1, 2, 3;
  quit;
  proc datasets lib=work nolist; delete boot_res; quit;
  %macro par(a, b, rot);
    proc sql;
      create table _g as
      select x.session_key, x.circuito, x.voltas, y.mae - x.mae as ganho
      from r_&nome._corr x inner join r_&nome._corr y on x.session_key = y.session_key
      where x.modelo = "&a" and y.modelo = "&b";
    quit;
    %boot(_g, 0, &rot)
  %mend par;
  %par(comB, semB, idade do pneu)
  %par(comB, zero, regressão vs zero)
  data boot_&nome; set boot_res; run;
  data cand.boot_&nome; set boot_&nome; run;
%mend exp_final;

%alvo(23, &e1_inf, &e1_sup, tr_c1)                      /* E1: mesmos limites de q (2023) */
%alvo(24, &e1_inf, &e1_sup, te_c1)
ods exclude all;
%exp_final(E1c, tr_c1, te_c1)
ods exclude none;
%alvo(23, &e2_inf, &e2_sup, tr_c2a)                     /* E2: mesmos limites de q (2023+2024) */
%alvo(24, &e2_inf, &e2_sup, tr_c2b)
data tr_c2; set tr_c2a tr_c2b; run;
%alvo(25, &e2_inf, &e2_sup, te_c2)
ods exclude all;
%exp_final(E2c, tr_c2, te_c2)
ods exclude none;
data cand.base_candidata; set tr_c2 te_c2; run;        /* base candidata 2023-2025 (limites E2) */

/* ---------- 4. resultados ---------- */
proc sql;
  title 'P1. Fronteiras de stint e sinais de pit-in por ano';
  select ano, sum(sinal_a) as fim_stint_nao_ultimo, sum(sinal_b) as registro_parada,
         sum(sinal_c) as antes_saida_box, sum(sinal_a and not sinal_b and not sinal_c) as so_fronteira,
         sum(troca_vermelha) as troca_vermelha, sum(abandono) as abandono, sum(pit_in) as pit_in_final
  from pin_all group by ano;
  title 'P2. Voltas afetadas: pit-in final que estava como limpa na V2 (usar2 = 1)';
  select ano, sum(pit_in and limpa_v2) as limpas_v2_reclass,
         sum(pit_in and limpa_v2 and not sinal_b) as sem_registro_parada,
         sum(pit_in and limpa_v2 and regra18) as tambem_regra18,
         sum(pit_in and limpa_v2 and not regra18) as so_regra_final,
         sum(regra18 and not pit_in and limpa_v2) as so_regra18
  from pin_all group by ano;
  title 'P3. Voltas limpas reclassificadas por pista (2023)';
  select circuito, sum(pit_in and limpa_v2) as reclass, sum(sinal_b) as registros_parada
  from pin_all where ano = 2023 group by circuito having calculated reclass > 0 order by 2 desc;
  title 'P4. Casos de exceção (troca sob vermelha ou abandono)';
  select ano, circuito, driver_number, lap_number, sinal_b, sinal_c, troca_vermelha, abandono, limpa_v2
  from pin_all where troca_vermelha or abandono order by 1, 2, 4;
  title 'P5. Tamanho das bases';
  select 'E1 treino 2023' as base, count(*) as voltas from tr_c1
  union all select 'E1 teste 2024', count(*) from te_c1
  union all select 'E2 treino 2023+2024', count(*) from tr_c2
  union all select 'E2 teste 2025', count(*) from te_c2;
quit;
proc print data=r_E1c noobs; title 'P6. E1 (2023 -> 2024), candidata'; run;
proc print data=boot_E1c noobs; title 'P7. E1 bootstrap'; run;
proc print data=r_E2c noobs; title 'P8. E2 (2023+2024 -> 2025), candidata'; run;
proc print data=boot_E2c noobs; title 'P9. E2 bootstrap'; run;
title;
