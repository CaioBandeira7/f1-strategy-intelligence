/* =====================================================================
   16_auditoria_cv_ca.sas - duas auditorias da V2 (só lê; não altera V1/V2)
   A. A referência estimada (CA) é mais estável ou comprime as diferenças
      entre pilotos? (2024, validação mascarada: pilotos com long run válido)
   B. Na validação cruzada por corrida de 2024, cada pista fica fora do
      treino. Como o SAS prevê uma pista que não viu?
      - regressão: compara a previsão real com a previsão trocando a pista
        pela pista de referência da codificação GLM (última em ordem alfabética);
        se forem iguais, a "previsão para pista nova" é a da pista de referência.
      - Forest: compara com a previsão usando pista em branco (valor ausente).
      - alternativa honesta: modelo sem termos de pista.
   Pré-requisito: sessão do programa 14 (loo_v, vl24, qa24 e macros %limites, %constroi_ca).
   ===================================================================== */
cas s2 sessopts=(timeout=7200);                          /* sessão CAS nova (a anterior expirou) */
libname casuser cas caslib="casuser" sessref=s2;        /* libref CASUSER na sessão nova */
%let ef_com = circuito compound prog tyre_age circuito*compound;   /* mesma especificação */

/* ---------- A. compressão da referência estimada ---------- */
proc sql;
  create table cmp as                                   /* centra no fim de semana: diferenças entre pilotos */
  select *, ref_a - median(ref_a) as ra_c, ref_est - median(ref_est) as re_c,
         med_piloto - median(med_piloto) as rc_c
  from loo_v group by session_key;
  create table sd_fds as                                /* dispersão entre pilotos em cada fim de semana */
  select session_key, circuito, max(sprint) as sprint, count(*) as n,
         std(ref_a) as dp_obs format=6.3, std(ref_est) as dp_est format=6.3,
         std(med_piloto) as dp_corrida format=6.3,
         calculated dp_est / calculated dp_obs as razao_dp format=6.3
  from loo_v group by session_key, circuito;
quit;
proc sort data=cmp; by sprint; run;
ods exclude all;
proc reg data=cmp outest=inc_obs rsquare noprint;       /* corrida centrada = b x referência observada centrada */
  by sprint; model rc_c = ra_c / noint;
run; quit;
proc reg data=cmp outest=inc_est rsquare noprint;       /* idem com a referência estimada */
  by sprint; model rc_c = re_c / noint;
run; quit;
proc reg data=cmp outest=inc_obs_t rsquare noprint; model rc_c = ra_c / noint; run; quit;
proc reg data=cmp outest=inc_est_t rsquare noprint; model rc_c = re_c / noint; run; quit;
ods exclude none;
data incl;                                              /* inclinação e R2 de cada referência */
  length grupo $12 referencia $10;
  set inc_obs(in=a) inc_est(in=b) inc_obs_t(in=c) inc_est_t(in=d);
  if a or c then do; referencia = 'observada'; inclinacao = ra_c; end;
  else do; referencia = 'estimada'; inclinacao = re_c; end;
  if c or d then grupo = 'todos'; else grupo = ifc(sprint = 1, 'sprint', 'normal');
  keep grupo referencia inclinacao _rsq_;
run;

/* ---------- B. validação cruzada: pistas não vistas ---------- */
proc sql noprint;
  select distinct session_key into :folds separated by ' ' from vl24;
quit;
%let nfold = &sqlobs;
proc datasets lib=work nolist; delete aud_cv aud_fo; quit;
%macro audcv;
  %do i = 1 %to &nfold;
    %let r = %scan(&folds, &i);
    %limites(session_key ne &r, f)                      /* mesmos limites por fold do programa 14 */
    %constroi_ca(24, &f_inf, &f_sup, caf)
    proc sql noprint;
      create table _cv as
      select l.session_key, l.circuito, l.driver_number, l.lap_number, l.compound, l.tyre_age, l.prog,
             l.lap_duration - c.ref_ca as y, (l.session_key = &r) as fora
      from vl24 l inner join caf c on l.session_key = c.session_key and l.driver_number = c.driver_number
      where not missing(c.ref_ca);
      select distinct circuito into :pista_fora trimmed from _cv where fora = 1;
    quit;
    %if %superq(pista_fora) = Zandvoort %then %let pista_ref = Yas Marina Circuit;
    %else %let pista_ref = Zandvoort;                   /* pista de referência da codificação GLM */
    data _cva;                                          /* teste original + teste com a pista trocada */
      set _cv;
      length papel $1; papel = ifc(fora, 'S', 'T'); troca = 0; output;
      if fora then do; circuito = "&pista_ref"; troca = 1; output; end;
    run;
    data _ftr _fte;                                     /* Forest: treino e teste (original e pista em branco) */
      set _cv;
      if not fora then output _ftr;
      else do; troca = 0; output _fte; circuito = ' '; troca = 2; output _fte; end;
    run;
    proc casutil;
      load data=work._cva outcaslib="casuser" casout="audall" replace;
      load data=work._ftr outcaslib="casuser" casout="audftr" replace;
      load data=work._fte outcaslib="casuser" casout="audfte" replace;
    quit;
    proc regselect data=casuser.audall;                 /* modelo completo (o mesmo da V2) */
      partition role=papel(train='T' test='S');
      class circuito compound;
      model y = &ef_com;
      selection method=stepwise(select=sbc choose=sbc);
      output out=casuser.ao copyvars=(session_key driver_number lap_number y troca papel) pred=p;
    run;
    proc regselect data=casuser.audall;                 /* alternativa honesta: sem termos de pista */
      partition role=papel(train='T' test='S');
      class compound;
      model y = compound prog tyre_age;
      selection method=none;
      output out=casuser.an copyvars=(session_key driver_number lap_number troca papel) pred=p_np;
    run;
    data _ao; set casuser.ao; where papel = 'S'; run;     /* traz a previsão do teste para a WORK */
    data _an; set casuser.an; where papel = 'S'; run;     /* idem, modelo sem pista */
    proc sql;
      create table _a as                                  /* junta as duas previsões por volta */
      select "&pista_fora" as pista_fora length=40, a.session_key, a.driver_number, a.lap_number,
             a.troca, a.y, a.p, n.p_np
      from _ao a inner join _an n
           on a.session_key = n.session_key and a.driver_number = n.driver_number
          and a.lap_number = n.lap_number and a.troca = n.troca;
    quit;
    proc append base=aud_cv data=_a force; run;
    proc forest data=casuser.audftr ntrees=100 seed=2025;
      input prog tyre_age / level=interval;
      input circuito compound / level=nominal;
      target y / level=interval;
      savestate rstore=casuser.audf_st;
    run;
    proc astore;
      score data=casuser.audfte rstore=casuser.audf_st out=casuser.afo
            copyvars=(session_key driver_number lap_number y troca);
    run;
    data _f; length pista_fora $40; set casuser.afo; pista_fora = "&pista_fora"; run;
    proc append base=aud_fo data=_f force; run;
  %end;
%mend audcv;
ods exclude all;
%audcv
ods exclude none;
proc sql;
  create table aud_reg as                               /* por fold: previsão real x pista trocada x sem pista */
  select a.pista_fora, mean(abs(a.p - b.p)) as dif_troca format=8.4,
         mean(abs(a.y - a.p)) as mae_completo format=6.3,
         mean(abs(a.y - a.p_np)) as mae_sem_pista format=6.3
  from aud_cv a inner join aud_cv b
       on a.session_key = b.session_key and a.driver_number = b.driver_number and a.lap_number = b.lap_number
  where a.troca = 0 and b.troca = 1
  group by a.pista_fora;
  create table aud_for as                               /* Forest: previsão real x pista em branco */
  select a.pista_fora, mean(abs(a.P_y - b.P_y)) as dif_branco format=8.4,
         mean(abs(a.y - a.P_y)) as mae_forest format=6.3
  from aud_fo a inner join aud_fo b
       on a.session_key = b.session_key and a.driver_number = b.driver_number and a.lap_number = b.lap_number
  where a.troca = 0 and b.troca = 2
  group by a.pista_fora;
quit;

/* ---------- resultados ---------- */
proc sql;
  title 'C1. Dispersão entre pilotos (desvio-padrão no fds): estimada x observada x corrida';
  select sprint, count(*) as fds, mean(dp_obs) as dp_obs format=6.3, mean(dp_est) as dp_est format=6.3,
         mean(dp_corrida) as dp_corrida format=6.3, mean(razao_dp) as razao_dp format=6.3
  from sd_fds group by sprint;
quit;
proc print data=incl noobs; title 'C2. Ritmo de corrida centrado = b x referência centrada (b = 1: sem compressão; b > 1: referência comprimida)'; run;
proc print data=sd_fds noobs; title 'C3. Dispersão por fim de semana'; var circuito sprint n dp_obs dp_est dp_corrida razao_dp; run;
proc sql;
  title 'C4. Por equipe: desvio médio da corrida (observada x estimada) e viés da estimativa';
  select team_name, count(*) as n, mean(dev_obs) as dev_obs format=6.3, mean(dev_est) as dev_est format=6.3,
         mean(erro) as vies_est format=6.3
  from loo_v group by 1 order by 1;
  title 'C5. Por pista';
  select circuito, max(sprint) as sprint, count(*) as n, mean(dev_obs) as dev_obs format=6.3,
         mean(dev_est) as dev_est format=6.3
  from loo_v group by 1 order by 1;
quit;
proc print data=aud_reg noobs; title 'C6. CV 2024 regressão: diferença ao trocar a pista não vista pela pista de referência (0 = idênticas)'; run;
proc print data=aud_for noobs; title 'C7. CV 2024 Forest: diferença ao usar pista em branco (0 = trata pista nova como ausente)'; run;
proc sql;
  title 'C8. Resumo: modelo completo x sem termos de pista (MAE médio por corrida)';
  select mean(mae_completo) as completo format=6.3, mean(mae_sem_pista) as sem_pista format=6.3,
         mean(dif_troca) as dif_troca_media format=8.4, sum(mae_sem_pista < mae_completo) as corridas_sem_pista_melhor
  from aud_reg;
quit;
title;
