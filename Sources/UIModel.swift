import SwiftUI

enum PanelPage { case home, memory, settings, disk, cpu, network, battery }

enum SmartPhase { case idle, scanning, done, running, finished }

enum AppSection: String, CaseIterable, Identifiable {
    case smart, cleanup, clutter, spaceLens, protection, performance, apps, tools, activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return t("Akıllı Bakım", "Smart Care")
        case .cleanup: return t("Sistem Çöpü", "System Junk")
        case .clutter: return t("Dağınıklık", "My Clutter")
        case .protection: return t("Koruma", "Protection")
        case .performance: return t("Performans", "Performance")
        case .apps: return t("Uygulama Kaldırıcı", "Uninstaller")
        case .spaceLens: return t("Alan Haritası", "Space Lens")
        case .tools: return t("Araçlarım", "My Tools")
        case .activity: return t("Etkinliğim", "My Activity")
        }
    }

    var icon: String {
        switch self {
        case .smart: return "sparkles"
        case .cleanup: return "trash.circle.fill"
        case .clutter: return "folder.fill"
        case .protection: return "hand.raised.fill"
        case .performance: return "bolt.fill"
        case .apps: return "square.grid.2x2.fill"
        case .spaceLens: return "circle.hexagongrid.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .activity: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Arayüz durumu ve Akıllı Bakım akışı.
final class UIModel: ObservableObject {
    @Published var panelPage: PanelPage = .home
    @Published var section: AppSection = .smart
    @Published var smartPhase: SmartPhase = .idle
    @Published var smartCleanup = true
    @Published var maintTasks: Set<String> = ["purge", "dns"]
    @Published var toolPage: String?

    private var poll: Timer?

    func startSmartScan(cleaner: CleanerModel, sec: SecurityModel, clutter: ClutterModel, apps: AppsModel) {
        smartPhase = .scanning
        cleaner.scan()
        sec.scan()
        clutter.scan()
        apps.load()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            if !cleaner.busy && !sec.scanning && !clutter.scanning && !apps.loading {
                t.invalidate()
                self?.smartPhase = .done
            }
        }
    }

    func runSmart(cleaner: CleanerModel) {
        guard smartCleanup else {
            smartPhase = .finished
            return
        }
        smartPhase = .running
        cleaner.clean()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            if !cleaner.busy {
                t.invalidate()
                self?.smartPhase = .finished
            }
        }
    }
}
