import SwiftUI
import Foundation
import SQLite3

enum Caminhos {
    /// Pasta do projeto: 1ª linha de ~/.config/prumo/raiz; sem o arquivo, ~/Prumo.
    static let base: URL = {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let raiz = (try? String(contentsOf: home.appendingPathComponent(".config/prumo/raiz"), encoding: .utf8))?
            .split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let raiz, !raiz.isEmpty else { return home.appendingPathComponent("Prumo") }
        return URL(fileURLWithPath: (raiz as NSString).expandingTildeInPath)
    }()
    static let db = ProcessInfo.processInfo.environment["ASSISTENTE_DB"] ?? base.appendingPathComponent("db/assistente.db").path
    /// Com ASSISTENTE_DB (ex.: banco de demonstração), rodada e estado vêm da pasta desse banco — nunca do projeto real.
    private static let pastaRodada = ProcessInfo.processInfo.environment["ASSISTENTE_DB"]
        .map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? base
    static let script = pastaRodada.appendingPathComponent("rodada.sh")
    static let estadoRodada = pastaRodada.appendingPathComponent("estado_rodada.json")
}

typealias Linha = [String: String]

/// Acesso mínimo ao SQLite: cada chamada abre, usa e fecha (o banco é pequeno e local).
enum Banco {
    private static let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func abrir() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(Caminhos.db, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw NSError(domain: "Banco", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não abriu o banco em \(Caminhos.db)"])
        }
        sqlite3_busy_timeout(db, 5000)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
        return db
    }

    private static func rodar(_ db: OpaquePointer, _ sql: String, _ args: [String?]) throws -> [Linha] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw erro(db) }
        defer { sqlite3_finalize(st) }
        for (i, a) in args.enumerated() {
            if let a { sqlite3_bind_text(st, Int32(i + 1), a, -1, TRANSIENT) } else { sqlite3_bind_null(st, Int32(i + 1)) }
        }
        var linhas: [Linha] = []
        while true {
            let r = sqlite3_step(st)
            if r == SQLITE_DONE { break }
            guard r == SQLITE_ROW else { throw erro(db) }
            var l = Linha()
            for c in 0..<sqlite3_column_count(st) {
                if let t = sqlite3_column_text(st, c) { l[String(cString: sqlite3_column_name(st, c))] = String(cString: t) }
            }
            linhas.append(l)
        }
        return linhas
    }

    private static func erro(_ db: OpaquePointer) -> NSError {
        NSError(domain: "Banco", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }

    static func consultar(_ sql: String, _ args: [String?] = []) throws -> [Linha] {
        let db = try abrir(); defer { sqlite3_close(db) }
        return try rodar(db, sql, args)
    }

    /// Executa vários comandos numa transação: ou entram todos (mudança + auditoria) ou nenhum.
    static func transacao(_ comandos: [(String, [String?])]) throws {
        let db = try abrir(); defer { sqlite3_close(db) }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        do {
            for (sql, args) in comandos { _ = try rodar(db, sql, args) }
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw erro(db) }
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
}


let colunas: [(id: String, nome: String, icone: String)] = [
    ("entrada", "Entrada", "tray"), ("a_fazer", "A fazer", "circle"), ("aguardando", "Aguardando", "hourglass"),
    ("concluido", "Concluído", "checkmark.circle"), ("cancelado", "Cancelado", "xmark.circle")]
let abertas: Set<String> = ["entrada", "a_fazer", "aguardando"]
/// Ambientes e clientes vêm do banco (tabelas `ambientes` e `clientes`); atualizado a cada recarga.
enum Cadastro {
    static var ambientes: [Linha] = []
    static var clientes: [Linha] = []
}

var ordemAmbiente: [String] { Cadastro.ambientes.compactMap { $0["id"] } }
func nomeAmbiente(_ id: String?) -> String {
    guard let id else { return "" }
    return Cadastro.ambientes.first { $0["id"] == id }?["nome"] ?? id
}
func nomeCliente(_ id: String?, _ ambiente: String? = nil) -> String {
    guard let id else { return "sem cliente" }
    return Cadastro.clientes.first { $0["id"] == id && (ambiente == nil || $0["ambiente"] == ambiente) }?["nome"] ?? id
}
/// Quem age no app: o usuário do Mac (vai para auditoria e comentários).
let usuario = NSUserName()

/// Datas de referência do dia (hora local) e cortes em UTC para comparar com `criado_em`.
enum Dia {
    static func local(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    static func utc(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); return f.string(from: d)
    }
    static var inicio: Date { Calendar.current.startOfDay(for: Date()) }
    static var hoje: String { local(inicio) }
    static var amanha: String { local(inicio.addingTimeInterval(86_400)) }
    static var ontem19h: String { utc(inicio.addingTimeInterval(-5 * 3600)) }
    static var haTresDias: String { utc(Date().addingTimeInterval(-3 * 86_400)) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Cor do ambiente: hex da tabela `ambientes` (ex.: #30A46C); sem cor, a secundária do sistema.
func corAmbiente(_ a: String?) -> Color {
    guard let h = Cadastro.ambientes.first(where: { $0["id"] == a })?["cor"]?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")),
          h.count == 6, let v = UInt32(h, radix: 16) else { return .secondary }
    return Color(hex: v)
}

func corStatus(_ c: String?) -> Color {
    switch c {
    case "entrada": Color(hex: 0x7A8CA3)
    case "a_fazer": .blue
    case "aguardando": Color(hex: 0xE0A000)
    case "concluido": .green
    default: .gray
    }
}

/// Datas do SQLite (`datetime('now')`) são UTC sem fuso.
private let formatoSQLite: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); return f
}()
func dataSQLite(_ s: String?) -> Date? { s.flatMap { formatoSQLite.date(from: String($0.prefix(19))) } }

/// `fim`/`inicio` do estado_rodada.json: ISO com ou sem fuso (sem fuso = hora local).
func dataISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    if let d = ISO8601DateFormatter().date(from: s) { return d }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f.date(from: String(s.prefix(19)))
}

/// "2026-10-28T08:12:00-03:00" → "28/10 08:12"; "2026-10-28" → "28/10"; outro formato fica como está.
func quandoLegivel(_ s: String?) -> String? {
    guard let s else { return nil }
    let p = s.prefix(10).split(separator: "-")
    guard p.count == 3 else { return s }
    return s.count >= 16 ? "\(p[2])/\(p[1]) \(s.dropFirst(11).prefix(5))" : "\(p[2])/\(p[1])"
}

func relativo(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "pt_BR"); f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

enum Selecao: Hashable {
    case hoje
    case atencao
    case todos
    case ambiente(String)
    case cliente(String, String)
    case semCliente(String)
}

final class Estado: ObservableObject {
    @Published var itens: [Linha] = []
    @Published var clientes: [Linha] = []
    @Published var rodada: [String: Any]? = nil
    @Published var erro: String? = nil
    @Published var rodandoLocal = false
    @Published var agendaHoje: [Linha] = []
    @Published var aberto: String? = nil
    @Published var paleta = false
    @Published var editando = false   // campo de texto em foco (atalhos de tarefa desligados)
    private var timer: Timer?

    init() {
        recarregar()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.recarregar() }
    }

    func recarregar() {
        do {
            Cadastro.ambientes = try Banco.consultar("SELECT id, nome, cor, ordem FROM ambientes ORDER BY ordem IS NULL, ordem, id")
            clientes = try Banco.consultar("SELECT ambiente, id, nome FROM clientes ORDER BY ambiente, coalesce(nome, id)")
            Cadastro.clientes = clientes
            itens = try Banco.consultar("""
                SELECT i.*, e.origem, (SELECT count(*) FROM comentarios c WHERE c.item_id = i.id) AS n_coment,
                       coalesce((SELECT max(a.quando) FROM auditoria a WHERE a.alvo = 'item:' || i.id AND a.acao = 'mover'),
                                i.criado_em) AS desde
                FROM itens i JOIN evidencias e ON e.id = i.evidencia_id
                ORDER BY (i.prazo IS NULL), i.prazo, i.criado_em DESC
                """)
            agendaHoje = try Banco.consultar("""
                SELECT e.*, b.id AS briefing_id, b.titulo AS briefing_titulo, b.conteudo AS briefing
                FROM evidencias e LEFT JOIN briefings b ON b.evidencia_id = e.id
                WHERE e.origem = 'agenda' AND e.removido_em IS NULL AND substr(e.quando, 1, 10) = ? ORDER BY e.quando
                """, [Dia.hoje])
            erro = nil
        } catch { self.erro = error.localizedDescription }
        if let d = try? Data(contentsOf: Caminhos.estadoRodada) {
            rodada = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        } else { rodada = nil }
    }

    var rodando: Bool { rodandoLocal || (rodada?["status"] as? String) == "rodando" }

    var itemAberto: Linha? { aberto.flatMap { id in itens.first { $0["id"] == id } } }

    func moverAberto(_ coluna: String) { if let i = itemAberto { mover(i, para: coluna) } }

    /// Grupos da visão Atenção (um item pode estar em mais de um grupo).
    var atencao: [(titulo: String, itens: [Linha])] {
        let ab = itens.filter { abertas.contains($0["coluna"] ?? "") }
        return [
            ("Vencidos", ab.filter { ($0["prazo"].map { String($0.prefix(10)) } ?? "9") < Dia.hoje }),
            ("Bloqueios abertos", ab.filter { $0["tipo"] == "bloqueio" }),
            ("Aguardando há mais de 3 dias", ab.filter { $0["coluna"] == "aguardando" && ($0["desde"] ?? "") < Dia.haTresDias }),
            ("Confiança baixa na Entrada", ab.filter { $0["coluna"] == "entrada" && $0["confianca"] == "baixa" }),
        ]
    }
    var nAtencao: Int { Set(atencao.flatMap { $0.itens.compactMap { $0["id"] } }).count }

    func abertos(_ filtro: (Linha) -> Bool) -> Int { itens.filter { abertas.contains($0["coluna"] ?? "") && filtro($0) }.count }

    func mover(_ item: Linha, para coluna: String) {
        guard let id = item["id"], let de = item["coluna"], de != coluna else { return }
        executar([
            ("UPDATE itens SET coluna=? WHERE id=?", [coluna, id]),
            ("INSERT INTO auditoria(ambiente, ator, acao, alvo, detalhe) VALUES(?, ?, 'mover', ?, ?)",
             [item["ambiente"], usuario, "item:\(id)", "\(de) → \(coluna)"]),
        ])
    }

    @discardableResult
    func comentar(_ item: Linha, _ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = item["id"], !t.isEmpty else { return false }
        return executar([
            ("INSERT INTO comentarios(item_id, autor, texto) VALUES(?, ?, ?)", [id, usuario, t]),
            ("INSERT INTO auditoria(ambiente, ator, acao, alvo, detalhe) VALUES(?, ?, 'comentar', ?, ?)",
             [item["ambiente"], usuario, "item:\(id)", String(t.prefix(200))]),
        ])
    }

    func decidir(_ r: Linha, aprovar: Bool) {
        guard let id = r["id"], let de = r["status"] else { return }
        let para = aprovar ? "aprovado" : "rejeitado"
        executar([
            (aprovar ? "UPDATE rascunhos SET status='aprovado', aprovado_em=datetime('now') WHERE id=?"
                     : "UPDATE rascunhos SET status='rejeitado' WHERE id=?", [id]),
            ("INSERT INTO auditoria(ambiente, ator, acao, alvo, detalhe) VALUES(?, ?, ?, ?, ?)",
             [r["ambiente"], usuario, aprovar ? "aprovar_rascunho" : "rejeitar_rascunho", "rascunho:\(id)", "\(de) → \(para)"]),
        ])
    }

    @discardableResult
    private func executar(_ cmds: [(String, [String?])]) -> Bool {
        defer { recarregar() }
        do { try Banco.transacao(cmds); return true } catch { erro = error.localizedDescription; return false }
    }

    func verificarAgora() {
        guard !rodando else { return }
        guard FileManager.default.fileExists(atPath: Caminhos.script.path) else {
            erro = "A rodada ainda não está instalada (falta rodada.sh)."
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Caminhos.script.path]
        var env = ProcessInfo.processInfo.environment
        env["MANUAL"] = "1"
        p.environment = env
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.rodandoLocal = false; self?.recarregar() } }
        do { try p.run(); rodandoLocal = true } catch { erro = "Não consegui iniciar a rodada: \(error.localizedDescription)" }
    }
}
