import AppKit
import SwiftUI

final class Delegado: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Gancho para screenshots: PRUMO_TAMANHO=1400x900 redimensiona a janela ao abrir.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let t = ProcessInfo.processInfo.environment["PRUMO_TAMANHO"]?.split(separator: "x"), t.count == 2,
              let w = Double(t[0]), let h = Double(t[1]) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let j = NSApp.windows.first(where: { $0.isVisible }) else { return }
            j.setFrame(NSRect(x: j.frame.minX, y: j.frame.minY, width: w, height: h), display: true)
        }
    }
}

/// Gancho para screenshots: PRUMO_APARENCIA=escura|clara força a aparência só deste app.
private let aparencia: ColorScheme? = {
    switch ProcessInfo.processInfo.environment["PRUMO_APARENCIA"] {
    case "escura": .dark
    case "clara": .light
    default: nil
    }
}()

@main
struct AssistenteApp: App {
    @NSApplicationDelegateAdaptor(Delegado.self) var delegado
    @StateObject private var estado = Estado()

    var body: some Scene {
        Window("Prumo", id: "principal") {
            Principal(estado: estado)
                .frame(minWidth: 1100, minHeight: 640)
                .preferredColorScheme(aparencia)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Tarefa") {
                Button("Buscar…") { estado.paleta = true }.keyboardShortcut("k")
                Divider()
                let semItem = estado.itemAberto == nil || estado.paleta
                Button("Mover para A fazer") { estado.moverAberto("a_fazer") }.keyboardShortcut("1").disabled(semItem)
                Button("Mover para Aguardando") { estado.moverAberto("aguardando") }.keyboardShortcut("2").disabled(semItem)
                Button("Mover para Concluído") { estado.moverAberto("concluido") }.keyboardShortcut("3").disabled(semItem)
                Button("Cancelar tarefa") { estado.moverAberto("cancelado") }
                    .keyboardShortcut("4").disabled(semItem)  // ⌘4: não dispara dentro de campo de texto como o ⌘⌫
            }
        }
    }
}
