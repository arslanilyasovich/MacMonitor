import SwiftUI
import AppKit

/// Kenar menülü ana pencere.
struct MainView: View {
    @ObservedObject var sys: SystemModel
    @ObservedObject var cleaner: CleanerModel
    @ObservedObject var sec: SecurityModel
    @ObservedObject var apps: AppsModel
    @ObservedObject var clutter: ClutterModel
    @ObservedObject var ui: UIModel
    @ObservedObject var lens: SpaceLensModel
    @ObservedObject var timeMachine: TimeMachineModel
    @ObservedObject var leftovers: LeftoversModel
    @ObservedObject var lang = Lang.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(ui: ui)
            Group {
                switch ui.section {
                case .smart: SmartCareView(sys: sys, cleaner: cleaner, sec: sec, apps: apps, clutter: clutter, ui: ui)
                case .cleanup: CleanupView(c: cleaner)
                case .clutter: ClutterView(cl: clutter)
                case .protection: ProtectionView(sec: sec)
                case .performance: PerformanceView(sys: sys, ui: ui)
                case .apps: AppsView(apps: apps)
                case .spaceLens: SpaceLensView(lens: lens)
                case .tools: ToolsView(tm: timeMachine, leftovers: leftovers, ui: ui, clutter: clutter)
                case .activity: ActivityView(sys: sys, sec: sec, cleaner: cleaner, clutter: clutter, ui: ui)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 660)
        .background(ThemeBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .id(lang.code) // dil değişince tüm metinler yeniden çizilsin
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

struct Sidebar: View {
    @ObservedObject var ui: UIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 8)
                VStack(alignment: .leading, spacing: 1) {
                    (Text("Mac").foregroundColor(.white) + Text("Monitor").foregroundColor(Theme.accent))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Signature(size: 10)
                }
            }
            .padding(.top, 40).padding(.bottom, 18).padding(.horizontal, 6)

            item(.smart)
            group(t("Temizlik", "Cleanup"))
            item(.cleanup)
            item(.clutter)
            item(.spaceLens)
            group(t("Koruma", "Protection"))
            item(.protection)
            group(t("Hız", "Speed"))
            item(.performance)
            group(t("Uygulamalar", "Applications"))
            item(.apps)
            Spacer()
            item(.tools)
            item(.activity)
                .padding(.bottom, 10)
            LanguagePicker().padding(.horizontal, 6).padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 230)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }

    private func group(_ title: String) -> some View {
        Text(title.uppercased(with: Locale(identifier: Lang.shared.code)))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.top, 14).padding(.bottom, 4).padding(.horizontal, 10)
    }

    private func item(_ s: AppSection) -> some View {
        let selected = ui.section == s
        return Button { ui.section = s } label: {
            HStack(spacing: 10) {
                Image(systemName: s.icon).frame(width: 20).foregroundStyle(selected ? Theme.accent : Theme.secondary)
                Text(s.title)
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.13) : .clear))
            .overlay(alignment: .leading) {
                if selected { RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3, height: 18) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Akıllı Bakım

struct SmartCareView: View {
    @ObservedObject var sys: SystemModel
    @ObservedObject var cleaner: CleanerModel
    @ObservedObject var sec: SecurityModel
    @ObservedObject var apps: AppsModel
    @ObservedObject var clutter: ClutterModel
    @ObservedObject var ui: UIModel

    private let cleanColors = [Color(red: 0.40, green: 0.95, blue: 0.75), Color(red: 0.08, green: 0.50, blue: 0.45)]
    private let protectColors = [Color(red: 0.45, green: 0.85, blue: 1.0), Color(red: 0.10, green: 0.35, blue: 0.75)]
    private let speedColors = [Color(red: 1.0, green: 0.80, blue: 0.40), Color(red: 0.85, green: 0.45, blue: 0.15)]
    private let appColors = [Color(red: 0.55, green: 0.70, blue: 1.0), Color(red: 0.20, green: 0.30, blue: 0.80)]
    private let clutterColors = [Color(red: 0.75, green: 0.85, blue: 0.95), Color(red: 0.30, green: 0.40, blue: 0.55)]

    private var perfTips: [String] {
        var tips: [String] = []
        if sys.pressureLevel >= 2 { tips.append(t("RAM baskısı yüksek", "High memory pressure")) }
        if let h = sys.top.first, h.bytes > 3_000_000_000 { tips.append(t("\(h.name) çok RAM kullanıyor", "\(h.name) uses a lot of RAM")) }
        if sys.diskTotal > 0, Double(sys.diskFree) / Double(sys.diskTotal) < 0.15 { tips.append(t("Disk dolmak üzere", "Disk is almost full")) }
        return tips
    }

    var body: some View {
        VStack(spacing: 22) {
            switch ui.smartPhase {
            case .idle: idle
            case .scanning: scanning
            case .done, .running, .finished: results
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) { Signature(size: 12).padding(22) }
    }

    private var idle: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 230, height: 230)
                .shadow(color: Theme.accent.opacity(0.5), radius: 40)
            Text(t("Mac'ine hızlı bir bakım yapalım", "Let's give your Mac a quick checkup")).font(.system(size: 30, weight: .bold))
            Text(t("Gereksiz dosyaları, güvenlik sorunlarını, yavaşlatanları ve dağınıklığı tek taramada bulur.",
                   "Finds junk, security issues, slowdowns and clutter in a single scan."))
                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            Spacer()
            BigRoundButton(title: t("Tara", "Scan")) {
                ui.startSmartScan(cleaner: cleaner, sec: sec, clutter: clutter, apps: apps)
            }
        }
    }

    private var scanning: some View {
        VStack(spacing: 22) {
            Text(t("İnceleniyor…", "Scanning…")).font(.system(size: 30, weight: .bold)).padding(.top, 20)
            Text(t("Biraz bekle, her köşeye bakıyoruz.", "Hang on, we're checking every corner."))
                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            Spacer()
            HStack(spacing: 44) {
                ScanTile(title: t("Temizlik", "Cleanup"), symbol: "internaldrive.fill", colors: cleanColors,
                         status: cleaner.busy ? t("Gereksiz dosyalar aranıyor…", "Looking for junk…")
                             : t("\(fmtBytes(cleaner.total)) bulundu", "\(fmtBytes(cleaner.total)) found"),
                         done: !cleaner.busy)
                ScanTile(title: t("Koruma", "Protection"), symbol: "checkmark.shield.fill", colors: protectColors,
                         status: sec.scanning ? t("İmzalar kontrol ediliyor…", "Checking signatures…") : t("Bitti", "Done"),
                         done: !sec.scanning)
                ScanTile(title: t("Dağınıklık", "Clutter"), symbol: "doc.on.doc.fill", colors: clutterColors,
                         status: clutter.scanning ? t("Büyük ve kopya dosyalar…", "Large and duplicate files…") : t("Bitti", "Done"),
                         done: !clutter.scanning)
            }
            Spacer()
            BigRoundButton(title: "", busy: true) {}
        }
    }

    private var results: some View {
        VStack(spacing: 20) {
            Text(ui.smartPhase == .finished ? t("Bakım tamamlandı", "All done")
                 : t("Görevler hazır. İşte bulduklarımız:", "Your tasks are ready. Here's what we found:"))
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 10)
            if ui.smartPhase == .finished, let r = cleaner.lastResult {
                Text(r).font(.system(size: 14)).foregroundStyle(Theme.good)
            }

            HStack(spacing: 14) {
                ResultCard(title: t("Temizlik", "Cleanup"), value: t("\(fmtBytes(cleaner.selectedTotal)) gereksiz", "\(fmtBytes(cleaner.selectedTotal)) of junk"),
                           subtitle: t("temizlenecek", "to clean"), symbol: "internaldrive.fill", colors: cleanColors,
                           checked: $ui.smartCleanup) { ui.section = .cleanup }
                ResultCard(title: t("Koruma", "Protection"),
                           value: sec.issueCount == 0 ? t("Tehdit yok", "No threats") : t("\(sec.issueCount) uyarı", "\(sec.issueCount) warnings"),
                           subtitle: sec.issueCount == 0 ? t("her şey doğrulandı", "everything verified") : t("incelemen gerekiyor", "needs your review"),
                           symbol: "checkmark.shield.fill", colors: protectColors) { ui.section = .protection }
                ResultCard(title: t("Performans", "Performance"),
                           value: perfTips.isEmpty ? t("Her şey yolunda", "All good") : t("\(perfTips.count) öneri", "\(perfTips.count) tips"),
                           subtitle: perfTips.first ?? t("RAM ve disk normal", "RAM and disk are fine"),
                           symbol: "bolt.fill", colors: speedColors) { ui.section = .performance }
            }
            HStack(spacing: 14) {
                ResultCard(title: t("Uygulamalar", "Applications"), value: t("\(apps.apps.count) uygulama", "\(apps.apps.count) apps"),
                           subtitle: apps.totalSize > 0 ? t("toplam \(fmtBytes(apps.totalSize))", "\(fmtBytes(apps.totalSize)) total")
                               : t("kaldırıcıda incele", "review in uninstaller"),
                           symbol: "square.grid.2x2.fill", colors: appColors) { ui.section = .apps }
                ResultCard(title: t("Dağınıklık", "Clutter"),
                           value: t("\(clutter.big.count) büyük · \(clutter.dups.count) kopya", "\(clutter.big.count) large · \(clutter.dups.count) duplicates"),
                           subtitle: clutter.dupWaste > 0 ? t("\(fmtBytes(clutter.dupWaste)) kopya israfı", "\(fmtBytes(clutter.dupWaste)) wasted on copies")
                               : t("büyük dosyalar listelendi", "large files listed"),
                           symbol: "folder.fill", colors: clutterColors) { ui.section = .clutter }
            }

            Spacer()
            HStack(spacing: 30) {
                if ui.smartPhase == .finished {
                    SecondaryButton(title: t("Baştan başla", "Start over")) { ui.smartPhase = .idle }
                } else {
                    SecondaryButton(title: t("Yeniden tara", "Rescan")) {
                        ui.startSmartScan(cleaner: cleaner, sec: sec, clutter: clutter, apps: apps)
                    }
                    BigRoundButton(title: t("Çalıştır", "Run"), busy: ui.smartPhase == .running) { ui.runSmart(cleaner: cleaner) }
                }
            }
        }
    }
}

struct ScanTile: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let status: String
    let done: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(colors[0].opacity(0.35), lineWidth: 1.5))
                Image(systemName: symbol).font(.system(size: 58))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .shadow(color: colors[0].opacity(0.6), radius: 18)
            }
            .frame(width: 140, height: 140)
            .opacity(done ? 1 : 0.75)
            Text(title).font(.system(size: 17, weight: .semibold))
            HStack(spacing: 6) {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(status).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct ResultCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    var checked: Binding<Bool>? = nil
    var review: (() -> Void)? = nil

    init(title: String, value: String, subtitle: String, symbol: String, colors: [Color],
         checked: Binding<Bool>? = nil, review: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.symbol = symbol
        self.colors = colors
        self.checked = checked
        self.review = review
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: colors[0].opacity(0.5), radius: 18)
                .padding(18)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let checked {
                        Toggle("", isOn: checked).toggleStyle(.checkbox).labelsHidden()
                    }
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(value).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                HStack {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer()
                    if let review { SecondaryButton(title: t("İncele", "Review"), action: review) }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 175)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(alignment: .top) {
            // kartın üst kenarında ince renkli çizgi
            LinearGradient(colors: [colors[0].opacity(0.0), colors[0].opacity(0.8), colors[0].opacity(0.0)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1.5)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
