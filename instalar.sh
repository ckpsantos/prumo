#!/bin/bash
# Instalador do Prumo (macOS). Normalmente quem roda é o Claude Code, pela skill /instalar-prumo.
# Uso: ./instalar.sh verificar | preparar | google <ambiente> | mcp | app | agenda | testar
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")" && pwd)"
cd "$RAIZ"
ok() { printf "  ✅ %s\n" "$1"; }
falta() { printf "  ❌ %s — %s\n" "$1" "$2"; FALTOU=1; }
cfg() { /usr/bin/python3 -c "import json,sys;c=json.load(open('cadastro/config.json'));print(eval(sys.argv[1]))" "$1"; }

case "${1:-}" in
verificar)
  FALTOU=0
  echo "Pré-requisitos:"
  v=$(sw_vers -productVersion | cut -d. -f1); [ "$v" -ge 15 ] && ok "macOS $v" || falta "macOS 15+" "atualize o sistema"
  command -v swift >/dev/null && ok "swift" || falta "swift" "xcode-select --install"
  command -v brew >/dev/null && ok "Homebrew" || falta "Homebrew" "https://brew.sh"
  command -v claude >/dev/null && ok "Claude Code ($(command -v claude))" || falta "Claude Code" "https://claude.com/claude-code"
  command -v uv >/dev/null && ok "uv (transcrição de áudio)" || falta "uv" "brew install uv"
  command -v google-mcp >/dev/null && ok "google-mcp" || falta "google-mcp" "brew install greatliontech/tap/google-mcp"
  /usr/bin/python3 -c "import cryptography" 2>/dev/null && ok "python3 + cryptography" || falta "cryptography" "/usr/bin/python3 -m pip install --user cryptography"
  command -v go >/dev/null && ok "go (opcional, ponte do WhatsApp)" || echo "  ➖ go (opcional, só para o WhatsApp) — brew install go"
  [ "$FALTOU" = 0 ] && echo "Tudo certo." || { echo "Instale o que falta e rode de novo."; exit 1; }
  ;;
preparar)
  [ -d cadastro ] || { cp -R cadastro.exemplo cadastro; echo "Criei cadastro/ a partir do exemplo — edite cadastro/config.json."; }
  mkdir -p midia
  printf '# Gerado por instalar.sh: o launchd não carrega o perfil do shell\nexport PATH="%s:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"\n' \
    "$(dirname "$(command -v claude)")" > cadastro/env.sh
  mkdir -p "$HOME/.config/prumo" && echo "$RAIZ" > "$HOME/.config/prumo/raiz"
  /usr/bin/python3 db/init.py --teste && /usr/bin/python3 db/init.py
  echo "Pronto: banco criado e o app sabe onde o Prumo está (~/.config/prumo/raiz)."
  ;;
google)
  AMB="${2:?uso: ./instalar.sh google <ambiente>}"
  TOK="$(cfg "c['ambientes']['$AMB'].get('google_tokens','~/.config/prumo/google/$AMB')")"; TOK="${TOK/#\~/$HOME}"
  CRED="$(cfg "c['ambientes']['$AMB']['credenciais']")"; CRED="${CRED/#\~/$HOME}"
  [ -f "$CRED" ] || { echo "Falta o arquivo do cliente OAuth em $CRED (ver README, passo Google Cloud)."; exit 1; }
  ESC="https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/calendar.readonly"
  [ "$(cfg "c['ambientes']['$AMB'].get('reunioes', False)")" = "True" ] && ESC="$ESC,https://www.googleapis.com/auth/documents.readonly"
  mkdir -p "$TOK" && chmod 700 "$TOK"
  echo "Abrindo o login do Google para '$AMB' (só leitura: $ESC)…"
  google-mcp auth add "$AMB" --config-dir "$TOK" --credentials "$CRED" --scopes "$ESC"
  /usr/bin/python3 conectores/testar_google.py "$AMB"
  ;;
mcp)
  /usr/bin/python3 - <<'PY'
import json, os
c = json.load(open("cadastro/config.json"))
x = lambda p: os.path.expanduser(p)
s = {}
for a, v in c["ambientes"].items():
    for svc in ("gmail", "calendar"):
        s[f"{svc}-{a}"] = {"command": "google-mcp", "args": [svc, "--read-only", "--config-dir",
                           x(v.get("google_tokens", f"~/.config/prumo/google/{a}")), "--credentials", x(v["credenciais"])]}
json.dump({"mcpServers": s}, open(".mcp.json", "w"), indent=2)
print(f".mcp.json com {len(s)} conectores só-leitura")
PY
  ;;
app)
  (cd app && ./build.sh --instalar) && open /Applications/Prumo.app
  ;;
agenda)
  ROT="$HOME/Library/LaunchAgents/io.github.prumo.rodada.plist"
  /usr/bin/python3 - "$RAIZ" <<'PY'
import plistlib, sys, os
raiz = sys.argv[1]
log = os.path.expanduser("~/Library/Logs/prumo.log")
plistlib.dump({"Label": "io.github.prumo.rodada", "ProgramArguments": ["/bin/bash", f"{raiz}/rodada.sh"],
               "StartCalendarInterval": [{"Weekday": d, "Hour": h, "Minute": 0} for d in range(1, 6) for h in range(7, 20)],
               "StandardOutPath": log, "StandardErrorPath": log}, open(f"{raiz}/prumo.plist", "wb"))
PY
  echo "Gerei prumo.plist (seg–sex, 07h e de hora em hora até 19h)."
  echo "Para ligar as rodadas automáticas, rode VOCÊ mesmo (no Claude Code, com ! na frente):"
  echo "  cp \"$RAIZ/prumo.plist\" \"$ROT\" && launchctl bootstrap gui/\$(id -u) \"$ROT\""
  ;;
testar)
  /usr/bin/python3 db/init.py --teste
  for a in $(cfg "' '.join(c['ambientes'])"); do /usr/bin/python3 conectores/testar_google.py "$a" || true; done
  ;;
*)
  sed -n '2,3p' "$0"; exit 1 ;;
esac
