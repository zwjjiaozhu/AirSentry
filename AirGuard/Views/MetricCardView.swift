import SwiftUI

struct MetricCardView<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    init(
        title: String,
        value: String,
        systemImage: String,
        tint: Color = .accentColor,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            content
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
