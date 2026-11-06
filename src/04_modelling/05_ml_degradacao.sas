/* =====================================================================
   05_ml_degradacao.sas - (4) curva de degradação com machine learning
   Alvo: delta = tempo da volta - tempo mediano daquele piloto naquela corrida
         (tira o nível do carro/piloto; sobra o efeito de pneu, combustível e clima)
   Treino: 2024   |   Teste: 2025 (nunca visto pelo modelo)
   Modelos: GLM (regressão linear), Gradient Boosting, Floresta
   ===================================================================== */

%macro base_ml(s);                                      /* monta a base de ML de um ano */
  proc sql;
    create table tmp&s as                               /* voltas usadas + clima */
    select v.session_key, v.circuito, v.driver_number, v.lap_number, v.compound,
           v.tyre_age, v.lap_duration,
           c.track_temperature, c.air_temperature, c.humidity,   /* clima no momento da volta */
           r.voltas_corrida as L,                       /* nº de voltas da corrida */
           v.lap_number / r.voltas_corrida as prog      /* progresso da corrida (0 a 1) = combustível */
    from v&s v
         left join cl&s c on v.session_key = c.session_key
                         and v.driver_number = c.driver_number
                         and v.lap_number = c.lap_number
         inner join (select distinct session_key, voltas_corrida from real&s) r
                 on v.session_key = r.session_key
    where v.usar2 = 1 and v.compound in ('SOFT','MEDIUM','HARD')  /* voltas limpas de pneu seco */
    order by session_key, driver_number;                /* ordem para o BY abaixo */
  quit;
  proc means data=tmp&s noprint nway;                   /* tempo mediano de cada piloto em cada corrida */
    class session_key driver_number;
    var lap_duration;
    output out=med&s(drop=_type_) median=volta_med n=n_voltas;
  run;
  data ml&s;                                            /* base final */
    merge tmp&s med&s;                                  /* junta a mediana em cada volta */
    by session_key driver_number;
    if n_voltas >= 10;                                  /* piloto precisa de 10+ voltas limpas */
    delta = lap_duration - volta_med;                   /* alvo: volta - mediana do piloto */
  run;
%mend base_ml;
%base_ml(24)                                            /* treino */
%base_ml(25)                                            /* teste */

proc sql;                                               /* teste justo: só pistas que o modelo viu em 2024 */
  create table ml25 as select * from ml25
  where circuito in (select distinct circuito from ml24);
quit;
data ml24;                                              /* separa 20% de 2024 para validação interna */
  set ml24;
  valid = (mod(session_key + driver_number, 5) = 0);    /* corrida-piloto inteira vai para um lado só */
run;

cas mysess;                                             /* abre sessão CAS */
caslib _all_ assign;                                    /* deixa as caslibs visíveis como bibliotecas */
proc casutil;                                           /* sobe as bases para a memória do CAS */
  load data=work.ml24 outcaslib="casuser" casout="ml24" replace;
  load data=work.ml25 outcaslib="casuser" casout="ml25" replace;
quit;

/* ---------- modelo 1: GLM (interpretável) ---------- */
proc regselect data=casuser.ml24;                       /* regressão linear no CAS */
  partition rolevar=valid(train='0' validate='1');      /* treino x validação */
  class circuito compound;                              /* variáveis de classe */
  model delta = compound circuito*prog                  /* ritmo do composto + combustível por pista */
                compound*tyre_age circuito*tyre_age     /* degradação por composto e por pista */
                track_temperature track_temperature*tyre_age;  /* calor muda o nível e o desgaste */
  selection method=none;                                /* usa todos os termos */
  code file="&pasta/glm_score.sas";                     /* gera código para pontuar 2025 */
run;
data casuser.p_glm25;                                   /* pontua 2025 com o GLM */
  set casuser.ml25;
  %include "&pasta/glm_score.sas";                      /* cria P_delta */
run;

/* ---------- modelo 2: Gradient Boosting (com e sem clima) ---------- */
%macro gb(nome, clima);                                 /* treina um gradient boosting */
  proc gradboost data=casuser.ml24 ntrees=300 learningrate=0.1 maxdepth=5
                 samplingrate=0.8 seed=2025;            /* parâmetros fixos (sem autotune, para ser reprodutível) */
    partition rolevar=valid(train='0' validate='1');    /* treino x validação */
    input tyre_age prog &clima / level=interval;        /* variáveis numéricas */
    input circuito compound / level=nominal;            /* variáveis de categoria */
    target delta / level=interval;                      /* alvo */
    savestate rstore=casuser.&nome._store;              /* guarda o modelo */
  run;
  proc astore;                                          /* pontua 2025 */
    score data=casuser.ml25 rstore=casuser.&nome._store
          out=casuser.p_&nome.25 copyvars=(_all_);
  run;
%mend gb;
%gb(gb, track_temperature air_temperature humidity)     /* com clima */
%gb(gb_sem_clima, )                                     /* sem clima: mostra quanto o clima ajuda */

/* ---------- modelo 3: Floresta ---------- */
proc forest data=casuser.ml24 ntrees=200 maxdepth=12 seed=2025;  /* floresta aleatória */
  partition rolevar=valid(train='0' validate='1');
  input tyre_age prog track_temperature air_temperature humidity / level=interval;
  input circuito compound / level=nominal;
  target delta / level=interval;
  savestate rstore=casuser.rf_store;
run;
proc astore;
  score data=casuser.ml25 rstore=casuser.rf_store out=casuser.p_rf25 copyvars=(_all_);
run;

/* ---------- comparação no teste (2025) ---------- */
%macro erro(tab, nome);                                 /* erro médio de um modelo em 2025 */
  proc sql;
    create table e_&nome as
    select "&nome" as modelo length=20,
           mean(abs(delta - P_delta)) as mae format=6.3,          /* erro absoluto médio (s) */
           sqrt(mean((delta - P_delta)**2)) as rmse format=6.3,   /* raiz do erro quadrático (s) */
           count(*) as voltas
    from &tab where P_delta ne .;
  quit;
%mend erro;
%erro(casuser.p_glm25, GLM)
%erro(casuser.p_gb25, GradBoost)
%erro(casuser.p_gb_sem_clima25, GradBoost_sem_clima)
%erro(casuser.p_rf25, Floresta)
proc sql;                                               /* chute ingênuo: prever delta = 0 (o ritmo mediano) */
  create table e_base as
  select 'Ingenuo (delta=0)' as modelo length=20,
         mean(abs(delta)) as mae format=6.3, sqrt(mean(delta**2)) as rmse format=6.3, count(*) as voltas
  from ml25;
quit;
data comparacao_ml;                                     /* junta tudo */
  set e_base e_GLM e_GradBoost e_GradBoost_sem_clima e_Floresta;
run;
proc print data=comparacao_ml noobs; title 'Erro em 2025 (voltas nunca vistas)'; run;
title;

/* ---------- extra: a degradação mudou de 2024 para 2025? ---------- */
proc sql;                                               /* compara a inclinação por pista nos dois anos */
  title 'Degradação por pista: 2024 (usada na previsão) x 2025 (real)';
  select a.circuito, a.deg as deg_2024 format=6.3, b.deg as deg_2025 format=6.3,
         b.deg - a.deg as diferenca format=6.3
  from deg24 a inner join deg25 b on a.circuito = b.circuito
  order by a.circuito;
  title;
quit;
