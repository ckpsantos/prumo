---
name: instalar-prumo
description: Instala e configura o Prumo (assistente pessoal de rotina para macOS) para o usuário — entrevista ambientes/clientes, guia o Google Cloud e os logins só-leitura, WhatsApp opcional, compila o app e prepara as rodadas automáticas. Usar quando o usuário pedir para instalar, configurar ou "montar o Prumo", ou rodar /instalar-prumo.
---

# Instalar o Prumo

Você vai montar o Prumo **do usuário** nesta pasta (o repositório clonado). Fale em português, um passo por vez, e confirme cada etapa antes de seguir. Leia o `README.md` antes de começar.

## Regras (não negocie)
- **Só leitura.** Todo login do Google pede apenas `gmail.readonly`, `calendar.readonly` e (se houver reuniões) `documents.readonly`. Nunca peça escopo de envio/edição.
- **Nada é enviado** a ninguém: o Prumo só sugere rascunhos. Não crie integração que envie.
- **Segredos:** nunca mostre no chat o conteúdo de `credentials.json`, tokens ou chaves. Não digite senha do usuário em lugar nenhum — o login é sempre ele, no navegador.
- **Persistência é do usuário:** você NÃO instala nada em `~/Library/LaunchAgents`. Gere o arquivo (`./instalar.sh agenda`) e peça para o usuário colar o comando com `!` na frente.
- **Dados pessoais ficam em `cadastro/`** (no `.gitignore`). Nunca faça commit de `cadastro/`, `db/*.db`, `midia/` ou `.mcp.json`.
- Não invente dado de cliente: se não souber, marque ❓ no cadastro.

## Passo 1 — Pré-requisitos
Rode `./instalar.sh verificar`. Para cada ❌, mostre o comando de instalação e espere o usuário instalar (ou rode você mesmo se for `brew install …` e ele concordar). Depois `./instalar.sh preparar`.

## Passo 2 — Entrevista (preencha `cadastro/config.json`)
Pergunte, de preferência com perguntas de múltipla escolha:
1. Nome do usuário (como ele quer ser chamado nas sugestões).
2. **Ambientes** — quais frentes da vida ele quer separar (ex.: "Agência", "Minha empresa", "Pessoal"). Para cada um: id curto (sem espaço), nome, cor (sugira), e-mail Google daquele ambiente, se lê a caixa **inteira** ou só a **Principal**, se quer ler **reuniões** (anotações do Gemini no Google Meet) e **briefing** antes de reunião com cliente.
3. **Clientes** de cada ambiente: id, nome e termos de busca (como o cliente aparece no título das reuniões).
4. Remetentes de e-mail que são puro ruído (opcional).
5. Se usa blocos "espelho" na agenda (ex.: "Ocupado") que não devem contar como conflito → `agenda_espelho` (regex).
Crie também um `cadastro/<ambiente>/<cliente>.md` por cliente com o que ele contar (modelo em `cadastro.exemplo/trabalho/`). Isolamento: dados de um ambiente nunca vão para o arquivo de outro.

## Passo 3 — Google (um ambiente por vez)
Para cada conta Google é preciso um cliente OAuth "App para computador". Guie o usuário no navegador (ele clica; você explica):
1. https://console.cloud.google.com/projectcreate — criar projeto (ex.: `prumo-<ambiente>`). Conta Google Workspace da empresa pode usar um projeto da própria empresa.
2. Ativar **Gmail API**, **Google Calendar API** e, se tiver reuniões, **Google Docs API** (se o `gcloud` estiver logado na mesma conta, você pode ativar com `gcloud services enable gmail.googleapis.com calendar-json.googleapis.com docs.googleapis.com --project <id>`).
3. **Google Auth Platform → Primeiros passos**: nome do app "Prumo", e-mail de suporte, público **Externo** (ou **Interno** se for Workspace e só ele usar).
4. **Público → Usuários de teste → Add users**: o e-mail dele (CONFIRA que salvou — sem isso o login dá 403 access_denied). Avise: em modo teste o Google derruba o login a cada 7 dias (é só repetir este passo 5 depois). Publicar ("Em produção") evita isso, mas exige página inicial e política de privacidade públicas.
5. **Clientes → Criar cliente → App para computador** → baixar o JSON e salvar no caminho `credenciais` do ambiente no `config.json` (ex.: `~/.config/prumo/google/<amb>/credentials.json`, `chmod 600`). Se ele não conseguir mexer na pasta, peça para salvar em um lugar que você leia e mova você.
6. `./instalar.sh google <ambiente>` abre o login (só leitura). O teste no fim confere se a conta logada é a do cadastro — se não for, refaça com a conta certa.
Depois de todos: `./instalar.sh mcp`.

## Passo 4 — WhatsApp (opcional)
Usa a ponte não oficial [whatsapp-mcp-plus](https://github.com/AllissonOliveira/whatsapp-mcp-plus) (WhatsApp Web, whatsmeow). **Avise o risco**: não é API oficial; o WhatsApp pode desconectar a sessão ou restringir a conta. Se ele quiser:
1. Clonar a ponte (ex.: em `~/.claude/whatsapp-mcp-plus`) e compilar com Go conforme o README dela (`go build` pode precisar ser rodado pelo usuário com `!`).
2. Rodar o binário numa janela do Terminal para mostrar o QR nativo e o usuário ler no celular (Aparelhos conectados). Espere o histórico parar de crescer.
3. Para um 2º número, aplique `conectores/whatsapp/multinumero.patch` numa cópia da ponte e rode com `BRIDGE_STORE_DIR` e `BRIDGE_PORT` próprios.
4. Ponha o caminho da pasta `store` em `whatsapp_store` do ambiente, liste os grupos (`sqlite3 "file:<store>/messages.db?mode=ro" "select jid,name from chats where jid like '%@g.us' order by last_message_time desc"`), proponha qual grupo é de qual cliente e grave **só os que ele autorizar** em `cadastro/whatsapp_autorizados.json`.
5. Manter a ponte ligada (launchd com KeepAlive) é persistência: gere o plist e peça para ele rodar o `launchctl bootstrap` com `!`.

## Passo 5 — Métricas no briefing (opcional)
Se ele já tiver MCPs de Google Ads/GA4 configurados com wrapper `.sh`, aponte os caminhos em `metricas_mcp`. Sem isso, o briefing sai sem números (e diz isso).

## Passo 6 — App e primeira rodada
1. `./instalar.sh app` (compila e abre `/Applications/Prumo.app`).
2. Primeira coleta: `MANUAL=1 ./rodada.sh` (ou o botão "Verificar agora"). Mostre quantos itens entraram e peça para ele conferir alguns cards.
3. `./instalar.sh agenda` e peça para ele rodar o comando mostrado (com `!`). Explique: seg–sex 07h (resumo do dia) e de hora em hora até 19h.

## Fim
Resuma o que ficou ligado (ambientes, contas, WhatsApp, métricas), o que ficou de fora e as datas de vencimento (login em modo teste: 7 dias). Lembre que `cadastro/` é dele e não vai para o Git.
