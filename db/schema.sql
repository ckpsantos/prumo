PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ambientes (
  id   TEXT PRIMARY KEY,          -- definido em cadastro/config.json (ex.: trabalho, empresa2, pessoal)
  nome TEXT NOT NULL,
  cor  TEXT,                      -- hex, ex.: #E70000
  ordem INTEGER
);

CREATE TABLE IF NOT EXISTS clientes (
  ambiente TEXT NOT NULL REFERENCES ambientes(id),
  id       TEXT NOT NULL,
  nome     TEXT,
  PRIMARY KEY (ambiente, id)
);

-- Tudo que entra (mensagem, e-mail, evento, documento). Reprocessar não duplica.
CREATE TABLE IF NOT EXISTS evidencias (
  id        INTEGER PRIMARY KEY,
  ambiente  TEXT NOT NULL REFERENCES ambientes(id),
  origem    TEXT NOT NULL,        -- whatsapp | email | agenda | documento | reuniao
  origem_id TEXT NOT NULL,        -- id da mensagem/e-mail/evento na fonte
  cliente   TEXT,                 -- pista vinda da fonte (ex.: grupo autorizado); NULL = classificador decide
  titulo    TEXT,                 -- grupo / assunto do e-mail / título do evento
  remetente TEXT,
  quando    TEXT,                 -- data/hora original (ISO, fuso de Brasília)
  link      TEXT,                 -- abre a fonte (Gmail, Agenda); WhatsApp não tem link
  conteudo  TEXT,
  processado_em TEXT,             -- quando o classificador leu
  removido_em   TEXT,             -- evento que saiu da agenda (cancelado/movido para fora da janela)
  criado_em TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (ambiente, cliente) REFERENCES clientes(ambiente, id),
  UNIQUE (origem, origem_id)
);

-- Cliente só pode ser do mesmo ambiente do item (FK composta = isolamento no banco).
-- cliente NULL = "pendente de classificação".
CREATE TABLE IF NOT EXISTS itens (
  id           INTEGER PRIMARY KEY,
  ambiente     TEXT NOT NULL,
  cliente      TEXT,
  evidencia_id INTEGER NOT NULL REFERENCES evidencias(id),
  tipo         TEXT NOT NULL CHECK (tipo IN ('acao','sugestao','bloqueio','acompanhamento')),
  titulo       TEXT NOT NULL,
  descricao    TEXT,
  prazo        TEXT,              -- só se comprovado na fonte
  responsavel  TEXT,
  prioridade   TEXT,
  confianca    TEXT CHECK (confianca IN ('alta','media','baixa')),
  coluna       TEXT NOT NULL DEFAULT 'entrada' CHECK (coluna IN ('entrada','a_fazer','aguardando','concluido','cancelado')),
  criado_em    TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (ambiente) REFERENCES ambientes(id),
  FOREIGN KEY (ambiente, cliente) REFERENCES clientes(ambiente, id),
  UNIQUE (evidencia_id, titulo)
);

CREATE TABLE IF NOT EXISTS rascunhos (
  id          INTEGER PRIMARY KEY,
  ambiente    TEXT NOT NULL REFERENCES ambientes(id),
  item_id     INTEGER REFERENCES itens(id),
  canal       TEXT NOT NULL CHECK (canal IN ('whatsapp','email')),
  destino     TEXT NOT NULL,
  texto       TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho','aprovado','rejeitado','enviado')),
  aprovado_em TEXT,
  criado_em   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Barreira técnica: nada vira "enviado" sem aprovação explícita registrada.
CREATE TRIGGER IF NOT EXISTS rascunho_sem_aprovacao
BEFORE UPDATE OF status ON rascunhos
WHEN NEW.status IN ('aprovado','enviado') AND NEW.aprovado_em IS NULL
BEGIN SELECT RAISE(ABORT, 'rascunho sem aprovado_em'); END;

CREATE TRIGGER IF NOT EXISTS rascunho_nasce_rascunho
BEFORE INSERT ON rascunhos
WHEN NEW.status <> 'rascunho'
BEGIN SELECT RAISE(ABORT, 'rascunho precisa nascer como rascunho'); END;

-- Auditoria só-inserção.
CREATE TABLE IF NOT EXISTS auditoria (
  id       INTEGER PRIMARY KEY,
  quando   TEXT NOT NULL DEFAULT (datetime('now')),
  ambiente TEXT,
  ator     TEXT NOT NULL,         -- usuario | claude | <script>
  acao     TEXT NOT NULL,
  alvo     TEXT,
  detalhe  TEXT
);
CREATE TRIGGER IF NOT EXISTS auditoria_sem_update BEFORE UPDATE ON auditoria
BEGIN SELECT RAISE(ABORT, 'auditoria é só-inserção'); END;
CREATE TRIGGER IF NOT EXISTS auditoria_sem_delete BEFORE DELETE ON auditoria
BEGIN SELECT RAISE(ABORT, 'auditoria é só-inserção'); END;

-- Ponto de leitura de cada fonte (coleta incremental).
CREATE TABLE IF NOT EXISTS cursores (
  fonte  TEXT PRIMARY KEY,        -- ex.: gmail:trabalho · whatsapp:trabalho
  valor  TEXT NOT NULL
);

-- Comentários do usuário em cada tarefa.
CREATE TABLE IF NOT EXISTS comentarios (
  id        INTEGER PRIMARY KEY,
  item_id   INTEGER NOT NULL REFERENCES itens(id),
  autor     TEXT NOT NULL DEFAULT 'usuario',
  texto     TEXT NOT NULL CHECK (length(trim(texto)) > 0),
  criado_em TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Briefing gerado antes de cada check-in de cliente (markdown simples: #, ##, -, **negrito**).
CREATE TABLE IF NOT EXISTS briefings (
  id           INTEGER PRIMARY KEY,
  ambiente     TEXT NOT NULL REFERENCES ambientes(id),
  cliente      TEXT,
  evidencia_id INTEGER NOT NULL REFERENCES evidencias(id),  -- o evento da agenda
  inicio       TEXT NOT NULL,                              -- horário da reunião (ISO)
  titulo       TEXT NOT NULL,
  conteudo     TEXT NOT NULL,
  criado_em    TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (ambiente, cliente) REFERENCES clientes(ambiente, id),
  UNIQUE (evidencia_id)
);
