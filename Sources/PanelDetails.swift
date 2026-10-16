import SwiftUI
import AppKit

/// Son 60 ölçümün (2 sn aralıkla ~2 dakika) dolgu alanlı çizgi grafiği.
struct LineChart: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let peak = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(v / peak, 1))))
            }
            ZStack {
                // ızgara
                Path { p in
                    for i in 1..<4 {
                        let y = geo.size.height * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                if points.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: points[0])
                        points.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .shadow(color: color.opacity(0.6), radius: 4)
                }
            }
        }
    }
}

/// Başlık + değer + açıklama + isteğe bağlı bağlantı içeren küçük kart.
struct InfoTile: View {
    let title: String
    let value: String
    var valueColor: Color = .white
    let text: String
    var link: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(valueColor).monospacedDigit()
                }
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if let link, let action {
                    Spacer(minLength: 0)
                    HStack { Spacer(); LinkButton(title: link, action: action) }
                }
            }
        }
    }
}

// MARK: - Disk

struct DiskPanelPage: View {
    @ObservedObject var sys: SystemModel
    let back: () -> Void
    let openCleanup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(title: sys.diskName, back: back)
            HStack(spacing: 22) {
                ZStack {
                    let total = Double(max(sys.diskTotal, 1))
                    Donut(segments: sys.diskParts.map { (Double($0.bytes ?? 0) / total, $0.color) }, lineWidth: 18)
                    VStack(spacing: 2) {
                        Text(fmtBytes(sys.diskFree)).font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                        Text(t("\(fmtBytes(sys.diskTotal)) içinden boş", "free of \(fmtBytes(sys.diskTotal))"))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 26)
                }
                .frame(width: 160, height: 160)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(sys.diskParts) { part in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(part.color).frame(width: 9, height: 9).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(part.title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                Text(part.bytes.map { fmtBytes($0) } ?? t("Hesaplanıyor…", "Calculating…"))
                                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                let smartOK = sys.diskSmart?.lowercased().contains("verified") ?? true
                InfoTile(title: t("Disk sağlığı", "Drive health"),
                         value: sys.diskSmart == nil ? "…" : (smartOK ? t("İyi", "Good") : t("Sorun", "Issue")),
                         valueColor: smartOK ? Theme.good : Theme.bad,
                         text: smartOK ? t("SMART durumu doğrulandı. Disk sorunsuz çalışıyor.", "SMART status verified. The drive is working fine.")
                                       : t("SMART bir sorun bildiriyor. Yedeğini al.", "SMART reports a problem. Back up your data."))
                InfoTile(title: t("Çöp Kutusu", "Trash"),
                         value: sys.trashSize.map { fmtBytes($0) } ?? "?",
                         text: t("Silinen dosyalar burada yer kaplamaya devam eder.", "Deleted files keep using space here."),
                         link: (sys.trashSize ?? 1) > 0 ? t("Boşalt", "Empty") : nil) { sys.emptyTrash() }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                SecondaryButton(title: t("Gereksiz dosyaları temizle", "Clean up junk"), action: openCleanup)
            }
        }
        .onAppear { sys.loadDiskDetails() }
    }
}

// MARK: - CPU

struct CPUPanelPage: View {
    @ObservedObject var sys: SystemModel
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(title: sys.chipName.isEmpty ? "CPU" : sys.chipName, back: back)
            HStack(spacing: 16) {
                LineChart(values: sys.cpuHistory, color: Theme.accent, maxValue: 100)
                    .frame(height: 120)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.2)))
                VStack(alignment: .leading, spacing: 10) {
                    stat(String(format: "%.1f %%", max(0, 100 - sys.cpu)), t("Boşta", "Idle"), Theme.secondary)
                    stat(String(format: "%.1f %%", sys.cpuUser), t("Kullanıcı", "User"), Theme.accent)
                    stat(String(format: "%.1f %%", sys.cpuSystem), t("Sistem", "System"), Theme.accent2)
                }
                .frame(width: 100, alignment: .leading)
            }
            HStack(spacing: 12) {
                let days = Int(sys.uptime / 86_400)
                InfoTile(title: t("Açık kalma", "Uptime"), value: duration(sys.uptime),
                         valueColor: days >= 7 ? Theme.warn : .white,
                         text: days >= 7 ? t("Bir haftayı geçti. Ara sıra yeniden başlatmak iyi gelir.", "Over a week now. Restart your Mac once in a while.")
                                         : t("Yakın zamanda yeniden başlatılmış.", "Restarted recently."))
                InfoTile(title: t("Yük", "Load"), value: String(format: "%.0f %%", sys.cpu),
                         valueColor: sys.cpu > 85 ? Theme.warn : .white,
                         text: sys.cpu > 85 ? t("İşlemci çok meşgul. Aşağıdaki listeye bak.", "The CPU is very busy. Check the list below.")
                                            : t("İşlemci rahat çalışıyor.", "The CPU is running comfortably."))
            }
            .fixedSize(horizontal: false, vertical: true)
            ConsumerList(sys: sys, rows: sys.topCPU, valueTitle: t("Kullanım, %", "Usage, %")) { p in
                String(format: "%.1f", p.cpu)
            } highlight: { $0.cpu > 80 }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// "En çok kullananlar" listesi: CPU ve bellek sayfalarında ortak.
struct ConsumerList: View {
    @ObservedObject var sys: SystemModel
    let rows: [ProcRow]
    let valueTitle: String
    let value: (ProcRow) -> String
    let highlight: (ProcRow) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("En Çok Kullananlar", "Top Consumers")).font(.system(size: 16, weight: .semibold))
            HStack {
                Text(t("İşlem", "Process"))
                Spacer()
                Text(valueTitle).frame(width: 80, alignment: .trailing)
                Color.clear.frame(width: 84, height: 1)
            }
            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if rows.isEmpty {
                Text(t("Ölçülüyor…", "Measuring…")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach(rows) { p in
                HStack(spacing: 10) {
                    AppIcon(path: p.iconPath, size: 26)
                    Text(p.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    if p.count > 1 { Text("×\(p.count)").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                    Spacer()
                    Text(value(p)).font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(highlight(p) ? Theme.bad : Theme.secondary)
                        .frame(width: 80, alignment: .trailing)
                    if p.quittable {
                        Button(sys.pendingQuit == p.id ? t("Emin misin?", "Sure?") : t("Kapat", "Quit")) { sys.quit(p) }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(sys.pendingQuit == p.id ? Theme.bad : Theme.accent)
                            .frame(width: 84, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: 84, height: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Ağ

struct NetworkPanelPage: View {
    @ObservedObject var sys: SystemModel
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(title: t("Ağ", "Network"), back: back)
            Card {
                HStack(spacing: 12) {
                    Image(systemName: sys.netSymbol).font(.system(size: 22)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sys.netName).font(.system(size: 15, weight: .semibold))
                        Text(sys.netKind == "vpn" ? t("VPN üzerinden bağlı — trafiğin şifreli", "Connected via VPN — traffic is encrypted")
                             : t("Bağlantı etkin", "Connection active"))
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                traffic(t("İndirme", "Download"), total: sys.netTotalDown, now: sys.netDown, history: sys.netDownHistory, color: Theme.accent)
                traffic(t("Yükleme", "Upload"), total: sys.netTotalUp, now: sys.netUp, history: sys.netUpHistory, color: Theme.bad)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(t("Bağlantını Test Et", "Test Your Connection")).font(.system(size: 16, weight: .semibold))
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: min((sys.speedDownMbps ?? 0) / 1000, 1))
                        .stroke(AngularGradient(colors: [Theme.accent2, Theme.accent], center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                    VStack(spacing: 2) {
                        if sys.speedTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(sys.speedDownMbps.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 26, weight: .bold)).monospacedDigit()
                            Text("Mbps").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    if let up = sys.speedUpMbps {
                        Label(String(format: "%.1f Mbps", up), systemImage: "arrow.up").font(.system(size: 13).monospacedDigit())
                    }
                    if let rpm = sys.speedRPM {
                        Text(t("Tepki: \(rpm) RPM", "Responsiveness: \(rpm) RPM")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Text(t("Nasıl çalışır", "How it works")).font(.system(size: 13, weight: .semibold))
                    Text(t("macOS'un kendi networkQuality aracı Apple sunucularına bağlanıp hızını ölçer.",
                           "macOS's built-in networkQuality tool measures your speed against Apple's servers."))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    SecondaryButton(title: sys.speedTesting ? t("Ölçülüyor…", "Testing…") : t("Testi Başlat", "Start Test"),
                                    disabled: sys.speedTesting) { sys.runSpeedTest() }
                }
            }
        }
    }

    private func traffic(_ title: String, total: UInt64, now: Double, history: [Double], color: Color) -> some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).padding([.top, .horizontal], 12)
                HStack {
                    Text(fmtBytes(total)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(speed(now)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 12)
                LineChart(values: history, color: color).frame(height: 54)
            }
        }
    }
}

// MARK: - Pil

struct BatteryPanelPage: View {
    @ObservedObject var sys: SystemModel
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackHeader(title: t("Pil", "Battery"), back: back)
            if let b = sys.battery {
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.06), lineWidth: 16)
                        Circle().trim(from: 0, to: Double(b.percent) / 100)
                            .stroke(b.percent < 20 ? Theme.bad : Theme.good, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(b.percent)%").font(.system(size: 34, weight: .bold))
                    }
                    .frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(b.charging ? t("Şarj oluyor", "Charging") : (b.percent >= 100 ? t("Tam dolu", "Fully charged") : t("Pilden çalışıyor", "On battery")))
                            .font(.system(size: 16, weight: .semibold))
                        if let m = b.minutesLeft { Text(duration(Double(m) * 60) + t(" kaldı", " remaining")).foregroundStyle(Theme.secondary) }
                        if let c = sys.batteryDetail?.cycles {
                            Text("\(c) / 1000").font(.system(size: 20, weight: .semibold)).padding(.top, 6)
                            Text(t("şarj döngüsü", "charge cycles")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                HStack(spacing: 12) {
                    let health = sys.batteryDetail?.healthPercent
                    InfoTile(title: t("Sağlık", "Health"), value: health.map { "%\($0)" } ?? "—",
                             valueColor: (health ?? 100) < 80 ? Theme.warn : Theme.good,
                             text: (health ?? 100) < 80 ? t("Pil kapasitesi belirgin şekilde düşmüş.", "Battery capacity has noticeably dropped.")
                                                        : t("Pil iyi durumda.", "Battery is in good condition."))
                    let temp = sys.batteryDetail?.temperature
                    InfoTile(title: t("Sıcaklık", "Temperature"), value: temp.map { String(format: "%.0f°C", $0) } ?? "—",
                             valueColor: (temp ?? 0) > 40 ? Theme.warn : .white,
                             text: (temp ?? 0) > 40 ? t("Pil ısınmış.", "The battery is warm.") : t("Normal aralıkta.", "Within the normal range."))
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(t("Bu Mac'te pil yok.", "This Mac has no battery.")).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - Öneri kartı

struct RecommendationCard: View {
    let rec: Recommendation
    let perform: (Recommendation) -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: rec.icon).font(.system(size: 20)).foregroundStyle(rec.color)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(rec.color.opacity(0.14)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.title).font(.system(size: 14, weight: .semibold))
                    Text(rec.text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if let action = rec.action {
                        HStack {
                            Spacer()
                            SecondaryButton(title: action) { perform(rec) }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }
}
