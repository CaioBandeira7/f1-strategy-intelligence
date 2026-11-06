# coleta_f1.py                                                              # nome do arquivo
# Baixa as corridas secas de UMA temporada da F1 pela API OpenF1 e gera     # o que o script faz
# todos os CSVs com as mesmas regras de limpeza de 2024.                    # (largada, box, safety car e bandeira vermelha)
# Como rodar no JupyterLab (pasta work):  %run coleta_f1.py                 # comando para executar dentro do notebook
# Para trocar de temporada, mude só a linha ANO abaixo.                     # 2024 = base do modelo, 2025 = teste da previsão

import time                                                                 # pausas entre pedidos à API
import json                                                                 # converte o texto da API em dados do Python
import urllib.request                                                       # faz os pedidos à API
import urllib.error                                                         # reconhece erros HTTP (como o 429)
import pandas as pd                                                         # tabelas

BASE = "https://api.openf1.org/v1"                                          # endereço base da OpenF1


def get(endpoint, tentativas=6, **params):                                  # pede um conjunto de dados e devolve uma tabela
    q = "&".join(f"{k}={v}" for k, v in params.items())                     # monta o filtro do endereço (ex.: session_key=9472)
    for i in range(tentativas):                                             # tenta até 6 vezes
        try:                                                                # tenta fazer o pedido
            with urllib.request.urlopen(f"{BASE}/{endpoint}?{q}", timeout=60) as r:   # abre o endereço
                data = json.loads(r.read())                                 # lê e converte a resposta
            time.sleep(2)                                                   # pausa de 2 s para não estourar o limite da API
            return pd.DataFrame(data)                                       # devolve a tabela
        except urllib.error.HTTPError as e:                                 # se a API respondeu com erro
            if e.code == 429:                                               # 429 = pedidos demais, é preciso esperar
                espera = 15 * (i + 1)                                       # espera cada vez mais: 15 s, 30 s, 45 s...
                print(f"  429 em {endpoint}; esperando {espera} s")         # avisa que vai esperar
                time.sleep(espera)                                          # espera antes de tentar de novo
            else:                                                           # qualquer outro erro
                raise                                                       # mostra o erro e para
    raise RuntimeError(f"Desisti de {endpoint} após {tentativas} tentativas")   # nenhuma tentativa funcionou


import os                                                                   # pastas
PASTA = os.path.expanduser('~/f1')                                          # pasta f1 no Home do SAS
os.makedirs(PASTA, exist_ok=True)                                           # cria se não existir
os.chdir(PASTA)                                                             # salva os CSVs ali


def coletar(ANO):                                                           # roda a coleta inteira para uma temporada
    # ---------------------------------------------------------------------------  # parte 1: escolher as corridas
    print(f"1) Listando as corridas de {ANO} e checando chuva...")              # aviso de progresso
    corridas = get("sessions", year=ANO, session_name="Race")                   # corridas principais da temporada (sem sprints)
    corridas = corridas.sort_values("date_start").reset_index(drop=True)        # ordena por data
    climas = {}                                                                 # guarda o clima de cada corrida (para não baixar duas vezes)
    chuva = []                                                                  # maior valor de chuva de cada corrida
    for sk in corridas["session_key"]:                                          # para cada corrida
        w = get("weather", session_key=sk)                                      # baixa o clima
        climas[sk] = w                                                          # guarda o clima no dicionário
        chuva.append(w["rainfall"].max() if not w.empty else None)              # 0 = não choveu em nenhum momento
    corridas["chuva_max"] = chuva                                               # coluna com o resultado da checagem
    secas = corridas[corridas["chuva_max"] == 0]                                # só as corridas sem chuva
    print(f"   {len(corridas)} corridas, {len(secas)} secas")                   # conferência (2024: 24 corridas, 19 secas)


    # ---------------------------------------------------------------------------  # parte 2: montar as voltas de cada corrida
    def montar_corrida(sk):                                                     # monta a tabela de voltas de uma corrida
        laps = get("laps", session_key=sk)                                      # voltas
        pits = get("pit", session_key=sk)                                       # paradas no box
        stints = get("stints", session_key=sk)                                  # trechos com o mesmo jogo de pneus
        entradas = set() if pits.empty else set(zip(pits["driver_number"], pits["lap_number"]))   # pares (piloto, volta) de entrada no box
        laps["is_in_lap"] = [(d, l) in entradas                                 # True nas voltas de entrada no box
                             for d, l in zip(laps["driver_number"], laps["lap_number"])]
        t = laps.merge(stints[["driver_number", "stint_number", "lap_start",    # junta cada volta a todos os stints do piloto
                               "lap_end", "compound", "tyre_age_at_start"]],
                       on="driver_number")
        t = t[(t["lap_number"] >= t["lap_start"]) &                             # mantém só o stint em que a volta cai
              (t["lap_number"] <= t["lap_end"])].copy()
        t["tyre_age"] = t["tyre_age_at_start"] + (t["lap_number"] - t["lap_start"])   # idade do pneu no início da volta
        saida = t["is_pit_out_lap"].eq(True)                                    # volta de saída do box (vazio conta como não)
        t["is_pit_out_lap"] = saida                                             # guarda a coluna já sem vazios
        t["limpa"] = ((~t["is_in_lap"]) & (~saida) &                            # sem entrada e sem saída do box
                      (t["lap_number"] > 1) &                                   # sem a volta 1 (largada)
                      t["lap_duration"].notna() &                               # a volta precisa ter tempo
                      t["compound"].notna() &                                   # precisa ter composto
                      t["tyre_age"].notna())                                    # precisa ter idade do pneu
        t["session_key"] = sk                                                   # código da corrida em cada linha
        stints["session_key"] = sk                                              # código da corrida nos stints
        return t, stints                                                        # devolve as voltas e os stints da corrida


    print("2) Baixando voltas, paradas, stints e mensagens de cada corrida seca...")   # aviso de progresso
    tabelas, avisos, trechos = [], [], []                                       # listas para voltas, mensagens e stints
    for _, c in secas.iterrows():                                               # para cada corrida seca
        t, st = montar_corrida(c["session_key"])                                # monta as voltas e pega os stints
        t["circuito"] = c["circuit_short_name"]                                 # nome da pista
        st["circuito"] = c["circuit_short_name"]                                # nome da pista nos stints
        tabelas.append(t)                                                       # guarda as voltas
        trechos.append(st)                                                      # guarda os stints
        rc = get("race_control", session_key=c["session_key"])                  # mensagens da direção de prova
        rc["circuito"] = c["circuit_short_name"]                                # nome da pista
        avisos.append(rc)                                                       # guarda
        print(f"   {c['circuit_short_name']}: {len(t)} voltas, {int(t['limpa'].sum())} limpas")   # progresso
    temporada = pd.concat(tabelas, ignore_index=True)                           # junta as voltas das 19 corridas
    rc_todas = pd.concat(avisos, ignore_index=True)                             # junta as mensagens das 19 corridas
    stints_todos = pd.concat(trechos, ignore_index=True)                        # junta os stints de todas as corridas


    # ---------------------------------------------------------------------------  # parte 3: safety car e VSC (regra por horário)
    print("3) Marcando safety car, VSC, relargada e bandeira vermelha...")      # aviso de progresso
    temporada["inicio_t"] = pd.to_datetime(temporada["date_start"], utc=True, format="ISO8601")   # horário de início de cada volta
    temporada["fim_t"] = temporada["inicio_t"] + pd.to_timedelta(temporada["lap_duration"], unit="s")   # horário de fim da volta
    sc_ok = rc_todas[rc_todas["category"] == "SafetyCar"].copy()                # só mensagens de safety car e VSC
    sc_ok["t"] = pd.to_datetime(sc_ok["date"], utc=True, format="ISO8601")      # horário de cada mensagem

    janelas = []                                                                # períodos em horário: (pista, começo, fim)
    for pista, g in sc_ok.sort_values("t").groupby("circuito"):                 # para cada pista, em ordem de horário
        voltas_pista = temporada[temporada["circuito"] == pista]                # voltas daquela pista
        fim_corrida = voltas_pista["fim_t"].max()                               # horário em que a última volta terminou
        t_ini = None                                                            # começa sem período aberto
        for _, r in g.iterrows():                                               # percorre as mensagens
            msg = r["message"]                                                  # texto da mensagem
            if "DEPLOYED" in msg and t_ini is None:                             # começou um período
                t_ini = r["t"]                                                  # guarda o horário de começo
            elif ("IN THIS LAP" in msg or "ENDING" in msg) and t_ini is not None and pd.notna(r["lap_number"]):   # terminou
                prox = voltas_pista[voltas_pista["lap_number"] == int(r["lap_number"]) + 1]   # voltas logo depois da volta do fim
                t_fim = prox["inicio_t"].min() if len(prox) else fim_corrida    # quando o líder começou essa volta
                janelas.append((pista, t_ini, t_fim))                           # guarda o período
                t_ini = None                                                    # fecha
        if t_ini is not None:                                                   # corrida terminou com período aberto
            janelas.append((pista, t_ini, fim_corrida))                         # vai até o fim da corrida

    temporada["sc_t"] = False                                                   # volta afetada por safety car ou VSC
    temporada["relargada_t"] = False                                            # primeira volta depois do período
    for pista, a, b in janelas:                                                 # para cada período
        na_pista = temporada["circuito"] == pista                               # voltas da pista
        encosta = (temporada["inicio_t"] < b) & (temporada["fim_t"] > a)        # a volta encosta no período
        temporada.loc[na_pista & encosta, "sc_t"] = True                        # marca
        depois = temporada[na_pista & (temporada["inicio_t"] >= b)]             # voltas que começam depois do fim
        primeira = depois.groupby("driver_number")["lap_number"].idxmin()       # primeira delas de cada piloto
        temporada.loc[primeira, "relargada_t"] = True                           # marca como relargada

    verm = rc_todas[rc_todas["flag"] == "RED"].groupby("circuito")["lap_number"].max()   # volta da bandeira vermelha em cada pista
    limite = (verm + 2).to_dict()                                               # tira até 2 voltas depois dela (Suzuka e Monte Carlo: voltas 1 a 3)
    temporada["pos_vermelha"] = [v <= limite.get(p, 0)                          # True nas voltas afetadas pela bandeira vermelha
                                 for p, v in zip(temporada["circuito"], temporada["lap_number"])]

    temporada["usar2"] = (temporada["limpa"] & ~temporada["sc_t"]               # voltas que vamos usar: limpas, sem safety car,
                          & ~temporada["relargada_t"] & ~temporada["pos_vermelha"])   # sem relargada e sem bandeira vermelha

    mediana = temporada[temporada["limpa"]].groupby("circuito")["lap_duration"].median()   # tempo mediano das voltas limpas de cada pista
    temporada["rel"] = temporada["lap_duration"] / temporada["circuito"].map(mediana)      # tempo relativo (1,00 = volta normal)


    # ---------------------------------------------------------------------------  # parte 4: clima em cada volta
    print("4) Juntando o clima a cada volta...")                                # aviso de progresso
    clima = pd.concat([w.assign(session_key=sk) for sk, w in climas.items()     # clima das corridas secas, com o código da corrida
                       if sk in set(secas["session_key"])], ignore_index=True)
    clima["date"] = pd.to_datetime(clima["date"], utc=True, format="ISO8601")   # horário de cada medição
    clima = clima.sort_values("date")                                           # ordena por horário (exigido pela junção)
    com_hora = temporada.dropna(subset=["inicio_t"]).sort_values("inicio_t")    # voltas com horário, em ordem
    temporada_c = pd.merge_asof(com_hora,                                       # junta a medição de clima mais próxima
                                clima[["date", "session_key", "air_temperature",
                                       "track_temperature", "humidity", "wind_speed"]],
                                left_on="inicio_t", right_on="date",            # compara horário da volta com horário do clima
                                by="session_key", direction="nearest")          # só clima da mesma corrida


    # ---------------------------------------------------------------------------  # parte 5: custo da parada no box por pista
    print("5) Calculando o custo da parada por pista...")                       # aviso de progresso
    base = (temporada[temporada["usar2"]]                                       # voltas usadas
            .groupby(["session_key", "driver_number"])["lap_duration"]          # por piloto em cada corrida
            .median().rename("volta_normal"))                                   # tempo típico de volta
    fora = ~temporada["sc_t"] & ~temporada["pos_vermelha"]                      # fora de safety car e de bandeira vermelha
    ent = temporada[temporada["is_in_lap"] & fora][["session_key", "circuito",  # voltas de entrada no box
                                                    "driver_number", "lap_number", "lap_duration"]]
    sai = temporada[temporada["is_pit_out_lap"] & fora][["session_key",         # voltas de saída do box
                                                         "driver_number", "lap_number", "lap_duration"]].copy()
    sai["lap_number"] = sai["lap_number"] - 1                                   # alinha a saída com a entrada da mesma parada
    par = ent.merge(sai, on=["session_key", "driver_number", "lap_number"],     # junta entrada e saída
                    suffixes=("_ent", "_sai"))
    par = par.join(base, on=["session_key", "driver_number"])                   # junta o tempo típico do piloto
    par["perda_box"] = par["lap_duration_ent"] + par["lap_duration_sai"] - 2 * par["volta_normal"]   # tempo perdido na parada
    tab_box = (par.groupby("circuito")["perda_box"]                             # por pista
               .agg(paradas="count", mediana="median", minimo="min", maximo="max")   # número de paradas e perdas
               .round(1).sort_values("mediana"))                                # arredonda e ordena


    # ---------------------------------------------------------------------------  # parte 6: salvar tudo na pasta atual (work)
    print("6) Salvando os arquivos...")                                         # aviso de progresso
    temporada.to_csv(f"f1_{ANO}_secas_voltas_marcadas.csv", index=False)          # voltas com todas as marcações
    rc_todas.to_csv(f"f1_{ANO}_secas_race_control.csv", index=False)              # mensagens da direção de prova
    clima.to_csv(f"f1_{ANO}_secas_clima.csv", index=False)                        # clima das corridas secas
    temporada_c.to_csv(f"f1_{ANO}_secas_voltas_clima.csv", index=False)           # voltas com clima
    tab_box.to_csv(f"f1_{ANO}_perda_box_por_pista.csv")                           # custo da parada por pista

    cols = ["session_key", "circuito", "driver_number", "lap_number",           # colunas para o SAS
            "stint_number", "compound", "tyre_age", "tyre_age_at_start",
            "lap_duration", "is_in_lap", "is_pit_out_lap", "sc_t", "usar2"]
    para_sas = temporada[cols].copy()                                           # copia só essas colunas
    for c in ["is_in_lap", "is_pit_out_lap", "sc_t", "usar2"]:                  # colunas de verdadeiro/falso
        para_sas[c] = para_sas[c].eq(True).astype(int)                          # troca por 1/0
    para_sas.to_csv(f"f1_{ANO}_voltas_para_sas.csv", index=False)              # CSV enxuto para o SAS Studio

    # Estratégia real de cada piloto (é o gabarito para testar a previsão)     # novo arquivo
    voltas_corrida = temporada.groupby("session_key")["lap_number"].max()       # número de voltas de cada corrida
    st = stints_todos.sort_values(["session_key", "driver_number", "stint_number"])   # stints em ordem
    real = (st.groupby(["session_key", "circuito", "driver_number"])            # um registro por piloto em cada corrida
            .agg(n_stints=("stint_number", "count"),                            # quantos stints ele fez
                 fim_stint1=("lap_end", "first"),                               # volta em que o 1º stint acabou = 1ª parada
                 compostos=("compound", lambda x: "-".join(x.dropna())))        # sequência de compostos (ex.: MEDIUM-HARD)
            .reset_index())
    real["paradas"] = real["n_stints"] - 1                                      # paradas = stints menos 1
    real["voltas_corrida"] = real["session_key"].map(voltas_corrida)            # voltas da corrida
    real["voltas_piloto"] = real.set_index(["session_key", "driver_number"]).index.map(   # quantas voltas o piloto completou
        temporada.groupby(["session_key", "driver_number"])["lap_number"].max())
    real["terminou"] = (real["voltas_piloto"] >= real["voltas_corrida"] - 1).astype(int)  # 1 = terminou (aceita 1 volta atrás)
    real["parada1_vermelha"] = [                                                # 1 = 1ª parada feita na bandeira vermelha
        int(pd.notna(v) and v <= limite.get(p, 0))
        for p, v in zip(real["circuito"], real["fim_stint1"])]
    stints_todos.to_csv(f"f1_{ANO}_stints.csv", index=False)                   # stints brutos
    real.to_csv(f"f1_{ANO}_estrategia_real.csv", index=False)                  # estratégia real por piloto


    # ---------------------------------------------------------------------------  # parte 7: conferências
    print(f"\nConferências {ANO} (entre parênteses, os valores de 2024):")     # título
    print("  Corridas secas:", len(secas), "(19)")                              # número de corridas secas
    print("  Voltas:", len(temporada), "(20510)")                               # total de voltas
    print("  Voltas limpas:", int(temporada["limpa"].sum()), "(18969)")         # voltas limpas
    print("  Voltas usadas:", int(temporada["usar2"].sum()), "(18091)")         # voltas usadas no modelo
    print("  Voltas com clima:", len(temporada_c), "(20500)")                   # voltas com clima
    print("  Períodos de safety car/VSC:", len(janelas), "(14)")                # períodos montados
    print("  Pilotos-corrida na estratégia real:", len(real))                    # registros do gabarito
    print(tab_box.to_string())                                                  # tabela do custo da parada



for ano in (2024, 2025):                                                    # 2024 = treino, 2025 = teste
    coletar(ano)                                                            # baixa e salva a temporada
print('Arquivos na pasta:', sorted(os.listdir(PASTA)))                       # conferência final