"""Coleta incremental: Gmail, Agenda e reuniões (Gemini) de cada ambiente + grupos autorizados do WhatsApp.
Grava em evidencias (reprocessar não duplica) e marca conflitos de agenda.
Uso: /usr/bin/python3 coletar.py   (precisa do pacote cryptography para áudio)
"""
import base64, datetime as dt, hashlib, hmac, json, re, sqlite3, subprocess, sys, urllib.parse, urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
sys.path.insert(0, str(RAIZ))
sys.path.insert(0, str(RAIZ / "conectores"))
from google import token, get
from prumo import AMB, CFG, TZ, USUARIO, caminho, cliente_por_titulo

AGORA = dt.datetime.now(TZ)
PRIMEIRA_JANELA = dt.timedelta(days=3)  # 1ª rodada de cada fonte olha só os últimos 3 dias
MIDIA = RAIZ / "midia"

con = sqlite3.connect(RAIZ / "db/assistente.db", timeout=30, isolation_level=None)  # autocommit: não segura o banco por minutos
con.execute("PRAGMA foreign_keys = ON")
novos = {}


def cursor(fonte, padrao):
    r = con.execute("SELECT valor FROM cursores WHERE fonte=?", (fonte,)).fetchone()
    return r[0] if r else padrao


def salvar_cursor(fonte, valor):
    con.execute("INSERT INTO cursores VALUES(?,?) ON CONFLICT(fonte) DO UPDATE SET valor=excluded.valor", (fonte, valor))


def inserir(amb, origem, oid, processado=False, **c):
    if origem == "agenda":  # evento muda de horário/título: atualiza em vez de ignorar
        con.execute("UPDATE evidencias SET titulo=?, remetente=?, quando=?, link=?, conteudo=?, removido_em=NULL"
                    " WHERE origem='agenda' AND origem_id=?",
                    (c.get("titulo"), c.get("remetente"), c.get("quando"), c.get("link"), c.get("conteudo"), oid))
    cur = con.execute(
        "INSERT OR IGNORE INTO evidencias(ambiente,origem,origem_id,cliente,titulo,remetente,quando,link,conteudo,processado_em)"
        " VALUES(?,?,?,?,?,?,?,?,?,?)",
        (amb, origem, oid, c.get("cliente"), c.get("titulo"), c.get("remetente"), c.get("quando"),
         c.get("link"), c.get("conteudo"), AGORA.isoformat(timespec="seconds") if processado else None))
    if cur.rowcount:
        novos[f"{origem}:{amb}"] = novos.get(f"{origem}:{amb}", 0) + 1
    return cur.lastrowid if cur.rowcount else con.execute(
        "SELECT id FROM evidencias WHERE origem=? AND origem_id=?", (origem, oid)).fetchone()[0]


# ---------- Gmail ----------
def texto_do_email(payload):
    """Primeiro text/plain do e-mail (ou text/html sem tags)."""
    partes, html = [payload], None
    while partes:
        p = partes.pop(0)
        partes += p.get("parts", [])
        dado = p.get("body", {}).get("data")
        if not dado:
            continue
        t = base64.urlsafe_b64decode(dado + "==").decode("utf-8", "replace")
        if p.get("mimeType") == "text/plain":
            return t
        if p.get("mimeType") == "text/html" and html is None:
            html = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", re.sub(r"(?is)<(style|script).*?</\1>", "", t)))
    return html or ""


# email_filtro por ambiente: "inteiro" = caixa toda menos ruido_email (o Claude descarta o irrelevante);
# "principal" = só a aba Principal do Gmail.
RUIDO = CFG.get("ruido_email", [])
FILTRO_INTEIRO = ("-from:(" + " OR ".join(RUIDO) + ")") if RUIDO else ""
FILTRO_PRINCIPAL = "-category:promotions -category:social -category:updates -category:forums"


def gmail(amb, tok):
    fonte = f"gmail:{amb}"
    desde = int(cursor(fonte, str(int((AGORA - PRIMEIRA_JANELA).timestamp()))))
    q = f"in:inbox after:{desde} " + (FILTRO_PRINCIPAL if AMB[amb].get("email_filtro") == "principal" else FILTRO_INTEIRO)
    ids, pagina = [], ""
    while len(ids) < 500:  # shortcut: teto de 500 e-mails por rodada; o resto entra na rodada seguinte
        r = get(f"https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=100&q={urllib.parse.quote(q)}{pagina}", tok)
        if "ERRO" in r:
            raise RuntimeError(f"Gmail {amb}: {r}")
        ids += [m["id"] for m in r.get("messages", [])]
        if not r.get("nextPageToken"):
            break
        pagina = f"&pageToken={r['nextPageToken']}"
    maior = desde
    for mid in ids:
        m = get(f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{mid}?format=full", tok)
        if "ERRO" in m:
            continue
        h = {x["name"].lower(): x["value"] for x in m["payload"].get("headers", [])}
        ts = int(m["internalDate"]) // 1000
        maior = max(maior, ts)
        inserir(amb, "email", f"{amb}:{mid}",
                titulo=h.get("subject", "(sem assunto)"), remetente=h.get("from", ""),
                quando=dt.datetime.fromtimestamp(ts, TZ).isoformat(timespec="seconds"),
                link=f"https://mail.google.com/mail/u/{AMB[amb]['email']}/#all/{m['threadId']}",
                conteudo=texto_do_email(m["payload"])[:6000] or m.get("snippet", ""))
    salvar_cursor(fonte, str(maior + 1))


# ---------- Agenda ----------
def agenda(amb, tok):
    """Eventos da agenda principal de hoje até +7 dias. Não passam pelo classificador."""
    ini = AGORA.replace(hour=0, minute=0, second=0, microsecond=0)
    p = urllib.parse.urlencode({"timeMin": ini.isoformat(), "timeMax": (ini + dt.timedelta(days=8)).isoformat(),
                                "singleEvents": "true", "orderBy": "startTime", "maxResults": 250})
    r = get(f"https://www.googleapis.com/calendar/v3/calendars/primary/events?{p}", tok)
    if "ERRO" in r:
        raise RuntimeError(f"Agenda {amb}: {r}")
    eventos, vistos = [], set()
    for e in r.get("items", []):
        vistos.add(f"{amb}:{e['id']}")
        eu = next((a for a in e.get("attendees", []) if a.get("self")), {})
        if e.get("status") == "cancelled" or eu.get("responseStatus") == "declined" or e.get("transparency") == "transparent":
            continue
        s, f = e["start"], e["end"]
        quem = ", ".join(a.get("displayName") or a["email"] for a in e.get("attendees", []) if not a.get("self"))[:500]
        ev = inserir(amb, "agenda", f"{amb}:{e['id']}", processado=True,
                     titulo=e.get("summary", "(sem título)"), remetente=e.get("organizer", {}).get("email", ""),
                     quando=s.get("dateTime") or s.get("date"), link=e.get("htmlLink"),
                     conteudo=f"Início: {s.get('dateTime') or s.get('date')}\nFim: {f.get('dateTime') or f.get('date')}\n"
                              f"Participantes: {quem}\n\n{(e.get('description') or '')[:3000]}")
        # dia inteiro, já passado ou bloco-espelho (config agenda_espelho, ex.: "Ocupado / Não disponível") não entra em conflito
        espelho = CFG.get("agenda_espelho") and re.search(CFG["agenda_espelho"], e.get("summary", ""), re.I)
        # bloco de 4h+ (ex.: "FOCO NO PROJETO") é reserva de tempo, não reunião
        longo = "dateTime" in s and dt.datetime.fromisoformat(f["dateTime"]) - dt.datetime.fromisoformat(s["dateTime"]) >= dt.timedelta(hours=4)
        if "dateTime" in s and not espelho and not longo and dt.datetime.fromisoformat(f["dateTime"]) > AGORA:
            eventos.append({"amb": amb, "ev": ev, "uid": e.get("iCalUID"), "titulo": e.get("summary", "(sem título)"),
                            "ini": dt.datetime.fromisoformat(s["dateTime"]), "fim": dt.datetime.fromisoformat(f["dateTime"])})
    # evento que estava na janela e sumiu (cancelado/recusado/movido): sai da tela Hoje
    for (eid, oid) in con.execute("SELECT id, origem_id FROM evidencias WHERE origem='agenda' AND ambiente=? AND removido_em IS NULL"
                                  " AND substr(quando,1,10) BETWEEN ? AND ?",
                                  (amb, f"{ini:%Y-%m-%d}", f"{ini + dt.timedelta(days=7):%Y-%m-%d}")).fetchall():
        if oid not in vistos:
            con.execute("UPDATE evidencias SET removido_em=? WHERE id=?", (AGORA.isoformat(timespec="seconds"), eid))
    return eventos


def conflitos(eventos):
    """Sobreposição entre quaisquer agendas. Do outro ambiente só aparece 'Outros (ocupado)'.
    Conflito antigo que não se repete nesta rodada (evento mudou/saiu) vai para Cancelado."""
    atuais = set()
    eventos.sort(key=lambda x: x["ini"])
    for i, a in enumerate(eventos):
        for b in eventos[i + 1:]:
            if b["ini"] >= a["fim"]:
                break
            if (a["uid"] and a["uid"] == b["uid"]) or a["titulo"].strip().lower() == b["titulo"].strip().lower():
                continue  # mesmo convite / mesmo compromisso copiado nas duas agendas
            for x, y in ((a, b), (b, a)) if a["amb"] != b["amb"] else ((a, b),):  # mesmo ambiente: 1 card só
                outro = y["titulo"] if x["amb"] == y["amb"] else "Outros (ocupado)"
                hora = f"{max(x['ini'], y['ini']).astimezone(TZ):%d/%m %H:%M}"
                atuais.add((x["ev"], f"Conflito de agenda {hora}: {x['titulo']} × {outro}"))
                con.execute("INSERT OR IGNORE INTO itens(ambiente,evidencia_id,tipo,titulo,descricao,prazo,confianca)"
                            " VALUES(?,?,'bloqueio',?,?,?,'alta')",
                            (x["amb"], x["ev"], f"Conflito de agenda {hora}: {x['titulo']} × {outro}",
                             f"'{x['titulo']}' ({x['ini'].astimezone(TZ):%H:%M}–{x['fim'].astimezone(TZ):%H:%M}) "
                             f"sobrepõe {outro} ({y['ini'].astimezone(TZ):%H:%M}–{y['fim'].astimezone(TZ):%H:%M}).",
                             f"{x['ini'].astimezone(TZ):%Y-%m-%d}"))
    for iid, ev, tit, amb in con.execute(
            "SELECT i.id, i.evidencia_id, i.titulo, i.ambiente FROM itens i JOIN evidencias e ON e.id=i.evidencia_id"
            " WHERE e.origem='agenda' AND i.tipo='bloqueio' AND i.coluna='entrada' AND i.prazo >= ?",
            (f"{AGORA:%Y-%m-%d}",)).fetchall():
        if (ev, tit) not in atuais:
            con.execute("UPDATE itens SET coluna='cancelado' WHERE id=?", (iid,))
            con.execute("INSERT INTO auditoria(ambiente,ator,acao,alvo,detalhe) VALUES(?,'coletar.py','mover',?,"
                        "'entrada → cancelado (conflito deixou de existir)')", (amb, f"item:{iid}"))


# ---------- Reuniões (anotações + transcrição do Gemini anexadas ao evento) ----------
def texto_doc(doc):
    """Todas as abas do Google Doc (Gemini põe Anotações e Transcrição em abas separadas)."""
    def corpo(b):
        return "".join(pe.get("textRun", {}).get("content", "")
                       for el in b.get("content", []) for pe in el.get("paragraph", {}).get("elements", []))
    abas = doc.get("tabs") or [{"tabProperties": {"title": ""}, "documentTab": {"body": doc.get("body", {})}}]
    return "\n\n".join(f"## {a['tabProperties'].get('title', '')}\n{corpo(a['documentTab']['body'])}" for a in abas)


def reunioes(amb, tok):
    """Eventos já encerrados com 'Anotações do Gemini' anexadas. 1ª rodada: últimos 14 dias."""
    fonte = f"reuniao:{amb}"
    desde = cursor(fonte, (AGORA - dt.timedelta(days=14)).isoformat(timespec="seconds"))
    p = urllib.parse.urlencode({"timeMin": desde, "timeMax": AGORA.isoformat(timespec="seconds"),
                                "singleEvents": "true", "orderBy": "startTime", "maxResults": 250})
    r = get(f"https://www.googleapis.com/calendar/v3/calendars/primary/events?{p}", tok)
    if "ERRO" in r:
        raise RuntimeError(f"Reuniões {amb}: {r}")
    for e in r.get("items", []):
        for a in e.get("attachments", []):
            if a.get("mimeType") != "application/vnd.google-apps.document" or "gemini" not in a.get("title", "").lower():
                continue
            d = get(f"https://docs.googleapis.com/v1/documents/{a['fileId']}?includeTabsContent=true", tok)
            if "ERRO" in d:
                if d["ERRO"] in (403, 404):
                    continue  # doc de outra pessoa sem acesso
                raise RuntimeError(f"Docs {amb}: {d}")
            titulo = e.get("summary", "(reunião)")
            cli = cliente_por_titulo(amb, titulo)
            inserir(amb, "reuniao", f"{amb}:{a['fileId']}", cliente=cli, titulo=f"{titulo} — {d.get('title', '')}"[:200],
                    remetente=e.get("organizer", {}).get("email", ""), quando=e["start"].get("dateTime") or e["start"].get("date"),
                    link=a.get("fileUrl"), conteudo=texto_doc(d)[:60000])
    salvar_cursor(fonte, AGORA.isoformat(timespec="seconds"))


# ---------- WhatsApp (ponte whatsmeow; só os grupos de cadastro/whatsapp_autorizados.json) ----------
INFO = {"image": b"WhatsApp Image Keys", "video": b"WhatsApp Video Keys",
        "audio": b"WhatsApp Audio Keys", "document": b"WhatsApp Document Keys"}


def baixar_audio(mid, url, key, sha):
    """Mídia do WhatsApp é criptografada: HKDF + AES-CBC + MAC (mesmo esquema do whatsmeow)."""
    from cryptography.hazmat.primitives import hashes, padding
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    dest = MIDIA / f"{mid}.ogg"
    if dest.exists():
        return dest
    enc = urllib.request.urlopen(url, timeout=600).read()
    k = HKDF(hashes.SHA256(), 112, None, INFO["audio"]).derive(key)
    iv, ck, mk = k[:16], k[16:48], k[48:80]
    body, mac = enc[:-10], enc[-10:]
    if hmac.new(mk, iv + body, hashlib.sha256).digest()[:10] != mac:
        raise ValueError("MAC inválido")
    d = Cipher(algorithms.AES(ck), modes.CBC(iv)).decryptor()
    raw = d.update(body) + d.finalize()
    u = padding.PKCS7(128).unpadder()
    raw = u.update(raw) + u.finalize()
    if sha and hashlib.sha256(raw).digest() != sha:
        raise ValueError("SHA256 não confere")
    MIDIA.mkdir(exist_ok=True)
    dest.write_bytes(raw)
    return dest


def whatsapp(amb, auth):
    store = caminho(AMB[amb]["whatsapp_store"])
    fonte = f"whatsapp:{amb}"
    desde = cursor(fonte, (AGORA - PRIMEIRA_JANELA).strftime("%Y-%m-%d %H:%M:%S") + AGORA.strftime("%z")[:3] + ":" + AGORA.strftime("%z")[3:])
    msgs = sqlite3.connect(f"file:{store}/messages.db?mode=ro", uri=True, timeout=60)
    nomes = sqlite3.connect(f"file:{store}/whatsapp.db?mode=ro", uri=True, timeout=60)
    q = ",".join("?" * len(auth))
    rows = msgs.execute(f"SELECT id, chat_jid, sender, content, timestamp, is_from_me, media_type, url, media_key, file_sha256"
                        f" FROM messages WHERE chat_jid IN ({q}) AND timestamp > ? ORDER BY timestamp",
                        (*auth, desde)).fetchall()

    def quem(sender):
        num = sender.split("@")[0]
        pn = nomes.execute("SELECT pn FROM whatsmeow_lid_map WHERE lid=?", (num,)).fetchone()
        pn = (pn[0] if pn else num).split("@")[0]
        c = nomes.execute("SELECT COALESCE(NULLIF(full_name,''), NULLIF(push_name,''), NULLIF(business_name,''))"
                          " FROM whatsmeow_contacts WHERE their_jid LIKE ? LIMIT 1", (pn + "@%",)).fetchone()
        return c[0] if c and c[0] else f"+{pn}"

    audios = {}
    for mid, chat, sender, texto, ts, eu, mtype, url, key, sha in rows:
        texto = texto or ""
        if mtype == "audio" and url and key:
            try:
                audios[mid] = baixar_audio(mid, url, key, sha)
            except Exception as e:  # mídia expirada: segue sem ela
                texto += f"\n[áudio não baixado: {e}]"
        elif mtype:
            texto = f"[{mtype}] {texto}".strip()
        inserir(amb, "whatsapp", f"{chat}:{mid}", cliente=auth[chat]["cliente"], titulo=auth[chat]["nome"],
                remetente=USUARIO if eu else quem(sender), quando=ts, conteudo=texto)
        desde = max(desde, ts)
    if audios:  # faster-whisper medium int8, mesmo script das Solicitações CEO
        saida = MIDIA / "transcricoes.json"
        subprocess.run(["uv", "run", "--with", "faster-whisper", "python",
                        str(RAIZ / "conectores/transcrever.py"), str(saida),
                        *map(str, audios.values())], check=False)
        tr = json.loads(saida.read_text()) if saida.exists() else {}
        for mid, arq in audios.items():
            t = tr.get(str(arq))
            con.execute("UPDATE evidencias SET conteudo = TRIM(COALESCE(conteudo,'') || ?) WHERE origem='whatsapp' AND origem_id LIKE ?",
                        (f"\n[áudio transcrito] {t}" if t else "\n[áudio sem transcrição]", f"%:{mid}"))
    salvar_cursor(fonte, desde)


if __name__ == "__main__":
    erros, eventos = [], []
    for amb in AMB:
        try:
            tok = token(amb)["access_token"]
            gmail(amb, tok)
            eventos += agenda(amb, tok)
            if AMB[amb].get("reunioes"):  # exige o escopo documents.readonly no login desse ambiente
                reunioes(amb, tok)
        except Exception as e:  # uma conta fora do ar não derruba as outras
            erros.append(f"{amb}: {e}")
        con.commit()
    conflitos(eventos)
    autorizados = json.load(open(RAIZ / "cadastro/whatsapp_autorizados.json")) if (RAIZ / "cadastro/whatsapp_autorizados.json").exists() else {}
    for amb in AMB:
        if AMB[amb].get("whatsapp_store") and autorizados.get(amb):
            try:
                whatsapp(amb, autorizados[amb])
            except Exception as e:
                erros.append(f"whatsapp {amb}: {e}")
    con.execute("INSERT INTO auditoria(ator,acao,detalhe) VALUES('coletar.py','coleta',?)",
                (json.dumps({"novos": novos, "erros": erros}, ensure_ascii=False),))
    con.commit()
    print(json.dumps({"novos": novos, "erros": erros}, ensure_ascii=False))
    sys.exit(1 if erros and not novos else 0)
