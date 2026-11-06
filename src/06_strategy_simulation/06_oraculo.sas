/* =====================================================================
   06_oraculo.sas - teste "e se soubéssemos a degradação de 2025?"
   Separa o erro do SIMULADOR (lógica) do erro da ENTRADA (degradação que mudou)
   Na prática, essa informação viria dos treinos livres (sexta-feira)
   ===================================================================== */
data deg24_orig; set deg24; run;                        /* guarda a degradação de 2024 */
data deg24; set deg25; run;                             /* troca pela degradação real de 2025 */
ods exclude all;                                        /* não imprime as tabelas intermediárias */
%simula(25)                                             /* simulador com a degradação "perfeita" */
ods exclude none;
%avalia(25)                                             /* mesma avaliação */
data prev25_oraculo; set prev25; run;                   /* guarda a previsão-oráculo */
data deg24; set deg24_orig; run;                        /* volta a degradação de 2024 */
ods exclude all;
%simula(25)                                             /* refaz a previsão oficial (só com 2024) */
ods exclude none;
