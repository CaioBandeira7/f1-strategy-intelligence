/* =====================================================================
   03_simulador_previsao.sas - prevê, ANTES de olhar 2025:
     (1) janela ideal da 1ª parada   (2) número de paradas
     (3) tamanho do stint por composto
   usando só informação de 2024 (degradação e perda no box) + nº de voltas
   ===================================================================== */

/* ---------- 1. diferença de ritmo entre compostos (GLM 2024) ---------- */
data comp24;                                            /* efeito de cada composto no tempo de volta */
  set pe24;                                             /* coeficientes do GLM 2024 */
  where Parameter =: 'compound';                        /* só as linhas "compound HARD/MEDIUM/SOFT" */
  length compound $10;                                  /* nome do composto */
  compound = strip(substr(Parameter, 10));              /* tira o prefixo "compound " */
  off = Estimate;                                       /* s por volta em relação ao composto de referência */
  keep compound off;                                    /* mantém só o necessário */
run;                                                    /* executa */
proc sql noprint;                                       /* deixa tudo relativo ao HARD */
  select off into :offH trimmed from comp24 where compound = 'HARD';     /* efeito do HARD */
  select off into :offM trimmed from comp24 where compound = 'MEDIUM';   /* efeito do MEDIUM */
quit;                                                   /* fim */
%let offM = %sysevalf(&offM - &offH);                   /* MEDIUM em relação ao HARD (2024 deu ~+0,014 s) */
%put NOTE: MEDIUM vs HARD = &offM s/volta;              /* mostra no log */

%macro simula(a);                                      /* a = ano-alvo: 24 (checagem dentro da amostra) ou 25 (previsão) */
/* ---------- 2. entrada do simulador: uma linha por corrida seca do ano-alvo ---------- */
proc sql;                                               /* junta o que se sabia antes da corrida */
  create table entrada&a as
  select distinct r.circuito,                           /* pista */
         r.voltas_corrida as L,                         /* nº de voltas da corrida de 2025 */
         d.deg as b,                                    /* degradação de 2024 */
         x.mediana as P                                 /* perda no box de 2024 */
  from real&a r
       inner join deg24 d on r.circuito = d.circuito    /* só pistas que existiam em 2024 */
       inner join box24 x on r.circuito = x.circuito;   /* e com perda no box medida */
quit;                                                   /* fim */

/* ---------- 3. simulador: custo de cada estratégia, para cada volta da 1ª parada ---------- */
data sim&a(keep=circuito cen n_paradas k1 custo c1 c2 c3 n1 n2 n3);  /* uma linha por pista x cenário x nº de paradas x volta da 1ª parada */
  set entrada&a;                                        /* uma corrida por vez */
  length c1 c2 c3 $6;                                   /* compostos do melhor plano naquela volta */
  array nome[3] $6 _temporary_ ('HARD' 'MEDIUM' 'SOFT');/* nomes dos compostos */
  array m[3] _temporary_;                               /* multiplicador de desgaste de cada composto */
  array o[3] _temporary_;                               /* diferença de ritmo de cada composto (s/volta) */
  do cen = 1 to 4;                                      /* 4 cenários de pneu (os mesmos de 2024) */
    m[1] = 1; m[2] = 1;                                 /* HARD e MEDIUM: desgaste igual à degradação da pista */
    m[3] = ifn(cen in (1,2), 1.0, 1.7);                 /* SOFT: desgasta 1,0x ou 1,7x */
    o[1] = 0; o[2] = &offM;                             /* ritmo do HARD (referência) e do MEDIUM */
    o[3] = ifn(cen in (1,3), -0.13, 0);                 /* SOFT novo 0,13 s mais rápido ou igual */
    /* --- 1 parada --- */
    do k1 = 5 to L - 5;                                 /* volta da parada; stints de pelo menos 5 voltas */
      custo = 1e9;                                      /* começa com custo "infinito" */
      do a = 1 to 3; do z = 1 to 3;                     /* composto do 1º e do 2º stint */
        if a ne z then do;                              /* regra: pelo menos 2 compostos diferentes */
          t1 = k1; t2 = L - k1;                         /* tamanho de cada stint */
          c = b*m[a]*t1*(t1-1)/2 + o[a]*t1              /* custo do stint 1: desgaste acumulado + ritmo */
            + b*m[z]*t2*(t2-1)/2 + o[z]*t2 + P;         /* + stint 2 + uma parada */
          if c < custo then do;                         /* guarda o melhor plano para essa volta */
            custo = c; c1 = nome[a]; c2 = nome[z]; c3 = ''; n1 = t1; n2 = t2; n3 = .;
          end;
        end;
      end; end;
      n_paradas = 1; output;                            /* grava a linha */
    end;
    /* --- 2 paradas --- */
    do k1 = 5 to L - 10;                                /* volta da 1ª parada */
      custo = 1e9;                                      /* começa com custo "infinito" */
      do k2 = k1 + 5 to L - 5;                          /* volta da 2ª parada */
        t1 = k1; t2 = k2 - k1; t3 = L - k2;             /* tamanho dos 3 stints */
        do a = 1 to 3; do z = 1 to 3; do w = 1 to 3;    /* compostos dos 3 stints */
          if not (a = z and z = w) then do;             /* regra: pelo menos 2 compostos diferentes */
            c = b*m[a]*t1*(t1-1)/2 + o[a]*t1            /* stint 1 */
              + b*m[z]*t2*(t2-1)/2 + o[z]*t2            /* stint 2 */
              + b*m[w]*t3*(t3-1)/2 + o[w]*t3 + 2*P;     /* stint 3 + duas paradas */
            if c < custo then do;                       /* guarda o melhor plano para essa 1ª parada */
              custo = c; c1 = nome[a]; c2 = nome[z]; c3 = nome[w]; n1 = t1; n2 = t2; n3 = t3;
            end;
          end;
        end; end; end;
      end;
      n_paradas = 2; output;                            /* grava a linha */
    end;
  end;
run;                                                    /* executa */

/* ---------- 4. previsão: nº de paradas e janela da 1ª parada ---------- */
proc sql;                                               /* melhor custo por pista, cenário e nº de paradas */
  create table melhor&a as
  select circuito, cen, n_paradas, min(custo) as custo_min
  from sim&a group by circuito, cen, n_paradas;
  create table rec_cen&a as                               /* nº de paradas recomendado em cada cenário */
  select a.circuito, a.cen,
         case when a.custo_min <= b.custo_min then 1 else 2 end as rec,   /* o mais barato vence */
         abs(a.custo_min - b.custo_min) as margem       /* vantagem do vencedor (s) */
  from melhor&a a inner join melhor&a b
       on a.circuito = b.circuito and a.cen = b.cen
  where a.n_paradas = 1 and b.n_paradas = 2;
  create table rec&a as                                   /* recomendação final: maioria dos 4 cenários */
  select circuito,
         case when sum(rec = 2) >= 3 then 2 else 1 end as paradas_prev,  /* 2 paradas só se 3+ cenários concordam */
         count(distinct rec) = 1 as unanime,            /* 1 = os 4 cenários concordam */
         mean(margem) as margem_media                   /* vantagem média (s) */
  from rec_cen&a group by circuito;
  create table janela_cen&a as                            /* voltas a menos de 1 s do ótimo, por cenário */
  select s.circuito, s.cen, s.k1, s.custo - m.custo_min as extra
  from sim&a s
       inner join rec&a r on s.circuito = r.circuito and s.n_paradas = r.paradas_prev
       inner join melhor&a m on s.circuito = m.circuito and s.cen = m.cen and s.n_paradas = m.n_paradas
  where calculated extra <= 1;                          /* tolerância de 1 s */
  create table otimo_cen&a as                             /* volta ótima da 1ª parada em cada cenário */
  select circuito, cen, k1 as k_otimo
  from janela_cen&a group by circuito, cen having extra = min(extra);
quit;                                                   /* pausa o SQL para calcular a mediana */
proc means data=otimo_cen&a noprint nway;               /* mediana das voltas ótimas dos 4 cenários */
  class circuito;                                       /* por pista */
  var k_otimo;                                          /* volta ótima */
  output out=kprev&a(drop=_type_ _freq_) median=k_prev; /* guarda a mediana */
run;                                                    /* executa */
proc sql;                                               /* volta ao SQL */
  create table prev&a as                                /* previsão final por pista */
  select r.circuito, e.L, e.b, e.P, r.paradas_prev, r.unanime, r.margem_media,
         (select min(k1) from janela_cen&a j where j.circuito = r.circuito) as jan_ini,   /* início da janela (qualquer cenário) */
         (select max(k1) from janela_cen&a j where j.circuito = r.circuito) as jan_fim,   /* fim da janela */
         k.k_prev                                       /* volta prevista (mediana dos 4 ótimos) */
  from rec&a r inner join entrada&a e on r.circuito = e.circuito
               inner join kprev&a k on r.circuito = k.circuito
  order by circuito;
quit;                                                   /* fim */

proc print data=prev&a noobs; title "Previsão para 20&a (feita só com dados de 2024)"; run;
title;                                                  /* limpa o título */
%mend simula;                                           /* fim da macro */

%simula(24)                                             /* 2024: deve repetir o dashboard */
%simula(25)                                             /* 2025: previsão fora da amostra */
