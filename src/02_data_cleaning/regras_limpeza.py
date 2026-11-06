# regras_limpeza.py                                                          # nome do arquivo
# Regras de limpeza compartilhadas pelos scripts de coleta.                  # para não haver duas versões da mesma regra
# Correção (auditoria 2026-11): a regra antiga da bandeira vermelha          # o que mudou
# excluía TODAS as voltas da 1 até (última bandeira + 2). Com bandeira no    # por que estava errado
# meio da prova, isso apagava a corrida inteira até aquele ponto.            # efeito do erro
# A regra nova exclui só a volta de cada bandeira e as 2 seguintes.          # regra corrigida


def eventos_vermelha(rc):                                                    # voltas com bandeira vermelha por pista
    verm = rc[(rc["flag"] == "RED") & rc["lap_number"].notna()]              # mensagens de bandeira vermelha com volta
    return {p: sorted({int(v) for v in g["lap_number"]})                     # pista -> lista de voltas (sem repetição)
            for p, g in verm.groupby("circuito")}


def afetada_vermelha(pista, volta, eventos, depois=2):                       # True se a volta foi afetada pela bandeira
    if volta is None or volta != volta:                                      # volta vazia (NaN) não é marcada
        return False                                                         # devolve falso
    return any(l <= volta <= l + depois for l in eventos.get(pista, []))     # da volta da bandeira até 2 voltas depois


def marca_vermelha(pistas, voltas, rc, depois=2):                            # aplica a regra a uma lista de voltas
    ev = eventos_vermelha(rc)                                                # eventos por pista
    return [afetada_vermelha(p, v, ev, depois) for p, v in zip(pistas, voltas)]   # uma marcação por volta
