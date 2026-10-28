import AppKit
import SwiftUI

let origens: [(id: String, nome: String, icone: String)] = [
    ("whatsapp", "WhatsApp", "message"), ("email", "E-mail", "envelope"), ("agenda", "Agenda", "calendar"),
    ("reuniao", "Reunião", "person.2")]
let tipos: [(id: String, nome: String, icone: String)] = [
    ("acao", "Ação", "bolt"), ("sugestao", "Sugestão", "lightbulb"),
    ("bloqueio", "Bloqueio", "exclamationmark.octagon"), ("acompanhamento", "Acompanhamento", "eye")]

func iconeOrigem(_ o: String?) -> String { origens.first { $0.id == o }?.icone ?? "doc" }
func tipoInfo(_ t: String?) -> (nome: String, icone: String) {
    let x = tipos.first { $0.id == t }; return (x?.nome ?? (t ?? ""), x?.icone ?? "circle")
}
let atalhos = ["a_fazer": "⌘1", "aguardando": "⌘2", "concluido": "⌘3", "cancelado": "⌘4"]

/// Prazo "AAAA-MM-DD…": vermelho se vencido, laranja se hoje/amanhã, neutro depois.
func prazo(_ s: String?) -> (texto: String, cor: Color)? {
    guard let s, s.count >= 10 else { return nil }
    let d = String(s.prefix(10))
    let p = d.split(separator: "-")
    guard p.count == 3 else { return (s, .secondary) }
    if d < Dia.hoje { return ("\(p[2])/\(p[1])", .red) }
    if d == Dia.hoje { return ("hoje", .orange) }
    if d == Dia.amanha { return ("amanhã", .orange) }
    return ("\(p[2])/\(p[1])", .secondary)
}

// MARK: - Liquid Glass com fallback (vidro só em navegação/controles, nunca no conteúdo)

extension View {
    @ViewBuilder func vidro<S: Shape>(_ forma: S, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: forma)
        } else {
            background(.regularMaterial, in: forma)
        }
    }

    @ViewBuilder func botaoVidro(destaque: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if destaque { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if destaque { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Fileira de botões de status (A fazer, Aguardando, Concluído, Cancelado) — 1 clique move.
struct AcoesRapidas: View {
    let item: Linha
    let aoMover: (Linha, String) -> Void

    var body: some View {
        let botoes = HStack(spacing: 4) {
            ForEach(colunas.filter { $0.id != "entrada" && $0.id != item["coluna"] }, id: \.id) { c in
                Button { aoMover(item, c.id) } label: {
                    Image(systemName: c.icone).foregroundStyle(corStatus(c.id)).frame(width: 18, height: 16)
                }
                .botaoVidro()
                .controlSize(.small)
                .help("\(c.nome) (\(atalhos[c.id] ?? ""))")
            }
        }
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 4) { botoes } } else { botoes }
    }
}

// MARK: - Janela principal

struct Principal: View {
    @ObservedObject var estado: Estado
    @State private var selecao: Selecao? = {
        switch ProcessInfo.processInfo.environment["PRUMO_TELA"] {
        case "atencao": .atencao
        case "quadro": .todos
        default: .hoje
        }
    }()
    @State private var origem: String? = nil
    @State private var tipo: String? = nil
    @State private var busca = ""
    @State private var mostrarCancelados = false
    @State private var recolhidas: Set<String> = []
    @State private var briefing: Linha? = nil

    private func passaSelecao(_ i: Linha, _ s: Selecao) -> Bool {
        switch s {
        case .hoje, .atencao, .todos: true
        case .ambiente(let a): i["ambiente"] == a
        case .cliente(let a, let c): i["ambiente"] == a && i["cliente"] == c
        case .semCliente(let a): i["ambiente"] == a && i["cliente"] == nil
        }
    }

    private var filtrados: [Linha] {
        let b = busca.trimmingCharacters(in: .whitespaces).lowercased()
        return estado.itens.filter { i in
            passaSelecao(i, selecao ?? .todos)
                && (origem == nil || i["origem"] == origem) && (tipo == nil || i["tipo"] == tipo)
                && (b.isEmpty || [i["titulo"], i["descricao"], i["cliente"], nomeCliente(i["cliente"], i["ambiente"])]
                    .contains { $0?.lowercased().contains(b) == true })
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selecao) {
                Section {
                    linhaLateral("Hoje", icone: "sun.max", n: 0).tag(Selecao.hoje)
                    linhaLateral("Atenção", icone: "exclamationmark.triangle", n: estado.nAtencao, destaque: true).tag(Selecao.atencao)
                    linhaLateral("Quadro", icone: "rectangle.split.3x1", n: estado.abertos { _ in true }).tag(Selecao.todos)
                }
                ForEach(ordemAmbiente, id: \.self) { a in
                    Section {
                        linhaLateral("Tudo", icone: "square.stack", n: estado.abertos { $0["ambiente"] == a }).tag(Selecao.ambiente(a))
                        ForEach(estado.clientes.filter { $0["ambiente"] == a }, id: \.self) { c in
                            let id = c["id"] ?? ""
                            linhaLateral(nomeCliente(id, a), icone: "person.crop.square",
                                         n: estado.abertos { $0["ambiente"] == a && $0["cliente"] == id })
                                .tag(Selecao.cliente(a, id))
                        }
                        linhaLateral("Sem cliente", icone: "questionmark.square.dashed",
                                     n: estado.abertos { $0["ambiente"] == a && $0["cliente"] == nil }).tag(Selecao.semCliente(a))
                    } header: {
                        HStack(spacing: 6) { Circle().fill(corAmbiente(a)).frame(width: 8, height: 8); Text(nomeAmbiente(a)) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                if let e = estado.erro {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(6).background(.red)
                }
                switch selecao ?? .todos {
                case .hoje: TelaHoje(estado: estado, briefing: $briefing)
                case .atencao: TelaAtencao(estado: estado)
                default: quadro
                }
            }
            .searchable(text: $busca, placement: .toolbar, prompt: "Filtrar quadro")
            .toolbar { barra }
            .inspector(isPresented: Binding(get: { estado.aberto != nil }, set: { if !$0 { estado.aberto = nil } })) {
                if let id = estado.aberto {
                    Detalhe(itemId: id, estado: estado).id(id)
                        .inspectorColumnWidth(min: 380, ideal: 440, max: 620)
                }
            }
            .sheet(item: Binding(get: { briefing.map(Aberto.init) }, set: { briefing = $0?.linha })) { b in
                TelaBriefing(evento: b.linha)
            }
            .overlay(alignment: .top) {
                if estado.paleta { Paleta(estado: estado).padding(.top, 40) }
            }
            .onAppear(perform: ganchosDeTela)
        }
    }

    /// Ganchos para gerar screenshots (README): PRUMO_ITEM abre o inspector, PRUMO_BRIEFING abre o briefing do evento.
    private func ganchosDeTela() {
        let env = ProcessInfo.processInfo.environment
        if let id = env["PRUMO_ITEM"] { estado.aberto = id }
        if let ev = env["PRUMO_BRIEFING"] {
            briefing = try? Banco.consultar("""
                SELECT e.*, b.id AS briefing_id, b.titulo AS briefing_titulo, b.conteudo AS briefing
                FROM evidencias e JOIN briefings b ON b.evidencia_id = e.id WHERE e.id = ?
                """, [ev]).first
        }
    }

    private var quadro: some View {
        let visiveis = colunas.filter { mostrarCancelados || $0.id != "cancelado" }
        return GeometryReader { geo in
            let abertasN = visiveis.filter { !recolhidas.contains($0.id) }.count
            let livre = geo.size.width - 28 - CGFloat(visiveis.count - 1) * 12 - CGFloat(visiveis.count - abertasN) * 44
            let largura = max(200, livre / CGFloat(max(abertasN, 1)))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(visiveis, id: \.id) { col in
                        Coluna(id: col.id, nome: col.nome, itens: filtrados.filter { $0["coluna"] == col.id },
                               recolhida: recolhidas.contains(col.id), largura: largura,
                               alternar: { if recolhidas.contains(col.id) { recolhidas.remove(col.id) } else { recolhidas.insert(col.id) } },
                               estado: estado)
                    }
                }
                .padding(14)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
    }

    private func linhaLateral(_ nome: String, icone: String, n: Int, destaque: Bool = false) -> some View {
        HStack {
            Label(nome, systemImage: icone)
            Spacer()
            if n > 0 {
                Text("\(n)").font(.caption.monospacedDigit())
                    .foregroundStyle(destaque ? Color.white : Color.secondary)
                    .padding(.horizontal, destaque ? 6 : 0).padding(.vertical, destaque ? 1 : 0)
                    .background(Capsule().fill(destaque ? Color.red : Color.clear))
            }
        }
    }

    @ToolbarContentBuilder private var barra: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Origem", selection: $origem) {
                Text("Todas as origens").tag(String?.none)
                ForEach(origens, id: \.id) { Label($0.nome, systemImage: $0.icone).tag(Optional($0.id)) }
            }
            Picker("Tipo", selection: $tipo) {
                Text("Todos os tipos").tag(String?.none)
                ForEach(tipos, id: \.id) { Label($0.nome, systemImage: $0.icone).tag(Optional($0.id)) }
            }
            Toggle(isOn: $mostrarCancelados) { Label("Mostrar cancelados", systemImage: "xmark.bin") }
                .help("Mostrar cancelados")
        }
        ToolbarItemGroup {
            Button { estado.paleta = true } label: { Label("Buscar", systemImage: "command") }.help("Buscar tarefas (⌘K)")
            statusRodada
            Button { estado.verificarAgora() } label: {
                if estado.rodando { ProgressView().controlSize(.small) } else { Label("Verificar agora", systemImage: "arrow.clockwise") }
            }
            .help("Verificar agora")
            .disabled(estado.rodando)
        }
    }

    @ViewBuilder private var statusRodada: some View {
        if estado.rodando {
            Text("Verificando…").font(.caption).foregroundStyle(.secondary)
        } else if let r = estado.rodada {
            let falhou = (r["status"] as? String) == "falha"
            let quando = dataISO(r["fim"] as? String) ?? dataISO(r["inicio"] as? String)
            Text(quando.map { "Atualizado \(relativo($0))" } ?? "Atualizado")
                .font(.caption).foregroundStyle(falhou ? Color.red : Color.secondary)
                .help((falhou ? "Última rodada falhou: " : "") + (r["mensagem"] as? String ?? ""))
        } else {
            Text("Nunca rodou").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Aberto: Identifiable {
    let linha: Linha
    var id: String { linha["id"] ?? "" }
}

// MARK: - Quadro

struct Coluna: View {
    let id: String
    let nome: String
    let itens: [Linha]
    let recolhida: Bool
    let largura: CGFloat
    let alternar: () -> Void
    @ObservedObject var estado: Estado
    @State private var alvo = false

    var body: some View {
        Group {
            if recolhida {
                VStack(spacing: 8) {
                    Circle().fill(corStatus(id)).frame(width: 9, height: 9)
                    Text("\(itens.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Text(nome).font(.headline).fixedSize().rotationEffect(.degrees(-90)).frame(width: 24, height: 120)
                    Spacer()
                }
                .padding(.vertical, 10)
                .frame(width: 44)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture(perform: alternar)
                .help("Expandir \(nome)")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: alternar) {
                        HStack(spacing: 6) {
                            Circle().fill(corStatus(id)).frame(width: 9, height: 9)
                            Text(nome).font(.headline)
                            Text("\(itens.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Recolher \(nome)")
                    .padding(.horizontal, 4)
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(itens, id: \.self) { i in
                                Cartao(item: i, selecionado: estado.aberto == i["id"], aoMover: estado.mover)
                                    .onTapGesture { estado.aberto = i["id"] }
                                    .draggable(i["id"] ?? "")
                                    .contextMenu {
                                        Menu("Mover para…") {
                                            ForEach(colunas.filter { $0.id != i["coluna"] }, id: \.id) { c in
                                                Button { estado.mover(i, para: c.id) } label: { Label(c.nome, systemImage: c.icone) }
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(2)
                    }
                }
                .padding(10)
                .frame(width: largura)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(alvo ? corStatus(id).opacity(0.14) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(alvo ? corStatus(id) : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { ids, _ in
            for itemId in ids { if let i = estado.itens.first(where: { $0["id"] == itemId }) { estado.mover(i, para: id) } }
            return !ids.isEmpty
        } isTargeted: { alvo = $0 }
        .animation(.easeOut(duration: 0.15), value: alvo)
    }
}

struct Cartao: View {
    let item: Linha
    var selecionado = false
    let aoMover: (Linha, String) -> Void
    @State private var sobre = false

    var body: some View {
        let t = item["tipo"]
        let baixa = item["confianca"] == "baixa"
        let forma = RoundedRectangle(cornerRadius: 10)
        HStack(spacing: 0) {
            Rectangle().fill(corAmbiente(item["ambiente"])).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(item["titulo"] ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t == "sugestao" ? .secondary : .primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Duas linhas curtas: em coluna estreita uma linha só cortava cliente e prazo.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(nomeCliente(item["cliente"], item["ambiente"]))
                            .font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(item["cliente"] == nil ? Color.orange.opacity(0.18) : corAmbiente(item["ambiente"]).opacity(0.16)))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let p = prazo(item["prazo"]) {
                            Label(p.texto, systemImage: "clock").foregroundStyle(p.cor).fixedSize()
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: iconeOrigem(item["origem"])).help(item["origem"] ?? "")
                        Image(systemName: tipoInfo(t).icone).foregroundStyle(t == "bloqueio" ? .red : .secondary)
                            .help(tipoInfo(t).nome)
                        if baixa { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("Confiança baixa") }
                        Spacer(minLength: 0)
                        if let n = Int(item["n_coment"] ?? "0"), n > 0 { Label("\(n)", systemImage: "bubble.left").help("\(n) comentário(s)") }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if sobre { HStack { Spacer(); AcoesRapidas(item: item, aoMover: aoMover) } }
            }
            .padding(10)
        }
        .background(forma.fill(t == "bloqueio" ? Color.red.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
        .clipShape(forma)
        .overlay(forma.strokeBorder(selecionado ? Color.accentColor : baixa ? Color.orange.opacity(0.7) : Color.primary.opacity(0.08),
                                    style: StrokeStyle(lineWidth: selecionado ? 2 : 1, dash: baixa && !selecionado ? [4, 3] : [])))
        .shadow(color: .black.opacity(sobre ? 0.12 : 0.05), radius: sobre ? 4 : 2, y: 1)
        .contentShape(forma)
        .onHover { sobre = $0 }
        .animation(.easeOut(duration: 0.12), value: sobre)
    }
}

// MARK: - Inspector

struct Detalhe: View {
    let itemId: String
    @ObservedObject var estado: Estado
    @State private var evidencia: Linha = [:]
    @State private var rascunhos: [Linha] = []
    @State private var comentarios: [Linha] = []
    @State private var novo = ""
    @FocusState private var comentando: Bool

    private var item: Linha { estado.itens.first { $0["id"] == itemId } ?? [:] }

    /// Resumo em texto para o menu Compartilhar (você escolhe para quem; o app não envia nada sozinho).
    private var textoParaCompartilhar: String {
        var t = [item["titulo"] ?? "", "\(nomeAmbiente(item["ambiente"])) · \(nomeCliente(item["cliente"], item["ambiente"]))"]
        if let p = item["prazo"] { t.append("Prazo: \(p)") }
        if let r = item["responsavel"] { t.append("Responsável: \(r)") }
        if let d = item["descricao"], !d.isEmpty { t.append("\n\(d)") }
        if !comentarios.isEmpty { t.append("\nComentários:\n" + comentarios.map { "- \($0["texto"] ?? "")" }.joined(separator: "\n")) }
        return t.joined(separator: "\n")
    }

    var body: some View {
        let cor = corAmbiente(item["ambiente"])
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(cor).frame(width: 8, height: 8)
                        Text("\(nomeAmbiente(item["ambiente"])) · \(nomeCliente(item["cliente"], item["ambiente"]))")
                            .font(.caption.weight(.semibold))
                    }
                    Text(item["titulo"] ?? "").font(.title3.bold()).textSelection(.enabled)
                }
                Spacer()
                ShareLink(item: textoParaCompartilhar) { Image(systemName: "square.and.arrow.up") }
                    .botaoVidro().help("Compartilhar a tarefa (Mail, Mensagens, Notas, AirDrop…)")
                Button { estado.aberto = nil } label: { Image(systemName: "xmark") }
                    .botaoVidro().keyboardShortcut(.cancelAction).help("Fechar (Esc)")
            }
            .padding(14)
            .vidro(RoundedRectangle(cornerRadius: 14), tint: cor.opacity(0.25))

            Picker("Estado", selection: Binding(get: { item["coluna"] ?? "entrada" }, set: { estado.mover(item, para: $0) })) {
                ForEach(colunas, id: \.id) { c in Text(c.nome).tag(c.id) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.large)
            .help("A fazer ⌘1 · Aguardando ⌘2 · Concluído ⌘3 · Cancelado ⌘4")

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    secao("Descrição") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            campo("Tipo", tipoInfo(item["tipo"]).nome)
                            campo("Prazo", item["prazo"])
                            campo("Responsável", item["responsavel"])
                            campo("Prioridade", item["prioridade"])
                            campo("Confiança", item["confianca"])
                        }
                        if let d = item["descricao"] { Text(d).textSelection(.enabled) }
                    }
                    secao("Origem") {
                        HStack(spacing: 6) {
                            Image(systemName: iconeOrigem(evidencia["origem"]))
                            Text(evidencia["titulo"] ?? "").bold()
                        }
                        Text([evidencia["remetente"], quandoLegivel(evidencia["quando"])].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(evidencia["conteudo"] ?? "").textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        if let l = evidencia["link"], let u = URL(string: l) { Link("Abrir na origem", destination: u) }
                    }
                    if !rascunhos.isEmpty {
                        secao("Respostas sugeridas") {
                            Text("O app nunca envia nada: copie e envie você mesmo.").font(.caption).foregroundStyle(.secondary)
                            ForEach(rascunhos, id: \.self) { r in rascunho(r) }
                        }
                    }
                    secao("Comentários") {
                        ForEach(comentarios, id: \.self) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c["autor"] ?? "") · \(dataSQLite(c["criado_em"]).map(relativo) ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(c["texto"] ?? "").textSelection(.enabled)
                            }
                        }
                        TextEditor(text: $novo)
                            .focused($comentando)
                            .font(.body).frame(minHeight: 60)
                            .padding(4).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                        HStack {
                            Spacer()
                            Button("Comentar") {
                                if estado.comentar(item, novo) { novo = ""; carregar() }
                            }
                            .botaoVidro(destaque: true)
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("Comentar (⌘↩)")
                            .disabled(novo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .padding(12)
        .onAppear(perform: carregar)
        .onChange(of: comentando) { _, v in estado.editando = v }
        .onDisappear { estado.editando = false }
    }

    private func secao<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo).font(.headline)
            conteudo()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rascunho(_ r: Linha) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(r["canal"] ?? "") → \(r["destino"] ?? "") · \(r["status"] ?? "")").font(.caption).foregroundStyle(.secondary)
            Text(r["texto"] ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(r["texto"] ?? "", forType: .string)
                }
                if r["status"] == "rascunho" {
                    Button("Aprovar") { estado.decidir(r, aprovar: true); carregar() }
                    Button("Rejeitar") { estado.decidir(r, aprovar: false); carregar() }
                }
            }
            .botaoVidro()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder private func campo(_ rotulo: String, _ valor: String?) -> some View {
        if let valor { GridRow { Text(rotulo).foregroundStyle(.secondary); Text(valor) } }
    }

    private func carregar() {
        evidencia = (try? Banco.consultar("SELECT * FROM evidencias WHERE id=?", [item["evidencia_id"]]).first) ?? [:]
        rascunhos = (try? Banco.consultar("SELECT * FROM rascunhos WHERE item_id=? ORDER BY id", [itemId])) ?? []
        comentarios = (try? Banco.consultar("SELECT * FROM comentarios WHERE item_id=? ORDER BY id", [itemId])) ?? []
    }
}
