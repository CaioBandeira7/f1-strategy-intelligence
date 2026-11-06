/* =====================================================================
   15_coleta_2023.sas - coleta da temporada 2023 (OpenF1) para a
   validação temporal 2023 -> 2024. Usa os MESMOS scripts já salvos em ~/f1
   (00_coleta_openf1.py e 07_coleta_treinos.py), aplicados só a 2023, com a
   regra corrigida da bandeira vermelha. Gera arquivos f1_2023_* novos:
   nenhum arquivo de 2024/2025, da V1 ou da V2 é alterado.
   ===================================================================== */
proc python;
submit;
import os, re, sys, json, time, urllib.request, urllib.error     # módulos
import pandas as pd                                                # tabelas
PASTA = os.path.expanduser("~/f1")                                 # pasta do projeto
os.chdir(PASTA)                                                    # trabalha ali
sys.path.insert(0, PASTA)                                          # para importar regras_limpeza

# 1. módulo com a regra corrigida (arquivo novo; não altera nenhum script existente)
open("regras_limpeza.py", "w").write('''# regras_limpeza.py - regra corrigida da bandeira vermelha (auditoria 2026-11)
def eventos_vermelha(rc):                                          # voltas com bandeira vermelha por pista
    verm = rc[(rc["flag"] == "RED") & rc["lap_number"].notna()]
    return {p: sorted({int(v) for v in g["lap_number"]}) for p, g in verm.groupby("circuito")}
def afetada_vermelha(pista, volta, eventos, depois=2):             # volta da bandeira e as 2 seguintes
    if volta is None or volta != volta:
        return False
    return any(l <= volta <= l + depois for l in eventos.get(pista, []))
''')

# 2. coleta das corridas: script salvo, com a regra corrigida e só 2023
src = open("00_coleta_openf1.py").read()                           # script usado em 2024/2025
antigo = re.compile(r'( *)verm = rc_todas\[rc_todas\["flag"\] == "RED"\]\.groupby\("circuito"\)\["lap_number"\]\.max\(\)[^\n]*\n'
                    r' *limite = \(verm \+ 2\)\.to_dict\(\)[^\n]*\n'
                    r' *temporada\["pos_vermelha"\] = \[v <= limite\.get\(p, 0\)[^\n]*\n'
                    r' *for p, v in zip\(temporada\["circuito"\], temporada\["lap_number"\]\)\]\n')
m = antigo.search(src); assert m, "bloco da bandeira vermelha não encontrado"
ind = m.group(1)
novo = (f'{ind}from regras_limpeza import eventos_vermelha, afetada_vermelha\n'
        f'{ind}ev_verm = eventos_vermelha(rc_todas)\n'
        f'{ind}temporada["pos_vermelha"] = [afetada_vermelha(p, v, ev_verm) for p, v in zip(temporada["circuito"], temporada["lap_number"])]\n')
src = src[:m.start()] + novo + src[m.end():]
assert "int(pd.notna(v) and v <= limite.get(p, 0))" in src
src = src.replace("int(pd.notna(v) and v <= limite.get(p, 0))", "int(afetada_vermelha(p, v, ev_verm))")
assert "for ano in (2024, 2025):" in src
src = src.replace("for ano in (2024, 2025):", "for ano in (2023,):")   # só 2023
src = re.sub(r'( +)if e\.code == 429:', lambda mm: mm.group(1) + 'if e.code == 404: return pd.DataFrame()  # API sem dados\n' + mm.group(0), src, count=1)   # 404 = consulta vazia
exec(compile(src, "coleta_2023", "exec"), {"__name__": "coleta_2023"})

# 3. treinos livres de 2023: script salvo, só 2023
src = open("07_coleta_treinos.py").read()
assert "for ano in (2024, 2025):" in src
src = src.replace("for ano in (2024, 2025):", "for ano in (2023,):")
src = re.sub(r'( +)if e\.code == 429:', lambda mm: mm.group(1) + 'if e.code == 404: return pd.DataFrame()  # API sem dados\n' + mm.group(0), src, count=1)   # 404 = consulta vazia
exec(compile(src, "treinos_2023", "exec"), {"__name__": "treinos_2023"})

# 4. equipes de 2023 (arquivo separado; f1_equipes.csv não muda)
real = pd.read_csv("f1_2023_estrategia_real.csv")
linhas = []
for sk in sorted(real["session_key"].unique()):
    for i in range(6):
        try:
            with urllib.request.urlopen(f"https://api.openf1.org/v1/drivers?session_key={int(sk)}", timeout=60) as r:
                d = pd.DataFrame(json.loads(r.read()))
            break
        except urllib.error.HTTPError as e:
            if e.code == 404: d = pd.DataFrame(columns=['session_key', 'driver_number', 'name_acronym', 'team_name']); break
            if e.code != 429: raise
            time.sleep(15 * (i + 1))
    time.sleep(2)
    d["ano"] = 2023
    linhas.append(d[["ano", "session_key", "driver_number", "name_acronym", "team_name"]])
pd.concat(linhas).to_csv("f1_2023_equipes.csv", index=False)

# 5. conferências de cobertura da API
m = pd.read_csv("f1_2023_secas_voltas_marcadas.csv")
print("COB corridas secas:", m["session_key"].nunique(), "| voltas:", len(m), "| usadas:", int(m["usar2"].sum()))
print("COB voltas sem composto por corrida:")
print(m.assign(semcomp=m["compound"].isna()).groupby("circuito")["semcomp"].mean().round(3).to_string())
print("COB compostos:", m["compound"].value_counts(dropna=False).to_dict())
fp = pd.read_csv("f1_2023_treinos_voltas.csv")
print("COB treinos por fim de semana:")
print(fp.groupby("circuito")["session_key"].nunique().to_string())
endsubmit;
run;
