# cadastro/ — seus dados (fora do Git)

O instalador copia esta pasta para `cadastro/` e preenche com você. `cadastro/` está no `.gitignore`.

- `config.json` — ambientes (ex.: trabalho, segunda empresa, pessoal), e-mail de cada um, cor, clientes e termos de busca (o cliente de uma reunião é achado pelo título), filtros de e-mail e o que está ligado (reuniões, briefing, WhatsApp).
- `whatsapp_autorizados.json` — os ÚNICOS grupos de WhatsApp que o Prumo lê, por ambiente.
- `<ambiente>/<cliente>.md` ou `<ambiente>.md` — contexto em texto para o Claude.
- `env.sh` — gerado pelo instalador (PATH para as rodadas automáticas acharem o `claude`).
