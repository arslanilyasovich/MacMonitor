import SwiftUI
import AppKit

// MARK: - Space Lens: klasör boyut haritası

struct LensItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let isDir: Bool
}

final class SpaceLensModel: ObservableObject {
    @Published var path: [URL] = [home]
    @Published var items: [LensItem] = []
    @Published var loading = false
    @Published var progress = ""
    @Published var pendingTrash: String?
    @Published var message: String?

    var current: URL { path.last ?? home }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }

    private var cache: [String: [LensItem]] = [:]
    private var generation = 0

    func load() {
        let url = current
        if let cached = cache[url.path] {
            items = cached
            return
        }
        generation += 1
        let gen = generation
        loading = true
        items = []
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
            var result: [LensItem] = []
            for child in children {
                guard gen == self.generation else { return }
                let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                if v?.isSymbolicLink == true { continue }
                DispatchQueue.main.async { if gen == self.generation { self.progress = child.lastPathComponent } }
                let size = sizeOf(child)
                guard size > 0 else { continue }
                result.append(LensItem(url: child, size: size, isDir: v?.isDirectory == true && v?.isPackage != true))
                let snapshot = result.sorted { $0.size > $1.size }
                DispatchQueue.main.async { if gen == self.generation { self.items = snapshot } }
            }
            let sorted = result.sorted { $0.size > $1.size }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.items = sorted
                self.cache[url.path] = sorted
                self.loading = false
                self.progress = ""
            }
        }
    }

    func open(_ item: LensItem) {
        guard item.isDir else { return }
        path.append(item.url)
        pendingTrash = nil
        load()
    }

    func goTo(_ index: Int) {
        guard index < path.count else { return }
        path = Array(path.prefix(index + 1))
        pendingTrash = nil
        load()
    }

    func rescan() {
        cache.removeAll()
        load()
    }

    /// İlk tıklama onay ister, ikinci tıklama Çöp Kutusu'na taşır (geri alınabilir).
    func trash(_ item: LensItem) {
        guard pendingTrash == item.id else {
            pendingTrash = item.id
            return
        }
        pendingTrash = nil
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            ActivityStore.shared.record(item.size)
            items.removeAll { $0.id == item.id }
            cache.removeAll() // üst klasörlerin boyutları değişti
            cache[current.path] = items
            message = t("✓ \(item.url.lastPathComponent) Çöp Kutusu'na taşındı", "✓ \(item.url.lastPathComponent) moved to Trash")
        } catch {
            message = t("Taşınamadı: \(item.url.lastPathComponent)", "Couldn't move: \(item.url.lastPathComponent)")
        }
    }
}

// MARK: - Time Machine yerel anlık görüntüleri

final class TimeMachineModel: ObservableObject {
    @Published var snapshots: [String] = []
    @Published var loading = false
    @Published var loaded = false
    @Published var message: String?

    func load() {
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let out = runCommand("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
            let dates = out.components(separatedBy: "\n").compactMap { line -> String? in
                guard let r = line.range(of: "com.apple.TimeMachine.") else { return nil }
                return String(line[r.upperBound...]).replacingOccurrences(of: ".local", with: "")
            }
            DispatchQueue.main.async {
                self.snapshots = dates
                self.loading = false
                self.loaded = true
            }
        }
    }

    /// Yerel anlık görüntüleri siler; harici Time Machine yedeklerine dokunmaz.
    func deleteAll() {
        guard !snapshots.isEmpty else { return }
        let cmd = snapshots.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: "; ")
        let ok = runAdmin(cmd, prompt: t("MacMonitor yerel Time Machine anlık görüntülerini silecek.", "MacMonitor will delete local Time Machine snapshots."))
        message = ok ? t("✓ \(snapshots.count) anlık görüntü silindi", "✓ \(snapshots.count) snapshots deleted") : t("İptal edildi", "Cancelled")
        load()
    }
}

// MARK: - Kaldırılmış uygulamaların artıkları

struct Leftover: Identifiable {
    var id: String { url.path }
    let url: URL
    let bundleID: String
    let size: Int64
}

final class LeftoversModel: ObservableObject {
    @Published var items: [Leftover] = []
    @Published var selected: Set<String> = []
    @Published var scanning = false
    @Published var scannedOnce = false
    @Published var message: String?

    var selectedSize: Int64 { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }

    private static let dirs = ["Application Support", "Caches", "Preferences", "Containers", "Saved Application State",
                               "HTTPStorages", "WebKit", "Logs", "Group Containers", "Application Scripts", "Cookies"]

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = nil
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let lib = home.appendingPathComponent("Library")
            var found: [Leftover] = []
            var installedCache: [String: Bool] = [:]
            let tools = Self.commandLineTools()
            for dir in Self.dirs {
                let base = lib.appendingPathComponent(dir)
                for name in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] {
                    guard let bid = Self.bundleID(from: name, inGroupContainers: dir == "Group Containers") else { continue }
                    if Self.isInstalled(bid, running: running, cache: &installedCache) { continue }
                    // "com.vercel.cli" gibi: kimliğin bir parçası kurulu bir komut satırı aracıysa artık değildir
                    if bid.lowercased().split(separator: ".").dropFirst().contains(where: { tools.contains(String($0)) }) { continue }
                    let url = base.appendingPathComponent(name)
                    if Self.mayHoldLogin(url) { continue }
                    let size = sizeOf(url)
                    if size > 0 { found.append(Leftover(url: url, bundleID: bid, size: size)) }
                }
            }
            found.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.items = found
                self.selected = []
                self.scanning = false
                self.scannedOnce = true
            }
        }
    }

    func trashSelected() {
        var moved = 0, failed = 0, freed: Int64 = 0
        for item in items where selected.contains(item.id) {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                moved += 1
                freed += item.size
            } catch { failed += 1 }
        }
        ActivityStore.shared.record(freed)
        items.removeAll { selected.contains($0.id) && !FileManager.default.fileExists(atPath: $0.url.path) }
        selected = []
        var msg = t("✓ \(moved) öğe Çöp Kutusu'na taşındı (\(fmtBytes(freed)))", "✓ \(moved) items moved to Trash (\(fmtBytes(freed)))")
        if failed > 0 { msg += t(" · \(failed) korumalı öğe atlandı", " · \(failed) protected items skipped") }
        message = msg
    }

    /// "com.firma.uygulama" biçimindeki klasör/dosya adından paket kimliğini çıkarır.
    static func bundleID(from name: String, inGroupContainers: Bool) -> String? {
        var n = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where n.hasSuffix(suffix) { n = String(n.dropLast(suffix.count)) }
        for prefix in ["groups.", "group."] where n.hasPrefix(prefix) { n = String(n.dropFirst(prefix.count)) }
        if inGroupContainers, let dot = n.firstIndex(of: "."), n.distance(from: n.startIndex, to: dot) == 10 {
            n = String(n[n.index(after: dot)...]) // "ABCDE12345.com.firma.app" → takım kimliğini at
        }
        let parts = n.split(separator: ".")
        guard parts.count >= 3, parts[0].count >= 2, parts[0].allSatisfy({ $0.isLetter && $0.isLowercase }) else { return nil }
        let lower = n.lowercased()
        if lower.contains("com.apple.") || lower.hasPrefix("is.workflow") || lower.hasPrefix("local.a26.") { return nil }
        return n
    }

    /// Kurulu komut satırı araçlarının adları (uygulama değil ama ~/Library'de verisi olabilir)
    static func commandLineTools() -> Set<String> {
        let fm = FileManager.default
        var dirs = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        dirs += [".local/bin", "bin", ".npm-global/bin", ".bun/bin", ".cargo/bin", "go/bin", ".deno/bin"].map { home.appendingPathComponent($0).path }
        // ~/local/node/bin, ~/.nvm/versions/node/v20/bin gibi iç içe kurulumlar
        for parent in ["local", ".nvm/versions/node"] {
            let base = home.appendingPathComponent(parent)
            for sub in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] {
                dirs.append(base.appendingPathComponent(sub).appendingPathComponent("bin").path)
            }
        }
        var names = Set<String>()
        for d in dirs { for n in (try? fm.contentsOfDirectory(atPath: d)) ?? [] { names.insert(n.lowercased()) } }
        return names
    }

    /// Klasörde giriş/oturum bilgisi olabilecek dosya var mı? Varsa asla artık olarak gösterme.
    static func mayHoldLogin(_ url: URL) -> Bool {
        let pattern = ["auth", "token", "credential", "session", "login", "account", "secret", "keychain", "password", "oauth"]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return false }
        var checked = 0
        for case let f as URL in e {
            let n = f.lastPathComponent.lowercased()
            if pattern.contains(where: n.contains) { return true }
            checked += 1
            if checked > 2_000 { return true } // çok büyük klasör: emin olamıyorsak dokunma
        }
        return false
    }

    /// Uygulama kurulu mu? Yardımcı kimlikler için ("com.firma.app.helper") üst kimlikleri de dener.
    static func isInstalled(_ bid: String, running: Set<String>, cache: inout [String: Bool]) -> Bool {
        var parts = bid.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            let candidate = parts.joined(separator: ".")
            let key = candidate.lowercased()
            if running.contains(key) { return true }
            if let hit = cache[key] { if hit { return true } }
            else {
                let hit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil
                cache[key] = hit
                if hit { return true }
            }
            parts.removeLast()
        }
        return false
    }
}

// MARK: - Etkinlik geçmişi

final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published private(set) var freedTotal: Int64
    @Published private(set) var cleanCount: Int
    @Published private(set) var lastClean: Date?

    private init() {
        let d = UserDefaults.standard
        freedTotal = Int64(d.integer(forKey: "freedTotal"))
        cleanCount = d.integer(forKey: "cleanCount")
        lastClean = d.object(forKey: "lastClean") as? Date
    }

    func record(_ bytes: Int64) {
        guard bytes > 0 else { return }
        freedTotal += bytes
        cleanCount += 1
        lastClean = Date()
        let d = UserDefaults.standard
        d.set(Int(freedTotal), forKey: "freedTotal")
        d.set(cleanCount, forKey: "cleanCount")
        d.set(lastClean, forKey: "lastClean")
    }
}

// MARK: - Öneriler

struct Recommendation: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let title: String
    let text: String
    let action: String?
    let section: AppSection?
    let panel: PanelPage?
}

func recommendations(sys: SystemModel, sec: SecurityModel, cleaner: CleanerModel, clutter: ClutterModel) -> [Recommendation] {
    var r: [Recommendation] = []
    if sys.pressureLevel >= 2 {
        r.append(Recommendation(id: "memory", icon: "memorychip.fill", color: Theme.warn,
                                title: t("Bellek zorlanıyor", "Memory is under pressure"),
                                text: t("RAM'i en çok kullanan uygulamalara göz at ve gereksizleri kapat.", "Check the top memory consumers and quit what you don't need."),
                                action: t("Belleği Gör", "View Memory"), section: .performance, panel: .memory))
    }
    if sec.issueCount > 0 {
        r.append(Recommendation(id: "security", icon: "exclamationmark.shield.fill", color: Theme.warn,
                                title: t("\(sec.issueCount) güvenlik uyarısı", "\(sec.issueCount) security warnings"),
                                text: sec.summary, action: t("Korumayı Aç", "Open Protection"), section: .protection, panel: nil))
    }
    if sys.uptime > 7 * 86_400 {
        r.append(Recommendation(id: "restart", icon: "power", color: Theme.accent2,
                                title: t("Mac'ini ara sıra yeniden başlat", "Restart your Mac once in a while"),
                                text: t("\(Int(sys.uptime / 86_400)) gündür açık. Yeniden başlatmak belleği ve takılan servisleri temizler.",
                                        "It's been \(Int(sys.uptime / 86_400)) days. A restart clears memory and stuck services."),
                                action: nil, section: nil, panel: nil))
    }
    if sys.diskTotal > 0, Double(sys.diskFree) / Double(sys.diskTotal) < 0.15 {
        r.append(Recommendation(id: "disk", icon: "internaldrive.fill", color: Theme.bad,
                                title: t("Disk dolmak üzere", "Your disk is almost full"),
                                text: t("Space Lens ile en çok yer kaplayan klasörleri bul.", "Find the biggest folders with Space Lens."),
                                action: t("Space Lens", "Space Lens"), section: .spaceLens, panel: nil))
    }
    if cleaner.total > 500_000_000 {
        r.append(Recommendation(id: "junk", icon: "trash.fill", color: Theme.good,
                                title: t("\(fmtBytes(cleaner.total)) gereksiz dosya", "\(fmtBytes(cleaner.total)) of junk"),
                                text: t("Önbellek ve günlükleri temizleyerek yer aç.", "Free up space by cleaning caches and logs."),
                                action: t("Temizle", "Clean Up"), section: .cleanup, panel: nil))
    }
    if clutter.dupWaste > 100_000_000 {
        r.append(Recommendation(id: "dups", icon: "doc.on.doc.fill", color: Theme.accent,
                                title: t("Kopya dosyalar \(fmtBytes(clutter.dupWaste)) yer kaplıyor", "Duplicates take \(fmtBytes(clutter.dupWaste))"),
                                text: t("Aynı dosyanın fazla kopyalarını kaldır.", "Remove extra copies of the same file."),
                                action: t("İncele", "Review"), section: .clutter, panel: nil))
    }
    r.append(Recommendation(id: "apps", icon: "square.grid.2x2.fill", color: Theme.accent,
                            title: t("Uygulamalarını gözden geçir", "Take control of your apps"),
                            text: t("Kullanmadığın uygulamaları artıklarıyla birlikte kaldır.", "Uninstall apps you don't use, along with their leftovers."),
                            action: t("Uygulamaları İncele", "Review Applications"), section: .apps, panel: nil))
    return r
}
