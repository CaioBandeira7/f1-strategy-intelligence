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
