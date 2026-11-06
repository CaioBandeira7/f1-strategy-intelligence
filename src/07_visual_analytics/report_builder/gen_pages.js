// ---- pages (uses window.__B, window.__h, window.__DS) ----
const {graph,listTable,prompt}=window.__B; const {header,kpi,panel,row,col,page,C,CARD,CARD_ALT,CARD_AMBER,CARD_RED}=window.__h; const text=window.__text;
const T=window.__n;
const BAR='ve231',DOT='ve243',HIST='ve283';
const bar=(ds,cat,resp,grp,title,orient='horizontal')=>graph(T,BAR,ds,{experiment:cat,mae_s:resp,model:grp===undefined?null:grp},title,{orient});
const ci=(title)=>listTable('compare',['label','gain_s','ci_low_s','ci_high_s','verdict'],title);
const dot=(title)=>graph(T,DOT,'compare',{comparison:'comparison',gain_s:'gain_s',exp_code:'exp_label'},title);
const S=(h)=>o=>Object.assign(o,{h});

// ================= PAGE 1 =================
{
 const hd=header('EXECUTIVE  |  1 · OVERVIEW','Formula 1 Tyre Degradation & Pit Strategy','Can practice-session pace predict race lap times as tyres wear?  F1 Strategy Intelligence · Tyre Degradation, Predictive Analytics & Pit Strategy · 2023–2025','Scope: 54 dry races (OpenF1). 2024 = development validation · 2025 = historical evaluation, previously examined.');
 const k1=kpi('RACES ANALYSED','54','2023: 17  |  2024: 19  |  2025: 18');
 const k2=kpi('MODELLED LAPS','50,580','Three-season candidate dataset (V3c)');
 const k3=kpi('2025 MODEL MAE','1.134 s/lap','Zero baseline: 1.302 s/lap · lower is better','kred');
 const k4=kpi('TYRE-AGE EFFECT','Inconclusive in 2025','+0.036 s gain · 95% CI [-0.021; +0.101] crosses zero','kamb',CARD_AMBER);
 const g1=bar('metrics','exp_label','mae_s','model_short','Predictive Accuracy Across Seasons · MAE (s per lap), lower is better','vertical');
 const g2=dot('Uncertainty in Model Improvements · estimated gain (s per lap)');
 const t2=ci('95% bootstrap confidence intervals (races resampled)');
 const p1=panel('The Challenge',['Can pre-race practice data explain lap-time variation and support pit-strategy analysis?','Target: race lap time minus the driver\'s practice long-run pace, explained by tyre age, compound and race progress.']);
 const p2=panel('What We Found',['Tyre age improved predictive performance in the 2024 evaluation, but its incremental benefit was not statistically conclusive in 2025.',['The model did not demonstrate a statistically reliable advantage over the zero baseline.','warn']]);
 const p3=panel('Two Analytical Components',['The V3c regression evaluates lap-time prediction (pages 2–4).','The strategy simulator separately uses degradation estimates from the original 2024 GLM (pages 5–6).',['They are not integrated into one predictive system.','warn']]);
 const nav=text([['NAVIGATION','klab'],['EXECUTIVE: 1 Overview   ·   TECHNICAL ANALYSIS: 2 Data & Quality · 3 Tyre Degradation · 4 Model Validation · 7 Method & Limitations   ·   STRATEGY SIMULATOR: 5 Simulator 2024 · 6 Simulator 2025','note'],['2024 was used during development; 2025 results are historical evaluations, not untouched holdout tests. Sources: F1VA_SEASON, F1VA_MODEL_METRICS, F1VA_MODEL_COMPARE, F1VA_NOTES.','note']],CARD_ALT,'Footer');
 page('1 · Overview',[S('15%')(hd),row([k1,k2,k3,k4],['25%','25%','25%','25%'],'15%'),row([g1,col([g2,t2],['60%','40%'])],['55%','45%'],'40%'),row([p1,p2,p3],['33%','34%','33%'],'19%'),S('11%')(nav)]);
}
// ================= PAGE 2 =================
{
 const hd=header('TECHNICAL ANALYSIS  |  2 · DATA & QUALITY','Data Engineering & Quality','From raw race telemetry to reproducible modelling datasets.','Scope: dry races 2023–2025 · OpenF1 laps, stints, pit stops and race control · cleaning rules V2/V3c.');
 const k1=kpi('TOTAL MODELLED LAPS','50,580','After cleaning and reference join');
 const k2=kpi('RACES PER SEASON','17 · 19 · 18','2023 · 2024 · 2025 (dry races)');
 const k3=kpi('PIT-IN LAPS RECLASSIFIED','205','2023: 128 · 2024: 43 · 2025: 34','kred');
 const k4=kpi('PRACTICE-REFERENCE COVERAGE','77.0% · 83.9% · 80.5%','Observed long-run reference, 2023 · 2024 · 2025');
 const g1=bar('funnel','stage_label','laps','season_label','Data Cleaning Funnel · laps per stage (categories can overlap; not additive)');
 const g2=bar('season','season_label','ref_a_coverage',undefined,'Practice Reference Coverage · driver-races with an observed long-run reference','vertical');
 const g3=bar('pitfix','circuit','laps_reclassified','season_label','Corrected Pit-In Detection · clean laps reclassified as pit-in, by circuit');
 const g4=bar('bias','team','bias_s',undefined,'Reference Estimation Bias by Team (s) · estimated minus observed practice reference');
 const p=panel('Data Quality Decisions',['Excluded: safety car / VSC laps, red-flag laps (flag lap + 2), lap 1, pit-in and pit-out laps. A lap can match more than one rule, so stage counts are not additive.','Pit-in rule (all seasons): pit record OR next lap is a pit-out lap OR last lap of a non-final stint; exceptions for red-flag tyre changes and retirements. OpenF1 lacks pit records for 6 races in 2023.',['Team bias refers to the estimated practice reference, not directly to the race-model error. Missing references are estimated from the driver\'s best lap and the weekend ratio; models were trained on observed references only.','note']]);
 page('2 · Data & Quality',[S('13%')(hd),row([k1,k2,k3,k4],['25%','25%','25%','25%'],'14%'),row([g1,g2],['60%','40%'],'30%'),row([g3,g4],['55%','45%'],'30%'),S('13%')(p)]);
}
// ================= PAGE 3 =================
{
 const hd=header('TECHNICAL ANALYSIS  |  3 · TYRE DEGRADATION','Tyre Degradation Analysis','How tyre-age assumptions shape estimated strategy costs.','Scope: degradation from the 2024 race GLM (program 02) and the 2025 practice-based input B. Not the V3c regression.');
 const k1=kpi('2024 DEGRADATION RANGE','0.026 – 0.120','seconds per lap, per lap of tyre age (18 circuits)');
 const k2=kpi('2025 INPUT B RANGE','0.016 – 0.107','practice-based, calibrated on 2024 (14 circuits)');
 const k3=kpi('PIT-STOP TIME LOSS','18.0 – 30.3 s','median per circuit, 2024 races');
 const k4=kpi('CIRCUITS WITH DATA','18','14 with both 2024 and 2025 estimates');
 const g1=bar('track','circuit','deg_race_2024_s_per_lap',undefined,'Estimated Degradation by Circuit · 2024 race GLM (s/lap per lap of tyre age)');
 const g2=bar('track','circuit',['deg_race_2024_s_per_lap','deg_fp2025_s_per_lap'],undefined,'2024 Race GLM vs 2025 Practice-Based Input B · different sources and methods');
 const g3=bar('track','circuit','pit_loss_2024_s',undefined,'Estimated Pit-Lane Time Loss (s) · in-lap + out-lap minus 2 typical laps');
 const g4=bar('lap','age_band','abs_error_s','compound','Lap-Time Error by Tyre Age · mean absolute error (s) by compound','vertical');
 const f1=prompt('lap','exp_code','Experiment',[g4]); const f2=prompt('lap','model_short','Model',[g4]);
 const p=panel('Method note',['The strategy simulator uses the degradation slope from the program-02 GLM (2024 races) or the practice-based input B, not the V3c regression. The two estimates come from different data and methods and are not directly equivalent measurements.',['Lap-time error panel uses frozen V3c evaluation predictions (F1VA_LAP_ERROR) and is filtered by experiment and model.','note']]);
 page('3 · Tyre Degradation',[S('13%')(hd),row([k1,k2,k3,k4],['25%','25%','25%','25%'],'13%'),row([g1,g2],['45%','55%'],'32%'),row([g3,col([row([f1,f2],['50%','50%'],'22%'),g4])],['45%','55%'],'30%'),S('12%')(p)]);
}
// ================= PAGE 4 =================
{
 const hd=header('TECHNICAL ANALYSIS  |  4 · MODEL VALIDATION','Model Validation & Generalisation','Evaluating predictive performance across racing seasons.','E1: train 2023 -> evaluate 2024 (development validation) · E2: train 2023–2024 -> evaluate 2025 (historical, previously examined).');
 const k1=kpi('E1 V3c MAE','1.325 s','Zero baseline 1.332 s · without tyre age 1.422 s','kred');
 const k2=kpi('E2 V3c MAE','1.134 s','Zero baseline 1.302 s · without tyre age 1.179 s','kred');
 const k3=kpi('E1 TYRE-AGE GAIN','+0.107 s','95% CI [+0.028; +0.207] · 11 of 14 races','kval');
 const k4=kpi('E2 TYRE-AGE GAIN','+0.036 s','95% CI [-0.021; +0.101] · inconclusive','kamb',CARD_AMBER);
 const g1=bar('metrics','exp_label','mae_s','model_short','Model Comparison · MAE (s per lap), lower is better','vertical');
 const g2=bar('race','circuit','mae_s',undefined,'Race-Level Prediction Error · MAE (s per lap) by race');
 const f1=prompt('race','exp_code','Experiment',[g2]); const f2=prompt('race','model_short','Model',[g2]);
 const g3=dot('Uncertainty & Statistical Evidence · gain (s per lap)');
 const t3=ci('95% confidence intervals');
 const g4=graph(T,HIST,'lap',{gain_s:'signed_error_s'},'Prediction Error Distribution · signed error (s), actual minus predicted');
 const f3=prompt('lap','exp_code','Experiment',[g4]); const f4=prompt('lap','model_short','Model',[g4]);
 const p=panel('What the Model Does Not Establish',[['No statistically reliable advantage over the zero baseline (E1 -0.011 s, E2 +0.178 s; both CIs cross zero).','warn'],'Tyre-age improvement varies across seasons. Circuit-level effects do not transfer reliably between years.','Previously examined seasons are not untouched test sets; 2025 metrics are not proof of future performance.']);
 page('4 · Model Validation',[S('12%')(hd),row([k1,k2,k3,k4],['25%','25%','25%','25%'],'13%'),row([g1,col([row([f1,f2],['50%','50%'],'20%'),g2])],['45%','55%'],'31%'),row([col([g3,t3],['60%','40%']),col([row([f3,f4],['50%','50%'],'20%'),g4])],['50%','50%'],'31%'),S('13%')(p)]);
}
// ================= PAGE 5 =================
{
 const hd=header('STRATEGY SIMULATOR  |  5 · SIMULATOR 2024','Pit Strategy Simulator | 2024','In-sample optimisation under simplified tyre-degradation assumptions.','Minimum estimated cost under model assumptions, not an optimal real-world race strategy.');
 const w1=text([['IN-SAMPLE ANALYSIS — 2024','warn'],['Degradation estimated on the same 2024 races.','note']],CARD_AMBER,'W1');
 const w2=text([['RELATIVE STRATEGY COST','warn'],['Seconds between strategies, not total race time.','note']],CARD_AMBER,'W2');
 const w3=text([['SOURCE — ORIGINAL 2024 GLM','warn'],['Program 02; not integrated with V3c.','note']],CARD_AMBER,'W3');
 const g1=bar('sim24','circuit','cost_advantage_s','recommended','One Stop vs Two Stops · cost advantage of the lowest-cost option (s), by circuit');
 const g2=bar('sim24','scenario',['lap_1stop','lap_2stop_first','lap_2stop_second'],undefined,'Optimal Pit Laps · lowest-cost stop laps by soft-tyre scenario');
 const t3=listTable('sim24',['scenario','recommended','plan_1stop','plan_2stop','lap_1stop','lap_2stop_first','lap_2stop_second','cost_advantage_s'],'Scenario Sensitivity · selected circuit, four soft-tyre scenarios');
 const fs=prompt('sim24','scenario','Soft-tyre scenario',[g1]);
 const fc=prompt('sim24','circuit','Circuit',[g2,t3]);
 const p=panel('Simulator Assumptions',['Cost = sum over stints of degradation x tyre age + compound pace offset + fixed pit-stop loss per stop. Linear degradation; tyre age resets at each stop; new tyres every stint; 1 or 2 stops; stints of at least 5 laps; at least two dry compounds.','Not modelled: traffic, safety car / VSC, undercut, tyre allocation, weather. The ±1 s pit window is not stored in the frozen mart, so only the lowest-cost stop laps are shown.']);
 page('5 · Simulator 2024',[S('12%')(hd),row([w1,w2,w3],['33%','34%','33%'],'10%'),row([fs,fc],['50%','50%'],'8%'),row([g1,g2],['55%','45%'],'34%'),S('22%')(t3),S('14%')(p)]);
}
// ================= PAGE 6 =================
{
 const hd=header('STRATEGY SIMULATOR  |  6 · SIMULATOR 2025','Pit Strategy Evaluation | 2025','Historical comparison of strategy inputs and simple baselines.','First half: used for input selection · second half: later historical evaluation, not a fully untouched test set.');
 const k1=kpi('CIRCUITS EVALUATED','14','2025 circuits with 2024 degradation and pit loss');
 const k2=kpi('FIRST HALF','7 races','Used to select input B (selection, not test)','kamb',CARD_AMBER);
 const k3=kpi('SECOND HALF','7 races','Later historical evaluation');
 const k4=kpi('INPUT B · 2ND HALF','43%','Stop-count accuracy (A: 29%, C: 43%)','kred');
 const g1=bar('halves','input_type','stop_count_accuracy','half','Strategy Input Comparison · stop-count accuracy (%) by season half');
 const g2=bar('halves','input_type','first_stop_error_laps','half','First Pit-Stop Prediction Error · mean absolute error (laps)');
 const g3=bar('base','strategy','relative_cost_vs_optimum_s','input_type','Estimated Strategy Cost vs Baselines · seconds above the simulator minimum (mean of 14 circuits)');
 const t4=listTable('base',['circuit','input_type','rule_check'],'Circuit-Level Strategy Validity');
 const p=text([['Reading notes','ctitle'],['Costs are seconds above the minimum of the simulator\'s own cost function; this is not real race-time saving. Monaco 2025 input A: INVALID — mandatory two-stop rule. Real-world team strategy is influenced by traffic, safety cars, tyre allocation and tactics absent from this simulator.','body']],CARD,'Notes');
 page('6 · Simulator 2025',[S('12%')(hd),row([k1,k2,k3,k4],['25%','25%','25%','25%'],'13%'),row([g1,g2],['50%','50%'],'30%'),row([g3,t4],['60%','40%'],'33%'),S('12%')(p)]);
}
// ================= PAGE 7 =================
{
 const hd=header('TECHNICAL ANALYSIS  |  7 · METHOD & LIMITATIONS','Methodology & Limitations','A reproducible workflow from practice data to analytical insights.','SAS Studio · CAS · Model Studio · Visual Analytics · OpenF1 API.');
 const s=(t,d,card=CARD)=>text([[t,'ctitle'],[d,'note']],card,t); const a=()=>text([['→','arrow']],null,'arrow');
 const r1=row([s('OpenF1 Data','Laps, stints, pits, race control, practice'),a(),s('Cleaning & Quality Checks','SC/VSC, red flags, pit-in rule'),a(),s('Practice Reference','Observed long run or weekend estimate'),a(),s('V3c Regression','Stepwise SBC, circuit × compound, tyre age',CARD_RED),a(),s('Temporal Evaluation','2023→2024, 2023–24→2025, bootstrap')],['17%','3%','17%','3%','17%','3%','17%','3%','20%'],'13%');
 const r2=row([s('2024 Race Data','Clean race laps, pit losses'),a(),s('Original Degradation GLM','Program 02, circuit × tyre-age slope'),a(),s('Strategy Cost Simulator','1–2 stops, exhaustive search'),a(),s('Retrospective Evaluation','2025 halves, simple baselines'),text([['No link between V3c and the simulator: separate components.','warn']],CARD_AMBER,'nolink')],['17%','3%','17%','3%','17%','3%','17%','23%'],'13%');
 const m1=panel('Dataset & Scope',['54 dry races, 2023–2025, 50,580 modelled laps. Target: race lap minus practice long-run pace.'],CARD,'note');
 const m2=panel('Model Specification',['Linear regression (SAS REGSELECT / Model Studio), stepwise SBC: circuit, compound, race progress, tyre age, circuit × compound.'],CARD,'note');
 const m3=panel('Temporal Design',['E1: train 2023, evaluate 2024. E2: train 2023–2024, evaluate 2025. No parameters chosen on the evaluation year.'],CARD,'note');
 const m4=panel('Bootstrap Uncertainty',['Paired differences per race; 1,000 race resamples; 95% percentile intervals.'],CARD,'note');
 const m5=panel('Simulator Assumptions',['Linear degradation, fixed pit loss, simplified compounds, minimum 5-lap stints, max 2 stops, no race dynamics.'],CARD,'note');
 const lim=listTable('notes',['page','note_type','note'],'Documented Limitations, Negative Results and Scope Notes');
 page('7 · Method & Limitations',[S('12%')(hd),r1,r2,row([m1,m2,m3,m4,m5],['20%','20%','20%','20%','20%'],'17%'),S('45%')(lim)]);
}
'pages '+window.__PAGES.length+' ve '+window.__OUT.ve.length
