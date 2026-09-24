import SwiftUI

// MARK: - Masonry con span di colonna

/// Quante colonne occupa una card (1…N). La passa la card via layoutValue.
struct WidgetSpanKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

extension View {
    func widgetSpan(_ span: Int) -> some View {
        layoutValue(key: WidgetSpanKey.self, value: span)
    }
}

/// Masonry a colonne CON span (D94): impacchetta le card senza lasciare
/// buchi tra blocchi di altezza diversa, e permette a una card di occupare
/// due colonne o l'intera riga. Posa ogni card (in ordine) nel gruppo di
/// colonne libero più in alto, a sinistra a parità.
struct MasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return CGSize(width: width, height: solve(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = solve(subviews, width: bounds.width).frames
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func solve(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let cols = max(columns, 1)
        guard width > 0 else {
            return (Array(repeating: .zero, count: subviews.count), 0)
        }
        let colWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        var bottoms = [CGFloat](repeating: 0, count: cols)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for subview in subviews {
            let span = min(max(subview[WidgetSpanKey.self], 1), cols)
            let cardWidth = colWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            let height = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height

            // Colonna di partenza che lascia la card più in alto possibile.
            var bestCol = 0
            var bestY = CGFloat.greatestFiniteMagnitude
            for start in 0...(cols - span) {
                var y: CGFloat = 0
                for column in start..<(start + span) { y = max(y, bottoms[column]) }
                if y < bestY - 0.5 { bestY = y; bestCol = start }
            }

            let x = CGFloat(bestCol) * (colWidth + spacing)
            frames.append(CGRect(x: x, y: bestY, width: cardWidth, height: height))
            let newBottom = bestY + height + spacing
            for column in bestCol..<(bestCol + span) { bottoms[column] = newBottom }
        }
        return (frames, max((bottoms.max() ?? 0) - spacing, 0))
    }
}

// MARK: - Stato del drag (disaccoppiato dal rendering per fluidità)

/// Stato del trascinamento in un tipo a riferimento osservabile: così
/// aggiornare la posizione del puntatore (ad ogni pixel) rigenera SOLO il
/// fantasma fluttuante, non l'intera griglia di card (grafici inclusi). È
/// la differenza tra scattoso e fluido.
@Observable
final class WidgetDragModel {
    var dragging: DashboardWidget?
    var location: CGPoint = .zero
    /// Frame "a riposo" di ogni card, nello spazio della griglia. Scritto dai
    /// GeometryReader, letto solo nel gesto e nel fantasma — mai nel corpo
    /// della griglia, per non innescare re-render.
    var frames: [DashboardWidget: CGRect] = [:]
}

// MARK: - Griglia riordinabile

struct ReorderableWidgetGrid<Content: View>: View {
    let items: [DashboardWidget]
    let columns: Int
    var spacing: CGFloat = DS.xl
    let spanFor: (DashboardWidget) -> Int
    @ViewBuilder let content: (DashboardWidget) -> Content
    let onReorder: ([DashboardWidget]) -> Void

    /// Ordine vivo, mutato durante il trascinamento; committato a fine drag.
    @State private var order: [DashboardWidget] = []
    @State private var model = WidgetDragModel()

    private let space = "reorderWidgetGrid"

    var body: some View {
        MasonryLayout(columns: max(columns, 1), spacing: spacing) {
            ForEach(order) { widget in
                cell(widget)
                    .widgetSpan(spanFor(widget))
            }
        }
        .coordinateSpace(name: space)
        .overlay(alignment: .topLeading) {
            DraggedWidgetGhost(model: model, content: content)
        }
        .onAppear { order = items }
        .onChange(of: items) { _, new in
            // Cambi esterni (mostra/nascondi, larghezza, switch colonne)
            // mentre non sto trascinando.
            if model.dragging == nil { order = new }
        }
    }

    private func cell(_ widget: DashboardWidget) -> some View {
        content(widget)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(model.dragging == widget ? 0 : 1)
            .overlay {
                if model.dragging == widget {
                    RoundedRectangle(cornerRadius: DS.Radius.medium)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .background(
                GeometryReader { geo in
                    let frame = geo.frame(in: .named(space))
                    Color.clear
                        .onAppear { model.frames[widget] = frame }
                        .onChange(of: frame) { _, new in model.frames[widget] = new }
                }
            )
            .contentShape(Rectangle())
            // .simultaneousGesture (non .gesture): così il trascinamento
            // riceve eventi CONTINUI anche partendo sopra un figlio
            // interattivo (grafici, righe, bottoni) — altrimenti il figlio
            // intercetta gli eventi e il riordino va "a salti" senza
            // animazione. I tap (soglia < 8pt) restano ai figli: aprire
            // un'attività continua a funzionare.
            .simultaneousGesture(dragGesture(widget))
    }

    /// Si afferra il widget da un'area non interattiva (intestazione, grafico,
    /// margini) e lo si trascina. macOS: soglia di 8pt (lo scroll è a rotella,
    /// nessun conflitto). iOS: pressione lunga poi trascina, per non litigare
    /// con lo scroll.
    private func dragGesture(_ widget: DashboardWidget) -> some Gesture {
        #if os(macOS)
        return DragGesture(minimumDistance: 8, coordinateSpace: .named(space))
            .onChanged { value in update(widget, at: value.location) }
            .onEnded { _ in finish() }
        #else
        return LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    update(widget, at: drag.location)
                }
            }
            .onEnded { _ in finish() }
        #endif
    }

    private func update(_ widget: DashboardWidget, at location: CGPoint) {
        if model.dragging != widget { model.dragging = widget }
        model.location = location
        guard let dragging = model.dragging,
              let target = order.first(where: {
                  $0 != dragging && (model.frames[$0]?.contains(location) ?? false)
              })
        else { return }
        let next = DashboardLayout.reordering(order, moving: dragging, to: target)
        if next != order {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                order = next
            }
        }
    }

    private func finish() {
        guard model.dragging != nil else { return }
        onReorder(order)
        model.dragging = nil
        model.location = .zero
    }
}

/// Il fantasma che segue il puntatore. Vive in una vista a sé: legge
/// `location` del modello, quindi è L'UNICA cosa che si ridisegna mentre
/// trascini — la griglia resta ferma finché non scatta un riordino.
private struct DraggedWidgetGhost<Content: View>: View {
    let model: WidgetDragModel
    @ViewBuilder let content: (DashboardWidget) -> Content

    var body: some View {
        if let widget = model.dragging, let home = model.frames[widget] {
            content(widget)
                .frame(width: home.width, height: home.height)
                .scaleEffect(1.02)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .position(model.location)
                .allowsHitTesting(false)
        }
    }
}
