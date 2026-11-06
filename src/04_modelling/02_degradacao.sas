/* =====================================================================
   02_degradacao.sas - degradação por pista (s por volta de idade do pneu)
   Mesmo modelo para os dois anos: 2024 vira a previsão, 2025 o "real"
   ===================================================================== */
%macro degradacao(s);                                     /* s = 24 ou 25 */
  data uso&s;                                             /* voltas usadas no modelo */
    set v&s;                                              /* voltas do ano */
    where usar2 = 1 and circuito ne 'Lusail';             /* só voltas limpas; Lusail fora (efeitos confundidos) */
    length rp $40;                                        /* chave corrida-piloto */
    rp = catx('_', session_key, driver_number);           /* um nível por piloto em cada corrida */
  run;                                                    /* executa */
  proc sort data=uso&s; by rp; run;                       /* ABSORB exige ordenação pela chave */

  ods exclude all;                                        /* não imprime a saída enorme do GLM */
  proc glm data=uso&s;                                    /* modelo linear de efeitos fixos */
    absorb rp;                                            /* efeito corrida-piloto (ritmo do carro/piloto) */
    class circuito compound;                              /* variáveis de classe */
    model lap_duration = circuito*lap_number              /* combustível e evolução da pista, por pista */
                         compound                         /* diferença de ritmo entre compostos */
                         circuito*tyre_age / solution;    /* degradação: inclinação da idade do pneu por pista */
    ods output ParameterEstimates=pe&s FitStatistics=fit&s;  /* guarda coeficientes e R² */
  run; quit;                                              /* executa */
  ods exclude none;                                       /* volta a imprimir */

  data deg&s;                                             /* uma linha por pista com a degradação */
    set pe&s;                                             /* coeficientes */
    where index(Parameter, 'tyre_age') > 0;               /* só os termos de idade do pneu */
    length circuito $40;                                  /* nome da pista */
    if index(Parameter, ' ') = 0 then delete;             /* segurança: ignora linhas sem nome de pista */
    circuito = strip(substr(Parameter, index(Parameter, ' ') + 1));  /* "circuito*tyre_age Yas Marina Circuit" -> nome da pista */
    deg = Estimate;                                       /* s perdidos por volta de idade do pneu */
    keep circuito deg StdErr;                             /* mantém só o necessário */
  run;                                                    /* executa */
%mend degradacao;                                         /* fim */

%degradacao(24)                                           /* 2024: base da previsão */
%degradacao(25)                                           /* 2025: o que de fato aconteceu */

proc print data=fit24 noobs; title 'Ajuste 2024'; run;    /* R² do modelo 2024 */
proc print data=deg24 noobs; title 'Degradação 2024 (s/volta)'; run;  /* conferência: Miami ~0,026 e Suzuka ~0,120 */
title;                                                    /* limpa o título */
