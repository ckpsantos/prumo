"""Cria/atualiza db/assistente.db a partir de schema.sql + cadastro/config.json.
Uso: python3 db/init.py          (cria e semeia)
     python3 db/init.py --teste  (roda o autoteste num banco em memória)
"""
import json, sqlite3, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent


def abrir(caminho, amb=None):
    """amb = dicionário de ambientes (padrão: cadastro/config.json). Nome/cor/ordem são atualizados a cada chamada."""
    con = sqlite3.connect(caminho)
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript((RAIZ / "db/schema.sql").read_text())
    if amb is None:
        amb = json.loads((RAIZ / "cadastro/config.json").read_text())["ambientes"]
    for ordem, (aid, a) in enumerate(amb.items()):
        con.execute("INSERT INTO ambientes(id,nome,cor,ordem) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET"
                    " nome=excluded.nome, cor=excluded.cor, ordem=excluded.ordem", (aid, a["nome"], a.get("cor"), ordem))
        for cid, c in a["clientes"].items():
            con.execute("INSERT INTO clientes(ambiente,id,nome) VALUES(?,?,?) ON CONFLICT(ambiente,id) DO UPDATE SET"
                        " nome=excluded.nome", (aid, cid, c.get("nome", cid)))
    con.commit()
    return con


def deve_falhar(con, sql, args=()):
    try:
        con.execute(sql, args)
    except sqlite3.DatabaseError:
        return
    raise AssertionError(f"deveria ter falhado: {sql}")


def autoteste():
    con = abrir(":memory:", {"trabalho": {"nome": "Trabalho", "clientes": {"cliente_a": {}}},
                             "empresa2": {"nome": "Empresa 2", "clientes": {"empresa2": {}}}})  # dados fictícios do teste
    ev = con.execute("INSERT INTO evidencias(ambiente,origem,origem_id) VALUES('trabalho','whatsapp','m1')").lastrowid
    # idempotência: mesma mensagem não entra duas vezes
    deve_falhar(con, "INSERT INTO evidencias(ambiente,origem,origem_id) VALUES('trabalho','whatsapp','m1')")
    con.execute("INSERT INTO itens(ambiente,cliente,evidencia_id,tipo,titulo) VALUES('trabalho','cliente_a',?,'acao','t')", (ev,))
    # isolamento: cliente de outro ambiente não pode entrar no item
    deve_falhar(con, "INSERT INTO itens(ambiente,cliente,evidencia_id,tipo,titulo) VALUES('trabalho','empresa2',?,'acao','x')", (ev,))
    # pendente de classificação é permitido
    con.execute("INSERT INTO itens(ambiente,cliente,evidencia_id,tipo,titulo) VALUES('trabalho',NULL,?,'sugestao','y')", (ev,))
    # envio só com aprovação
    r = con.execute("INSERT INTO rascunhos(ambiente,canal,destino,texto) VALUES('trabalho','whatsapp','g','oi')").lastrowid
    deve_falhar(con, "INSERT INTO rascunhos(ambiente,canal,destino,texto,status) VALUES('trabalho','email','d','x','enviado')")
    deve_falhar(con, "UPDATE rascunhos SET status='enviado' WHERE id=?", (r,))
    con.execute("UPDATE rascunhos SET status='aprovado', aprovado_em=datetime('now') WHERE id=?", (r,))
    # auditoria imutável
    a = con.execute("INSERT INTO auditoria(ator,acao) VALUES('claude','teste')").lastrowid
    deve_falhar(con, "UPDATE auditoria SET acao='x' WHERE id=?", (a,))
    deve_falhar(con, "DELETE FROM auditoria WHERE id=?", (a,))
    print("autoteste ok")


if __name__ == "__main__":
    if "--teste" in sys.argv:
        autoteste()
    else:
        con = abrir(RAIZ / "db/assistente.db")
        con.execute("INSERT INTO auditoria(ator,acao,detalhe) VALUES('init.py','banco criado/atualizado','schema + ambientes.json')")
        con.commit()
        n = con.execute("SELECT ambiente, count(*) FROM clientes GROUP BY 1").fetchall()
        print("banco ok:", dict(n))
