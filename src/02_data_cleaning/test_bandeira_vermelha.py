# test_bandeira_vermelha.py                                                  # nome do arquivo
# Testes da regra de bandeira vermelha (rodar: python -m pytest -q)          # como executar
import pandas as pd                                                          # tabelas
from regras_limpeza import marca_vermelha                                    # regra corrigida


def regra_antiga(pistas, voltas, rc):                                        # cópia fiel da regra antiga (para comparar)
    verm = rc[rc["flag"] == "RED"].groupby("circuito")["lap_number"].max()   # última volta com bandeira por pista
    limite = (verm + 2).to_dict()                                            # limite = última bandeira + 2
    return [v <= limite.get(p, 0) for p, v in zip(pistas, voltas)]          # tudo até o limite


def _corrida(pista, n):                                                      # corrida sintética com n voltas
    return [pista] * n, list(range(1, n + 1))                                # pistas e voltas 1..n


def test_bandeira_no_meio_da_corrida():                                      # o caso que a regra antiga errava
    pistas, voltas = _corrida("Teste", 60)                                   # 60 voltas
    rc = pd.DataFrame({"circuito": ["Teste"], "flag": ["RED"], "lap_number": [30]})   # bandeira na volta 30
    nova = marca_vermelha(pistas, voltas, rc)                                # regra nova
    antiga = regra_antiga(pistas, voltas, rc)                                # regra antiga
    assert [v for v, m in zip(voltas, nova) if m] == [30, 31, 32]            # nova: só 30, 31 e 32
    assert sum(antiga) == 32                                                 # antiga: voltas 1 a 32 (erro)


def test_bandeira_na_volta_1_igual_a_antiga():                               # caso real de 2024 (Mônaco e Suzuka)
    pistas, voltas = _corrida("Monte Carlo", 78)                             # 78 voltas
    rc = pd.DataFrame({"circuito": ["Monte Carlo"], "flag": ["RED"], "lap_number": [1]})   # bandeira na volta 1
    assert marca_vermelha(pistas, voltas, rc) == regra_antiga(pistas, voltas, rc)   # as duas dão o mesmo resultado


def test_duas_bandeiras_na_mesma_corrida():                                  # dois eventos
    pistas, voltas = _corrida("Teste", 60)                                   # 60 voltas
    rc = pd.DataFrame({"circuito": ["Teste", "Teste"], "flag": ["RED", "RED"], "lap_number": [5, 40]})
    nova = marca_vermelha(pistas, voltas, rc)                                # regra nova
    assert [v for v, m in zip(voltas, nova) if m] == [5, 6, 7, 40, 41, 42]   # cada evento + 2 voltas


def test_sem_bandeira_e_volta_vazia():                                       # nada a marcar
    rc = pd.DataFrame({"circuito": ["X"], "flag": ["RED"], "lap_number": [None]})   # bandeira sem volta
    assert marca_vermelha(["X", "X"], [1, float("nan")], rc) == [False, False]   # nada marcado
