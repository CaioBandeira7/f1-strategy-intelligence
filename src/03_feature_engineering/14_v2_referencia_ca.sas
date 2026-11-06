/* =====================================================================
   14_v2_referencia_ca.sas - V2 experimental (V1 permanece intacta)
   Referência CA:
     - observada: mediana das voltas de simulação de corrida (= V1), se
       a razão q = referência / melhor volta do piloto estiver entre os
       limites aprendidos SÓ em 2024 (Q1 - 3 IQR, Q3 + 3 IQR);
     - estimada: melhor volta do piloto x q_fds, onde q_fds = mediana de q
       dos pilotos com referência observada válida NO MESMO fim de semana
       (informação de treino, disponível antes da largada).
   Parâmetros globais aprendidos: só os limites de q (2024).
   Informação do fim de semana (pré-corrida): melhor volta, q_fds.
   Experimentos: V1 (benchmark), V2-A (treina com observadas + estimadas),
   V2-B (treina só com observadas). ref_estimada NÃO é preditora.
   2025 já foi examinado no desenvolvimento: aqui só é avaliado.
   ===================================================================== */
options locale=en_US validvarname=v7;                   /* ponto decimal e nomes válidos */
%let pasta = ~/f1;                                      /* pasta do projeto */
%let home  = %sysget(HOME);                             /* caminho completo do Home */

%macro importa(arq, tab);                               /* leitura de CSV */
  proc import datafile="&pasta/&arq" out=&tab dbms=csv replace; guessingrows=max; run;
%mend importa;

/* ---------- 0. base: voltas, treinos e referência A (V1) ---------- */
%macro garante;
  %if not %sysfunc(exist(work.lr25)) %then %do;         /* sessão nova: recria tudo */
    ods exclude all;
    %include "&pasta/08_degradacao_treinos.sas";        /* importa, limpa e separa as simulações de corrida */
    ods exclude none;
  %end;
%mend garante;
%garante
%macro ref(s);                                          /* referência A = mesma do programa 10 (V1) */
  proc means data=lr&s noprint nway;
    class race_session_key driver_number; var lap_duration;
    output out=ref&s(drop=_type_ rename=(_freq_=n_ref race_session_key=session_key)) median=ritmo_treino;
  run;
%mend ref;
%ref(24)
%ref(25)
%importa(f1_equipes.csv, eq)                            /* equipe por corrida e piloto (OpenF1) */
%importa(f1_2024_secas_race_control.csv, rc24)          /* direção de prova 2024 */
%importa(f1_2025_secas_race_control.csv, rc25)          /* direção de prova 2025 */
cas mysess;                                             /* sessão CAS */
caslib _all_ assign;

/* ---------- 1. informação pré-corrida do fim de semana ---------- */
%macro prepara(s);
  proc sql;
    create table best_bruto&s as                        /* melhor volta de cada piloto nos treinos */
    select race_session_key, driver_number, min(lap_duration) as melhor
    from fp&s where lap_duration > 0 and is_pit_out_lap = 0 group by 1, 2;
    create table best&s as                              /* tira erro de cronometragem (5% abaixo da mediana do fds) */
    select b.* from best_bruto&s b inner join
         (select race_session_key, median(melhor) as mm from best_bruto&s group by 1) m
         on b.race_session_key = m.race_session_key
    where b.melhor >= 0.95 * m.mm;
    create table sprint&s as                            /* fim de semana sprint = só 1 treino livre */
    select race_session_key as session_key, (count(distinct session_key) = 1) as sprint
    from fp&s group by 1;
    create table qa&s as                                /* razão q da referência A */
    select a.session_key, a.driver_number, a.ritmo_treino as ref_a, b.melhor,
           a.ritmo_treino / b.melhor as q_a
    from ref&s a inner join best&s b
         on a.session_key = b.race_session_key and a.driver_number = b.driver_number;
  quit;
%mend prepara;
%prepara(24)
%prepara(25)

%macro limites(onde, pref);                             /* limites de q (parâmetro global) */
  proc univariate data=qa24(where=(&onde)) noprint; var q_a; output out=_lim q1=q1 q3=q3 n=n; run;
  data _null_;
    set _lim;
    call symputx("&pref._inf", q1 - 3 * (q3 - q1), 'G');   /* Q1 - 3 x IQR */
    call symputx("&pref._sup", q3 + 3 * (q3 - q1), 'G');   /* Q3 + 3 x IQR */
    call symputx("&pref._n", n, 'G');                      /* nº de referências usadas */
  run;
%mend limites;

%macro constroi_ca(s, inf, sup, saida);                 /* referência CA de um ano com limites dados */
  proc sql;
    create table _qa as                                 /* checagem de cada referência A */
    select *, (not missing(q_a) and &inf <= q_a <= &sup) as valido from qa&s;
    create table _qf as                                 /* q_fds: mediana de q das referências válidas do fds */
    select session_key, median(q_a) as q_fds, count(*) as n_validos from _qa where valido = 1 group by 1;
    create table &saida as
    select coalesce(r.session_key, b.race_session_key) as session_key,
           coalesce(r.driver_number, b.driver_number) as driver_number,
           r.ritmo_treino as ref_a, b.melhor, q.q_a, f.q_fds, f.n_validos,
           case when not missing(r.ritmo_treino) and q.valido = 1 then r.ritmo_treino
                when not missing(r.ritmo_treino) and missing(b.melhor) then r.ritmo_treino
                when not missing(b.melhor) and not missing(f.q_fds) then b.melhor * f.q_fds
                else . end as ref_ca,
           case when not missing(r.ritmo_treino) and q.valido = 1 then 'valida'
                when not missing(r.ritmo_treino) and missing(b.melhor) then 'nao_verificada'
                when not missing(r.ritmo_treino) then 'reprovada_checagem'
                else 'ausente' end as qualidade_referencia length=20,
           case when calculated qualidade_referencia in ('valida', 'nao_verificada') then 'observada_longrun'
                when not missing(calculated ref_ca) then 'estimada_melhor_volta'
                else 'nenhuma' end as metodo_referencia length=22,
           (calculated metodo_referencia = 'estimada_melhor_volta') as ref_estimada
    from ref&s r full join best&s b
         on r.session_key = b.race_session_key and r.driver_number = b.driver_number
         left join _qa q on coalesce(r.session_key, b.race_session_key) = q.session_key
                        and coalesce(r.driver_number, b.driver_number) = q.driver_number
         left join _qf f on coalesce(r.session_key, b.race_session_key) = f.session_key;
  quit;
%mend constroi_ca;

%limites(1, g)                                          /* limites globais: todas as referências de 2024 */
%constroi_ca(24, &g_inf, &g_sup, ca24)
%constroi_ca(25, &g_inf, &g_sup, ca25)                  /* 2025 usa os limites congelados de 2024 */

/* ---------- 2. voltas de corrida e marcações de voltas atípicas ---------- */
%macro voltas(s);
  proc sql;
    create table vl&s as                                /* voltas limpas de pneu seco */
    select v.session_key, v.circuito, v.driver_number, v.lap_number, v.compound, v.tyre_age, v.lap_duration,
           v.lap_number / r.voltas_corrida as prog, e.team_name, coalesce(sp.sprint, 0) as sprint
    from v&s v
         inner join (select distinct session_key, voltas_corrida from real&s) r on v.session_key = r.session_key
         left join eq e on v.session_key = e.session_key and v.driver_number = e.driver_number
         left join sprint&s sp on v.session_key = sp.session_key
    where v.usar2 = 1 and v.compound in ('SOFT','MEDIUM','HARD');
    create table ult&s as                               /* última volta registrada de cada piloto */
    select session_key, driver_number, max(lap_number) as ultima from v&s group by 1, 2;
    create table amar&s as                              /* voltas com bandeira amarela (volta do líder: aproximado) */
    select distinct circuito, lap_number from rc&s
    where upcase(flag) in ('YELLOW', 'DOUBLE YELLOW') and not missing(lap_number);
    create table inc&s as                               /* incidentes/punições citando o carro */
    select distinct circuito, lap_number, message from rc&s
    where (index(upcase(message), 'INCIDENT') > 0 or index(upcase(message), 'PENALTY') > 0)
          and not missing(lap_number);
    create table medp&s as                              /* mediana do piloto na corrida (só auditoria) */
    select session_key, driver_number, median(lap_duration) as med_piloto from vl&s group by 1, 2;
    create table incl&s as                              /* volta em que a mensagem cita o carro ("CAR 10 (") */
    select l.session_key, l.driver_number, l.lap_number,
           max(index(upcase(i.message), catx(' ', 'CAR', l.driver_number, '(')) > 0) as incidente
    from vl&s l inner join inc&s i on l.circuito = i.circuito and l.lap_number = i.lap_number
    group by 1, 2, 3;
    create table flag&s as                              /* uma linha por volta */
    select l.session_key, l.driver_number, l.lap_number,
           (l.lap_number = u.ultima and coalesce(t.terminou, 1) = 0) as volta_pre_abandono,
           (not missing(a.lap_number)) as bandeira_amarela,
           coalesce(n.incidente, 0) as incidente,
           (l.lap_duration > 1.10 * m.med_piloto) as volta_lenta_110
    from vl&s l
         left join ult&s u on l.session_key = u.session_key and l.driver_number = u.driver_number
         left join (select session_key, driver_number, terminou from real&s) t
              on l.session_key = t.session_key and l.driver_number = t.driver_number
         left join amar&s a on l.circuito = a.circuito and l.lap_number = a.lap_number
         left join incl&s n on l.session_key = n.session_key and l.driver_number = n.driver_number
                           and l.lap_number = n.lap_number
         left join medp&s m on l.session_key = m.session_key and l.driver_number = m.driver_number;
  quit;
%mend voltas;
%voltas(24)
%voltas(25)

/* ---------- 3. tabela V2 (nova, não sobrescreve a V1) ---------- */
proc sql noprint;
  select distinct quote(strip(circuito)) into :pistas24 separated by ',' from vl24;   /* escopo: pistas de 2024 */
quit;
%macro monta(s);
  proc sql;
    create table pv&s as
    select l.*, 2000 + &s as ano_c, c.ref_a, c.melhor, c.q_a, c.q_fds, c.n_validos, c.ref_ca,
           coalesce(c.qualidade_referencia, 'sem_treino') as qualidade_referencia length=20,
           coalesce(c.metodo_referencia, 'nenhuma') as metodo_referencia length=22,
           coalesce(c.ref_estimada, 0) as ref_estimada,
           l.lap_duration - c.ref_ca as y,                 /* alvo V2 */
           l.lap_duration - c.ref_a as y_v1,               /* alvo V1 (quando existe) */
           f.volta_pre_abandono, f.bandeira_amarela, f.incidente, f.volta_lenta_110,
           max(f.volta_pre_abandono, f.bandeira_amarela, f.incidente, f.volta_lenta_110) as atipica,
           (l.circuito in (&pistas24)) as no_escopo
    from vl&s l
         left join ca&s c on l.session_key = c.session_key and l.driver_number = c.driver_number
         left join flag&s f on l.session_key = f.session_key and l.driver_number = f.driver_number
                           and l.lap_number = f.lap_number;
  quit;
%mend monta;
%monta(24)
%monta(25)
data prerace_v2;                                        /* mesma regra de partição da V1 */
  set pv24(in=t) pv25;
  where no_escopo = 1 and not missing(ref_ca);
  ano = ifn(t, 2024, 2025);
  if not t then particao = 0;                           /* 0 = teste 2025 */
  else if mod(session_key, 5) = 0 then particao = 2;    /* 2 = validação 2024 (corridas inteiras) */
  else particao = 1;                                    /* 1 = treino 2024 */
  papel_b = particao;                                   /* V2-B: estimadas de 2024 ficam fora do ajuste */
  if t and ref_estimada = 1 then papel_b = 9;
run;
%let criou = %sysfunc(dcreate(v2, &home/f1));           /* pasta ~/f1/v2 */
libname v2 "&home/f1/v2";
data v2.prerace_v2; set prerace_v2; run;                /* cópia permanente */
proc casutil;
  droptable casdata="F1_PRERACE_V2" incaslib="casuser" quiet;
  load data=work.prerace_v2 outcaslib="casuser" casout="F1_PRERACE_V2" promote;
  save casdata="F1_PRERACE_V2" incaslib="casuser" outcaslib="casuser" casout="F1_PRERACE_V2.sashdat" replace;
quit;

/* ---------- 4. cobertura por categoria ---------- */
proc sql;
  create table cob_pc as                                /* uma linha por piloto-corrida com voltas limpas */
  select distinct ano_c as ano,
         session_key, circuito, driver_number, team_name, sprint,
         case when no_escopo = 0 then '1_fora_escopo_pista'
              when qualidade_referencia = 'sem_treino' and missing(melhor) then '2_sem_voltas_treino'
              when qualidade_referencia in ('valida', 'nao_verificada') then '3_observada_valida'
              when qualidade_referencia = 'reprovada_checagem' and not missing(ref_ca) then '4_reprovada_substituida'
              when qualidade_referencia = 'ausente' and not missing(ref_ca) then '5_ausente_estimada'
              else '6_sem_estimativa' end as categoria length=26
  from (select * from pv24 union all corr select * from pv25);
quit;

/* ---------- 5. validação mascarada da estimativa (2024, deixa o piloto de fora) ---------- */
/*      limites refeitos sem o fim de semana avaliado; q_fds sem o próprio piloto           */
proc sql noprint;
  select distinct session_key into :fds24 separated by ' ' from qa24;
quit;
%let nfds = &sqlobs;
proc datasets lib=work nolist; delete loo_all; quit;
%macro loo;
  %do i = 1 %to &nfds;
    %let w = %scan(&fds24, &i);
    %limites(session_key ne &w, f)                      /* limites sem o fds avaliado */
    proc sql;
      create table _v as select *, (&f_inf <= q_a <= &f_sup) as valido from qa24 where session_key = &w;
      create table _loo as                              /* estimativa sem o próprio piloto */
      select a.session_key, a.driver_number, a.ref_a, a.melhor, a.q_a,
             a.melhor * median(b.q_a) as ref_est, count(b.q_a) as n_outros
      from _v a inner join _v b on a.driver_number ne b.driver_number
      where a.valido = 1 and b.valido = 1
      group by a.session_key, a.driver_number, a.ref_a, a.melhor, a.q_a;
    quit;
    proc append base=loo_all data=_loo force; run;
  %end;
%mend loo;
%loo
proc sql;
  create table loo_v as                                 /* erro da estimativa e relação com a corrida */
  select l.*, l.ref_est - l.ref_a as erro, abs(l.ref_est - l.ref_a) as erro_abs,
         c.circuito, c.team_name, c.sprint, m.med_piloto,
         m.med_piloto - l.ref_a as yobs, m.med_piloto - l.ref_est as yest
  from loo_all l
       inner join (select distinct session_key, circuito, driver_number, team_name, sprint from vl24) c
             on l.session_key = c.session_key and l.driver_number = c.driver_number
       inner join medp24 m on l.session_key = m.session_key and l.driver_number = m.driver_number;
  create table loo_v as                                 /* desvio em relação à mediana do grid (base observada) */
  select *, median(yobs) as base_fds,
         abs(yobs - calculated base_fds) as dev_obs, abs(yest - calculated base_fds) as dev_est
  from loo_v group by session_key;
quit;

/* ---------- 6. modelos principais: V1, V2-A, V2-B (mesma especificação) ---------- */
%let ef_com = circuito compound prog tyre_age circuito*compound;   /* com idade do pneu */
%let ef_sem = circuito compound prog circuito*compound;            /* sem idade do pneu */
%macro ajusta(exp, tabela, papel, nome, efeitos);
  proc regselect data=&tabela;
    partition role=&papel(train='1' validate='2' test='0');
    class circuito compound;
    model y = &efeitos;
    selection method=stepwise(select=sbc choose=sbc);
    output out=casuser.p_&exp._&nome copyvars=(session_key driver_number lap_number particao y) pred=p;
  run;
  data _p;
    length exp $4 modelo $3;
    set casuser.p_&exp._&nome;
    exp = "&exp"; modelo = "&nome";
  run;
  proc append base=pred_raw data=_p force; run;
%mend ajusta;
proc datasets lib=work nolist; delete pred_raw; quit;
ods exclude all;
%ajusta(V1,  casuser.F1_2024_PARA_MODEL_STUDIO, particao, com, &ef_com)
%ajusta(V1,  casuser.F1_2024_PARA_MODEL_STUDIO, particao, sem, &ef_sem)
%ajusta(V2A, casuser.F1_PRERACE_V2, particao, com, &ef_com)
%ajusta(V2A, casuser.F1_PRERACE_V2, particao, sem, &ef_sem)
%ajusta(V2B, casuser.F1_PRERACE_V2, papel_b, com, &ef_com)
%ajusta(V2B, casuser.F1_PRERACE_V2, papel_b, sem, &ef_sem)
ods exclude none;
proc sql;
  create table comum as                                 /* voltas com referência observada válida (iguais em V1 e V2) */
  select session_key, driver_number, lap_number from prerace_v2
  where qualidade_referencia in ('valida', 'nao_verificada');
  create table pred as                                  /* previsões + atributos da V2 */
  select p.exp, p.modelo, p.session_key, p.driver_number, p.lap_number, p.particao, p.y, p.p,
         v.circuito, v.compound, v.tyre_age, v.ref_ca, v.lap_duration,
         coalesce(v.ref_estimada, 0) as ref_estimada, coalesce(v.atipica, 0) as atipica,
         (not missing(c.lap_number)) as comum
  from pred_raw p
       left join prerace_v2 v on p.session_key = v.session_key and p.driver_number = v.driver_number
                             and p.lap_number = v.lap_number
       left join comum c on p.session_key = c.session_key and p.driver_number = c.driver_number
                        and p.lap_number = c.lap_number
  where not missing(p.p) and p.particao in (0, 1, 2)
        and not (p.exp = 'V2B' and p.particao in (1, 2) and calculated ref_estimada = 1);   /* V2-B: avalia 2024 só nas observadas */
quit;

/* ---------- 7. métricas ---------- */
%macro met(saida, onde, grupo);
  proc sql;
    create table &saida as
    select exp, modelo, &grupo, count(*) as voltas,
           mean(abs(y - p)) as mae format=6.3, sqrt(mean((y - p)**2)) as rmse format=6.3
    from pred where &onde group by exp, modelo, &grupo;
  quit;
%mend met;
%met(m_part,  1, particao)
%met(m_comum, %str(comum = 1), particao)
%met(m_ref,   %str(particao = 0), ref_estimada)
%met(m_atip,  1, %str(particao, atipica))
%met(m_comp,  %str(particao = 0), compound)
data pred; set pred;                                    /* faixa de idade do pneu */
  length faixa_idade $6;
  if tyre_age <= 5 then faixa_idade = '00-05'; else if tyre_age <= 10 then faixa_idade = '06-10';
  else if tyre_age <= 20 then faixa_idade = '11-20'; else faixa_idade = '21+';
run;
%met(m_idade, %str(particao = 0), faixa_idade)
proc sql;
  create table m_abs as                                 /* consistência: tempo absoluto reconstruído */
  select exp, modelo, mean(abs(lap_duration - (ref_ca + p))) as mae_abs format=6.3,
         mean(abs(y - p)) as mae_y format=6.3,
         max(abs((lap_duration - (ref_ca + p)) - (y - p))) as dif_max format=e10.
  from pred where exp ne 'V1' and particao = 0 group by exp, modelo;
quit;

/* ---------- 8. diferença pareada por corrida + bootstrap + LORO 2025 ---------- */
%macro ganho(exp, onde, saida);                         /* MAE por corrida: sem - com (positivo = idade ajuda) */
  proc sql;
    create table &saida as
    select a.session_key, a.circuito, a.voltas, b.mae - a.mae as ganho
    from (select session_key, circuito, count(*) as voltas, mean(abs(y - p)) as mae from pred
          where exp = "&exp" and modelo = 'com' and particao = 0 and &onde group by 1, 2) a
         inner join
         (select session_key, mean(abs(y - p)) as mae from pred
          where exp = "&exp" and modelo = 'sem' and particao = 0 and &onde group by 1) b
         on a.session_key = b.session_key;
  quit;
%mend ganho;
%macro boot(tab, peso, rot);
  proc surveyselect data=&tab out=_b method=urs samprate=1 outhits reps=1000 seed=2025 noprint; run;
  proc sql;
    create table _bm as select replicate,
      %if &peso = 1 %then %do; sum(ganho * voltas) / sum(voltas) %end; %else %do; mean(ganho) %end; as g
    from _b group by replicate;
    create table _pt as select
      %if &peso = 1 %then %do; sum(ganho * voltas) / sum(voltas) %end; %else %do; mean(ganho) %end; as ponto,
      sum(ganho > 0) as corridas_melhor, count(*) as corridas from &tab;
  quit;
  proc univariate data=_bm noprint; var g; output out=_ic pctlpts=2.5 97.5 pctlpre=ic_; run;
  data _r; length analise $40; merge _pt _ic; analise = "&rot"; run;
  proc append base=boot_res data=_r force; run;
%mend boot;
proc datasets lib=work nolist; delete boot_res; quit;
%ganho(V1,  1, g_v1)
%ganho(V2A, 1, g_v2a)
%ganho(V2B, 1, g_v2b)
%ganho(V2A, %str(comum = 1), g_v2a_c)
%ganho(V2B, %str(comum = 1), g_v2b_c)
%ganho(V1,  %str(comum = 1), g_v1_c)
%ganho(V2A, %str(atipica = 0), g_v2a_sa)
%ganho(V2A, %str(ref_estimada = 0), g_v2a_obs)
%boot(g_v1,     0, V1 peso igual)
%boot(g_v1,     1, V1 peso por voltas)
%boot(g_v2a,    0, V2-A peso igual (principal))
%boot(g_v2a,    1, V2-A peso por voltas)
%boot(g_v2b,    0, V2-B peso igual)
%boot(g_v2b,    1, V2-B peso por voltas)
%boot(g_v1_c,   0, V1 conjunto comum)
%boot(g_v2a_c,  0, V2-A conjunto comum)
%boot(g_v2b_c,  0, V2-B conjunto comum)
%boot(g_v2a_sa, 0, V2-A sem voltas atípicas)
%boot(g_v2a_obs,0, V2-A só referências observadas)
proc sql;                                               /* LORO 2025: tira uma corrida por vez (só sensibilidade) */
  create table loro25 as
  select a.circuito as corrida_retirada, mean(b.ganho) as ganho_sem_ela format=6.3
  from g_v2a a inner join g_v2a b on a.session_key ne b.session_key
  group by a.circuito order by calculated ganho_sem_ela;
quit;

/* ---------- 9. validação cruzada por corrida em 2024 (19 folds) ---------- */
/*      cada fold: limites de q só com as 18 corridas de treino; q_fds do fds avaliado é pré-corrida */
proc sql noprint;
  select distinct session_key into :folds separated by ' ' from vl24;
quit;
%let nfold = &sqlobs;
proc datasets lib=work nolist; delete cvpred; quit;
%macro cv;
  %do i = 1 %to &nfold;
    %let r = %scan(&folds, &i);
    %limites(session_key ne &r, f)                      /* parâmetro global só com o treino do fold */
    %constroi_ca(24, &f_inf, &f_sup, caf)
    proc sql;
      create table _cv as
      select l.session_key, l.circuito, l.driver_number, l.lap_number, l.compound, l.tyre_age, l.prog,
             l.lap_duration - c.ref_ca as y, c.ref_estimada,
             case when l.session_key = &r then 'S' else 'T' end as papel_a length=1,
             case when l.session_key = &r then 'S' when c.ref_estimada = 1 then 'X' else 'T' end as papel_b length=1
      from vl24 l inner join caf c on l.session_key = c.session_key and l.driver_number = c.driver_number
      where not missing(c.ref_ca);
    quit;
    data _cvtr _cvte; set _cv; if papel_a = 'T' then output _cvtr; else output _cvte; run;
    proc casutil;
      load data=work._cv   outcaslib="casuser" casout="cvall" replace;
      load data=work._cvtr outcaslib="casuser" casout="cvtr"  replace;
      load data=work._cvte outcaslib="casuser" casout="cvte"  replace;
    quit;
    %cvreg(com,  papel_a, &ef_com)
    %cvreg(sem,  papel_a, &ef_sem)
    %cvreg(comB, papel_b, &ef_com)
    %cvreg(semB, papel_b, &ef_sem)
    proc forest data=casuser.cvtr ntrees=100 seed=2025;  /* Forest com os mesmos folds */
      input prog tyre_age / level=interval;
      input circuito compound / level=nominal;
      target y / level=interval;
      savestate rstore=casuser.cvf_st;
    run;
    proc astore;
      score data=casuser.cvte rstore=casuser.cvf_st out=casuser.cvf_o
            copyvars=(session_key circuito driver_number lap_number y ref_estimada);
    run;
    data _p; length modelo $6; set casuser.cvf_o; modelo = 'forest'; p = P_y; fold = &r;
      keep modelo fold session_key circuito driver_number lap_number y p ref_estimada; run;
    proc append base=cvpred data=_p force; run;
  %end;
%mend cv;
%macro cvreg(nome, papel, efeitos);
  proc regselect data=casuser.cvall;
    partition role=&papel(train='T' test='S');
    class circuito compound;
    model y = &efeitos;
    selection method=stepwise(select=sbc choose=sbc);
    output out=casuser.cvo copyvars=(session_key circuito driver_number lap_number y ref_estimada papel_a) pred=p;
  run;
  data _p; length modelo $6; set casuser.cvo; where papel_a = 'S'; modelo = "&nome"; fold = &r;
    keep modelo fold session_key circuito driver_number lap_number y p ref_estimada; run;
  proc append base=cvpred data=_p force; run;
%mend cvreg;
ods exclude all;
%cv
ods exclude none;
proc sql;
  create table cv_corr as                               /* MAE por corrida avaliada e modelo */
  select modelo, session_key, circuito, count(*) as voltas, mean(abs(y - p)) as mae
  from cvpred where not missing(p) group by 1, 2, 3;
  create table cv_res as                                /* resumo: média por corrida (peso igual) */
  select modelo, count(*) as corridas, mean(mae) as mae_medio format=6.3,
         min(mae) as mae_min format=6.3, max(mae) as mae_max format=6.3
  from cv_corr group by modelo;
  create table cv_par as                                /* pares: com x sem, regressão x forest */
  select 'com vs sem (V2-A)' as comparacao length=30, mean(b.mae - a.mae) as ganho format=6.3,
         sum(b.mae > a.mae) as corridas_favor, count(*) as corridas
  from cv_corr a inner join cv_corr b on a.session_key = b.session_key where a.modelo = 'com' and b.modelo = 'sem'
  union all
  select 'com vs sem (V2-B)', mean(b.mae - a.mae), sum(b.mae > a.mae), count(*)
  from cv_corr a inner join cv_corr b on a.session_key = b.session_key where a.modelo = 'comB' and b.modelo = 'semB'
  union all
  select 'regressão com vs forest', mean(b.mae - a.mae), sum(b.mae > a.mae), count(*)
  from cv_corr a inner join cv_corr b on a.session_key = b.session_key where a.modelo = 'com' and b.modelo = 'forest';
  create table cv_ref as                                /* CV por tipo de referência */
  select modelo, ref_estimada, count(*) as voltas, mean(abs(y - p)) as mae format=6.3
  from cvpred where not missing(p) group by 1, 2;
quit;
data v2.pred_v2; set pred; run;                         /* guarda previsões e CV */
data v2.cvpred_v2; set cvpred; run;

/* ---------- 10. resultados ---------- */
proc sql;
  title "T1. Parâmetros da referência CA (limites de q aprendidos em 2024 com &g_n referências)";
  select &g_inf as q_inf format=8.4, &g_sup as q_sup format=8.4 from sashelp.class(obs=1);
  title 'T1b. q_fds: nº de referências válidas por fim de semana';
  select 2024 as ano, min(n_validos) as min, median(n_validos) as mediana, max(n_validos) as max
  from (select distinct session_key, n_validos from ca24 where not missing(n_validos))
  union all select 2025, min(n_validos), median(n_validos), max(n_validos)
  from (select distinct session_key, n_validos from ca25 where not missing(n_validos));
  title 'T2. Cobertura por categoria (denominador = piloto-corridas com voltas limpas de pneu seco)';
  select ano, categoria, count(*) as piloto_corridas from cob_pc group by 1, 2 order by 1, 2;
  title 'T3. Validação mascarada da estimativa CA (2024, piloto fora, limites sem o fds)';
  select count(*) as n, mean(erro) as vies format=6.3, mean(erro_abs) as mae format=6.3,
         median(erro_abs) as mediana_abs format=6.3, mean(dev_obs) as dev_corrida_obs format=6.3,
         mean(dev_est) as dev_corrida_est format=6.3
  from loo_v;
quit;
proc univariate data=loo_v noprint; var erro_abs; output out=loo_pct pctlpts=90 95 pctlpre=p; run;
proc print data=loo_pct noobs; title 'T3b. Percentis do erro absoluto da estimativa (s)'; run;
proc sql;
  title 'T3c. Estimativa por tipo de fim de semana';
  select sprint, count(*) as n, mean(erro) as vies format=6.3, mean(erro_abs) as mae format=6.3,
         mean(dev_obs) as dev_obs format=6.3, mean(dev_est) as dev_est format=6.3 from loo_v group by 1;
  title 'T3d. Estimativa por pista';
  select circuito, count(*) as n, mean(erro) as vies format=6.3, mean(erro_abs) as mae format=6.3
  from loo_v group by 1 order by calculated mae desc;
  title 'T3e. Estimativa por equipe';
  select team_name, count(*) as n, mean(erro) as vies format=6.3, mean(erro_abs) as mae format=6.3
  from loo_v group by 1 order by calculated mae desc;
quit;
proc print data=m_part noobs; title 'T4. MAE/RMSE por partição (1 treino, 2 validação, 0 teste)'; run;
proc print data=m_comum noobs; title 'T5. Conjunto comum (referência observada válida)'; run;
proc print data=m_ref noobs; title 'T6. Teste 2025 por tipo de referência'; run;
proc print data=m_atip noobs; title 'T7. Com e sem voltas atípicas'; run;
proc print data=m_comp noobs; title 'T8. Teste 2025 por composto'; run;
proc print data=m_idade noobs; title 'T9. Teste 2025 por faixa de idade do pneu'; run;
proc print data=m_abs noobs; title 'T10. Consistência: tempo absoluto reconstruído'; run;
proc print data=boot_res noobs; title 'T11. Ganho da idade do pneu (s/volta, sem - com) e IC 95% bootstrap por corrida'; run;
proc print data=g_v2a noobs; title 'T12. V2-A: ganho por corrida no teste 2025'; run;
proc print data=loro25 noobs; title 'T13. LORO 2025 (sensibilidade): ganho médio sem cada corrida'; run;
proc print data=cv_res noobs; title 'T14. Validação cruzada por corrida 2024: MAE médio por corrida'; run;
proc print data=cv_par noobs; title 'T15. Validação cruzada: comparações pareadas por corrida'; run;
proc print data=cv_ref noobs; title 'T16. Validação cruzada por tipo de referência'; run;
proc sql;
  title 'T17. Atípicas por tipo (todas as voltas da V2)';
  select ano, count(*) as voltas, sum(volta_pre_abandono) as pre_abandono, sum(bandeira_amarela) as amarela,
         sum(incidente) as incidente, sum(volta_lenta_110) as lenta_110, sum(atipica) as alguma
  from prerace_v2 group by ano;
  title 'T18. Cobertura por equipe (categoria x ano)';
  select ano, team_name, sum(categoria = '3_observada_valida') as observada,
         sum(categoria in ('4_reprovada_substituida', '5_ausente_estimada')) as estimada,
         sum(categoria in ('2_sem_voltas_treino', '6_sem_estimativa')) as sem_ref,
         sum(categoria = '1_fora_escopo_pista') as fora_escopo, count(*) as total
  from cob_pc group by 1, 2 order by 1, 2;
  title 'T19. Cobertura por corrida (categoria x ano)';
  select ano, circuito, sum(categoria = '3_observada_valida') as observada,
         sum(categoria in ('4_reprovada_substituida', '5_ausente_estimada')) as estimada,
         sum(categoria in ('2_sem_voltas_treino', '6_sem_estimativa')) as sem_ref,
         sum(categoria = '1_fora_escopo_pista') as fora_escopo, count(*) as total
  from cob_pc group by 1, 2 order by 1, 2;
quit;
title;
