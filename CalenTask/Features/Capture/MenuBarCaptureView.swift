#if os(macOS)
import SwiftUI
import SwiftData

/// Always-available capture point in the macOS menu bar.
struct MenuBarCaptureView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cattura rapida")
                .font(.dsSectionTitle)
                .padding(.horizontal, DS.l)
                .padding(.top, DS.l)
            QuickCaptureView()
        }
        .frame(width: 360)
    }
}

#Preview {
    MenuBarCaptureView()
        .modelContainer(PreviewSampleData.make().container)
}
#endif
