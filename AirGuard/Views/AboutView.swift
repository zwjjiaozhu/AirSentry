import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AirSentry")
                        .font(.title2.weight(.semibold))
                    Text("AirSentry｜MacBook Air 高温提醒与系统状态看板")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("菜单栏常驻监控", systemImage: "menubar.rectangle")
                Label("官方热状态指标", systemImage: "thermometer.medium")
                Label("CPU、内存、网络基础读数", systemImage: "gauge.with.dots.needle.67percent")
                Label("高温通知提醒", systemImage: "bell.badge")
            }
            .font(.body)

            Spacer()

            Text("版本 1.0 MVP")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}
