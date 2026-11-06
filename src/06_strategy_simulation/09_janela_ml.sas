/* =====================================================================
   09_janela_ml.sas - janela da 1ª parada aprendida dos dados
   O simulador físico põe a parada perto do meio da corrida; as equipes
   param antes. Aqui um modelo de REGRESSÃO QUANTÍLICA aprende, em 2024,
   em que fração da corrida os pilotos fazem a 1ª parada:
     - quantil 50%  = volta prevista
     - quantis 25% e 75% = janela (deve conter ~50% das paradas)
   Entradas (todas conhecidas antes da largada):
     volta ótima do simulador / nº de voltas, nº de paradas previsto,
     composto de largada do piloto.
   Pré-requisito: rodar o 08 antes. Defina a entrada escolhida na validação.
   ===================================================================== */
%let escolha = B_treinos;                               /* entrada vencedora na VALIDAÇÃO (ver 08) */

/* ---------- 1. simulador de 2024 com a mesma lógica de entrada (para treinar) ---------- */
data deg24;                                             /* 2024: degradação "de treino" calibrada */
  set fpdeg24;
  deg = max(&ca + &cb * fp_slope, 0.005);
  keep circuito deg;
run;
ods exclude all;
%simula(24)                                             /* gera prev24 com essa entrada */
ods exclude none;
data deg24; set deg24_orig; run;                        /* restaura */

/* ---------- 2. base de treino (2024) e de pontuação (2025) ---------- */
%macro base_jan(a, prev);                               /* a = 24/25; prev = tabela de previsão do simulador */
  proc sql;
    create table bj&a as
    select p.circuito, p.session_key, p.driver_number, p.L, p.volta_parada1,
           p.volta_parada1 / p.L as frac,               /* alvo: fração da corrida na 1ª parada */
           f.k_prev / f.L as kfrac_sim,                 /* volta ótima do simulador / nº de voltas */
           f.paradas_prev,                              /* nº de paradas previsto */
           scan(r.compostos, 1, '-') as comp_ini length=6   /* composto de largada */
    from par1_&a p
         inner join &prev f on p.circuito = f.circuito
         inner join real&a r on p.session_key = r.session_key and p.driver_number = r.driver_number
    where p.parada_sc = 0                               /* só paradas em bandeira verde */
      and calculated comp_ini in ('SOFT','MEDIUM','HARD');
  quit;
%mend base_jan;
%base_jan(24, prev24)                                   /* treino */
%base_jan(25, prev25_&escolha)                          /* teste */

data bj_all;                                            /* empilha: 2025 entra sem alvo (só é pontuado) */
  set bj24(in=t) bj25(in=s);
  ano = ifn(t, 2024, 2025);
  frac_treino = ifn(t, frac, .);                        /* o modelo só enxerga o alvo de 2024 */
run;

/* ---------- 3. regressão quantílica (25%, 50%, 75%) ---------- */
%macro qr(q, nome);
  proc quantreg data=bj_all;
    class comp_ini;
    model frac_treino = kfrac_sim paradas_prev comp_ini / quantile=&q;
    output out=q_&nome(keep=circuito session_key driver_number ano p_&nome) p=p_&nome;
  run;
%mend qr;
%qr(0.25, q25)
%qr(0.50, q50)
%qr(0.75, q75)

/* ---------- 4. avaliação em 2025 (validação x teste) ---------- */
proc sql;
  create table aval_jan25 as
  select b.circuito, b.driver_number, b.L, b.volta_parada1, m.grupo,
         round(a.p_q25 * b.L) as jan_ini, round(c.p_q75 * b.L) as jan_fim, round(d.p_q50 * b.L) as k_ml,
         (b.volta_parada1 between calculated jan_ini and calculated jan_fim) as dentro_ml,
         abs(b.volta_parada1 - calculated k_ml) as erro_ml,
         abs(b.volta_parada1 - round(b.kfrac_sim * b.L)) as erro_fisico,
         abs(b.volta_parada1 - round(i.k_med24 * b.L / i.L24)) as erro_ingenuo
  from bj25 b
       inner join q_q25 a on b.session_key = a.session_key and b.driver_number = a.driver_number and a.ano = 2025
       inner join q_q75 c on b.session_key = c.session_key and b.driver_number = c.driver_number and c.ano = 2025
       inner join q_q50 d on b.session_key = d.session_key and b.driver_number = d.driver_number and d.ano = 2025
       inner join metade25 m on b.circuito = m.circuito
       left join ing24 i on b.circuito = i.circuito;
  title 'Janela da 1ª parada 2025 - ML x físico x ingênuo';
  select grupo, count(*) as paradas,
         mean(dentro_ml) as dentro_janela_ml format=percent8.0,
         mean(jan_fim - jan_ini + 1) as largura_ml format=5.1,
         mean(erro_ml) as mae_ml format=5.2,
         mean(erro_fisico) as mae_fisico format=5.2,
         mean(erro_ingenuo) as mae_ingenuo format=5.2
  from aval_jan25 group by grupo;
  title;
quit;
