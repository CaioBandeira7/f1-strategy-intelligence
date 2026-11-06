/* =====================================================================
   13_referencia_alternativas.sas - compara 3 formas de montar a
   referência de ritmo dos treinos (alvo y = volta - referência).
   NÃO altera a base do Model Studio. Cria tabelas novas com sufixo _A/_B/_C.
     A = referência atual (mediana das voltas de simulação de corrida)
     B = referência robusta por piloto: modelo por fim de semana
         stint = piloto + sessão + composto, com checagem de consistência
         do próprio piloto (resíduo do stint e razão long run / melhor volta)
     C = B + estimativa pré-corrida para referências inválidas ou ausentes
         (melhor volta do piloto nos treinos x razão típica do fim de semana)
   Escolha só com 2024 (desenvolvimento). 2025 aparece apenas como cobertura.
   ===================================================================== */
options locale=en_US validvarname=v7;                   /* ponto decimal e nomes válidos */
%let pasta = ~/f1;                                      /* pasta do projeto */
%let home  = %sysget(HOME);                             /* caminho completo do Home (para criar pasta) */

%macro importa(arq, tab);                               /* leitura de CSV (igual ao 01) */
  proc import datafile="&pasta/&arq" out=&tab dbms=csv replace; guessingrows=max; run;
%mend importa;

/* ---------- 0. benchmark v1: guarda os resultados atuais sem sobrescrever ---------- */
%let criou = %sysfunc(dcreate(benchmark_v1, &home/f1));   /* cria ~/f1/benchmark_v1 (se já existir, segue) */
libname bench "&home/f1/benchmark_v1";                  /* biblioteca permanente do benchmark */
%macro guarda(origem, destino);                         /* copia só se a tabela existir e o destino não */
  %if %sysfunc(exist(&origem)) and not %sysfunc(exist(bench.&destino)) %then %do;
    data bench.&destino; set &origem; run;              /* cópia permanente */
  %end;
%mend guarda;
%guarda(work.ms,       prerace_v1)                      /* base do Model Studio v1 (26.953 voltas) */
%guarda(work.metricas, metricas_reg_v1)                 /* MAE/RMSE das regressões (programa 11) */
%guarda(work.corrida,  corrida_reg_v1)                  /* MAE por corrida (programa 11) */
%guarda(work.ic,       bootstrap_reg_v1)                /* IC do ganho da idade do pneu (programa 11) */

/* ---------- 1. equipes de cada piloto (OpenF1, uma vez só) ---------- */
proc python;
submit;
import os, json, time, urllib.request, urllib.error                  # pastas, API e pausas
import pandas as pd                                                  # tabelas
os.chdir(os.path.expanduser("~/f1"))                                 # pasta do projeto
if not os.path.exists("f1_equipes.csv"):                             # só baixa se ainda não existir
    linhas = []                                                      # tabelas por corrida
    for ano in (2024, 2025):                                         # os dois anos
        real = pd.read_csv(f"f1_{ano}_estrategia_real.csv")          # corridas secas do ano
        for sk in sorted(real["session_key"].unique()):              # cada corrida
            for i in range(6):                                       # até 6 tentativas
                try:
                    url = f"https://api.openf1.org/v1/drivers?session_key={int(sk)}"   # pilotos da corrida
                    with urllib.request.urlopen(url, timeout=60) as r:
                        d = pd.DataFrame(json.loads(r.read()))       # resposta em tabela
                    break                                            # deu certo
                except urllib.error.HTTPError as e:                  # erro HTTP
                    if e.code != 429: raise                          # só insiste no limite de pedidos
                    time.sleep(15 * (i + 1))                         # espera e tenta de novo
            time.sleep(2)                                            # respeita o limite da API
            d["ano"] = ano                                           # ano
            linhas.append(d[["ano", "session_key", "driver_number", "name_acronym", "team_name"]])
    pd.concat(linhas).to_csv("f1_equipes.csv", index=False)          # salva
endsubmit;
run;
%importa(f1_equipes.csv, eq)                            /* equipe por corrida e piloto */

/* ---------- 2. bandeira vermelha: regra antiga x corrigida, nos dados reais e num teste ---------- */
%importa(f1_2024_secas_race_control.csv, rc24)          /* mensagens da direção de prova 2024 */
%importa(f1_2025_secas_race_control.csv, rc25)          /* idem 2025 */
%macro vermelha(s);
  proc sql;
    create table ev&s as                                /* eventos: pista e volta da bandeira */
    select distinct circuito, lap_number as volta_verm from rc&s
    where upcase(flag) = 'RED' and not missing(lap_number);
    create table mkv&s as                               /* cada volta x eventos da mesma pista */
    select m.circuito, m.lap_number, upcase(cats(m.pos_vermelha)) = 'TRUE' as antiga,
           max(case when m.lap_number between e.volta_verm and e.volta_verm + 2 then 1 else 0 end) as nova
    from mk&s m inner join ev&s e on m.circuito = e.circuito
    group by m.circuito, m.lap_number, m.driver_number, calculated antiga;
    create table cmp_verm&s as                          /* voltas excluídas por cada regra */
    select "20&s" as ano, circuito, sum(antiga) as regra_antiga, sum(nova) as regra_nova
    from mkv&s group by circuito;
  quit;
%mend vermelha;
%vermelha(24)
%vermelha(25)
data teste_verm;                                        /* corrida sintética: 60 voltas, bandeira na 30 */
  do lap_number = 1 to 60;
    antiga = (lap_number <= 30 + 2);                    /* regra antiga: tudo até a bandeira + 2 */
    nova   = (30 <= lap_number <= 32);                  /* regra nova: só 30, 31 e 32 */
    output;
  end;
run;

/* ---------- 3. voltas muito lentas: contexto, sem remover nada ---------- */
proc sql;
  create table lentas as                                /* voltas com y > 20 s ou > 110% da mediana do piloto */
  select l.*, a.lap_duration as volta_anterior, d.lap_duration as volta_seguinte
  from (select t.circuito, t.session_key, t.driver_number, t.lap_number, t.lap_duration, t.rel, '2024' as ano
        from lt24 t where t.rel > 1.10
        union all
        select t.circuito, t.session_key, t.driver_number, t.lap_number, t.lap_duration, t.rel, '2025'
        from lt25 t where t.rel > 1.10) l
       left join (select session_key, driver_number, lap_number, lap_duration from v24
                  union all select session_key, driver_number, lap_number, lap_duration from v25) a
         on l.session_key = a.session_key and l.driver_number = a.driver_number and a.lap_number = l.lap_number - 1
       left join (select session_key, driver_number, lap_number, lap_duration from v24
                  union all select session_key, driver_number, lap_number, lap_duration from v25) d
         on l.session_key = d.session_key and l.driver_number = d.driver_number and d.lap_number = l.lap_number + 1;
  create table lentas_msg as                            /* mensagens da direção de prova na mesma volta */
  select l.ano, l.circuito, l.driver_number, l.lap_number, l.lap_duration format=7.2, l.rel format=5.2,
         r.category, r.flag, substr(r.message, 1, 70) as mensagem length=70
  from lentas l
       inner join (select circuito, lap_number, driver_number, category, flag, message, '2024' as ano from rc24
                   union all select circuito, lap_number, driver_number, category, flag, message, '2025' from rc25) r
       on l.ano = r.ano and l.circuito = r.circuito and r.lap_number = l.lap_number
          and (missing(r.driver_number) or r.driver_number = l.driver_number)
  order by l.ano, l.circuito, l.driver_number;
quit;

/* ---------- 4. stints de simulação de corrida e melhor volta de cada piloto nos treinos ---------- */
%macro prepara(s);
  proc sql;
    create table stf&s as                               /* uma linha por stint de simulação de corrida */
    select race_session_key, max(circuito) as circuito length=40, treino, session_key, driver_number,
           id_stint, max(compound) as compound length=8, count(*) as n_voltas,
           median(lap_duration) as med, min(tyre_age) as idade_ini, max(tyre_age) as idade_fim
    from lr&s group by race_session_key, treino, session_key, driver_number, id_stint;
    create table best_bruto&s as                        /* melhor volta do piloto no fim de semana */
    select race_session_key, driver_number, min(lap_duration) as melhor
    from fp&s where lap_duration > 0 and is_pit_out_lap = 0
    group by race_session_key, driver_number;
    create table best&s as                              /* descarta erro de cronometragem (5% abaixo da mediana) */
    select b.* from best_bruto&s b inner join
         (select race_session_key, median(melhor) as mm from best_bruto&s group by race_session_key) m
         on b.race_session_key = m.race_session_key
    where b.melhor >= 0.95 * m.mm;
  quit;
%mend prepara;
%prepara(24)
%prepara(25)

/* ---------- 5. alternativa B: modelo por fim de semana com checagem de consistência ---------- */
%macro alt_b(s);
  proc sort data=stf&s; by race_session_key; run;
  proc glm data=stf&s noprint;                          /* etapa 1: stint = piloto + sessão + composto */
    by race_session_key;
    class driver_number treino compound;
    model med = driver_number treino compound;
    output out=r1_&s r=res;                             /* resíduo de cada stint */
  run; quit;
  proc sql;
    create table r1_&s as                               /* nº de stints do piloto no fim de semana */
    select a.*, b.nst from r1_&s a inner join
         (select race_session_key, driver_number, count(*) as nst from stf&s group by 1, 2) b
         on a.race_session_key = b.race_session_key and a.driver_number = b.driver_number;
    create table mad&s as                               /* escala robusta do resíduo (pilotos com 2+ stints) */
    select race_session_key, median(abs(res)) as mad from r1_&s where nst >= 2 group by 1;
    create table st_b&s as                              /* stint inconsistente com os outros stints do piloto */
    select a.*, (abs(a.res) > max(3 * 1.4826 * m.mad, 0.75)) as stint_fora
    from r1_&s a left join mad&s m on a.race_session_key = m.race_session_key;
    create table kept&s as select * from st_b&s where stint_fora = 0;
    create table sess&s as                              /* sessão de referência: a com mais stints */
    select race_session_key, treino, count(*) as n from kept&s group by 1, 2 order by 1, 3 desc;
    create table comp&s as                              /* composto de referência: MEDIUM, se houver */
    select race_session_key, compound, count(*) as n, (compound = 'MEDIUM') as eh_medio
    from kept&s group by 1, 2 order by 1, 4 desc, 3 desc;
  quit;
  data sess&s; set sess&s; by race_session_key; if first.race_session_key; run;
  data comp&s; set comp&s; by race_session_key; if first.race_session_key; run;
  proc sql;
    create table score&s as                             /* linhas para prever cada piloto na sessão/composto de referência */
    select distinct k.race_session_key, k.driver_number, s.treino, c.compound, . as med
    from kept&s k inner join sess&s s on k.race_session_key = s.race_session_key
                  inner join comp&s c on k.race_session_key = c.race_session_key;
  quit;
  data fit2_&s;                                         /* stints válidos + linhas de previsão */
    set kept&s(keep=race_session_key driver_number treino compound med in=a)
        score&s(in=b);
    escore = b;                                         /* 1 = linha de previsão */
  run;
  proc sort data=fit2_&s; by race_session_key; run;
  proc glm data=fit2_&s noprint;                        /* etapa 2: refaz sem os stints inconsistentes */
    by race_session_key;
    class driver_number treino compound;
    model med = driver_number treino compound;
    output out=p2_&s p=pred;
  run; quit;
  proc sql;
    create table refb&s as                              /* referência B + razão sobre a melhor volta */
    select p.race_session_key as session_key, p.driver_number, p.pred as ref_b,
           b.melhor, p.pred / b.melhor as q
    from p2_&s p left join best&s b
         on p.race_session_key = b.race_session_key and p.driver_number = b.driver_number
    where p.escore = 1;
  quit;
%mend alt_b;
%alt_b(24)
%alt_b(25)

proc univariate data=refb24 noprint;                    /* limites da razão: SÓ 2024 (desenvolvimento) */
  var q; output out=qlim q1=q1 q3=q3 median=qmed;
run;
data _null_;
  set qlim;
  call symputx('q_inf', q1 - 3 * (q3 - q1));            /* limite inferior: Q1 - 3 x IQR */
  call symputx('q_sup', q3 + 3 * (q3 - q1));            /* limite superior: Q3 + 3 x IQR */
  call symputx('q_med', qmed);
run;
%put NOTE: razão long run / melhor volta válida entre &q_inf e &q_sup (mediana &q_med, só 2024);

/* ---------- 6. alternativa C: estimativa pré-corrida para inválidos e ausentes ---------- */
%macro alt_c(s);
  data refb&s;                                          /* marca a referência B válida */
    set refb&s;
    valido_b = (not missing(q) and &q_inf <= q <= &q_sup);
  run;
  proc sql;
    create table qfim&s as                              /* razão típica do fim de semana (só referências válidas) */
    select session_key, median(q) as q_fds, count(*) as n_validos
    from refb&s where valido_b = 1 group by session_key;
    create table refc&s as                              /* todos os pilotos com melhor volta nos treinos */
    select b.race_session_key as session_key, b.driver_number, b.melhor,
           r.ref_b, coalesce(r.valido_b, 0) as valido_b, f.q_fds,
           case when r.valido_b = 1 then r.ref_b else b.melhor * f.q_fds end as ref_c,
           (calculated valido_b = 0) as estimada
    from best&s b left join refb&s r on b.race_session_key = r.session_key and b.driver_number = r.driver_number
                  left join qfim&s f on b.race_session_key = f.session_key;
  quit;
%mend alt_c;
%alt_c(24)
%alt_c(25)

proc sql;                                               /* validação do estimador C com 2024: deixa um piloto de fora */
  create table loo24 as
  select a.session_key, a.driver_number, a.ref_b,
         a.melhor * median(b.q) as ref_est,             /* melhor volta x razão dos OUTROS pilotos */
         a.melhor * median(b.q) - a.ref_b as erro
  from refb24 a inner join refb24 b
       on a.session_key = b.session_key and a.driver_number ne b.driver_number
  where a.valido_b = 1 and b.valido_b = 1
  group by a.session_key, a.driver_number, a.ref_b, a.melhor;
quit;

/* ---------- 7. bases de voltas para cada alternativa (não substitui nada) ---------- */
%macro base_alt(s);
  proc sql;
    create table lap&s as                               /* voltas limpas de corrida com as 3 referências */
    select v.session_key, v.circuito, v.driver_number, v.lap_number, v.compound, v.tyre_age, v.lap_duration,
           v.lap_number / r.voltas_corrida as prog,
           a.ritmo_treino as ref_a, b.ref_b, b.valido_b, c.ref_c, c.estimada,
           e.team_name
    from v&s v
         inner join (select distinct session_key, voltas_corrida from real&s) r on v.session_key = r.session_key
         left join ref&s a  on v.session_key = a.session_key and v.driver_number = a.driver_number
         left join refb&s b on v.session_key = b.session_key and v.driver_number = b.driver_number
         left join refc&s c on v.session_key = c.session_key and v.driver_number = c.driver_number
         left join eq e     on v.session_key = e.session_key and v.driver_number = e.driver_number
    where v.usar2 = 1 and v.compound in ('SOFT','MEDIUM','HARD');
  quit;
%mend base_alt;
%base_alt(24)
%base_alt(25)
proc sql;                                               /* 2025: só pistas vistas em 2024 (igual ao v1) */
  create table lap25f as select * from lap25 where circuito in (select distinct circuito from lap24);
quit;
data lap_all;                                           /* empilha e calcula o alvo de cada alternativa */
  set lap24(in=t) lap25f;
  ano = ifn(t, 2024, 2025);
  y_a = ifn(not missing(ref_a), lap_duration - ref_a, .);   /* A: atual */
  y_b = ifn(valido_b = 1,       lap_duration - ref_b, .);   /* B: só referências consistentes */
  y_c = ifn(not missing(ref_c), lap_duration - ref_c, .);   /* C: B + estimadas */
run;

/* ---------- 8. qualidade do alvo (escolha SÓ com 2024) ---------- */
%macro qualidade(alt);
  proc sql;
    create table pc_&alt as                             /* mediana de y por piloto-corrida */
    select ano, session_key, circuito, driver_number, team_name, count(*) as voltas, median(y_&alt) as y_med
    from lap_all where not missing(y_&alt) group by 1, 2, 3, 4, 5;
    create table q_&alt as
    select "&alt" as alternativa, ano, count(*) as piloto_corridas, sum(voltas) as voltas,
           sum(abs(y_med) > 3) as anomalias_3s,         /* piloto-corrida com mediana |y| > 3 s */
           mean(dp) as dp_entre_pilotos format=6.3      /* dispersão média entre pilotos na mesma corrida */
    from (select p.*, std(y_med) as dp from pc_&alt p group by ano, session_key)
    group by ano;
  quit;
%mend qualidade;
%qualidade(a)
%qualidade(b)
%qualidade(c)
data qualidade; set q_a q_b q_c; run;
proc sort data=qualidade; by ano alternativa; run;

proc sql;                                               /* universo: piloto-corridas com voltas limpas */
  create table univ as select distinct ano, session_key, circuito, driver_number, team_name from lap_all;
  create table perda_pista as                           /* perda por pista (piloto-corridas sem referência) */
  select u.ano, u.circuito, count(*) as total,
         sum(missing(a.voltas)) as sem_a, sum(missing(b.voltas)) as sem_b, sum(missing(c.voltas)) as sem_c
  from univ u left join pc_a a on u.session_key = a.session_key and u.driver_number = a.driver_number
              left join pc_b b on u.session_key = b.session_key and u.driver_number = b.driver_number
              left join pc_c c on u.session_key = c.session_key and u.driver_number = c.driver_number
  group by u.ano, u.circuito order by u.ano, calculated sem_a desc;
  create table perda_equipe as                          /* perda por equipe */
  select u.ano, u.team_name, count(*) as total,
         sum(missing(a.voltas)) as sem_a, sum(missing(b.voltas)) as sem_b, sum(missing(c.voltas)) as sem_c
  from univ u left join pc_a a on u.session_key = a.session_key and u.driver_number = a.driver_number
              left join pc_b b on u.session_key = b.session_key and u.driver_number = b.driver_number
              left join pc_c c on u.session_key = c.session_key and u.driver_number = c.driver_number
  group by u.ano, u.team_name order by u.ano, calculated sem_a desc;
quit;

/* ---------- 9. casos anômalos: stints que formaram cada referência ---------- */
data casos;                                             /* casos apontados na auditoria A */
  infile datalines dlm=',';
  length circuito $40;
  input ano circuito $ driver_number;
  datalines;
2025,Baku,10
2024,Melbourne,63
2025,Las Vegas,4
2025,Las Vegas,44
2025,Las Vegas,14
2025,Las Vegas,31
2024,Las Vegas,44
2024,Las Vegas,14
2024,Lusail,1
;
run;
proc sql;
  create table casos_stints as                          /* cada stint usado na referência A, com o diagnóstico B */
  select c.ano, c.circuito, c.driver_number, s.treino, s.compound, s.n_voltas,
         s.med format=8.3, s.idade_ini, s.idade_fim, s.res format=7.2, s.stint_fora
  from casos c inner join
       (select 2024 as ano, * from st_b24 union all select 2025 as ano, * from st_b25) s
       on c.ano = s.ano and c.circuito = s.circuito and c.driver_number = s.driver_number
  order by c.ano, c.circuito, c.driver_number, s.treino;
  create table casos_ref as                             /* referências A, B, C x ritmo real da corrida */
  select c.ano, c.circuito, c.driver_number,
         a.ritmo_treino as ref_a format=8.3, b.ref_b format=8.3, b.melhor format=8.3, b.q format=6.3,
         b.valido_b, k.ref_c format=8.3, k.estimada, m.corrida_med format=8.3,
         m.corrida_med - a.ritmo_treino as y_med_a format=7.2,
         m.corrida_med - k.ref_c as y_med_c format=7.2
  from casos c
       inner join (select distinct ano, circuito, session_key from lap_all) l on c.ano = l.ano and c.circuito = l.circuito
       left join (select session_key, driver_number, ritmo_treino from ref24 union all
                  select session_key, driver_number, ritmo_treino from ref25) a
         on l.session_key = a.session_key and c.driver_number = a.driver_number
       left join (select * from refb24 union all select * from refb25) b
         on l.session_key = b.session_key and c.driver_number = b.driver_number
       left join (select session_key, driver_number, ref_c, estimada from refc24 union all
                  select session_key, driver_number, ref_c, estimada from refc25) k
         on l.session_key = k.session_key and c.driver_number = k.driver_number
       left join (select session_key, driver_number, median(lap_duration) as corrida_med
                  from lap_all group by 1, 2) m
         on l.session_key = m.session_key and c.driver_number = m.driver_number
  order by c.ano, c.circuito, c.driver_number;
quit;

/* ---------- 10. condições das sessões: treino muito diferente da corrida? ---------- */
proc sql;
  create table dm24 as select 2024 as ano, k.*, mean(k.med) as dm
    from kept24 k group by k.race_session_key, k.driver_number;   /* média do piloto (remerge) */
  create table dm25 as select 2025 as ano, k.*, mean(k.med) as dm
    from kept25 k group by k.race_session_key, k.driver_number;
  create table cond_sessao as                           /* efeito de cada sessão (stint - média do piloto) */
  select ano, circuito, treino, count(*) as stints, mean(med - dm) as efeito_s format=7.2
  from (select * from dm24 union all corr select * from dm25)
  group by ano, circuito, treino;
  create table cond_fds as                              /* corrida - treino no nível do grid */
  select ano, circuito, median(lap_duration) - median(ref_a) as corrida_menos_treino format=7.2,
         count(distinct driver_number) as pilotos
  from lap_all where not missing(ref_a) group by ano, circuito
  order by calculated corrida_menos_treino;
quit;

/* ---------- 11. resultados ---------- */
proc print data=cmp_verm24 noobs; title 'R1. Bandeira vermelha 2024: voltas excluídas (regra antiga x nova)'; run;
proc print data=cmp_verm25 noobs; title 'R1b. Bandeira vermelha 2025'; run;
proc sql; title 'R1c. Teste sintético: bandeira na volta 30 de 60';
  select sum(antiga) as excluidas_antiga, sum(nova) as excluidas_nova from teste_verm; quit;
proc print data=lentas_msg noobs; title 'R2. Voltas > 110% da mediana do piloto: mensagens na mesma volta'; run;
proc print data=lentas noobs; var ano circuito driver_number lap_number lap_duration rel volta_anterior volta_seguinte;
  title 'R2b. Voltas > 110% (todas, com volta anterior e seguinte)'; run;
proc print data=casos_ref noobs; title 'R3. Casos anômalos: referências A, B, C x corrida'; run;
proc print data=casos_stints noobs; title 'R3b. Stints de treino que formaram cada referência (res = resíduo; stint_fora = inconsistente)'; run;
proc print data=qualidade noobs; title "R4. Qualidade do alvo por alternativa (razão válida entre &q_inf e &q_sup)"; run;
proc means data=loo24 n mean median p90 maxdec=3; var erro;
  title 'R5. Validação do estimador C em 2024 (erro em s; deixa um piloto de fora)'; run;
proc sql; title 'R5b. Erro absoluto do estimador C em 2024';
  select count(*) as n, mean(abs(erro)) as mae format=6.3, median(abs(erro)) as mediana format=6.3 from loo24; quit;
proc print data=perda_pista noobs; title 'R6. Piloto-corridas sem referência por pista'; run;
proc print data=perda_equipe noobs; title 'R7. Piloto-corridas sem referência por equipe'; run;
proc print data=cond_fds noobs; title 'R8. Corrida - treino (nível do grid) por fim de semana'; run;
proc sql; title 'R8b. Sessões com efeito acima de 1 s (condição diferente das outras sessões)';
  select * from cond_sessao where abs(efeito_s) > 1 order by ano, circuito; quit;
title;

/* ---------- 12. variante CA: referência A + checagem própria + estimativa pré-corrida ---------- */
%macro qa(s);
  proc sql;
    create table qa&s as                                /* razão da referência A sobre a melhor volta do piloto */
    select a.session_key, a.driver_number, a.ritmo_treino as ref_a, b.melhor, a.ritmo_treino / b.melhor as q_a
    from ref&s a inner join best&s b on a.session_key = b.race_session_key and a.driver_number = b.driver_number;
  quit;
%mend qa;
%qa(24)
%qa(25)
proc univariate data=qa24 noprint; var q_a; output out=qalim q1=q1 q3=q3; run;   /* limites só com 2024 */
data _null_;
  set qalim;
  call symputx('a_inf', q1 - 3 * (q3 - q1));            /* Q1 - 3 x IQR */
  call symputx('a_sup', q3 + 3 * (q3 - q1));            /* Q3 + 3 x IQR */
run;
%macro ca(s);
  data qa&s; set qa&s; valido_a = (&a_inf <= q_a <= &a_sup); run;   /* checagem com dados do próprio piloto */
  proc sql;
    create table qfa&s as                               /* razão típica do fim de semana (referências A válidas) */
    select session_key, median(q_a) as q_fds from qa&s where valido_a = 1 group by 1;
    create table refca&s as                             /* A válida; senão melhor volta x razão do fim de semana */
    select b.race_session_key as session_key, b.driver_number,
           case when q.valido_a = 1 then q.ref_a else b.melhor * f.q_fds end as ref_ca,
           (coalesce(q.valido_a, 0) = 0) as estimada_ca
    from best&s b left join qa&s q on b.race_session_key = q.session_key and b.driver_number = q.driver_number
                  left join qfa&s f on b.race_session_key = f.session_key;
  quit;
%mend ca;
%ca(24)
%ca(25)
proc sql;
  create table lap_all2 as                              /* acrescenta o alvo da variante CA */
  select l.*, r.ref_ca, r.estimada_ca, ifn(not missing(r.ref_ca), l.lap_duration - r.ref_ca, .) as y_ca
  from lap_all l left join (select * from refca24 union all select * from refca25) r
       on l.session_key = r.session_key and l.driver_number = r.driver_number;
quit;
data lap_all; set lap_all2; run;
%qualidade(ca)
%macro dam(alt);                                        /* desvio médio da mediana da corrida (sem efeito de nível) */
  proc sql;
    create table dm_&alt as select ano, session_key, y_med, median(y_med) as med_corrida
      from pc_&alt group by ano, session_key;
    create table r_&alt as select "&alt" as alt length=3, ano, mean(abs(y_med - med_corrida)) as dam_s format=6.3
      from dm_&alt group by ano;
  quit;
%mend dam;
%dam(a)
%dam(b)
%dam(c)
%dam(ca)
data rob; set r_a r_b r_c r_ca; run;
data qualidade2; length alternativa $3; set q_a q_b q_c q_ca; run;
proc sql;
  create table qual_final as select q.*, r.dam_s from qualidade2 q left join rob r
  on q.ano = r.ano and strip(q.alternativa) = strip(r.alt) order by ano, alternativa;
quit;
proc print data=qual_final noobs; title "R9. Qualidade do alvo por alternativa (escolha só com 2024; limites CA: &a_inf a &a_sup)"; run;
title;
