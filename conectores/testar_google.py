"""Testa o acesso só-leitura de Gmail + Agenda de um ambiente.
Uso: python3 -I conectores/testar_google.py <ambiente>   (ids em cadastro/config.json)
Confere: conta logada = e-mail do cadastro, escopos só de leitura, Gmail e Agenda respondendo.
"""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from google import token, get

RAIZ = Path(__file__).resolve().parent.parent


amb = sys.argv[1]
from prumo import AMB
esperado = AMB[amb]["email"].lower()
t = token(amb)  # já recusa escopo além de leitura
escopos = set(t["scope"].split())
tok = t["access_token"]

perfil = get("https://gmail.googleapis.com/gmail/v1/users/me/profile", tok)
email = perfil.get("emailAddress", "").lower()
print("Gmail:", perfil if "ERRO" in perfil else f"{email} · {perfil['messagesTotal']} mensagens")
if email and email != esperado:
    sys.exit(f"PARAR: conta logada {email} ≠ cadastro {esperado}. Refazer o login com a conta certa.")

cals = get("https://www.googleapis.com/calendar/v3/users/me/calendarList", tok)
if "ERRO" in cals:
    print("Agenda:", cals)
else:
    for c in cals.get("items", []):
        print(f"Agenda: {c['summary'][:40]:40} id={c['id'][:45]:45} acesso={c['accessRole']}"
              + (" ← PRINCIPAL" if c.get("primary") else ""))
    dono = next((c["id"].lower() for c in cals.get("items", []) if c.get("primary")), "")
    if dono and dono != esperado:
        sys.exit(f"PARAR: agenda principal é de {dono} ≠ cadastro {esperado}. Refazer o login com a conta certa.")
print("Escopos:", sorted(s.rsplit('/', 1)[-1] for s in escopos))
