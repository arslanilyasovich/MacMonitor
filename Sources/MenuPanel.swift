import SwiftUI
import AppKit

/// Menü çubuğundan açılan panel.
struct MenuPanel: View {
    @ObservedObject var sys: SystemModel
    @ObservedObject var sec: SecurityModel
    @ObservedObject var ui: UIModel
    @ObservedObject var cleaner: CleanerModel
    @ObservedObject var clutter: ClutterModel
    @ObservedObject var lang = Lang.shared
    @Environment(\.openWindow) private var openWindow

    private func goHome() { ui.panelPage = .home }

    var body: some View {
        Group {
            switch ui.panelPage {
            case .home: home
            case .memory:
                VStack(alignment: .leading, spacing: 16) {
                    BackHeader(title: t("Bellek", "Memory")) { ui.panelPage = .home }
                    MemoryDetailView(sys: sys, compact: true)
                }
            case .settings: settings
            case .disk: DiskPanelPage(sys: sys, back: goHome) { openMain(.cleanup) }
            case .cpu: CPUPanelPage(sys: sys, back: goHome)
            case .network: NetworkPanelPage(sys: sys, back: goHome)
            case .battery: BatteryPanelPage(sys: sys, back: goHome)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(ThemeBackground())
        .environment(\.colorScheme, .dark)
        .id(lang.code) // dil değişince tüm metinler yeniden çizilsin
    }

    private func openMain(_ section: AppSection) {
        ui.section = section
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var health: (String, Color) {
        var score = 0
        if sys.pressureLevel >= 4 { score += 2 } else if sys.pressureLevel >= 2 { score += 1 }
        if sys.diskTotal > 0, Double(sys.diskFree) / Double(sys.diskTotal) < 0.1 { score += 1 }
        if sec.issueCount > 0 { score += 1 }
        switch score {
        case 0: return (t("İyi", "Good"), Theme.good)
        case 1: return (t("Dikkat", "Fair"), Theme.warn)
        default: return (t("Kötü", "Poor"), Theme.bad)
        }
    }

    // MARK: Ana sayfa

    private var home: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    (Text(t("Mac Sağlığı: ", "Mac Health: ")).foregroundColor(.white) + Text(health.0).foregroundColor(health.1))
                        .font(.system(size: 24, weight: .bold))
                    Text(sys.machineName).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: sys.machineSymbol)
                    .font(.system(size: 46))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.accent], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 16)
            }
            .padding(.bottom, 4)

            protectionCard.fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                tappable(diskCard, .disk)
                tappable(memoryCard, .memory)
            }.fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                tappable(cpuCard, .cpu)
                tappable(secondCard, sys.battery != nil ? .battery : .memory)
            }.fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                tappable(networkCard, .network)
                devicesCard
            }.fixedSize(horizontal: false, vertical: true)

            if let rec = recommendations(sys: sys, sec: sec, cleaner: cleaner, clutter: clutter).first {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("Bugünün Önerisi", "Today's Recommendation")).font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RecommendationCard(rec: rec) { r in
                        if let p = r.panel { ui.panelPage = p } else if let s = r.section { openMain(s) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            Divider().overlay(Theme.stroke).padding(.top, 4)

            HStack {
                Button { openMain(.smart) } label: {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                        .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                }.buttonStyle(.plain)
                Spacer()
                Button(t("MacMonitor'ü Göster", "Open MacMonitor")) { openMain(.smart) }
                    .buttonStyle(.plain).font(.system(size: 15, weight: .medium))
                Spacer()
                Button { ui.panelPage = .settings } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 17))
                        .frame(width: 26, height: 26)
                        .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                }.buttonStyle(.plain)
            }
        }
    }

    /// Kartın tamamı tıklanınca ayrıntı sayfasına gider (CleanMyMac'teki gibi)
    private func tappable<V: View>(_ card: V, _ page: PanelPage) -> some View {
        card.contentShape(Rectangle()).onTapGesture { ui.panelPage = page }
    }

    private var protectionCard: some View {
        let ok = sec.issueCount == 0
        return Button { openMain(.protection) } label: {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(ok ? Theme.good : Theme.warn)
                        Text(t("Koruma", "Protection")).font(.system(size: 16, weight: .semibold))
                        Spacer()
                        if sec.scanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(ok ? t("Korunuyor", "Protected") : t("\(sec.issueCount) uyarı", "\(sec.issueCount) warnings"),
                                  systemImage: ok ? "checkmark" : "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ok ? Color.white : Theme.warn)
                        }
                    }
                    Text(sec.summary).font(.system(size: 14)).lineLimit(1)
                    Text(t("Son kontrol: ", "Last check: ") + ago(sec.lastScan)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
        }.buttonStyle(.plain)
    }

    private func tile(icon: String, title: String, subtitle: String, subtitleColor: Color = Theme.secondary,
                      detail: String? = nil, link: String? = nil, action: (() -> Void)? = nil) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Theme.accent.opacity(0.85)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(subtitleColor).lineLimit(1)
                        if let detail {
                            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let link, let action {
                    Spacer(minLength: 0)
                    HStack { Spacer(); LinkButton(title: link, action: action) }
                }
            }
        }
    }

    private var diskCard: some View {
        tile(icon: "internaldrive.fill", title: sys.diskName, subtitle: t("Boş: ", "Available: ") + fmtBytes(sys.diskFree),
             link: t("Boşalt", "Free Up")) { openMain(.cleanup) }
    }

    private var memoryCard: some View {
        let color: Color = sys.pressureLevel >= 4 ? Theme.bad : sys.pressureLevel >= 2 ? Theme.warn : Theme.secondary
        return tile(icon: "memorychip.fill", title: t("Bellek", "Memory"),
                    subtitle: t("Baskı: %\(sys.pressurePercent)", "Pressure: \(sys.pressurePercent)%"), subtitleColor: color,
                    link: t("Boşalt", "Free Up")) { ui.panelPage = .memory }
    }

    private var cpuCard: some View {
        tile(icon: "cpu.fill", title: "CPU",
             subtitle: t(String(format: "Yük: %%%.0f", sys.cpu), String(format: "Load: %.0f%%", sys.cpu)),
             subtitleColor: sys.cpu > 85 ? Theme.warn : Theme.secondary,
             detail: t("Açık: ", "Up: ") + duration(sys.uptime))
    }

    @ViewBuilder private var secondCard: some View {
        if let b = sys.battery {
            tile(icon: b.charging ? "battery.100.bolt" : "battery.75", title: t("Pil", "Battery") + " · \(b.percent)%",
                 subtitle: b.charging ? t("Şarj oluyor", "Charging")
                     : b.minutesLeft.map { duration(Double($0) * 60) + t(" kaldı", " remaining") } ?? t("Hesaplanıyor…", "Calculating…"))
        } else if let heavy = sys.top.first {
            tile(icon: "flame.fill", title: t("En Yoğun", "Top Consumer"), subtitle: "\(heavy.name) · \(fmtBytes(heavy.bytes))",
                 subtitleColor: heavy.bytes > 3_000_000_000 ? Theme.bad : Theme.secondary,
                 link: t("Ayrıntı", "Details")) { ui.panelPage = .memory }
        } else {
            tile(icon: "flame.fill", title: t("En Yoğun", "Top Consumer"), subtitle: "—")
        }
    }

    private var networkCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: sys.netSymbol).font(.system(size: 18)).foregroundStyle(Theme.accent.opacity(0.85))
                    Text(sys.netName).font(.system(size: 15, weight: .semibold))
                }
                Label(speed(sys.netUp), systemImage: "arrow.up").font(.system(size: 13).monospacedDigit())
                Label(speed(sys.netDown), systemImage: "arrow.down").font(.system(size: 13).monospacedDigit())
                if let r = sys.speedResult {
                    Text(r).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.good)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    if sys.speedTesting {
                        ProgressView().controlSize(.small)
                        Text(t("Ölçülüyor…", "Testing…")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    } else {
                        LinkButton(title: t("Hız Testi", "Test Speed")) { sys.runSpeedTest() }
                    }
                }
            }
        }
    }

    private var devicesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Bağlı Cihazlar", "Connected Devices")).font(.system(size: 15, weight: .semibold))
                if sys.devices.isEmpty {
                    Text(t("Bluetooth cihazı yok", "No Bluetooth devices")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                ForEach(sys.devices.prefix(3)) { d in
                    HStack(spacing: 8) {
                        Image(systemName: d.symbol).foregroundStyle(Theme.secondary).frame(width: 18)
                        Text(d.name).font(.system(size: 13)).lineLimit(1).foregroundStyle(Theme.secondary)
                        Spacer(minLength: 4)
                        if let b = d.battery { Text(b).font(.system(size: 13, weight: .semibold)) }
                    }
                }
            }
        }
    }

    // MARK: Ayarlar

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            BackHeader(title: t("Ayarlar", "Settings")) { ui.panelPage = .home }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Dil", "Language")).font(.system(size: 14, weight: .medium))
                    LanguagePicker()
                }
            }.fixedSize(horizontal: false, vertical: true)
            Card {
                Toggle(isOn: $sys.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Açılışta otomatik başlat", "Launch at login")).font(.system(size: 14, weight: .medium))
                        Text(t("Mac açıldığında menü çubuğunda belirir", "Shows in the menu bar when your Mac starts"))
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }.toggleStyle(.switch)
            }.fixedSize(horizontal: false, vertical: true)
            Card {
                HStack {
                    Text(t("Etkinlik Monitörü", "Activity Monitor")).font(.system(size: 14, weight: .medium))
                    Spacer()
                    SecondaryButton(title: t("Aç", "Open")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacMonitor 2.3").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Signature()
                }
                Spacer()
                Button(t("MacMonitor'den Çık", "Quit MacMonitor")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(Theme.bad).font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

/// Bellek ayrıntısı: halka grafik, baskı/swap kartları, en çok kullananlar.
struct MemoryDetailView: View {
    @ObservedObject var sys: SystemModel
    var compact = false

    private let appColor = Theme.accent
    private let wiredColor = Theme.accent2
    private let compColor = Color(red: 0.55, green: 0.62, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                ZStack {
                    let total = Double(sys.memTotal)
                    Donut(segments: [(Double(sys.memApp) / total, appColor),
                                     (Double(sys.memWired) / total, wiredColor),
                                     (Double(sys.memCompressed) / total, compColor)],
                          lineWidth: compact ? 20 : 24)
                    VStack(spacing: 2) {
                        (Text(String(format: "%.1f", Double(sys.memFree) / 1_073_741_824)).font(.system(size: compact ? 30 : 38, weight: .bold))
                            + Text(" GB").font(.system(size: 15, weight: .medium)))
                        Text(t("\(fmtBytes(sys.memTotal)) içinden boş", "free of \(fmtBytes(sys.memTotal))"))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(width: compact ? 170 : 210, height: compact ? 170 : 210)

                VStack(alignment: .leading, spacing: 14) {
                    legend(t("Uygulama", "App"), sys.memApp, appColor)
                    legend(t("Sabit (wired)", "Wired"), sys.memWired, wiredColor)
                    legend(t("Sıkıştırılmış", "Compressed"), sys.memCompressed, compColor)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                infoCard(title: t("Baskı", "Pressure"), value: t("%\(sys.pressurePercent)", "\(sys.pressurePercent)%"),
                         text: sys.pressureLevel >= 4 ? t("Bellek çok dolu, uygulamalar kapanabilir.", "Memory is full, apps may be killed.") :
                               sys.pressureLevel >= 2 ? t("Bellek zorlanıyor, ağır uygulamaları kapat.", "Memory is strained, quit heavy apps.") :
                               t("Mac'in yeni işlere hazır.", "Your Mac is ready for more tasks."),
                         color: sys.pressureLevel >= 4 ? Theme.bad : sys.pressureLevel >= 2 ? Theme.warn : .white)
                infoCard(title: "Swap", value: fmtBytes(sys.swapUsed),
                         text: t("RAM dolunca diskte kullanılan ek alan.", "Disk space used when RAM is full."), color: .white)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(t("En Çok Kullananlar", "Top Consumers")).font(.system(size: 16, weight: .semibold))
                Spacer()
                SecondaryButton(title: sys.maintenanceRunning ? t("Boşaltılıyor…", "Freeing…") : t("RAM'i Boşalt", "Free Up RAM"),
                                disabled: sys.maintenanceRunning) {
                    sys.runMaintenance(["purge"])
                }
            }
            VStack(spacing: 8) {
                HStack {
                    Text(t("İşlem", "Process"))
                    Spacer()
                    Text(t("Kullanım", "Usage")).frame(width: 80, alignment: .trailing)
                    Color.clear.frame(width: 84, height: 1)
                }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                ForEach(sys.top) { p in
                    HStack(spacing: 10) {
                        AppIcon(path: p.iconPath, size: 26)
                        Text(p.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        if p.count > 1 { Text("×\(p.count)").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        Spacer()
                        Text(fmtBytes(p.bytes)).font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(p.bytes > 3_000_000_000 ? Theme.bad : Theme.secondary)
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
            if let r = sys.maintenanceResult {
                Text(r).font(.system(size: 12)).foregroundStyle(Theme.good)
            }
        }
    }

    private func legend(_ title: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Text(fmtBytes(bytes)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
        }
    }

    private func infoCard(title: String, value: String, text: String, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(color).monospacedDigit()
                }
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
