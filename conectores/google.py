"""Acesso só-leitura ao Google (Gmail, Agenda, Docs) por ambiente. Credencial e tokens vêm de cadastro/config.json."""
import json, sys, urllib.request, urllib.parse, urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from prumo import AMB, caminho


def _tokens(amb):
    return caminho(AMB[amb].get("google_tokens", f"~/.config/prumo/google/{amb}")) / "tokens.json"

SO_LEITURA = {"https://www.googleapis.com/auth/gmail.readonly",
              "https://www.googleapis.com/auth/calendar.readonly",
              "https://www.googleapis.com/auth/documents.readonly"}  # anotações/transcrições do Gemini


def token(amb):
    """Troca o refresh token por um access token. Recusa se o escopo passar de leitura."""
    c = json.load(open(caminho(AMB[amb]["credenciais"])))["installed"]  # cliente OAuth "App para computador"
    t = json.load(open(_tokens(amb)))
    rt = t["accounts"][amb]["token"]["refresh_token"]
    r = json.loads(urllib.request.urlopen(c["token_uri"], urllib.parse.urlencode({
        "client_id": c["client_id"], "client_secret": c["client_secret"],
        "refresh_token": rt, "grant_type": "refresh_token"}).encode(), timeout=30).read())
    escopos = set(r.get("scope", "").split())
    if not escopos <= SO_LEITURA:
        raise PermissionError(f"escopo além de leitura em {amb}: {escopos - SO_LEITURA}")
    return r


def get(url, tok):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=60).read())
    except urllib.error.HTTPError as e:
        return {"ERRO": e.code, "msg": json.loads(e.read() or b"{}").get("error", {}).get("message", "")[:200]}
