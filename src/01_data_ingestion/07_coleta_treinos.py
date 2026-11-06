# 07_coleta_treinos.py                                                       # nome do arquivo
# Baixa os treinos livres (FP1, FP2, FP3) dos fins de semana das corridas    # o que o script faz
# secas de 2024 e 2025. Ideia: estimar a degradação ANTES da corrida,        # como as equipes fazem na sexta-feira
# a partir das simulações de corrida (stints longos) dos treinos.

import os                                                                   # pastas
import time                                                                 # pausas entre pedidos
import json                                                                 # converte a resposta da API
import urllib.request                                                       # faz os pedidos
import urllib.error                                                         # reconhece o erro 429
import pandas as pd                                                         # tabelas

BASE = "https://api.openf1.org/v1"                                          # endereço da OpenF1
PASTA = os.path.expanduser("~/f1")                                          # pasta do projeto no Home do SAS
os.chdir(PASTA)                                                             # salva tudo ali


def get(endpoint, tentativas=6, **params):                                  # pede dados e devolve uma tabela
    q = "&".join(f"{k}={v}" for k, v in params.items())                     # monta o filtro do endereço
    for i in range(tentativas):                                             # tenta até 6 vezes
        try:
            with urllib.request.urlopen(f"{BASE}/{endpoint}?{q}", timeout=60) as r:   # abre o endereço
                data = json.loads(r.read())                                 # lê a resposta
            time.sleep(2)                                                   # pausa para respeitar o limite da API
            return pd.DataFrame(data)                                       # devolve a tabela
        except urllib.error.HTTPError as e:                                 # erro HTTP
            if e.code == 429:                                               # pedidos demais
                time.sleep(15 * (i + 1))                                    # espera e tenta de novo
            else:
                raise                                                       # outro erro: para
    raise RuntimeError(f"Desisti de {endpoint}")                            # nenhuma tentativa funcionou


for ano in (2024, 2025):                                                    # treino (2024) e teste (2025)
    real = pd.read_csv(f"f1_{ano}_estrategia_real.csv")                     # corridas secas já coletadas
    corridas = get("sessions", year=ano, session_name="Race")               # corridas do ano (para achar o fim de semana)
    corridas = corridas[corridas["session_key"].isin(real["session_key"].unique())]   # só as secas
    treinos = get("sessions", year=ano, session_type="Practice")            # todos os treinos livres do ano
    treinos = treinos[treinos["meeting_key"].isin(corridas["meeting_key"])] # só dos fins de semana das corridas secas
    tabelas = []                                                            # voltas de todos os treinos
    for _, s in treinos.iterrows():                                         # para cada treino
        laps = get("laps", session_key=s["session_key"])                    # voltas do treino
        stints = get("stints", session_key=s["session_key"])                # stints do treino
        if laps.empty or stints.empty:                                      # treino sem dados
            continue                                                        # pula
        t = laps.merge(stints[["driver_number", "stint_number", "lap_start", "lap_end",
                               "compound", "tyre_age_at_start"]], on="driver_number")   # junta voltas e stints
        t = t[(t["lap_number"] >= t["lap_start"]) & (t["lap_number"] <= t["lap_end"])].copy()   # volta dentro do stint
        t["tyre_age"] = t["tyre_age_at_start"] + (t["lap_number"] - t["lap_start"])      # idade do pneu
        t["volta_no_stint"] = t["lap_number"] - t["lap_start"]               # 0 = 1ª volta do stint (saída do box)
        t["ultima_do_stint"] = (t["lap_number"] == t["lap_end"]).astype(int) # 1 = volta de entrada no box
        t["circuito"] = corridas.loc[corridas["meeting_key"] == s["meeting_key"], "circuit_short_name"].iloc[0]  # pista
        t["treino"] = s["session_name"]                                     # Practice 1/2/3
        t["race_session_key"] = corridas.loc[corridas["meeting_key"] == s["meeting_key"], "session_key"].iloc[0]  # corrida do fim de semana
        tabelas.append(t[["race_session_key", "circuito", "treino", "session_key", "driver_number",
                          "stint_number", "compound", "lap_number", "lap_duration", "tyre_age",
                          "volta_no_stint", "ultima_do_stint", "is_pit_out_lap"]])   # colunas úteis
        print(f"  {ano} {t['circuito'].iloc[0]} {s['session_name']}: {len(t)} voltas")   # progresso
    tudo = pd.concat(tabelas, ignore_index=True)                            # junta todos os treinos
    tudo["is_pit_out_lap"] = tudo["is_pit_out_lap"].eq(True).astype(int)    # verdadeiro/falso vira 1/0
    tudo.to_csv(f"f1_{ano}_treinos_voltas.csv", index=False)                # salva
    print(ano, "treinos:", tudo["session_key"].nunique(), "voltas:", len(tudo))   # conferência
