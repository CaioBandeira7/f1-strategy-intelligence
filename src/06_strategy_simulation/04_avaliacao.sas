/* =====================================================================
   04_avaliacao.sas - compara as previsões com o que aconteceu
     (1) janela da 1ª parada  (2) nº de paradas  (3) tamanho do stint
   Cada previsão é comparada com um "chute ingênuo" (repetir 2024)
   ===================================================================== */

%macro gabarito(s);                                     /* monta o gabarito de um ano (s = 24 ou 25) */
  proc sql;
    create table par1_&s as                             /* 1ª parada de cada piloto, com marcação de safety car */
    select r.session_key, r.circuito, r.driver_number, r.paradas, r.voltas_corrida as L,
           r.fim_stint1 as volta_parada1,               /* volta da 1ª parada */
           coalesce(v.sc_t, 0) as parada_sc             /* 1 = parou com safety car/VSC na pista */
    from real&s r
         left join v&s v on r.session_key = v.session_key
                        and r.driver_number = v.driver_number
                        and r.fim_stint1 = v.lap_number
    where r.terminou = 1 and r.paradas >= 1             /* só quem terminou e parou */
          and r.parada1_vermelha = 0;                   /* parada na bandeira vermelha não é decisão de estratégia */
  quit;                                                 /* fim */
  proc freq data=real&s(where=(terminou=1)) noprint;    /* nº de paradas mais comum de cada corrida */
    tables circuito*paradas / out=fp&s;                 /* contagem por pista e nº de paradas */
  run;                                                  /* executa */
  proc sort data=fp&s; by circuito descending count; run;   /* o mais frequente primeiro */
  data moda&s; set fp&s; by circuito; if first.circuito;    /* fica com a moda */
    rename paradas = paradas_real count = pilotos;      /* nomes claros */
    keep circuito paradas count;                        /* mantém só o necessário */
  run;                                                  /* executa */
%mend gabarito;                                         /* fim */
%gabarito(24)                                           /* gabarito de 2024 */
%gabarito(25)                                           /* gabarito de 2025 */

/* ---------- chute ingênuo: repetir a volta mediana da 1ª parada de 2024 (proporcional ao nº de voltas) ---------- */
proc means data=par1_24(where=(parada_sc=0)) noprint nway;  /* só paradas em bandeira verde */
  class circuito;                                       /* por pista */
  var volta_parada1 L;                                  /* volta da parada e nº de voltas */
  output out=ing24(drop=_type_ _freq_) median(volta_parada1)=k_med24 max(L)=L24;
run;                                                    /* executa */

/* ---------- (1) e (2): nº de paradas e janela, piloto a piloto ---------- */
%macro avalia(a);                                       /* a = 24 (dentro da amostra) ou 25 (fora da amostra) */
  proc sql;
    create table aval_pil&a as                          /* uma linha por piloto */
    select p.*, f.paradas_prev, f.jan_ini, f.jan_fim, f.k_prev,
           (p.volta_parada1 between f.jan_ini and f.jan_fim) as dentro,   /* 1 = parou dentro da janela */
           abs(p.volta_parada1 - f.k_prev) as erro_modelo,               /* erro do modelo (voltas) */
           abs(p.volta_parada1 - round(i.k_med24 * p.L / i.L24)) as erro_ingenuo  /* erro do chute ingênuo */
    from par1_&a p
         inner join prev&a f on p.circuito = f.circuito
         left join ing24 i on p.circuito = i.circuito
    where p.parada_sc = 0;                              /* avalia só paradas em bandeira verde */
    create table aval_pista&a as                        /* uma linha por pista */
    select f.circuito, f.paradas_prev, m.paradas_real, (f.paradas_prev = m.paradas_real) as acertou_paradas,
           f.jan_ini, f.jan_fim, f.k_prev,
           count(p.driver_number) as pilotos,           /* paradas avaliadas */
           mean(p.dentro) as pct_dentro format=percent8.0,   /* % dentro da janela */
           mean(p.erro_modelo) as mae_modelo format=5.1,     /* erro médio do modelo */
           mean(p.erro_ingenuo) as mae_ingenuo format=5.1    /* erro médio do chute ingênuo */
    from prev&a f
         inner join moda&a m on f.circuito = m.circuito
         left join aval_pil&a p on f.circuito = p.circuito
    group by f.circuito, f.paradas_prev, m.paradas_real, f.jan_ini, f.jan_fim, f.k_prev
    order by f.circuito;
    title "Resultado por pista - 20&a";
    select * from aval_pista&a;
    title "Resumo - 20&a";
    select count(*) as corridas,
           mean(acertou_paradas) as acerto_paradas format=percent8.0,
           (select mean(dentro) from aval_pil&a) as pct_dentro format=percent8.0,
           (select mean(erro_modelo) from aval_pil&a) as mae_modelo format=5.2,
           (select mean(erro_ingenuo) from aval_pil&a) as mae_ingenuo format=5.2,
           mean(jan_fim - jan_ini + 1) as largura_media format=5.1
    from aval_pista&a;
    title;
  quit;
%mend avalia;
%avalia(24)                                             /* referência dentro da amostra */
%avalia(25)                                             /* o teste de verdade */

/* ---------- (3) tamanho do stint por composto ---------- */
%macro stints(s);                                       /* tamanho real dos stints de um ano */
  proc sql;
    create table stl&s as
    select t.circuito, t.compound, t.lap_end - t.lap_start + 1 as tamanho
    from st&s t inner join real&s r
         on t.session_key = r.session_key and t.driver_number = r.driver_number
    where r.terminou = 1                                /* só quem terminou (stint não foi cortado por abandono) */
          and t.compound in ('SOFT','MEDIUM','HARD')    /* só pneus de pista seca */
          and calculated tamanho >= 5;                  /* ignora stints muito curtos (problemas, bandeira) */
  quit;
  proc means data=stl&s noprint nway;                   /* mediana por pista e composto */
    class circuito compound;
    var tamanho;
    output out=stmed&s(drop=_type_) median=stint_med n=n_stints;
  run;
%mend stints;
%stints(24)                                             /* 2024 */
%stints(25)                                             /* 2025 */

proc sql;
  create table plano25 as                               /* plano ótimo de cada cenário, no nº de paradas previsto */
  select s.circuito, s.cen, s.c1, s.n1, s.c2, s.n2, s.c3, s.n3
  from sim25 s
       inner join otimo_cen25 o on s.circuito = o.circuito and s.cen = o.cen and s.k1 = o.k_otimo
       inner join rec25 r on s.circuito = r.circuito and s.n_paradas = r.paradas_prev;
quit;
data plano_long25;                                      /* um stint por linha */
  set plano25;
  length compound $6;
  compound = c1; tamanho = n1; output;                  /* 1º stint */
  compound = c2; tamanho = n2; output;                  /* 2º stint */
  if c3 ne '' then do; compound = c3; tamanho = n3; output; end;   /* 3º stint, se houver */
  keep circuito cen compound tamanho;
run;
proc means data=plano_long25 noprint nway;              /* tamanho previsto pelo modelo */
  class circuito compound;
  var tamanho;
  output out=stprev25(drop=_type_ _freq_) mean=stint_modelo;
run;
proc sql;
  create table aval_stint25 as                          /* real 2025 x modelo x chute ingênuo */
  select r.circuito, r.compound, r.n_stints, r.stint_med as real_2025,
         m.stint_modelo format=5.1, i.stint_med as ingenuo_2024,
         abs(r.stint_med - m.stint_modelo) as erro_modelo format=5.1,
         abs(r.stint_med - i.stint_med) as erro_ingenuo format=5.1
  from stmed25 r
       left join stprev25 m on r.circuito = m.circuito and r.compound = m.compound
       left join stmed24 i on r.circuito = i.circuito and r.compound = i.compound
  where r.n_stints >= 3                                 /* só combinações com pelo menos 3 stints */
  order by r.circuito, r.compound;
  title 'Tamanho do stint - 2025';
  select * from aval_stint25;
  title 'Resumo stints - 2025';
  select count(*) as combinacoes,
         sum(erro_modelo ne .) as com_modelo, mean(erro_modelo) as mae_modelo format=5.2,
         sum(erro_ingenuo ne .) as com_ingenuo, mean(erro_ingenuo) as mae_ingenuo format=5.2
  from aval_stint25;
  title;
quit;
