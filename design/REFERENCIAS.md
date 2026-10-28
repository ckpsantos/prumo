# Referências de design do Prumo (pesquisa de 28/10/2026, dados do GitHub/Apple verificados no dia)

## Top 5 para aplicar
1. Sample oficial **Landmarks (Liquid Glass)** + WWDC25 sessão 323 — sidebar/toolbar/inspector com vidro, sem dependência. APIs macOS 26+: glassEffect(_:in:), GlassEffectContainer, glassEffectID, .glass/.glassProminent, ToolbarSpacer, backgroundExtensionEffect. Sempre com `if #available(macOS 26, *)` e fallback `.regularMaterial`.
   https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
2. **Drag and drop nativo** (draggable/dropDestination + Transferable; macOS 26 tem drag de vários itens) — Kanban sem biblioteca.
   https://developer.apple.com/documentation/swiftui/adopting-drag-and-drop-using-swiftui
3. **Propel** (MIT, macOS 15+, Kanban pessoal) — LER, não depender: colunas protegidas, recolhíveis, visão "Atenção" (atrasados/bloqueados). github.com/ran-isenberg/propel
4. **Textual** (MIT, macOS 15) — única dependência que vale: Markdown na evidência/rascunhos/comentários. github.com/gonzalezreal/textual
5. **CodeEdit** (MIT) — LER: janela sidebar/inspector/command palette em SwiftUI. github.com/CodeEditApp/CodeEdit

## Outras referências (só leitura)
- Maccy (MIT): triagem por teclado + busca instantânea · IceCubesApp (AGPL — NÃO copiar código): cards ricos, troca de conta na sidebar · Pika (MIT): acabamento · Enchanted (Apache): composer de rascunho · NetNewsWire: UX Mac, mas é AppKit.
- `inspector(isPresented:)` (macOS 14+) para o painel de detalhe nativo. KeyboardShortcuts (MIT) só se quiser atalho GLOBAL de captura.
- HIG macOS: sidebars, toolbars, materials, keyboards, drag-and-drop. Kits Figma macOS 26: developer.apple.com/design/resources/

## Alertas
- GPL/AGPL (IceCubes, Ice, Loop, Pragma): só referência visual.
- Pow/Settings sem release desde 2024; MarkdownUI em manutenção; Whisky arquivado.
- Propel (18★) e AdvancedKanban (6★) têm pouca adoção; não compilados/testados.
