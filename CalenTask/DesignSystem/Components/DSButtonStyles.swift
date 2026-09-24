import SwiftUI

/// E9 — hover (macOS) e pressed vivono nei token, non nelle viste.
private struct DSButtonChrome: ViewModifier {
    let isPressed: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.04 : 0)
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.dsQuick, value: isPressed)
            #if os(macOS)
            .onHover { hovering in
                withAnimation(.dsQuick) { isHovering = hovering }
            }
            #endif
    }
}

struct DSProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsRowTitle)
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.s + 2)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: DS.Radius.small))
            .foregroundStyle(.white)
            .modifier(DSButtonChrome(isPressed: configuration.isPressed))
    }
}

struct DSGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsRowTitle)
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.s + 2)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.small))
            .foregroundStyle(Color.accentColor)
            .modifier(DSButtonChrome(isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == DSProminentButtonStyle {
    static var dsProminent: DSProminentButtonStyle { DSProminentButtonStyle() }
}

extension ButtonStyle where Self == DSGhostButtonStyle {
    static var dsGhost: DSGhostButtonStyle { DSGhostButtonStyle() }
}

#Preview {
    HStack(spacing: DS.l) {
        Button("Salva") {}.buttonStyle(.dsProminent)
        Button("Annulla") {}.buttonStyle(.dsGhost)
    }
    .padding()
}
