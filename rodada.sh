#!/bin/bash
# Rodada do Prumo: coleta (Gmail, Agenda, reuniões, WhatsApp) → classifica por ambiente → briefings → atualiza o app.
# Às 07h também manda o resumo do dia (resumo_dia.py).
# Agendada pelo launchd (plist gerado por instalar.sh) seg–sex 07h e de hora em hora até 19h; o app chama com MANUAL=1.
BASE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
[ -f "$BASE/cadastro/env.sh" ] && . "$BASE/cadastro/env.sh"  # PATH do claude, gerado pelo instalador
LOCK="$BASE/.rodando"
EST="$BASE/estado_rodada.json"
exec >> "$HOME/Library/Logs/prumo.log" 2>&1

estado() {  # status mensagem
  /usr/bin/python3 - "$EST" "$1" "$2" "$INICIO" <<'PY'
import json, sys, sqlite3, datetime as dt
est, status, msg, ini = sys.argv[1:5]
novos = 0
if status != "rodando":
    con = sqlite3.connect(sys.argv[1].rsplit("/", 1)[0] + "/db/assistente.db")
    novos = con.execute("SELECT count(*) FROM itens WHERE criado_em >= datetime(?, 'utc')", (ini,)).fetchone()[0]
json.dump({"status": status, "inicio": ini, "mensagem": msg, "novos_itens": novos,
           "fim": None if status == "rodando" else dt.datetime.now().astimezone().isoformat(timespec="seconds")},
          open(est, "w"), ensure_ascii=False)
PY
}

INICIO="$(date '+%Y-%m-%dT%H:%M:%S')"
echo "===== $(date '+%d/%m/%Y %H:%M') rodada ${MANUAL:+manual}"
mkdir "$LOCK" 2>/dev/null || { echo "outra rodada em andamento, saindo"; exit 0; }
trap 'rmdir "$LOCK"' EXIT

estado rodando "Coletando e-mails, agenda e WhatsApp"
COL=$(/usr/bin/python3 "$BASE/coletar.py" | tail -1); C1=$?
echo "coletar: $COL"

if [ "$(date +%H)" = "07" ]; then /usr/bin/python3 "$BASE/resumo_dia.py"; fi

estado rodando "Classificando com o Claude"
CLA=$(/usr/bin/python3 "$BASE/classificar.py" | tail -1); C2=$?
echo "classificar: $CLA"

estado rodando "Preparando briefings das próximas reuniões"
BRI=$(/usr/bin/python3 "$BASE/briefing.py" | tail -1)
echo "briefing: $BRI"
NB=$(/usr/bin/python3 -c "import json,sys;print(len(json.loads(sys.argv[1]).get('briefings',[])))" "$BRI" 2>/dev/null || echo 0)
[ "$NB" != "0" ] && osascript -e "display notification \"$NB briefing(s) de reunião prontos\" with title \"Prumo\""

ERROS=$(/usr/bin/python3 -c "import json,sys;e=sum((json.loads(l).get('erros',[]) for l in sys.argv[1:] if l.startswith('{')),[]);print('; '.join(e))" "$COL" "$CLA" "$BRI")
if [ -n "$ERROS" ]; then
  estado falha "Concluída com avisos: $ERROS"
  osascript -e "display notification \"Rodada com avisos — abra o Prumo\" with title \"Prumo\""
else
  estado ok "Concluída"
  N=$(/usr/bin/python3 -c "import json;print(json.load(open('$EST'))['novos_itens'])")
  [ "$N" != "0" ] && osascript -e "display notification \"$N itens novos na Entrada\" with title \"Prumo\""
fi
