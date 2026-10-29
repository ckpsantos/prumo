"""Gera o briefing das reuniões com cliente que começam nas próximas 3 horas (1 por evento),
nos ambientes com "briefing": true em cadastro/config.json.
Usa pendências, última reunião, grupo de WhatsApp e números do Google Ads/GA4 (só leitura, se configurados).
Uso: /usr/bin/python3 briefing.py [--evento <id da evidência>]  (--evento ignora a janela de 3h)
"""
import datetime as dt, json, re, sqlite3, subprocess, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
sys.path.insert(0, str(RAIZ))
from prumo import AMB, CFG, TZ, USUARIO, caminho, cadastro_md, cliente_por_titulo

AGORA = dt.datetime.now(TZ)
JANELA = dt.timedelta(hours=3)  # rodada é de hora em hora: briefing sai 1–3h antes
MCP = {"mcpServers": {n: {"type": "stdio", "command": str(caminho(c))}
                      for n, c in CFG.get("metricas_mcp", {}).items() if caminho(c).exists()}}
FERRAMENTAS = {"google-ads": ["mcp__google-ads__query", "mcp__google-ads__list_accounts"],
               "google-analytics": ["mcp__google-analytics__run_report", "mcp__google-analytics__get_property_details"]}

con = sqlite3.connect(RAIZ / "db/assistente.db", timeout=30)
con.execute("PRAGMA foreign_keys = ON")


def cliente_do(amb, titulo, conteudo):
    """Cliente pelo título; evento sem convidados é bloco do próprio usuário (ex.: "Planejamento X"), não reunião."""
    if re.search(r"^Participantes:\s*$", conteudo or "", re.M):
        return None
    return cliente_por_titulo(amb, titulo)


def contexto(amb, cli):
    pend = con.execute("SELECT coluna, tipo, COALESCE(prazo,''), titulo, COALESCE(responsavel,'') FROM itens"
                       " WHERE ambiente=? AND cliente=? AND coluna IN ('entrada','a_fazer','aguardando')"
                       " AND tipo<>'bloqueio' ORDER BY prazo IS NULL, prazo", (amb, cli)).fetchall()
    reu = con.execute("SELECT quando, titulo, conteudo FROM evidencias WHERE ambiente=? AND origem='reuniao'"
                      " AND cliente=? ORDER BY quando DESC LIMIT 1", (amb, cli)).fetchone()
    desde = (AGORA - dt.timedelta(days=7)).strftime("%Y-%m-%d")
    grupo = con.execute("SELECT quando, remetente, conteudo FROM evidencias WHERE ambiente=? AND origem='whatsapp'"
                        " AND cliente=? AND quando >= ? ORDER BY quando", (amb, cli, desde)).fetchall()
    return {
        "{{CADASTRO}}": cadastro_md(amb, cli),
        "{{PENDENCIAS}}": "\n".join(f"- [{c}/{t}] {ti} {('— prazo ' + p) if p else ''} {('— ' + r) if r else ''}"
                                    for c, t, p, ti, r in pend) or "(nenhuma)",
        "{{REUNIAO}}": f"{reu[0]} — {reu[1]}\n{reu[2][:12000]}" if reu else "(nenhuma registrada)",
        "{{GRUPO}}": "\n".join(f"{q[:16]} {r}: {(c or '')[:400]}" for q, r, c in grupo[-150:]) or "(sem mensagens)",
    }


def gerar(amb, ev_id, titulo, inicio, cli):
    trocas = {"{{USUARIO}}": USUARIO, "{{AMBIENTE}}": AMB[amb]["nome"], "{{HOJE}}": AGORA.strftime("%d/%m/%Y"),
              "{{EVENTO}}": titulo, "{{INICIO}}": f"{inicio.astimezone(TZ):%d/%m %H:%M}",
              "{{CLIENTE}}": AMB[amb]["clientes"][cli].get("nome", cli), **contexto(amb, cli)}
    prompt = (RAIZ / "prompt_briefing.md").read_text()
    for k, v in trocas.items():
        prompt = prompt.replace(k, v)
    cfg = RAIZ / "midia/.mcp-briefing.json"
    cfg.parent.mkdir(exist_ok=True)
    cfg.write_text(json.dumps(MCP))
    permitidas = [f for n in MCP["mcpServers"] for f in FERRAMENTAS.get(n, [])] or [""]  # só consultas
    r = subprocess.run(["claude", "-p", "--no-session-persistence", "--mcp-config", str(cfg), "--strict-mcp-config", "--allowedTools", *permitidas],
                       input=prompt, capture_output=True, text=True, timeout=900)
    texto = r.stdout.strip()
    if r.returncode or not texto.startswith("#"):
        raise RuntimeError(f"claude falhou ({r.returncode}): {(r.stderr or r.stdout)[-300:]}")
    con.execute("INSERT OR IGNORE INTO briefings(ambiente,cliente,evidencia_id,inicio,titulo,conteudo) VALUES(?,?,?,?,?,?)",
                (amb, cli, ev_id, inicio.isoformat(timespec="seconds"), f"Briefing — {titulo}", texto))
    con.execute("INSERT INTO auditoria(ambiente,ator,acao,alvo,detalhe) VALUES(?,'briefing.py','briefing',?,?)",
                (amb, f"evidencia:{ev_id}", titulo))
    con.commit()


if __name__ == "__main__":
    feitos, erros = [], []
    com_briefing = [a for a in AMB if AMB[a].get("briefing")]
    eventos = con.execute("SELECT e.ambiente, e.id, e.titulo, e.quando, e.conteudo FROM evidencias e"
                          " LEFT JOIN briefings b ON b.evidencia_id=e.id WHERE e.origem='agenda' AND e.removido_em IS NULL"
                          " AND b.id IS NULL AND length(e.quando) > 10").fetchall()
    for amb, ev_id, titulo, quando, conteudo in eventos:
        if amb not in com_briefing:
            continue
        inicio = dt.datetime.fromisoformat(quando)
        cli = cliente_do(amb, titulo or "", conteudo)
        forcado = "--evento" in sys.argv and str(ev_id) == sys.argv[sys.argv.index("--evento") + 1]  # teste manual
        if not cli or not (forcado or AGORA <= inicio <= AGORA + JANELA):
            continue
        try:
            gerar(amb, ev_id, titulo, inicio, cli)
            feitos.append(titulo)
        except Exception as e:  # tenta de novo na próxima rodada
            erros.append(f"{titulo}: {e}")
    print(json.dumps({"briefings": feitos, "erros": erros}, ensure_ascii=False))
    sys.exit(1 if erros and not feitos else 0)
