"""Cria docs/demo/demo.db: banco FICTÍCIO para conhecer o Prumo e gerar screenshots.

Uso: python3 docs/demo/criar_demo.py
Abrir o app com ele: ASSISTENTE_DB=docs/demo/demo.db /Applications/Prumo.app/Contents/MacOS/Assistente

Tudo aqui é inventado (empresas, pessoas, números). Datas são relativas ao dia em que o script roda.
"""
import datetime as dt
import sqlite3
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
DB = Path(__file__).resolve().parent / "demo.db"

hoje = dt.date.today()
dia = lambda n: (hoje + dt.timedelta(days=n)).isoformat()
hora = lambda n, hm: f"{dia(n)}T{hm}:00-03:00"
utc = lambda dias=0, horas=0: (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=dias, hours=horas)).strftime("%Y-%m-%d %H:%M:%S")

AMBIENTES = [("agencia", "Agência", "#E5484D", 0), ("estudio", "Estúdio", "#F5A524", 1), ("pessoal", "Pessoal", "#30A46C", 2)]
CLIENTES = [
    ("agencia", "padaria-aurora", "Padaria Aurora"), ("agencia", "clinica-vida-plena", "Clínica Vida Plena"),
    ("agencia", "loja-horizonte", "Loja Horizonte"), ("estudio", "cafe-ponto-alto", "Café Ponto Alto"),
    ("estudio", "estudio", "Estúdio"), ("pessoal", "pessoal", "Pessoal"),
]

BRIEFING = """# Briefing — Check-in mensal | Padaria Aurora

## O que ficou da última reunião
- Aprovado o calendário de posts de novembro (3 por semana).
- **Decisão:** testar anúncio de encomendas de Natal a partir do dia 10.
- Ficou pendente a foto nova da vitrine (com a Marina).

## Pendências abertas
- **Do nosso lado**
  - Atrasada: relatório de outubro (prazo era ontem).
  - Ajustar a página de encomendas para celular.
  - Preparar 2 opções de criativo para o Natal.
- **Do cliente**
  - Enviar a tabela de preços das cestas de Natal.
  - Confirmar o horário estendido de dezembro.

## O que rolou no grupo (7 dias)
- Marina perguntou se dá para impulsionar o post do pão de fermentação natural.
- Rafael avisou que o forno novo chega na próxima semana e quer divulgar.
- O cliente elogiou o vídeo curto da semana passada.

## Números da semana
- **Período:** últimos 7 dias vs. 7 dias anteriores
- **Anúncios de busca**
  - **Investimento:** R$ 1.240,00 (antes R$ 1.180,00, +5,1%)
  - **Cliques:** 860 (antes 790, +8,9%)
  - **Pedidos pelo site:** 42 (antes 35, +20,0%)
- **Redes sociais**
  - **Alcance:** 18.400 (antes 15.900, +15,7%)
  - **Mensagens no WhatsApp:** 61 (antes 48, +27,1%)

## Pauta sugerida
- Mostrar o crescimento de pedidos e o que puxou o resultado.
- Fechar a data de início da campanha de Natal.
- Pedir a tabela de preços das cestas | prazo sugerido: sexta.
"""


def criar():
    DB.unlink(missing_ok=True)
    con = sqlite3.connect(DB)
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript((RAIZ / "db/schema.sql").read_text())
    con.executemany("INSERT INTO ambientes(id, nome, cor, ordem) VALUES (?,?,?,?)", AMBIENTES)
    con.executemany("INSERT INTO clientes(ambiente, id, nome) VALUES (?,?,?)", CLIENTES)

    def ev(amb, origem, oid, cli, titulo, remetente, quando, conteudo, link=None):
        return con.execute(
            "INSERT INTO evidencias(ambiente, origem, origem_id, cliente, titulo, remetente, quando, link, conteudo) "
            "VALUES (?,?,?,?,?,?,?,?,?)", (amb, origem, oid, cli, titulo, remetente, quando, link, conteudo)).lastrowid

    def it(amb, cli, e, tipo, titulo, coluna, prazo=None, conf="alta", desc=None, resp=None, criado=None):
        return con.execute(
            "INSERT INTO itens(ambiente, cliente, evidencia_id, tipo, titulo, descricao, prazo, responsavel, confianca, coluna, criado_em) "
            "VALUES (?,?,?,?,?,?,?,?,?,?, coalesce(?, datetime('now')))",
            (amb, cli, e, tipo, titulo, desc, prazo, resp, conf, coluna, criado)).lastrowid

    # Agenda de hoje (3 ambientes) + amanhã
    a_aurora = ev("agencia", "agenda", "ag-1", "padaria-aurora", "Check-in mensal — Padaria Aurora", None, hora(0, "10:00"),
                  "Reunião de acompanhamento com o cliente.")
    a_clinica = ev("agencia", "agenda", "ag-2", "clinica-vida-plena", "Alinhamento de campanha — Clínica Vida Plena", None,
                   hora(0, "14:30"), "Revisão dos anúncios de consultas.")
    ev("estudio", "agenda", "ag-3", None, "Planejamento da semana", None, hora(0, "09:00"), "Ritual semanal do estúdio.")
    ev("pessoal", "agenda", "ag-4", None, "Consulta no dentista", None, hora(0, "14:00"), "Ocupado.")
    ev("pessoal", "agenda", "ag-5", None, "Aniversário da Júlia", None, dia(0), "Dia todo.")
    ev("agencia", "agenda", "ag-6", "loja-horizonte", "Apresentação de resultados — Loja Horizonte", None, hora(1, "11:00"), "")
    con.execute("INSERT INTO briefings(ambiente, cliente, evidencia_id, inicio, titulo, conteudo) VALUES (?,?,?,?,?,?)",
                ("agencia", "padaria-aurora", a_aurora, hora(0, "10:00"), "Briefing — Check-in mensal | Padaria Aurora", BRIEFING))

    w1 = ev("agencia", "whatsapp", "wa-1", "padaria-aurora", "Padaria Aurora • Marketing", "Marina", hora(0, "08:12"),
            "Bom dia! Consegue me mandar até amanhã o relatório de outubro? Quero mostrar para o sócio.")
    w2 = ev("agencia", "whatsapp", "wa-2", "loja-horizonte", "Loja Horizonte • Equipe", "Paulo", hora(-1, "17:40"),
            "As vendas da coleção nova caíram essa semana. Dá para ver o que aconteceu nos anúncios?")
    w3 = ev("estudio", "whatsapp", "wa-3", "cafe-ponto-alto", "Café Ponto Alto", "Bianca", hora(-4, "10:05"),
            "Vamos gravar o vídeo do cardápio de inverno? Pode ser semana que vem.")
    e1 = ev("agencia", "email", "em-1", None, "Proposta de parceria — feira de negócios", "contato@feira-exemplo.com",
            hora(-1, "15:20"), "Olá! Gostaríamos de apresentar o espaço de expositores da feira regional de março.",
            "https://mail.google.com/")
    e2 = ev("agencia", "email", "em-2", "clinica-vida-plena", "Ajuste no texto do anúncio", "Dra. Helena (Clínica Vida Plena)",
            hora(0, "07:50"), "Precisamos trocar 'agende já' por 'agende sua avaliação'. Pode ajustar hoje?",
            "https://mail.google.com/")
    e3 = ev("pessoal", "email", "em-3", None, "Fatura do cartão disponível", "banco@exemplo.com", hora(-2, "09:00"),
            "Sua fatura vence em 5 dias.")
    r1 = ev("agencia", "reuniao", "re-1", "loja-horizonte", "Anotações — Reunião Loja Horizonte", None, hora(-2, "16:00"),
            "Decidido: pausar a campanha de liquidação e criar uma nova com foco na coleção de verão. "
            "Paulo vai enviar as fotos até sexta.")
    s1 = ev("estudio", "whatsapp", "wa-4", "estudio", "Estúdio • Time", "Caio", hora(-1, "18:30"),
            "Alguém consegue revisar o roteiro do episódio 12 antes de quinta?")

    i_rel = it("agencia", "padaria-aurora", w1, "acao", "Enviar relatório de outubro para a Padaria Aurora", "a_fazer",
               dia(1), desc="Cliente quer mostrar ao sócio. Incluir pedidos pelo site e alcance.", resp="Você")
    it("agencia", "padaria-aurora", a_aurora, "acao", "Atualizar página de encomendas para celular", "a_fazer", dia(-1),
       desc="Pendência da última reunião, prazo vencido.")
    i_clin = it("agencia", "clinica-vida-plena", e2, "acao", "Trocar chamada do anúncio da Clínica Vida Plena", "entrada", dia(0),
                desc="Trocar 'agende já' por 'agende sua avaliação' em todos os anúncios ativos.", resp="Você")
    it("agencia", "loja-horizonte", w2, "acao", "Investigar queda de vendas da coleção nova", "entrada", dia(2),
       desc="Comparar investimento, cliques e conversões das últimas 2 semanas.")
    it("agencia", "loja-horizonte", r1, "acompanhamento", "Receber fotos da coleção de verão (Paulo)", "aguardando", dia(3),
       resp="Paulo", criado=utc(5))
    it("agencia", "loja-horizonte", r1, "acao", "Pausar campanha de liquidação", "concluido", dia(-2))
    it("agencia", None, e1, "sugestao", "Avaliar proposta de expositor na feira regional", "entrada", conf="baixa",
       desc="Pode não ser prioridade; decidir se responde.")
    it("agencia", "clinica-vida-plena", a_clinica, "bloqueio", "Conflito 14:30: alinhamento × Outros (ocupado)", "entrada",
       dia(0), desc="O alinhamento com a Clínica Vida Plena cruza com um compromisso de outro ambiente.")
    it("estudio", "cafe-ponto-alto", w3, "acao", "Agendar gravação do vídeo do cardápio de inverno", "a_fazer", dia(4),
       criado=utc(4))
    it("estudio", "estudio", s1, "acao", "Revisar roteiro do episódio 12", "entrada", dia(1), conf="media")
    it("estudio", "cafe-ponto-alto", w3, "sugestao", "Propor série de vídeos curtos para o café", "entrada", conf="baixa")
    it("estudio", "estudio", s1, "acompanhamento", "Aguardando trilha sonora do episódio 11", "aguardando", criado=utc(6))
    it("estudio", "cafe-ponto-alto", w3, "acao", "Atualizar fotos do cardápio no site", "cancelado")
    it("pessoal", "pessoal", e3, "acao", "Pagar fatura do cartão", "a_fazer", dia(5))
    it("pessoal", "pessoal", e3, "acao", "Renovar seguro do carro", "concluido", dia(-3))

    con.execute("INSERT INTO rascunhos(ambiente, item_id, canal, destino, texto) VALUES (?,?,?,?,?)",
                ("agencia", i_rel, "whatsapp", "Padaria Aurora • Marketing",
                 "Bom dia, Marina! Envio o relatório de outubro até amanhã de manhã, com pedidos pelo site e alcance."))
    con.execute("INSERT INTO rascunhos(ambiente, item_id, canal, destino, texto) VALUES (?,?,?,?,?)",
                ("agencia", i_clin, "email", "Dra. Helena (Clínica Vida Plena)",
                 "Olá, Dra. Helena! Ajusto a chamada hoje mesmo em todos os anúncios ativos e te aviso quando estiver no ar."))
    con.execute("INSERT INTO comentarios(item_id, autor, texto, criado_em) VALUES (?,?,?,?)",
                (i_rel, "você", "Separar também o comparativo com setembro.", utc(0, 2)))
    con.execute("INSERT INTO comentarios(item_id, autor, texto, criado_em) VALUES (?,?,?,?)",
                (i_rel, "você", "Marina prefere PDF.", utc(0, 1)))
    con.commit()
    n = con.execute("SELECT count(*) FROM itens").fetchone()[0]
    con.close()
    return n


if __name__ == "__main__":
    n = criar()
    assert n >= 15, n
    print(f"demo.db criado com {n} itens em {DB}")
