"""Notificação das 07h: reuniões, prazos e conflitos de hoje (sem IA, só o banco). Uso: python3 resumo_dia.py"""
import datetime as dt, sqlite3, subprocess, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
sys.path.insert(0, str(RAIZ))
from prumo import TZ

hoje = dt.datetime.now(TZ).strftime("%Y-%m-%d")
con = sqlite3.connect(RAIZ / "db/assistente.db")
abertos = "coluna IN ('entrada','a_fazer','aguardando')"
reunioes = con.execute("SELECT count(*) FROM evidencias WHERE origem='agenda' AND removido_em IS NULL AND length(quando)>10"
                       " AND substr(quando,1,10)=?", (hoje,)).fetchone()[0]
vencidos = con.execute(f"SELECT count(*) FROM itens WHERE {abertos} AND tipo<>'bloqueio' AND prazo < ?", (hoje,)).fetchone()[0]
de_hoje = con.execute(f"SELECT count(*) FROM itens WHERE {abertos} AND tipo<>'bloqueio' AND prazo = ?", (hoje,)).fetchone()[0]
conflitos = con.execute(f"SELECT count(*) FROM itens WHERE {abertos} AND tipo='bloqueio' AND prazo = ?", (hoje,)).fetchone()[0]
msg = f"{reunioes} compromissos · {de_hoje} prazos hoje · {vencidos} vencidos · {conflitos} conflitos"
subprocess.run(["osascript", "-e", f'display notification "{msg}" with title "Prumo — bom dia"'])
con.execute("INSERT INTO auditoria(ator,acao,detalhe) VALUES('resumo_dia.py','resumo_dia',?)", (msg,))
con.commit()
print(msg)
