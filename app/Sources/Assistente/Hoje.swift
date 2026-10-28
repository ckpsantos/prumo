import SwiftUI

/// Linha compacta (Hoje / Atenção / paleta): clique abre o inspector; ações de status ao passar o mouse.
struct LinhaItem: View {
    let item: Linha
    @ObservedObject var estado: Estado
    @State private var sobre = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(corAmbiente(item["ambiente"])).frame(width: 4, height: 28)
            Image(systemName: iconeOrigem(item["origem"])).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item["titulo"] ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text("\(nomeCliente(item["cliente"], item["ambiente"])) · \(colunas.first { $0.id == item["coluna"] }?.nome ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if sobre { AcoesRapidas(item: item, aoMover: estado.mover) }
            if let p = prazo(item["prazo"]) { Label(p.texto, systemImage: "clock").font(.caption).foregroundStyle(p.cor).fixedSize() }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(estado.aberto == item["id"] ? Color.accentColor.opacity(0.12)
                                                            : sobre ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { estado.aberto = item["id"] }
        .onHover { sobre = $0 }
    }
}

private struct Grupo<C: View>: View {
    let titulo: String
    let n: Int
    var cor: Color = .secondary
    @ViewBuilder let conteudo: C

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(titulo).font(.headline)
                Text("\(n)").font(.subheadline.monospacedDigit()).foregroundStyle(cor)
            }
            if n == 0 { Text("Nada aqui.").font(.callout).foregroundStyle(.tertiary) } else { conteudo }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TelaHoje: View {
    @ObservedObject var estado: Estado
    @Binding var briefing: Linha?

    var body: some View {
        let ab = estado.itens.filter { abertas.contains($0["coluna"] ?? "") }
        let comPrazo = ab.filter { ($0["prazo"].map { String($0.prefix(10)) } ?? "9") <= Dia.amanha }
        let conflitos = estado.itens.filter {
            $0["tipo"] == "bloqueio" && $0["origem"] == "agenda" && $0["prazo"].map { String($0.prefix(10)) } == Dia.hoje
        }
        let chegou = estado.itens.filter { ($0["criado_em"] ?? "") >= Dia.ontem19h }
        let parados = estado.itens.filter {
            ["entrada", "a_fazer"].contains($0["coluna"] ?? "") && ($0["criado_em"] ?? "9") < Dia.haTresDias
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text({ let t = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))); return t.prefix(1).uppercased() + t.dropFirst() }())
                    .font(.largeTitle.bold())
                Grupo(titulo: "Agenda de hoje", n: estado.agendaHoje.count) {
                    ForEach(estado.agendaHoje, id: \.self) { e in evento(e) }
                }
                Grupo(titulo: "Prazos", n: comPrazo.count, cor: .red) {
                    ForEach(comPrazo, id: \.self) { LinhaItem(item: $0, estado: estado) }
                }
                Grupo(titulo: "Conflitos de hoje", n: conflitos.count, cor: .red) {
                    ForEach(conflitos, id: \.self) { LinhaItem(item: $0, estado: estado) }
                }
                Grupo(titulo: "Chegou desde ontem 19h", n: chegou.count) {
                    ForEach(chegou, id: \.self) { LinhaItem(item: $0, estado: estado) }
                }
                Grupo(titulo: "Parados há mais de 3 dias", n: parados.count, cor: .orange) {
                    ForEach(parados, id: \.self) { LinhaItem(item: $0, estado: estado) }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func evento(_ e: Linha) -> some View {
        let q = e["quando"] ?? ""
        let hora = q.count >= 16 ? String(q.dropFirst(11).prefix(5)) : "Dia todo"
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(corAmbiente(e["ambiente"])).frame(width: 4, height: 28)
            Text(hora).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(e["titulo"] ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text([nomeAmbiente(e["ambiente"]), e["cliente"].map { nomeCliente($0, e["ambiente"]) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if e["briefing_id"] != nil {
                Button { briefing = e } label: { Label("Briefing", systemImage: "doc.text") }.botaoVidro(destaque: true)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
    }
}

struct TelaAtencao: View {
    @ObservedObject var estado: Estado

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Atenção").font(.largeTitle.bold())
                ForEach(estado.atencao, id: \.titulo) { g in
                    Grupo(titulo: g.titulo, n: g.itens.count, cor: .red) {
                        ForEach(g.itens, id: \.self) { LinhaItem(item: $0, estado: estado) }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

// MARK: - Briefing (markdown simples, sem dependência)

struct TelaBriefing: View {
    let evento: Linha
    @Environment(\.dismiss) private var fechar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(evento["briefing_titulo"] ?? evento["titulo"] ?? "Briefing").font(.title2.bold())
                Spacer()
                Button("Fechar") { fechar() }.keyboardShortcut(.cancelAction).botaoVidro()
            }
            .padding(16)
            .vidro(Rectangle(), tint: corAmbiente(evento["ambiente"]).opacity(0.2))
            ScrollView { Markdown(texto: evento["briefing"] ?? "").padding(20) }
        }
        .frame(width: 640, height: 640)
    }
}

/// Renderiza `# `, `## `, `- ` e parágrafos; negrito e links via AttributedString(markdown:) por linha.
struct Markdown: View {
    let texto: String

    private func inline(_ s: String) -> Text {
        let a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        return Text(a)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(texto.components(separatedBy: "\n").enumerated()), id: \.offset) { _, linha in
                let l = linha.trimmingCharacters(in: .whitespaces)
                let nivel = linha.prefix { $0 == " " }.count / 2   // sub-item = 2 espaços por nível
                if l.hasPrefix("## ") {
                    inline(String(l.dropFirst(3))).font(.headline).padding(.top, 6)
                } else if l.hasPrefix("# ") {
                    inline(String(l.dropFirst(2))).font(.title2.bold()).padding(.top, 4)
                } else if l.hasPrefix("- ") || l.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(nivel > 0 ? "◦" : "•").foregroundStyle(.secondary)
                        inline(String(l.dropFirst(2)))
                    }
                    .padding(.leading, CGFloat(nivel) * 18)
                } else if l.isEmpty {
                    Spacer().frame(height: 2)
                } else {
                    inline(l)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Paleta ⌘K

struct Paleta: View {
    @ObservedObject var estado: Estado
    @State private var termo = ""
    @State private var marcado = 0
    @FocusState private var foco: Bool

    private var resultados: [Linha] {
        let b = termo.trimmingCharacters(in: .whitespaces).lowercased()
        return estado.itens.filter { i in
            abertas.contains(i["coluna"] ?? "")
                && (b.isEmpty || [i["titulo"], i["descricao"], nomeCliente(i["cliente"], i["ambiente"])].contains { $0?.lowercased().contains(b) == true })
        }
        .prefix(12).map { $0 }
    }

    private func abrir(_ i: Linha?) {
        guard let i else { return }
        estado.aberto = i["id"]; estado.paleta = false
    }

    var body: some View {
        let r = resultados
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar tarefas abertas (título, cliente, descrição)", text: $termo)
                    .textFieldStyle(.plain).font(.title3).focused($foco)
                    .onSubmit { abrir(r.indices.contains(marcado) ? r[marcado] : nil) }
                    .onChange(of: termo) { marcado = 0 }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(r.enumerated()), id: \.offset) { n, i in
                        HStack(spacing: 8) {
                            Circle().fill(corAmbiente(i["ambiente"])).frame(width: 8, height: 8)
                            Text(i["titulo"] ?? "").lineLimit(1)
                            Spacer()
                            Text(nomeCliente(i["cliente"], i["ambiente"])).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(n == marcado ? Color.accentColor.opacity(0.2) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { abrir(i) }
                    }
                    if r.isEmpty { Text("Nada encontrado.").foregroundStyle(.secondary).padding(12) }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 560)
        .vidro(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .onAppear { foco = true }
        .onKeyPress(.downArrow) { marcado = min(marcado + 1, max(r.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { marcado = max(marcado - 1, 0); return .handled }
        .onExitCommand { estado.paleta = false }
    }
}
