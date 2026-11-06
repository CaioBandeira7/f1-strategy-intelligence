/* =====================================================================
   21_ajustes_simulador.sas - três ajustes autorizados após a auditoria.
   Só cria tabelas novas; não altera simulador, parâmetros, V3c ou benchmarks.
   Pré-requisito: sessão com 03, 04 e 08 (prev25_A_2024, res_*, F1_SIMULADOR).
   ===================================================================== */
cas s3 sessopts=(timeout=7200);                          /* sessão CAS */
libname casuser cas caslib="casuser" sessref=s3;         /* libref CASUSER */
options sessref=s3;
%let home = %sysget(HOME);
%let criou = %sysfunc(dcreate(simulador_final, &home/f1));   /* pasta dos ajustes */
libname simf "&home/f1/simulador_final";
data simf.prev25_a_validade;                             /* 1. Mônaco 2025 na entrada A */
  set prev25_A_2024;
  length validade_regra $70;
  if circuito = 'Monte Carlo' and paradas_prev < 2 then validade_regra = 'INVALIDA: Monaco 2025 exige no minimo 2 paradas';
  else validade_regra = 'valida';
run;
data simf.entrada_b_metades;                             /* 2. 2025 por metade da temporada */
  set res_A_2024 res_B_treinos res_C_media;
  length uso $80;
  if grupo = 'validacao' then uso = '1a metade: usada na escolha da entrada (nao e teste independente)';
  else uso = '2a metade: avaliacao posterior (fora da escolha)';
run;
data f1_sim_rot;                                         /* 3. rótulos do dashboard */
  set casuser.F1_SIMULADOR;
  length escopo $60 unidade $80 fonte_degradacao $90;
  escopo = '2024 dentro da amostra (descritivo)';
  unidade = 'custo relativo entre estrategias (s), nao tempo absoluto de corrida';
  fonte_degradacao = 'GLM do programa 02 (corridas 2024); nao integrado a V3c';
run;
proc casutil;                                            /* tabela nova para o VA; a original fica intacta */
  load data=work.f1_sim_rot outcaslib="casuser" casout="F1_SIMULADOR_ROTULADO" promote
       label="Simulador 2024 dentro da amostra - custos relativos - degradacao do programa 02";
  save casdata="F1_SIMULADOR_ROTULADO" incaslib="casuser" outcaslib="casuser" casout="F1_SIMULADOR_ROTULADO.sashdat" replace;
quit;
data simf.f1_simulador_rotulado; set f1_sim_rot; run;
