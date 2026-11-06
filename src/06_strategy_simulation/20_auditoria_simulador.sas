/* =====================================================================
   20_auditoria_simulador.sas - auditoria do simulador (%simula, programa 03)
   Só lê. Não altera o simulador, a V3c nem os benchmarks.
   T1 testes sintéticos: o %simula roda numa corrida fictícia (ano 99) e cada
      custo é comparado com um recálculo independente volta a volta.
   T2 integridade das tabelas reais (sim24, sim25, F1_SIMULADOR).
   T3 regras esportivas e limites operacionais.
   T4 integridade temporal das entradas.
   T5 baselines: 1 parada fixa, 2 paradas fixas e estratégia observada
      (retrospectiva), todas avaliadas com a mesma função de custo.
   Pré-requisito: sessão com 01-04 e 08 (real*, deg24_orig, box24, cand, st25, offM).
   ===================================================================== */

/* ---------- 0. guarda o estado da sessão (restaurado no fim) ---------- */
data _bk_deg24; set deg24; run;                         /* entrada atual do simulador */
data _bk_box24; set box24; run;                         /* perda no box atual */
proc sql noprint;                                       /* offM recalculado do GLM 2024 (a macro global pode não existir na sessão) */
  select off into :offH trimmed from comp24 where compound = 'HARD';
  select off into :offM0 trimmed from comp24 where compound = 'MEDIUM';
quit;
%let _offM_bk = %sysevalf(&offM0 - &offH);              /* ritmo MEDIUM x HARD (2024: 0,01594 s/volta) */

/* ---------- 1. avaliador independente volta a volta ---------- */
/* custo de um plano = soma, volta a volta, de b*m*idade + o (idade reinicia em 0 a cada stint) + P por parada */
%macro defarr;                                          /* arrays dos cenários (uma vez por DATA step) */
  array _m[3] _temporary_; array _o[3] _temporary_;
%mend defarr;
%macro avaliador;
  _m[1] = 1; _m[2] = 1; _m[3] = ifn(cen in (1,2), 1.0, 1.7);   /* mesmos cenários do %simula */
  _o[1] = 0; _o[2] = &offM; _o[3] = ifn(cen in (1,3), -0.13, 0);
  custo_ind = 0; voltas_cont = 0; idade_ok = 1;
  do _s = 1 to nst;                                     /* cada stint */
    do _v = 1 to len[_s];                               /* cada volta do stint */
      _idade = _v - 1;                                  /* pneu novo: idade 0 na 1ª volta */
      custo_ind + b * _m[cp[_s]] * _idade + _o[cp[_s]];
      voltas_cont + 1;
    end;
  end;
  custo_ind + (nst - 1) * P;                            /* uma perda de box por parada */
%mend avaliador;

/* ---------- T1. testes sintéticos com o próprio %simula ---------- */
data real99;                                            /* 3 corridas fictícias */
  length circuito $40;
  input circuito $ voltas_corrida;
  datalines;
T_base 20
T_semdeg 20
T_altodeg 20
;
run;
data deg24; length circuito $40; input circuito $ deg; datalines;
T_base 0.10
T_semdeg 0
T_altodeg 1.00
;
run;
data box24; length circuito $40; input circuito $ mediana; datalines;
T_base 20
T_semdeg 20
T_altodeg 20
;
run;
%let offM = 0.05;                                       /* valor redondo para o teste */
ods exclude all;
%simula(99)
ods exclude none;
proc sql;
  create table t1 as
  select s.*, e.b, e.P, e.L from sim99 s inner join entrada99 e on s.circuito = e.circuito;
quit;
data t1;
  set t1;
  array len[3]; array cp[3]; %defarr
  nst = n_paradas + 1;
  len[1] = n1; len[2] = n2; len[3] = coalesce(n3, 0);
  cp[1] = whichc(c1, 'HARD', 'MEDIUM', 'SOFT'); cp[2] = whichc(c2, 'HARD', 'MEDIUM', 'SOFT');
  cp[3] = ifn(c3 = '', 1, whichc(c3, 'HARD', 'MEDIUM', 'SOFT'));
  %avaliador
  dif_custo = abs(custo - custo_ind);                   /* simulador x recálculo */
  soma_ok = (voltas_cont = L);                          /* stints somam a distância */
  comp_ok = (n_paradas = 1 and c1 ne c2) or (n_paradas = 2 and not (c1 = c2 and c2 = c3));
  min_ok = (min(n1, n2, coalesce(n3, 99)) >= 5);
  parada_ok = (k1 = n1);                                /* volta da 1ª parada = fim do 1º stint */
run;
data t1b;                                               /* busca exaustiva independente do ótimo (1 e 2 paradas) */
  set entrada99;
  array len[3]; array cp[3]; %defarr
  do cen = 1 to 4;
    melhor1 = 1e9; melhor2 = 1e9;
    do k1 = 5 to L - 5; do x = 1 to 3; do y = 1 to 3; if x ne y then do;
      nst = 2; len[1] = k1; len[2] = L - k1; len[3] = 0; cp[1] = x; cp[2] = y; cp[3] = 1;
      %avaliador
      melhor1 = min(melhor1, custo_ind);
    end; end; end; end;
    do k1 = 5 to L - 10; do k2 = k1 + 5 to L - 5; do x = 1 to 3; do y = 1 to 3; do w = 1 to 3;
      if not (x = y and y = w) then do;
        nst = 3; len[1] = k1; len[2] = k2 - k1; len[3] = L - k2; cp[1] = x; cp[2] = y; cp[3] = w;
        %avaliador
        melhor2 = min(melhor2, custo_ind);
      end;
    end; end; end; end; end;
    output;
  end;
  keep circuito cen melhor1 melhor2;
run;
proc sql;
  create table t1c as                                   /* ótimo do simulador x busca independente */
  select b.circuito, b.cen, b.melhor1, m1.c as sim1, b.melhor2, m2.c as sim2,
         abs(b.melhor1 - m1.c) + abs(b.melhor2 - m2.c) as dif_otimo
  from t1b b
       inner join (select circuito, cen, min(custo) as c from sim99 where n_paradas = 1 group by 1, 2) m1
             on b.circuito = m1.circuito and b.cen = m1.cen
       inner join (select circuito, cen, min(custo) as c from sim99 where n_paradas = 2 group by 1, 2) m2
             on b.circuito = m2.circuito and b.cen = m2.cen;
  create table t1d as                                   /* simetria: 1 parada na volta k e na volta L-k */
  select a.circuito, a.cen, max(abs(a.custo - b.custo)) as dif_simetria
  from sim99 a inner join sim99 b
       on a.circuito = b.circuito and a.cen = b.cen and a.n_paradas = 1 and b.n_paradas = 1
      and b.k1 = 20 - a.k1
  group by 1, 2;
quit;
data t1e;                                               /* contas manuais (L=20, b=0,1, P=20, cenário 2) */
  length caso $60;
  b = 0.1; P = 20; L = 20;
  caso = '1 parada 10+10, HARD-HARD (só referência)'; esperado = 2 * (b * 10 * 9 / 2) + P; output;
  caso = '1 parada 10+10, MEDIUM-HARD';               esperado = 2 * (b * 45) + 10 * 0.05 + P; output;
  caso = '2 paradas 7+7+6, SOFT-HARD-HARD';           esperado = b * (21 + 21 + 15) + 2 * P; output;
run;
proc sql;
  create table t1f as                                   /* valores do simulador nos mesmos planos */
  select 'sim 1 parada k1=10 cen 2' as caso length=60, custo, c1, c2, c3
  from sim99 where circuito = 'T_base' and cen = 2 and n_paradas = 1 and k1 = 10
  union all
  select 'sim 2 paradas k1=7 cen 2', custo, c1, c2, c3
  from sim99 where circuito = 'T_base' and cen = 2 and n_paradas = 2 and k1 = 7;
quit;

/* restaura o estado antes das checagens reais */
data deg24; set _bk_deg24; run;
data box24; set _bk_box24; run;
%let offM = &_offM_bk;

/* ---------- T2. integridade das tabelas reais ---------- */
%macro t2(tab, lab);
  proc sql;
    create table t2_&lab as
    select "&lab" as tabela length=12, count(*) as linhas,
           sum(n1 + n2 + coalesce(n3, 0) ne L) as soma_errada,
           sum(min(n1, n2, coalesce(n3, 99)) < 5) as stint_curto,
           sum((n_paradas = 1 and c1 = c2) or (n_paradas = 2 and c1 = c2 and c2 = c3)) as um_composto,
           sum(k1 ne n1) as parada_desalinhada,
           count(*) - count(distinct catx('|', circuito, cen, n_paradas, k1)) as duplicadas
    from (select s.*, e.L from &tab s inner join (select distinct circuito, L from entrada%substr(&lab,4)) e
          on s.circuito = e.circuito);
  quit;
%mend t2;
%t2(sim24, sim24)
%t2(sim25, sim25)
proc sql;
  create table t2u as                                   /* unidades e faixas das entradas */
  select 'deg24 (s/volta por volta de idade)' as entrada length=40, min(deg) as minimo, median(deg) as mediana, max(deg) as maximo, count(*) as n from deg24_orig
  union all select 'cand.deg_treino (B, 2025)', min(deg_treino), median(deg_treino), max(deg_treino), count(*) from cand
  union all select 'box24 mediana (s por parada)', min(mediana), median(mediana), max(mediana), count(*) from box24
  union all select 'offM MEDIUM-HARD (s/volta)', &offM, &offM, &offM, 1 from deg24_orig(obs=1)
  union all select 'deg24 atual = deg24_orig?', sum(a.deg ne b.deg), ., ., count(*)
            from deg24 a inner join deg24_orig b on a.circuito = b.circuito;
quit;

/* ---------- T3. regras esportivas e voltas programadas ---------- */
data prog_oficial;                                      /* voltas programadas 2024 e 2025 (calendário oficial) */
  infile datalines dlm=',' truncover; length circuito $40; input ano circuito $ voltas_prog;
  datalines;
2024,Sakhir,57
2024,Jeddah,50
2024,Melbourne,58
2024,Suzuka,53
2024,Shanghai,56
2024,Miami,57
2024,Imola,63
2024,Monte Carlo,78
2024,Hungaroring,70
2024,Spa-Francorchamps,44
2024,Zandvoort,72
2024,Monza,53
2024,Baku,51
2024,Singapore,62
2024,Austin,56
2024,Mexico City,71
2024,Las Vegas,50
2024,Lusail,57
2024,Yas Marina Circuit,58
2025,Melbourne,58
2025,Shanghai,56
2025,Suzuka,53
2025,Sakhir,57
2025,Jeddah,50
2025,Miami,57
2025,Imola,63
2025,Monte Carlo,78
2025,Catalunya,66
2025,Spielberg,70
2025,Silverstone,52
2025,Spa-Francorchamps,44
2025,Hungaroring,70
2025,Zandvoort,72
2025,Monza,53
2025,Baku,51
2025,Singapore,62
2025,Austin,56
2025,Mexico City,71
2025,Interlagos,71
2025,Las Vegas,50
2025,Lusail,57
2025,Yas Marina Circuit,58
;
run;
proc sql;
  create table t3_voltas as                             /* L usado pelo simulador x voltas programadas */
  select 2024 as ano, e.circuito, e.L, p.voltas_prog, (e.L ne p.voltas_prog) as diferente
  from (select distinct circuito, L from entrada24) e left join prog_oficial p on p.ano = 2024 and e.circuito = p.circuito
  union all
  select 2025, e.circuito, e.L, p.voltas_prog, (e.L ne p.voltas_prog)
  from (select distinct circuito, L from entrada25) e left join prog_oficial p on p.ano = 2025 and e.circuito = p.circuito;
  create table t3_reg as                                /* regras especiais de 2025 x previsão oficial (entradas A e B) */
  select 'A_2024' as entrada length=8, circuito, paradas_prev, unanime from prev25_A_2024 where circuito in ('Monte Carlo', 'Lusail')
  union all
  select 'B_treino', circuito, paradas_prev, unanime from prev25_B_treinos where circuito in ('Monte Carlo', 'Lusail');
  create table t3_pistas as                             /* pistas de 2025 que o simulador não cobre */
  select distinct r.circuito, (e.circuito is not null) as simulada
  from real25 r left join (select distinct circuito from entrada25) e on r.circuito = e.circuito;
quit;

/* ---------- T5. baselines com a mesma função de custo ---------- */
/* entradas: A = degradação de corrida 2024; B = treinos 2025 calibrados (entrada escolhida no 08) */
proc sql;
  create table ent5 as
  select 'A_2024' as entrada length=8, e.circuito, e.L, d.deg as b, x.mediana as P
  from (select distinct circuito, L from entrada25) e
       inner join deg24_orig d on e.circuito = d.circuito inner join box24 x on e.circuito = x.circuito
  union all
  select 'B_treino', e.circuito, e.L, max(c.deg_treino, 0.005), x.mediana
  from (select distinct circuito, L from entrada25) e
       inner join cand c on e.circuito = c.circuito inner join box24 x on e.circuito = x.circuito;
  create table obs5 as                                  /* estratégias reais de 2025 (só retrospectiva) */
  select t.session_key, r.circuito, t.driver_number, t.stint_number, t.compound,
         t.lap_end - t.lap_start + 1 as tamanho, r.voltas_corrida as L_real, r.paradas
  from st25 t inner join real25 r on t.session_key = r.session_key and t.driver_number = r.driver_number
  where r.terminou = 1 and r.paradas between 1 and 2
  order by r.circuito, t.driver_number, t.stint_number;
quit;
data obs5p;                                             /* um plano por piloto, só se válido no simulador */
  set obs5; by circuito driver_number;
  length plano $40; retain plano nst soma cp1-cp3 len1-len3 ok;
  array cpa[3] cp1-cp3; array lena[3] len1-len3;
  if first.driver_number then do; plano = ''; nst = 0; soma = 0; ok = 1; do _i = 1 to 3; cpa[_i] = .; lena[_i] = .; end; end;
  nst + 1;
  if nst <= 3 then do; cpa[nst] = whichc(compound, 'HARD', 'MEDIUM', 'SOFT'); lena[nst] = tamanho; end;
  if cpa[min(nst,3)] = 0 then ok = 0;                   /* composto não seco */
  soma + tamanho; plano = catx('-', plano, compound);
  if last.driver_number then do;
    if soma ne L_real or nst ne paradas + 1 then ok = 0;
    output;
  end;
  keep circuito driver_number plano nst cp1-cp3 len1-len3 ok soma L_real;
run;
data t5;                                                /* custo de cada estratégia nos 4 cenários */
  set ent5;
  array len[3]; array cp[3]; %defarr
  length estrategia $20;
  do cen = 1 to 4;
    estrategia = '1p fixa M-H 50%';                     /* fixada a priori: parada na metade */
    nst = 2; len[1] = round(L / 2); len[2] = L - len[1]; len[3] = 0; cp[1] = 2; cp[2] = 1; cp[3] = 1;
    %avaliador
    output;
    estrategia = '2p fixa M-H-H 1/3';                   /* fixada a priori: paradas em 1/3 e 2/3 */
    nst = 3; len[1] = round(L / 3); len[2] = round(2 * L / 3) - len[1]; len[3] = L - round(2 * L / 3);
    cp[1] = 2; cp[2] = 1; cp[3] = 1;
    %avaliador
    output;
  end;
  keep entrada circuito L cen estrategia custo_ind;
run;
data t5s;                                               /* ótimo do simulador (mesma busca do %simula) */
  set ent5;
  array len[3]; array cp[3]; %defarr
  length estrategia $20;
  do cen = 1 to 4;
    melhor = 1e9;
    do k1 = 5 to L - 5; do x = 1 to 3; do y = 1 to 3; if x ne y then do;
      nst = 2; len[1] = k1; len[2] = L - k1; len[3] = 0; cp[1] = x; cp[2] = y; cp[3] = 1;
      %avaliador
      melhor = min(melhor, custo_ind);
    end; end; end; end;
    do k1 = 5 to L - 10; do k2 = k1 + 5 to L - 5; do x = 1 to 3; do y = 1 to 3; do w = 1 to 3;
      if not (x = y and y = w) then do;
        nst = 3; len[1] = k1; len[2] = k2 - k1; len[3] = L - k2; cp[1] = x; cp[2] = y; cp[3] = w;
        %avaliador
        melhor = min(melhor, custo_ind);
      end;
    end; end; end; end; end;
    estrategia = 'simulador (ótimo)'; custo_ind = melhor; output;
  end;
  keep entrada circuito L cen estrategia custo_ind;
run;
proc sql;
  create table t5o_in as                                /* estratégias observadas x entradas */
  select e.entrada, e.circuito, e.L, e.b, e.P, o.driver_number, o.nst, o.cp1, o.cp2, o.cp3, o.len1, o.len2, o.len3, o.L_real
  from ent5 e inner join obs5p o on e.circuito = o.circuito where o.ok = 1;
quit;
data t5o;
  set t5o_in;
  array len[3]; array cp[3]; %defarr
  length estrategia $20;
  cp[1] = cp1; cp[2] = cp2; cp[3] = coalesce(cp3, 1); len[1] = len1; len[2] = len2; len[3] = coalesce(len3, 0);
  do cen = 1 to 4;
    %avaliador
    estrategia = 'observada (piloto)'; output;
  end;
  keep entrada circuito L cen estrategia custo_ind driver_number;
run;
proc sql;
  create table t5_long as                               /* todas as estratégias, uma linha por entrada x pista x cenário */
  select entrada, circuito, cen, estrategia, custo_ind as custo from t5
  union all select entrada, circuito, cen, estrategia, custo_ind from t5s
  union all select entrada, circuito, cen, 'observada mediana', median(custo_ind) from t5o group by 1, 2, 3
  union all select entrada, circuito, cen, 'observada melhor', min(custo_ind) from t5o group by 1, 2, 3;
  create table t5_rel as                                /* extra em relação ao ótimo do simulador (s) */
  select a.entrada, a.circuito, a.cen, a.estrategia, a.custo, a.custo - s.custo as extra_s
  from t5_long a inner join t5_long s
       on a.entrada = s.entrada and a.circuito = s.circuito and a.cen = s.cen and s.estrategia = 'simulador (ótimo)';
quit;

/* ---------- T4. integridade temporal (o que cada entrada usa) ---------- */
data t4;
  length item $60 fonte $60 momento $30 uso $30;
  item = 'b (degradação) - entrada A'; fonte = 'corridas 2024 (GLM 02)'; momento = 'antes de 2025'; uso = 'escolha'; output;
  item = 'b (degradação) - entrada B'; fonte = 'treinos livres 2025 + calibração 2024'; momento = 'antes da corrida'; uso = 'escolha'; output;
  item = 'escolha da entrada B'; fonte = 'resultados reais da 1ª metade de 2025'; momento = 'depois das corridas'; uso = 'seleção (vazamento)'; output;
  item = 'P (perda no box)'; fonte = 'corridas 2024'; momento = 'antes de 2025'; uso = 'escolha'; output;
  item = 'L (nº de voltas)'; fonte = 'voltas observadas na corrida (real&a)'; momento = 'depois da corrida'; uso = 'escolha (= programado)'; output;
  item = 'offM e cenários SOFT'; fonte = 'GLM 2024 + hipóteses fixas'; momento = 'antes de 2025'; uso = 'escolha'; output;
  item = 'paradas reais, voltas de parada, stints'; fonte = 'corridas 2025'; momento = 'depois da corrida'; uso = 'só avaliação (04, 09)'; output;
  item = 'janela ML (09)'; fonte = 'regressão quantílica treinada em 2024'; momento = 'antes de 2025'; uso = 'escolha'; output;
run;

/* ---------- resultados ---------- */
proc sql;
  title 'S1. T1 sintético: simulador x recálculo volta a volta (todas as linhas)';
  select circuito, count(*) as linhas, max(dif_custo) as dif_max format=12.9,
         sum(not soma_ok) as soma_errada, sum(not comp_ok) as regra_composto, sum(not min_ok) as stint_curto,
         sum(not parada_ok) as parada_desalinhada
  from t1 group by circuito;
  title 'S2. T1 ótimo do simulador x busca exaustiva independente';
  select * from t1c;
  title 'S3. T1 simetria (1 parada em k e em L-k)';
  select * from t1d;
  title 'S4. T1 contas manuais x simulador (L=20, b=0,1, P=20, cen 2)';
  select * from t1e; select * from t1f;
  title 'S5. T1 recomendações sintéticas';
  select circuito, cen, n_paradas, min(custo) as custo_min format=8.2 from sim99 group by 1, 2, 3;
quit;
proc print data=t2_sim24 noobs; title 'S6. T2 integridade sim24'; run;
proc print data=t2_sim25 noobs; title 'S7. T2 integridade sim25'; run;
proc print data=t2u noobs; title 'S8. T2 unidades e faixas das entradas'; run;
proc print data=t3_voltas noobs; where diferente ne 0; title 'S9. T3 L do simulador diferente das voltas programadas'; run;
proc print data=t3_reg noobs; title 'S10. T3 Monaco 2025 (mín. 2 paradas) e Lusail 2025 (máx. 25 voltas/jogo): previsão oficial'; run;
proc print data=t3_pistas noobs; title 'S11. T3 pistas de 2025 cobertas pelo simulador'; run;
proc sql;
  title 'S12. T5 extra em relação ao ótimo do simulador (s), média dos 4 cenários e das pistas';
  select entrada, estrategia, count(distinct circuito) as pistas, mean(extra_s) as extra_medio format=8.2,
         min(extra_s) as extra_min format=8.2, max(extra_s) as extra_max format=8.2
  from t5_rel group by 1, 2 order by 1, 4;
  title 'S13. T5 por pista (entrada B, cenário 1)';
  select circuito, estrategia, extra_s format=8.2 from t5_rel where entrada = 'B_treino' and cen = 1 order by 1, 3;
  title 'S14. T5 estratégias observadas válidas';
  select count(*) as pilotos, sum(ok) as validas from obs5p;
quit;
proc print data=t4 noobs; title 'S15. T4 origem temporal das entradas'; run;
title;
