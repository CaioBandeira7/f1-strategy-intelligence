/* =====================================================================
   17_auditoria_2023.sas - cobertura e qualidade de 2023 x 2024 x 2025
   Só lê os arquivos f1_2023_* e cria tabelas novas com sufixo 23.
   Mesmas regras de limpeza dos módulos de 2024/2025 (programas 01_02 e 08).
   Pré-requisito: sessão com 2024/2025 carregados (programa 14).
   ===================================================================== */
options locale=en_US validvarname=v7;
%let pasta = ~/f1;

/* ---------- 0. importa 2023 com os mesmos procedimentos ---------- */
%importa(f1_2023_voltas_para_sas.csv,     v23)          /* voltas com usar2 */
%importa(f1_2023_estrategia_real.csv,     real23)       /* estratégia real */
%importa(f1_2023_stints.csv,              st23)         /* stints brutos */
%importa(f1_2023_perda_box_por_pista.csv, box23)        /* perda no box */
%importa(f1_2023_secas_voltas_marcadas.csv, mk23)       /* todas as marcações */
%importa(f1_2023_secas_race_control.csv,  rc23)         /* direção de prova */
%importa(f1_2023_treinos_voltas.csv,      fp23)         /* treinos livres */
%importa(f1_2023_equipes.csv,             eq23)         /* equipes */
%importa(f1_2024_secas_voltas_marcadas.csv, mk24)       /* comparação 2024 */
%importa(f1_2025_secas_voltas_marcadas.csv, mk25)       /* comparação 2025 */
%macro funil(s);                                        /* mesmo funil do programa 12 */
  select "20&s" as ano, count(*) as total, sum(lap_number = 1) as volta1,
         sum(upcase(cats(is_in_lap)) = 'TRUE') as entrada_box, sum(upcase(cats(is_pit_out_lap)) = 'TRUE') as saida_box,
         sum(upcase(cats(limpa)) = 'TRUE') as limpas, sum(upcase(cats(sc_t)) = 'TRUE') as sc_vsc,
         sum(upcase(cats(relargada_t)) = 'TRUE') as relargada, sum(upcase(cats(pos_vermelha)) = 'TRUE') as bandeira_verm,
         sum(upcase(cats(usar2)) = 'TRUE') as usadas
  from mk&s
%mend funil;
ods exclude all;
%longos(23)                                             /* simulações de corrida nos treinos (mesma regra do 08) */
ods exclude none;
%ref(23)                                                /* referência A de 2023 */

/* ---------- 1. corridas e escopo ---------- */
proc sql;
  create table pistas_ano as                            /* pistas secas por ano */
  select distinct 2023 as ano, circuito from v23
  union select distinct 2024, circuito from v24
  union select distinct 2025, circuito from v25;
  title 'Q1. Pistas secas por ano e sobreposição (1 = presente)';
  select circuito, max(ano = 2023) as a2023, max(ano = 2024) as a2024, max(ano = 2025) as a2025
  from pistas_ano group by circuito order by 2 desc, 3 desc, 1;
  title 'Q2. Resumo de escopo para a validação temporal';
  select sum(a23 and a24) as pistas_23_e_24, sum(a23 and a24 and a25) as pistas_nos_3_anos,
         sum(a24 and not a23) as pistas_24_sem_23, sum(a25 and not a23 and not a24) as pistas_25_sem_historico
  from (select circuito, max(ano = 2023) as a23, max(ano = 2024) as a24, max(ano = 2025) as a25
        from pistas_ano group by circuito);
quit;

/* ---------- 2. funil de limpeza (mesma régua de 2024/2025) ---------- */
proc sql;
  title 'Q3. Funil de limpeza por ano';
  %funil(23) union all %funil(24) union all %funil(25);
  title 'Q4. Bandeira vermelha em 2023 (regra corrigida: volta da bandeira + 2)';
  select circuito, min(lap_number) as primeira, max(lap_number) as ultima, count(*) as voltas_excluidas
  from mk23 where upcase(cats(pos_vermelha)) = 'TRUE' group by circuito;
  select circuito, lap_number as volta_bandeira from rc23
  where upcase(flag) = 'RED' and not missing(lap_number) order by 1, 2;
quit;

/* ---------- 3. compostos, idade do pneu e stints ---------- */
proc sql;
  title 'Q5. Compostos nas voltas de corrida (todas as voltas marcadas)';
  select '2023' as ano, compound, count(*) as voltas from mk23 group by compound
  union all select '2024', compound, count(*) from mk24 group by compound
  union all select '2025', compound, count(*) from mk25 group by compound;
  title 'Q6. Idade do pneu: ausentes, negativos e extremos (voltas usadas)';
  select '2023' as ano, count(*) as voltas, nmiss(tyre_age) as idade_ausente, sum(tyre_age < 0) as negativa,
         max(tyre_age) as idade_max, sum(tyre_age_at_start > 0) as stints_pneu_usado_voltas
  from v23 where usar2 = 1
  union all select '2024', count(*), nmiss(tyre_age), sum(tyre_age < 0), max(tyre_age), sum(tyre_age_at_start > 0) from v24 where usar2 = 1
  union all select '2025', count(*), nmiss(tyre_age), sum(tyre_age < 0), max(tyre_age), sum(tyre_age_at_start > 0) from v25 where usar2 = 1;
  title 'Q7. Cobertura de stints: voltas de corrida por piloto-corrida e voltas sem composto';
  select '2023' as ano, count(distinct catx('_', session_key, driver_number)) as piloto_corridas,
         count(*) as voltas, sum(missing(compound)) as sem_composto from v23
  union all select '2024', count(distinct catx('_', session_key, driver_number)), count(*), sum(missing(compound)) from v24
  union all select '2025', count(distinct catx('_', session_key, driver_number)), count(*), sum(missing(compound)) from v25;
quit;

/* ---------- 4. treinos livres e referência ---------- */
proc sql;
  title 'Q8. Treinos livres por fim de semana e simulações de corrida';
  select 2023 as ano, f.circuito, count(distinct f.session_key) as treinos, count(*) as voltas_treino,
         (select count(distinct id_stint) from lr23 l where l.race_session_key = f.race_session_key) as stints_longos,
         (select count(*) from ref23 r where r.session_key = f.race_session_key) as pilotos_com_ref
  from fp23 f group by f.race_session_key, f.circuito order by 2;
  title 'Q9. Cobertura da referência A por ano (piloto-corridas com voltas limpas de pneu seco)';
  select '2023' as ano, count(*) as piloto_corridas, sum(not missing(r.ritmo_treino)) as com_ref,
         calculated com_ref / calculated piloto_corridas as cobertura format=percent8.1
  from (select distinct session_key, driver_number from v23 where usar2 = 1 and compound in ('SOFT','MEDIUM','HARD')) p
       left join ref23 r on p.session_key = r.session_key and p.driver_number = r.driver_number
  union all
  select '2024', count(*), sum(not missing(r.ritmo_treino)), calculated com_ref / calculated piloto_corridas
  from (select distinct session_key, driver_number from v24 where usar2 = 1 and compound in ('SOFT','MEDIUM','HARD')) p
       left join ref24 r on p.session_key = r.session_key and p.driver_number = r.driver_number
  union all
  select '2025', count(*), sum(not missing(r.ritmo_treino)), calculated com_ref / calculated piloto_corridas
  from (select distinct session_key, driver_number from v25 where usar2 = 1 and compound in ('SOFT','MEDIUM','HARD')) p
       left join ref25 r on p.session_key = r.session_key and p.driver_number = r.driver_number;
  title 'Q10. Treinos antes da corrida (session_key do treino < da corrida)';
  select sum(antes) as fds_ok, count(*) as fds from
    (select race_session_key, (max(session_key) < race_session_key) as antes from fp23 group by 1);
quit;

/* ---------- 5. consistência das variáveis ---------- */
data prog_oficial23;                                    /* voltas programadas das pistas que só aparecem em 2023 */
  infile datalines dlm=',' truncover; length circuito $40; input circuito $ voltas_prog;
  datalines;
Sakhir,57
Jeddah,50
Melbourne,58
Baku,51
Miami,57
Monte Carlo,78
Catalunya,66
Montreal,70
Spielberg,71
Silverstone,52
Hungaroring,70
Spa-Francorchamps,44
Zandvoort,72
Monza,51
Singapore,62
Suzuka,53
Lusail,57
Austin,56
Mexico City,71
Interlagos,71
Las Vegas,50
Yas Marina Circuit,58
;
run;
proc sql;
  title 'Q11. Voltas da corrida (denominador de prog) x programadas em 2023';
  select r.circuito, r.voltas_corrida, p.voltas_prog, (r.voltas_corrida ne p.voltas_prog) as diferente
  from (select distinct circuito, voltas_corrida from real23) r left join prog_oficial23 p on r.circuito = p.circuito
  order by 4 desc, 1;
  title 'Q12. Tempo de volta e equipes (consistência entre anos)';
  select '2023' as ano, count(distinct e.team_name) as equipes, count(distinct e.driver_number) as pilotos,
         min(v.lap_duration) as volta_min format=8.2, max(v.lap_duration) as volta_max format=8.2
  from v23 v left join eq23 e on v.session_key = e.session_key and v.driver_number = e.driver_number where v.usar2 = 1
  union all
  select '2024', count(distinct e.team_name), count(distinct e.driver_number), min(v.lap_duration), max(v.lap_duration)
  from v24 v left join eq e on v.session_key = e.session_key and v.driver_number = e.driver_number where v.usar2 = 1;
  title 'Q13. Equipes de 2023';
  select team_name, count(distinct driver_number) as pilotos from eq23 group by 1;
quit;
title;
