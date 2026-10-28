"""Lê evidências ainda não processadas e, POR AMBIENTE (nunca mistura), pede ao Claude as tarefas.
Grava itens na Entrada e respostas sugeridas como rascunho. Nada é enviado.
Uso: python3 classificar.py [--max-lotes N]
"""
import datetime as dt, json, re, sqlite3, subprocess, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
sys.path.insert(0, str(RAIZ))
from prumo import AMB, TZ, USUARIO, cadastro_md
LOTE = 60
MAX_LOTES = int(sys.argv[sys.argv.index("--max-lotes") + 1]) if "--max-lotes" in sys.argv else 6
DIAS = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]
TIPOS = {"acao", "sugestao", "bloqueio", "acompanhamento"}
NIVEIS = {"alta", "media", "baixa"}

con = sqlite3.connect(RAIZ / "db/assistente.db", timeout=30)
con.execute("PRAGMA foreign_keys = ON")


def abertas(amb):
    rows = con.execute("SELECT COALESCE(i.cliente,'sem cliente'), i.titulo FROM itens i JOIN evidencias e ON e.id=i.evidencia_id"
                       " WHERE i.ambiente=? AND e.origem<>'agenda' AND i.coluna IN ('entrada','a_fazer','aguardando')"
                       " ORDER BY 1", (amb,)).fetchall()  # conflitos de agenda ficam fora
    return "\n".join(f"- [{c}] {t}" for c, t in rows) or "(nenhuma)"


def chamar_claude(prompt):
    vazio = RAIZ / "midia/.mcp-vazio.json"
    vazio.parent.mkdir(exist_ok=True)
    vazio.write_text('{"mcpServers":{}}')
    r = subprocess.run(["claude", "-p", "--mcp-config", str(vazio), "--strict-mcp-config", "--allowedTools", ""],
                       input=prompt, capture_output=True, text=True, timeout=900)
    m = re.search(r"\{.*\}", r.stdout, re.S)
    if r.returncode or not m:
        raise RuntimeError(f"claude falhou (código {r.returncode}): {(r.stderr or r.stdout)[-300:]}")
    return json.loads(m.group(0))


def validar(it, lote, clientes):
    """Devolve o item limpo ou None. O banco ainda barra cliente de outro ambiente (FK)."""
    ids = [i for i in it.get("evidencias", []) if i in lote]
    if not ids or it.get("tipo") not in TIPOS or not (it.get("titulo") or "").strip():
        return None
    dica = lote[ids[0]]["cliente"]
    cli = dica or (it.get("cliente") if it.get("cliente") in clientes else None)  # grupo autorizado manda
    prazo = it.get("prazo") if re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(it.get("prazo"))) else None
    nivel = lambda k: it.get(k) if it.get(k) in NIVEIS else None
    return {"ids": ids, "cliente": cli, "tipo": it["tipo"], "titulo": it["titulo"].strip()[:120],
            "descricao": it.get("descricao"), "prazo": prazo, "responsavel": it.get("responsavel") or None,
            "prioridade": nivel("prioridade"), "confianca": nivel("confianca") or "baixa",
            "resposta": (it.get("resposta_sugerida") or "").strip() or None}


def processar(amb, hoje):
    clientes = list(AMB[amb]["clientes"])
    sql = ("SELECT id, origem, cliente, titulo, remetente, quando, conteudo FROM evidencias"
           " WHERE ambiente=? AND processado_em IS NULL AND origem {} ORDER BY origem, titulo, quando LIMIT ?")
    rows = (con.execute(sql.format("IN ('whatsapp','email')"), (amb, LOTE)).fetchall()
            or con.execute(sql.format("= 'reuniao'"), (amb, 4)).fetchall())  # transcrição é longa: 4 por chamada
    if not rows:
        return None
    lote = {r[0]: {"id": r[0], "origem": r[1], "cliente": r[2], "grupo_ou_assunto": r[3], "remetente": r[4],
                   "quando": r[5], "texto": (r[6] or "")[:20000 if r[1] == "reuniao" else 3000]} for r in rows}
    prompt = (open(RAIZ / "prompt_classificar.md").read()
              .replace("{{USUARIO}}", USUARIO).replace("{{HOJE}}", hoje.strftime("%d/%m/%Y")).replace("{{DIA_SEMANA}}", DIAS[hoje.weekday()])
              .replace("{{AMBIENTE}}", AMB[amb]["nome"]).replace("{{CLIENTES}}", ", ".join(clientes))
              .replace("{{CADASTRO}}", cadastro_md(amb)).replace("{{ABERTAS}}", abertas(amb))
              + json.dumps(list(lote.values()), ensure_ascii=False))
    resposta = chamar_claude(prompt)
    criados = rascunhos = descartados = 0
    for bruto in resposta.get("itens", []):
        it = validar(bruto, lote, clientes)
        if not it:
            descartados += 1
            continue
        ev = lote[it["ids"][0]]
        desc = (it["descricao"] or "") + (f"\n\nEvidências: {', '.join(map(str, it['ids']))}" if len(it["ids"]) > 1 else "")
        cur = con.execute("INSERT OR IGNORE INTO itens(ambiente,cliente,evidencia_id,tipo,titulo,descricao,prazo,"
                          "responsavel,prioridade,confianca) VALUES(?,?,?,?,?,?,?,?,?,?)",
                          (amb, it["cliente"], ev["id"], it["tipo"], it["titulo"], desc.strip(), it["prazo"],
                           it["responsavel"], it["prioridade"], it["confianca"]))
        if not cur.rowcount:
            continue
        criados += 1
        if it["resposta"]:
            destino = ev["grupo_ou_assunto"] if ev["origem"] in ("whatsapp", "reuniao") else ev["remetente"]
            con.execute("INSERT INTO rascunhos(ambiente,item_id,canal,destino,texto) VALUES(?,?,?,?,?)",
                        (amb, cur.lastrowid, "whatsapp" if ev["origem"] == "whatsapp" else "email", destino or "?", it["resposta"]))
            rascunhos += 1
    con.execute(f"UPDATE evidencias SET processado_em=? WHERE id IN ({','.join('?' * len(lote))})",
                (dt.datetime.now(TZ).isoformat(timespec="seconds"), *lote))
    con.commit()
    return {"lidas": len(lote), "itens": criados, "rascunhos": rascunhos, "descartados": descartados}


if __name__ == "__main__":
    hoje = dt.datetime.now(TZ).date()
    resumo, erros = {}, []
    for amb in AMB:
        for _ in range(MAX_LOTES):
            try:
                r = processar(amb, hoje)
            except Exception as e:  # lote fica sem processado_em e volta na próxima rodada
                erros.append(f"{amb}: {e}")
                break
            if not r:
                break
            s = resumo.setdefault(amb, {k: 0 for k in r})
            for k, v in r.items():
                s[k] += v
    con.execute("INSERT INTO auditoria(ator,acao,detalhe) VALUES('classificar.py','classificacao',?)",
                (json.dumps({"resumo": resumo, "erros": erros}, ensure_ascii=False),))
    con.commit()
    print(json.dumps({"resumo": resumo, "erros": erros}, ensure_ascii=False))
    sys.exit(1 if erros and not resumo else 0)
