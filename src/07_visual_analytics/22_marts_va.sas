/* =====================================================================
   22_marts_va.sas - marts do dashboard SAS VA (só reorganiza resultados
   congelados: V3c, auditorias e simulador rotulado). Sem modelagem nova.
   Rótulos em inglês (público internacional). Cada mart tem um grão único.
   Pré-requisito: sessão dos programas 14-21 (tabelas na WORK e em ~/f1).
   ===================================================================== */
cas s4 sessopts=(timeout=7200);                          /* sessão CAS nova */
libname casuser cas caslib="casuser" sessref=s4;
options sessref=s4;
%let home = %sysget(HOME);
%let criou = %sysfunc(dcreate(va_marts, &home/f1));
libname mart "&home/f1/va_marts";                        /* cópia permanente dos marts */
libname cand "&home/f1/candidata";
libname simf "&home/f1/simulador_final";

/* ---------- 1. temporadas (grão: ano) ---------- */
proc sql;
  create table m_season as
  select b.ano as season, count(distinct b.session_key) as races_evaluated,
         count(*) as laps_modelled, count(distinct catx('_', b.session_key, b.driver_number)) as driver_races,
         mean(b.ref_estimada) as share_laps_estimated_ref format=percent8.1
  from cand.base_candidata b group by b.ano;
  create table _pit as select ano as season, sum(pit_in and limpa_v2) as pitin_laps_reclassified,
         sum(sinal_b) as pit_records from pin_all group by ano;
  create table m_season as select s.*, p.pitin_laps_reclassified, p.pit_records
  from m_season s left join _pit p on s.season = p.season;
quit;

/* ---------- 2. métricas dos modelos (grão: experimento x modelo) ---------- */
data m_model;
  length experiment $70 exp_code $3 model $45 model_code $6 evaluation_scope $70;
  set r_E1c(in=a) r_E2c;
  exp_code = ifc(a, 'E1', 'E2');
  experiment = ifc(a, 'Train 2023 -> evaluate 2024', 'Train 2023-2024 -> evaluate 2025');
  evaluation_scope = ifc(a, 'Development validation (2024 used earlier to compare alternatives)',
                            'Historical evaluation (2025 previously examined)');
  model_code = modelo;
  select (modelo);
    when ('comB') model = 'V3c regression (with tyre age)';
    when ('semB') model = 'Regression without tyre age';
    when ('zero') model = 'Baseline: practice pace (zero)';
    otherwise model = modelo;
  end;
  mae_s = mae; rmse_s = rmse; mae_observed_ref_s = mae_obs;
  keep experiment exp_code evaluation_scope model model_code voltas corridas mae_s rmse_s mae_observed_ref_s;
  rename voltas = laps corridas = races;
run;

/* ---------- 3. comparações pareadas (grão: experimento x comparação) ---------- */
data m_compare;
  length exp_code $3 comparison $60 verdict $40;
  set boot_E1c(in=a) boot_E2c;
  exp_code = ifc(a, 'E1', 'E2');
  comparison = ifc(analise =: 'idade', 'Tyre-age effect (with vs without)', 'V3c regression vs practice-pace baseline');
  gain_s = ponto; ci_low_s = ic_2_5; ci_high_s = ic_97_5;
  races_better = corridas_melhor; races = corridas;
  verdict = ifc(ic_2_5 > 0, 'Improvement (95% CI above zero)', 'Not conclusive (95% CI crosses zero)');
  keep exp_code comparison gain_s ci_low_s ci_high_s races_better races verdict;
run;

/* ---------- 4. erro por volta (grão: experimento x modelo x volta) ---------- */
proc sql;
  create table _te as
  select 'E1' as exp_code length=3, session_key, driver_number, lap_number, circuito, compound, tyre_age, sprint, team_name from te_c1
  union all
  select 'E2', session_key, driver_number, lap_number, circuito, compound, tyre_age, sprint, team_name from te_c2;
  create table m_lap as
  select p.exp_code, p.modelo as model_code, p.session_key, p.circuito as circuit, p.driver_number, p.lap_number,
         t.compound, t.tyre_age, t.team_name as team, ifc(t.sprint = 1, 'Sprint', 'Standard') as weekend_type length=8,
         ifc(p.ref_estimada = 1, 'Estimated', 'Observed') as reference_type length=9,
         p.y as target_s, p.p as prediction_s, abs(p.y - p.p) as abs_error_s
  from (select 'E1' as exp_code length=3, * from pred_E1c union all select 'E2', * from pred_E2c) p
       inner join _te t on p.exp_code = t.exp_code and p.session_key = t.session_key
                       and p.driver_number = t.driver_number and p.lap_number = t.lap_number;
  create table m_race as                                /* grão: experimento x modelo x corrida */
  select exp_code, model_code, session_key, circuit, count(*) as laps, mean(abs_error_s) as mae_s
  from m_lap group by 1, 2, 3, 4;
quit;

/* ---------- 5. qualidade dos dados ---------- */
%macro funil(s);
  select 20&s as season, count(*) as total, sum(upcase(cats(is_in_lap)) = 'TRUE') as pit_in,
         sum(upcase(cats(is_pit_out_lap)) = 'TRUE') as pit_out, sum(upcase(cats(sc_t)) = 'TRUE') as sc_vsc,
         sum(upcase(cats(pos_vermelha)) = 'TRUE') as red_flag, sum(upcase(cats(usar2)) = 'TRUE') as clean_v2
  from mk&s
%mend funil;
proc sql;
  create table _f as %funil(23) union all %funil(24) union all %funil(25);
quit;
data m_funnel;                                          /* grão: ano x etapa */
  set _f; length stage $40;
  stage_order = 1; stage = 'All race laps (dry races)'; laps = total; output;
  stage_order = 2; stage = 'Safety car / VSC laps'; laps = sc_vsc; output;
  stage_order = 3; stage = 'Red-flag laps'; laps = red_flag; output;
  stage_order = 4; stage = 'Clean laps (V2 rules)'; laps = clean_v2; output;
  keep season stage_order stage laps;
run;
proc sql;
  create table m_pitfix as                              /* grão: ano x pista */
  select ano as season, circuito as circuit, sum(pit_in and limpa_v2) as laps_reclassified,
         sum(sinal_b) as pit_records, sum(troca_vermelha) as red_flag_tyre_changes
  from pin_all group by 1, 2 having calculated laps_reclassified > 0 or calculated red_flag_tyre_changes > 0;
  create table m_refbias as                             /* grão: equipe (2024, validação mascarada) */
  select team_name as team, count(*) as driver_races, mean(erro) as bias_s, mean(abs(erro)) as mae_s,
         mean(dev_obs) as dev_observed_s, mean(dev_est) as dev_estimated_s
  from loo_v group by 1;
quit;

/* ---------- 6. degradação e perda no box (grão: pista) ---------- */
proc sql;
  create table m_track as
  select d.circuito as circuit, d.deg as deg_race_2024_s_per_lap, c.deg_treino as deg_fp2025_s_per_lap,
         x.mediana as pit_loss_2024_s, x.paradas as pit_stops_measured
  from deg24_orig d left join cand c on d.circuito = c.circuito left join box24 x on d.circuito = x.circuito;
quit;

/* ---------- 7. simulador 2025 retrospectivo ---------- */
data m_sim_halves;                                      /* grão: entrada x metade */
  set simf.entrada_b_metades; length input_type $40 half $40;
  input_type = ifc(entrada = 'A_2024', 'A: race degradation 2024', ifc(entrada = 'B_treinos', 'B: practice 2025 (calibrated)', 'C: average of A and B'));
  half = ifc(grupo = 'validacao', '1st half 2025 - used to select input', '2nd half 2025 - later evaluation');
  stop_count_accuracy = acerto_paradas; first_stop_error_laps = mae_janela;
  keep input_type half corridas stop_count_accuracy first_stop_error_laps;
  rename corridas = races;
run;
proc sql;
  create table m_sim_base as                            /* grão: entrada x pista x estratégia (média dos 4 cenários) */
  select ifc(entrada = 'A_2024', 'A: race degradation 2024', 'B: practice 2025 (calibrated)') as input_type length=40,
         circuito as circuit, estrategia as strategy, rel as relative_cost_vs_optimum_s,
         case when entrada = 'A_2024' and circuito = 'Monte Carlo' then 'Invalid: Monaco 2025 requires 2 stops'
              else 'Valid' end as rule_check length=45
  from (select entrada, circuito, estrategia, mean(extra_s) as rel from t5_rel group by entrada, circuito, estrategia);
quit;
data m_sim_base; set m_sim_base; length strategy_en $45 strategy_role $30;   /* rótulos em inglês */
  select;
    when (strategy =: 'simulador') do; strategy_en = 'Simulator optimum (reference = 0)'; strategy_role = 'Simulator'; sort_order = 1; end;
    when (strategy =: '1p') do; strategy_en = 'Fixed 1-stop (M-H at half distance)'; strategy_role = 'Simple baseline'; sort_order = 2; end;
    when (strategy =: '2p') do; strategy_en = 'Fixed 2-stop (M-H-H at 1/3, 2/3)'; strategy_role = 'Simple baseline'; sort_order = 3; end;
    when (strategy =: 'observada melhor') do; strategy_en = 'Best observed driver strategy'; strategy_role = 'Retrospective (actual race)'; sort_order = 4; end;
    otherwise do; strategy_en = 'Median observed driver strategy'; strategy_role = 'Retrospective (actual race)'; sort_order = 5; end;
  end;
  drop strategy; rename strategy_en = strategy;
run;

/* ---------- 8. notas (resultados negativos, limitações, escopo) ---------- */
data m_notes;
  length page $30 note_type $20 note $250;
  infile datalines dlm='|' truncover; input page $ note_type $ note $;
  datalines;
Overview|Negative result|In 2023->2024 the V3c regression does not beat the practice-pace baseline (MAE 1.325 vs 1.332 s, CI crosses zero).
Overview|Negative result|Tyre-age effect is clear in 2024 but not conclusive in 2025 (95% CI crosses zero).
Overview|Scope|2024 was used to compare alternatives, 2025 was examined before. Neither is an untouched test.
Model|Negative result|Track-level offsets learned in one season do not transfer to the next.
Model|Limitation|Estimated practice reference has team-level bias (Alpine +0.62 s, Haas -0.31 s).
Model|Limitation|Sprint weekends: practice reference explains little of race pace.
Data|Limitation|OpenF1 lacks pit records for 6 races in 2023, pit-in laps were identified from stint boundaries and out-laps.
Simulator|Scope|Simulator 2024 is in-sample and descriptive.
Simulator|Scope|Costs are relative seconds between strategies, not absolute race times.
Simulator|Scope|Simulator uses the program-02 degradation model, it is not integrated with the V3c regression.
Simulator|Scope|2025 input B was selected with 1st-half results, only the 2nd half is a later evaluation.
Simulator|Limitation|No traffic, safety car, undercut, tyre allocation or weather. Max 2 stops, new tyres every stint.
Simulator|Limitation|Monaco 2025 two-stop rule not modelled, input A recommendation flagged invalid. Lusail, Catalunya, Interlagos and Spielberg 2025 not simulated.
;
run;

/* ---------- 9. validações ---------- */
%macro chave(tab, chave);                                /* duplicatas na chave do grão */
  select "&tab" as mart length=20, count(*) as rows,
         count(*) - count(distinct catx('|', &chave)) as duplicate_keys from &tab
%mend chave;
proc sql;
  create table v_grain as
  %chave(m_season, season) union all
  %chave(m_model, %str(exp_code, model_code)) union all
  %chave(m_compare, %str(exp_code, comparison)) union all
  %chave(m_lap, %str(exp_code, model_code, session_key, driver_number, lap_number)) union all
  %chave(m_race, %str(exp_code, model_code, session_key)) union all
  %chave(m_funnel, %str(season, stage_order)) union all
  %chave(m_pitfix, %str(season, circuit)) union all
  %chave(m_refbias, team) union all
  %chave(m_track, circuit) union all
  %chave(m_sim_halves, %str(input_type, half)) union all
  %chave(m_sim_base, %str(input_type, circuit, strategy)) union all
  %chave(casuser.F1_SIMULADOR_ROTULADO, %str(circuito, cenario));
  create table v_consist as                             /* mesmas métricas por caminhos diferentes */
  select m.exp_code, m.model_code, m.laps as laps_model, l.n as laps_lap_mart, m.mae_s, l.mae as mae_from_laps,
         abs(m.mae_s - l.mae) as diff
  from m_model m inner join (select exp_code, model_code, count(*) as n, mean(abs_error_s) as mae from m_lap group by 1, 2) l
       on m.exp_code = l.exp_code and m.model_code = l.model_code;
  create table v_rel as                                 /* integridade das relações */
  select 'm_race -> m_lap (session)' as relation length=40,
         (select count(*) from (select distinct session_key from m_race) where session_key not in (select session_key from m_lap)) as orphans
  from m_season(obs=1)
  union all select 'm_pitfix -> m_season (year)', (select count(*) from m_pitfix where season not in (select season from m_season)) from m_season(obs=1)
  union all select 'm_sim_base -> m_track (circuit)', (select count(distinct circuit) from m_sim_base where circuit not in (select circuit from m_track)) from m_season(obs=1)
  union all select 'm_lap teams missing', (select count(*) from m_lap where missing(team)) from m_season(obs=1);
quit;

/* ---------- 10. publica no CAS e salva cópia ---------- */
%macro pub(src, nome);
  proc casutil;
    droptable casdata="&nome" incaslib="casuser" quiet;
    load data=work.&src outcaslib="casuser" casout="&nome" promote;
    save casdata="&nome" incaslib="casuser" outcaslib="casuser" casout="&nome..sashdat" replace;
  quit;
  data mart.&nome; set work.&src; run;
%mend pub;
%pub(m_season,     F1VA_SEASON)
%pub(m_model,      F1VA_MODEL_METRICS)
%pub(m_compare,    F1VA_MODEL_COMPARE)
%pub(m_lap,        F1VA_LAP_ERROR)
%pub(m_race,       F1VA_RACE_ERROR)
%pub(m_funnel,     F1VA_DATA_FUNNEL)
%pub(m_pitfix,     F1VA_PITIN_FIX)
%pub(m_refbias,    F1VA_REF_BIAS_TEAM)
%pub(m_track,      F1VA_TRACK)
%pub(m_sim_halves, F1VA_SIM2025_HALVES)
%pub(m_sim_base,   F1VA_SIM2025_BASELINES)
%pub(m_notes,      F1VA_NOTES)

proc print data=v_grain noobs; title 'G. Grão e duplicatas'; run;
proc print data=v_consist noobs; title 'C. Consistência MAE (mart de métricas x mart de voltas)'; run;
proc print data=v_rel noobs; title 'R. Relações'; run;
proc print data=m_season noobs; title 'S. Temporadas'; run;
proc print data=m_model noobs; title 'M. Modelos'; run;
proc print data=m_compare noobs; title 'P. Comparações'; run;
title;
