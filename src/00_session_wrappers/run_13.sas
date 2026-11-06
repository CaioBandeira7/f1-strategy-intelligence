/* run_13.sas - sessão nova: recria a base (12), refaz as métricas v1 (11) e compara as alternativas (13) */
ods exclude all;                                        /* 12 e 11 sem imprimir (já reportados) */
/* =====================================================================
   12_auditoria_dados.sas - Auditoria A (dados) e B (vazamento temporal)
   Só LÊ e CONFERE: não altera nenhuma tabela usada pelos modelos.
   Pré-requisito: WORK com v24/v25, lr24/lr25, ref24/ref25, real24/real25
   (o bloco 0 recria tudo, se a sessão tiver sido reiniciada).
   ===================================================================== */
options locale=en_US validvarname=v7;                   /* ponto decimal e nomes válidos */
%let pasta = ~/f1;                                      /* pasta do projeto */

/* ---------- 0. garante as tabelas da WORK ---------- */
%macro garante;
  %if not %sysfunc(exist(work.ref25)) %then %do;        /* sessão nova: recria a base */
    ods exclude all;                                    /* sem imprimir a reconstrução */
    %include "&pasta/08_degradacao_treinos.sas";        /* importa, limpa, treinos (inclui 01_02, 03, 04) */
    %macro ref(s);                                      /* mesma referência do programa 10 */
      proc means data=lr&s noprint nway;
        class race_session_key driver_number; var lap_duration;
        output out=ref&s(drop=_type_ rename=(_freq_=n_ref race_session_key=session_key)) median=ritmo_treino;
      run;
    %mend ref;
    %ref(24) %ref(25)
    ods exclude none;
  %end;
%mend garante;
%garante

%macro importa(arq, tab);                               /* leitura de CSV (igual ao 01) */
  proc import datafile="&pasta/&arq" out=&tab dbms=csv replace; guessingrows=max; run;
%mend importa;

/* ---------- A1. base usada no Model Studio ---------- */
cas mysess;                                             /* sessão CAS */
caslib _all_ assign;
data ms; set casuser.F1_2024_PARA_MODEL_STUDIO; run;    /* cópia local da tabela do Model Studio */
proc sql;
  title 'A1. Voltas, corridas e pistas por partição (1 treino, 2 validação, 0 teste)';
  select particao, ano, count(*) as voltas, count(distinct session_key) as corridas,
         count(distinct circuito) as pistas
  from ms group by particao, ano;
  title 'A2. Duplicatas na chave corrida-piloto-volta';
  select count(*) as linhas,
         count(distinct catx('_', session_key, driver_number, lap_number)) as chaves_unicas
  from ms;
  title 'A3. Corridas de validação (2024) - divisão por corrida inteira?';
  select session_key, circuito, count(*) as voltas,
         count(distinct particao) as particoes_na_corrida   /* 1 = corrida inteira numa partição */
  from ms where ano = 2024 group by session_key, circuito having max(particao) = 2;
  title 'A3b. Alguma corrida aparece em mais de uma partição?';
  select count(*) as corridas_misturadas from
    (select session_key from ms group by session_key having count(distinct particao) > 1);
quit;
proc means data=ms n nmiss min p1 median p99 max maxdec=3;   /* ausentes e extremos */
  class particao; var y prog tyre_age;
  title 'A4. Ausentes e extremos por partição';
run;

/* ---------- A5. funil de limpeza das voltas de corrida ---------- */
%importa(f1_2024_secas_voltas_marcadas.csv, mk24)       /* voltas com todas as marcações (2024) */
%importa(f1_2025_secas_voltas_marcadas.csv, mk25)       /* idem 2025 */
%macro funil(s);
  select "20&s" as ano, count(*) as total,
         sum(lap_number = 1) as volta1,
         sum(upcase(cats(is_in_lap)) = 'TRUE') as entrada_box,
         sum(upcase(cats(is_pit_out_lap)) = 'TRUE') as saida_box,
         sum(upcase(cats(limpa)) = 'TRUE') as limpas,
         sum(upcase(cats(sc_t)) = 'TRUE') as sc_vsc,
         sum(upcase(cats(relargada_t)) = 'TRUE') as relargada,
         sum(upcase(cats(pos_vermelha)) = 'TRUE') as bandeira_verm,
         sum(upcase(cats(usar2)) = 'TRUE') as usadas
  from mk&s
%mend funil;
proc sql;
  title 'A5. Funil de limpeza (uma volta pode ter mais de um motivo)';
  %funil(24) union all %funil(25);
  title 'A6. Regra da bandeira vermelha: quais voltas foram excluídas';
  select '2024' as ano, circuito, min(lap_number) as primeira, max(lap_number) as ultima,
         count(*) as voltas_excluidas
  from mk24 where upcase(cats(pos_vermelha)) = 'TRUE' group by circuito
  union all
  select '2025', circuito, min(lap_number), max(lap_number), count(*)
  from mk25 where upcase(cats(pos_vermelha)) = 'TRUE' group by circuito;
quit;

/* ---------- A7. voltas lentas que sobreviveram à limpeza ---------- */
%macro lentas(s);
  proc sql;
    create table lt&s as
    select v.session_key, v.circuito, v.driver_number, v.lap_number, v.lap_duration,
           v.lap_duration / m.med as rel                /* tempo relativo à mediana do piloto */
    from v&s v inner join
         (select session_key, driver_number, median(lap_duration) as med
          from v&s where usar2 = 1 group by session_key, driver_number) m
         on v.session_key = m.session_key and v.driver_number = m.driver_number
    where v.usar2 = 1;
  quit;
%mend lentas;
%lentas(24)
%lentas(25)
proc sql;
  title 'A7. Voltas "limpas" muito lentas (acima de 105% e 110% da mediana do piloto)';
  select '2024' as ano, count(*) as voltas, sum(rel > 1.05) as acima_105, sum(rel > 1.10) as acima_110 from lt24
  union all select '2025', count(*), sum(rel > 1.05), sum(rel > 1.10) from lt25;
quit;

/* ---------- B1. cobertura da referência de treino ---------- */
%macro cobertura(s);
  proc sql;
    create table cob&s as
    select v.session_key, v.circuito, v.driver_number, count(*) as voltas, max(f.n_ref) as n_ref
    from v&s v left join ref&s f
         on v.session_key = f.session_key and v.driver_number = f.driver_number
    where v.usar2 = 1 and v.compound in ('SOFT','MEDIUM','HARD')
    group by v.session_key, v.circuito, v.driver_number;
  quit;
%mend cobertura;
%cobertura(24)
%cobertura(25)
%macro resumo_cob(s);
  select "20&s" as ano, count(*) as pilotos_corrida,
         sum(missing(n_ref)) as sem_ref,
         sum(not missing(n_ref) and n_ref < 6) as ref_curta,
         sum(voltas) as voltas_limpas,
         sum(voltas * (not missing(n_ref) and n_ref >= 6)) as voltas_mantidas
  from cob&s
%mend resumo_cob;
proc sql;
  title 'B1. Pilotos sem referência válida de treino (são excluídos da base)';
  %resumo_cob(24) union all %resumo_cob(25);
  title 'B2. Pistas de 2025 fora da base (não existem em 2024)';
  select distinct circuito from v25
  where usar2 = 1 and circuito not in (select distinct circuito from ms where ano = 2024);
quit;

/* ---------- B3. os treinos aconteceram antes da corrida? ---------- */
%macro antes(s);
  select "20&s" as ano, race_session_key, max(circuito) as circuito,
         count(distinct session_key) as treinos, max(session_key) as ultimo_treino,
         (max(session_key) < race_session_key) as antes_da_corrida
  from lr&s group by race_session_key
%mend antes;
proc sql;
  title 'B3. Sessões de treino usadas na referência (session_key menor = antes)';
  %antes(24) union all %antes(25);
quit;

/* ---------- B4. nº de voltas da corrida: real x programado ---------- */
data prog_oficial;                                      /* voltas programadas (regulamento) */
  infile datalines dlm=',' truncover;
  length circuito $40;
  input circuito $ voltas_prog;
  datalines;
Sakhir,57
Jeddah,50
Melbourne,58
Suzuka,53
Shanghai,56
Miami,57
Imola,63
Monte Carlo,78
Montreal,70
Catalunya,66
Spielberg,71
Silverstone,52
Hungaroring,70
Spa-Francorchamps,44
Zandvoort,72
Monza,53
Baku,51
Singapore,62
Austin,56
Mexico City,71
Interlagos,71
Las Vegas,50
Lusail,57
Yas Marina Circuit,58
;
run;
proc sql;
  title 'B4. Voltas usadas no denominador de prog x voltas programadas';
  select r.ano, r.circuito, r.voltas_corrida, p.voltas_prog,
         (r.voltas_corrida ne p.voltas_prog) as diferente
  from (select distinct '2024' as ano, circuito, voltas_corrida from real24
        union select distinct '2025', circuito, voltas_corrida from real25) r
       left join prog_oficial p on r.circuito = p.circuito
  order by calculated diferente desc, r.ano, r.circuito;
quit;

/* ---------- B5. a referência de treino é comparável? ---------- */
proc sql;
  title 'B5. Composto das voltas de simulação de corrida nos treinos';
  select '2024' as ano, compound, count(*) as voltas from lr24 group by compound
  union all select '2025', compound, count(*) from lr25 group by compound;
quit;
proc means data=ms n mean std p5 median p95 maxdec=3;  /* nível do alvo: corrida mais lenta que o treino? */
  class ano compound; var y;
  title 'B6. Alvo y (corrida - ritmo de treino) por ano e composto';
run;

/* ---------- A8-A10. valores extremos do alvo ---------- */
proc sql;
  title 'A8. Voltas com |y| > 5 s por partição';
  select particao, count(*) as voltas, sum(abs(y) > 5) as acima_5s, sum(abs(y) > 10) as acima_10s,
         sum(y < -5) as rapidas_demais
  from ms group by particao;
  title 'A9. Piloto-corrida com mediana de y mais distante de zero (referência suspeita)';
  select ano, circuito, driver_number, count(*) as voltas,
         median(y) as y_mediano format=7.2, min(y) as y_min format=7.2, max(y) as y_max format=7.2
  from ms group by ano, circuito, driver_number
  having abs(calculated y_mediano) > 3
  order by calculated y_mediano;
  title 'A10. Voltas individuais com y > 20 s';
  select ano, circuito, driver_number, lap_number, compound, tyre_age, y format=7.2
  from ms where y > 20 order by y desc;
quit;
title;

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

ods exclude none;                                       /* volta a imprimir */
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
    create table best&s as                              /* melhor volta do piloto no fim de semana */
    select race_session_key, driver_number, min(lap_duration) as melhor
    from fp&s where lap_duration > 0 and is_pit_out_lap = 0
    group by race_session_key, driver_number;
    create table best&s as                              /* descarta erro de cronometragem (5% abaixo da mediana) */
    select b.* from best&s b inner join
         (select race_session_key, median(melhor) as mm from best&s group by race_session_key) m
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
  create table lap25 as select * from lap25 where circuito in (select distinct circuito from lap24);
quit;
data lap_all;                                           /* empilha e calcula o alvo de cada alternativa */
  set lap24(in=t) lap25;
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
