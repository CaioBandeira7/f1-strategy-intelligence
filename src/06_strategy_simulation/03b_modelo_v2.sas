/* =====================================================================
   03b_modelo_v2.sas - versão 2 do simulador
   Problema da v1: HARD e MEDIUM tinham o MESMO desgaste (só o SOFT
   variava por cenário), então o modelo previa stints simétricos.
   v2: estima com os dados de 2024 o desgaste EXTRA de cada composto
       degradação(pista, composto) = inclinação da pista + extra do composto
   e usa esse valor no simulador (sem cenários inventados).
   ===================================================================== */

/* ---------- 1. GLM 2024 com desgaste por pista E por composto ---------- */
ods exclude all;                                        /* não imprime a saída enorme */
proc glm data=uso24;                                    /* mesma base de voltas usadas de 2024 */
  absorb rp;                                            /* efeito corrida-piloto */
  class circuito compound;                              /* variáveis de classe */
  model lap_duration = circuito*lap_number              /* combustível e evolução da pista */
                       compound                         /* ritmo do composto novo */
                       circuito*tyre_age                /* desgaste de cada pista */
                       compound*tyre_age / solution;    /* desgaste extra de cada composto */
  ods output ParameterEstimates=pe24v2;                 /* coeficientes */
run; quit;
ods exclude none;                                       /* volta a imprimir */

data comp_v2;                                           /* ritmo e desgaste extra de cada composto */
  set pe24v2;
  length compound $10 tipo $8;
  if Parameter =: 'tyre_age*compound' then do;          /* desgaste extra (s/volta de idade) */
    tipo = 'desgaste'; compound = strip(substr(Parameter, 19)); output;
  end;
  else if Parameter =: 'compound ' then do;             /* ritmo do composto novo (s/volta) */
    tipo = 'ritmo'; compound = strip(substr(Parameter, 10)); output;
  end;
  keep tipo compound Estimate;
run;
proc sql noprint;                                       /* guarda em macro variáveis, relativo ao HARD */
  select Estimate into :dH trimmed from comp_v2 where tipo='desgaste' and compound='HARD';
  select Estimate into :dM trimmed from comp_v2 where tipo='desgaste' and compound='MEDIUM';
  select Estimate into :dS trimmed from comp_v2 where tipo='desgaste' and compound='SOFT';
  select Estimate into :rH trimmed from comp_v2 where tipo='ritmo' and compound='HARD';
  select Estimate into :rM trimmed from comp_v2 where tipo='ritmo' and compound='MEDIUM';
  select Estimate into :rS trimmed from comp_v2 where tipo='ritmo' and compound='SOFT';
quit;
data deg24v2;                                           /* desgaste da pista na v2 (o composto de referência do GLM tem extra = 0) */
  set pe24v2;
  where Parameter =: 'tyre_age*circuito';               /* termos de pista */
  length circuito $40;
  circuito = strip(substr(Parameter, index(Parameter, ' ') + 1));   /* nome da pista */
  deg = Estimate;                                       /* desgaste base da pista */
  keep circuito deg;
run;
%put NOTE: desgaste extra M-H = %sysevalf(&dM - &dH)  S-H = %sysevalf(&dS - &dH);   /* mostra no log */
%put NOTE: ritmo M-H = %sysevalf(&rM - &rH)  S-H = %sysevalf(&rS - &rH);

/* ---------- 2. simulador v2 (mesma lógica, desgaste por composto estimado) ---------- */
%macro simula_v2(a);                                    /* a = 24 ou 25 */
proc sql;
  create table ent_v2_&a as                             /* entrada: só informação de 2024 + nº de voltas */
  select distinct r.circuito, r.voltas_corrida as L, d.deg as b, x.mediana as P
  from real&a r inner join deg24v2 d on r.circuito = d.circuito
                inner join box24 x on r.circuito = x.circuito;
quit;
data sim_v2_&a(keep=circuito n_paradas k1 custo c1 c2 c3 n1 n2 n3);
  set ent_v2_&a;
  length c1 c2 c3 $6;
  array nome[3] $6 _temporary_ ('HARD' 'MEDIUM' 'SOFT');
  array d[3] _temporary_;                               /* desgaste de cada composto nesta pista */
  array o[3] _temporary_;                               /* ritmo de cada composto (relativo ao HARD) */
  d[1] = max(b + &dH, 0.001);                           /* HARD = desgaste da pista + extra do HARD */
  d[2] = max(b + &dM, 0.001);                           /* MEDIUM = desgaste da pista + extra do MEDIUM */
  d[3] = max(b + &dS, 0.001);                           /* SOFT = desgaste da pista + extra do SOFT (referência = 0) */
  o[1] = 0; o[2] = &rM - &rH; o[3] = &rS - &rH;         /* ritmo do pneu novo */
  do k1 = 5 to L - 5;                                   /* 1 parada */
    custo = 1e9;
    do x = 1 to 3; do y = 1 to 3;
      if x ne y then do;
        t1 = k1; t2 = L - k1;
        c = d[x]*t1*(t1-1)/2 + o[x]*t1 + d[y]*t2*(t2-1)/2 + o[y]*t2 + P;
        if c < custo then do; custo = c; c1 = nome[x]; c2 = nome[y]; c3 = ''; n1 = t1; n2 = t2; n3 = .; end;
      end;
    end; end;
    n_paradas = 1; output;
  end;
  do k1 = 5 to L - 10;                                  /* 2 paradas */
    custo = 1e9;
    do k2 = k1 + 5 to L - 5;
      t1 = k1; t2 = k2 - k1; t3 = L - k2;
      do x = 1 to 3; do y = 1 to 3; do w = 1 to 3;
        if not (x = y and y = w) then do;
          c = d[x]*t1*(t1-1)/2 + o[x]*t1 + d[y]*t2*(t2-1)/2 + o[y]*t2
            + d[w]*t3*(t3-1)/2 + o[w]*t3 + 2*P;
          if c < custo then do; custo = c; c1 = nome[x]; c2 = nome[y]; c3 = nome[w]; n1 = t1; n2 = t2; n3 = t3; end;
        end;
      end; end; end;
    end;
    n_paradas = 2; output;
  end;
run;
proc sql;
  create table melhor_v2_&a as                          /* melhor custo por nº de paradas */
  select circuito, n_paradas, min(custo) as custo_min from sim_v2_&a group by circuito, n_paradas;
  create table rec_v2_&a as                             /* nº de paradas previsto */
  select a.circuito, case when a.custo_min <= b.custo_min then 1 else 2 end as paradas_prev,
         abs(a.custo_min - b.custo_min) as margem_media
  from melhor_v2_&a a inner join melhor_v2_&a b on a.circuito = b.circuito
  where a.n_paradas = 1 and b.n_paradas = 2;
  create table jan_v2_&a as                             /* janela: voltas a menos de 1 s do ótimo */
  select s.*, s.custo - m.custo_min as extra
  from sim_v2_&a s inner join rec_v2_&a r on s.circuito = r.circuito and s.n_paradas = r.paradas_prev
                   inner join melhor_v2_&a m on s.circuito = m.circuito and s.n_paradas = m.n_paradas
  where calculated extra <= 1;
  create table prev_v2_&a as                            /* previsão final por pista */
  select r.circuito, e.L, e.b, e.P, r.paradas_prev, r.margem_media,
         min(j.k1) as jan_ini, max(j.k1) as jan_fim,
         (select min(k1) from jan_v2_&a z where z.circuito = r.circuito and z.extra = 0) as k_prev,   /* volta ótima */
         (select catx('-', c1, c2, c3) from jan_v2_&a z where z.circuito = r.circuito and z.extra = 0
            and z.k1 = (select min(k1) from jan_v2_&a y where y.circuito = r.circuito and y.extra = 0)) as plano   /* plano ótimo */
  from rec_v2_&a r inner join ent_v2_&a e on r.circuito = e.circuito
                   inner join jan_v2_&a j on r.circuito = j.circuito
  group by r.circuito, e.L, e.b, e.P, r.paradas_prev, r.margem_media
  order by r.circuito;
quit;
%mend simula_v2;
%simula_v2(24)
%simula_v2(25)

/* ---------- 3. avaliação v2 (mesmas regras da v1) ---------- */
%macro avalia_v2(a);
  proc sql;
    create table aval_pil_v2_&a as
    select p.*, f.paradas_prev, f.jan_ini, f.jan_fim, f.k_prev,
           (p.volta_parada1 between f.jan_ini and f.jan_fim) as dentro,
           abs(p.volta_parada1 - f.k_prev) as erro_modelo,
           abs(p.volta_parada1 - round(i.k_med24 * p.L / i.L24)) as erro_ingenuo
    from par1_&a p inner join prev_v2_&a f on p.circuito = f.circuito
                   left join ing24 i on p.circuito = i.circuito
    where p.parada_sc = 0;
    create table aval_pista_v2_&a as
    select f.circuito, f.plano, f.paradas_prev, m.paradas_real, (f.paradas_prev = m.paradas_real) as acertou_paradas,
           f.jan_ini, f.jan_fim, f.k_prev, count(p.driver_number) as pilotos,
           mean(p.dentro) as pct_dentro format=percent8.0,
           mean(p.erro_modelo) as mae_modelo format=5.1, mean(p.erro_ingenuo) as mae_ingenuo format=5.1
    from prev_v2_&a f inner join moda&a m on f.circuito = m.circuito
                      left join aval_pil_v2_&a p on f.circuito = p.circuito
    group by f.circuito, f.plano, f.paradas_prev, m.paradas_real, f.jan_ini, f.jan_fim, f.k_prev
    order by f.circuito;
    title "v2 - Resultado por pista - 20&a"; select * from aval_pista_v2_&a;
    title "v2 - Resumo - 20&a";
    select count(*) as corridas, mean(acertou_paradas) as acerto_paradas format=percent8.0,
           (select mean(dentro) from aval_pil_v2_&a) as pct_dentro format=percent8.0,
           (select mean(erro_modelo) from aval_pil_v2_&a) as mae_modelo format=5.2,
           (select mean(erro_ingenuo) from aval_pil_v2_&a) as mae_ingenuo format=5.2,
           mean(jan_fim - jan_ini + 1) as largura_media format=5.1
    from aval_pista_v2_&a;
    title;
  quit;
%mend avalia_v2;
%avalia_v2(24)
%avalia_v2(25)

/* ---------- 4. tamanho do stint v2 ---------- */
data plano_long_v2;                                     /* stints do plano ótimo v2 em 2025 */
  set jan_v2_25(where=(extra = 0));
  length compound $6;
  compound = c1; tamanho = n1; output;
  compound = c2; tamanho = n2; output;
  if c3 ne '' then do; compound = c3; tamanho = n3; output; end;
  keep circuito compound tamanho;
run;
proc means data=plano_long_v2 noprint nway;
  class circuito compound; var tamanho;
  output out=stprev_v2(drop=_type_ _freq_) mean=stint_v2;
run;
proc sql;
  title 'Desgaste por composto estimado em 2024 (s/volta, relativo ao HARD)';
  select tipo, compound, Estimate from comp_v2;
  title 'Stints 2025 - v1 x v2 x ingênuo (mesmas combinações)';
  select count(*) as combinacoes,
         mean(abs(a.real_2025 - a.stint_modelo)) as mae_v1 format=5.2,
         mean(abs(a.real_2025 - b.stint_v2)) as mae_v2 format=5.2,
         mean(a.erro_ingenuo) as mae_ingenuo format=5.2
  from aval_stint25 a inner join stprev_v2 b on a.circuito = b.circuito and a.compound = b.compound
  where a.stint_modelo ne . and a.ingenuo_2024 ne .;
  title;
quit;
