"""Configuração do Prumo, lida de cadastro/config.json (fica só na máquina do usuário; ver cadastro.exemplo/)."""
import datetime as dt, json
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
CFG = json.load(open(RAIZ / "cadastro/config.json"))
AMB = CFG["ambientes"]
TZ = dt.timezone(dt.timedelta(hours=CFG.get("fuso_horas", -3)))
USUARIO = CFG.get("usuario", "você")


def caminho(p):
    return Path(p).expanduser() if p else None


def cliente_por_titulo(amb, texto):
    """Primeiro cliente do ambiente cujo termo de busca aparece no texto (título de reunião/evento)."""
    t = (texto or "").lower()
    return next((cid for cid, c in AMB[amb]["clientes"].items() if any(b in t for b in c.get("busca", []))), None)


def cadastro_md(amb, cliente=None):
    """Contexto em markdown: cadastro/<amb>/<cliente>.md, todos de cadastro/<amb>/, ou cadastro/<amb>.md."""
    pasta = RAIZ / "cadastro" / amb
    if cliente and (pasta / f"{cliente}.md").exists():
        return (pasta / f"{cliente}.md").read_text()
    if pasta.is_dir():
        return "\n\n".join(a.read_text() for a in sorted(pasta.glob("*.md")))
    arq = RAIZ / f"cadastro/{amb}.md"
    return arq.read_text() if arq.exists() else "(sem cadastro)"
