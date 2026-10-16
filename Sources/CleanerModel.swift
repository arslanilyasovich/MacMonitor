import SwiftUI
import AppKit

struct JunkItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let size: Int64
}

struct JunkCategory: Identifiable {
    let id: String
    let icon: String
    var items: [JunkItem] = []
    var selected = true
    var toTrash = false      // kullanıcı dosyaları silinmez, Çöp Kutusu'na taşınır
    var unknownSize = false
    var inUse: [JunkItem] = []   // açık uygulamalara ait olduğu için bu taramada atlananlar
    var size: Int64 { items.reduce(0) { $0 + $1.size } }

    var title: String {
        switch id {
        case "caches": return t("Uygulama önbellekleri", "App caches")
        case "browser": return t("Tarayıcı önbellekleri", "Browser caches")
        case "logs": return t("Günlük dosyaları", "Log files")
        case "dev": return t("Geliştirici önbellekleri", "Developer caches")
        case "installers": return t("Kurulum dosyaları", "Installers")
        case "mail": return t("Mail ekleri", "Mail attachments")
        default: return t("Çöp Kutusu", "Trash")
        }
    }

    var note: String {
        switch id {
        case "caches": return t("Uygulamalar gerektiğinde yeniden oluşturur", "Apps rebuild them when needed")
        case "browser": return t("Brave, Chrome, Firefox… Oturumların ve şifrelerin silinmez", "Brave, Chrome, Firefox… logins and passwords are kept")
        case "logs": return t("Uygulamaların tuttuğu kayıt dosyaları", "Log files written by apps")
        case "dev": return t("npm, Xcode, Gradle — araçlar gerekince yeniden indirir", "npm, Xcode, Gradle — tools re-download as needed")
        case "installers": return t("İndirilenler'deki .dmg ve .pkg dosyaları — Çöp Kutusu'na taşınır", ".dmg and .pkg files in Downloads — moved to Trash")
        case "mail": return unknownSize
            ? t("Okumak için Tam Disk Erişimi gerekiyor", "Needs Full Disk Access to read")
            : t("Mail'de açtığın eklerin kopyaları — sunucuda durdukları için yeniden indirilebilir", "Copies of attachments you opened — re-downloadable from the server")
        default: return t("Finder üzerinden boşaltılır — geri alınamaz", "Emptied via Finder — can't be undone")
        }
    }
}

/// Sistem çöpü: önbellekler, günlükler, geliştirici artıkları, kurulum dosyaları, Çöp Kutusu.
final class CleanerModel: ObservableObject {
    @Published var cats: [JunkCategory] = []
    @Published var busy = false
    @Published var lastResult: String?
    @Published var expanded: Set<String> = []

    var selectedTotal: Int64 { cats.filter(\.selected).reduce(0) { $0 + $1.size } }
    var total: Int64 { cats.reduce(0) { $0 + $1.size } }
    var trashSelected: Bool { cats.contains { $0.id == "trash" && $0.selected } }

    private let fm = FileManager.default

    private static let browserCaches: Set<String> = [
        "BraveSoftware", "Google", "com.brave.Browser", "com.google.Chrome", "Mozilla", "Firefox",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.microsoft.edgemac", "Microsoft Edge",
    ]
    // Hiç dokunulmayanlar: Apple'ın sistem önbellekleri ve silinirse kullanıcı verisi kaybettiren önbellekler
    // (Spotify çevrimdışı şarkıları, Playwright'ın indirdiği tarayıcılar, JetBrains indeksleri)
    private static let skipCacheNames: Set<String> = [
        "CloudKit", "GeoServices", "FamilyCircle", "local.a26.macmonitor",
        "com.spotify.client", "ms-playwright", "ms-playwright-go", "JetBrains",
    ]
    // Klasör adı uygulama kimliğine benzemeyen önbelleklerin sahibi
    private static let cacheOwners: [String: String] = [
        "bravesoftware": "com.brave.browser", "google": "com.google.chrome", "mozilla": "org.mozilla.firefox",
        "firefox": "org.mozilla.firefox", "microsoft edge": "com.microsoft.edgemac",
    ]

    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func scan() {
        guard !busy else { return }
        busy = true
        lastResult = nil
        let previous = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0.selected) })
        // Açık uygulamaların önbelleğini silmek onları bozabilir: kimliklerini ve adlarını şimdi topla
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.compactMap { $0.bundleIdentifier?.lowercased() } + apps.compactMap { $0.localizedName?.lowercased() })
        DispatchQueue.global(qos: .userInitiated).async {
            var cats = self.buildCategories(running: running)
            for i in cats.indices { cats[i].selected = previous[cats[i].id] ?? cats[i].selected }
            DispatchQueue.main.async {
                self.cats = cats
                self.busy = false
            }
        }
    }

    func clean() {
        let targets = cats.filter(\.selected)
        guard !targets.isEmpty, !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0
            var skipped = 0
            var emptyTrash = false
            for c in targets {
                if c.id == "trash" {
                    emptyTrash = true
                    freed += c.size
                    continue
                }
                for item in c.items {
                    do {
                        if c.toTrash { try self.fm.trashItem(at: item.url, resultingItemURL: nil) }
                        else { try self.fm.removeItem(at: item.url) }
                        freed += item.size
                    } catch {
                        skipped += 1
                    }
                }
            }
            DispatchQueue.main.async {
                if emptyTrash, !runAppleScript("tell application \"Finder\" to empty trash") { skipped += 1 }
                ActivityStore.shared.record(freed)
                var msg = t("✓ \(fmtBytes(freed)) temizlendi", "✓ \(fmtBytes(freed)) cleaned")
                if skipped > 0 { msg += t(" · \(skipped) öğe atlandı (kullanımda/korumalı)", " · \(skipped) items skipped (in use/protected)") }
                self.busy = false
                self.scan()
                self.lastResult = msg
            }
        }
    }

    private static func isInUse(_ url: URL, running: Set<String>) -> Bool {
        let n = url.lastPathComponent.lowercased()
        if running.contains(n) { return true }
        if let owner = cacheOwners[n] ?? cacheOwners[url.lastPathComponent], running.contains(owner) { return true }
        // örn. "com.microsoft.VSCode.ShipIt" → "com.microsoft.vscode" açıksa
        return running.contains { $0.contains(".") && n.hasPrefix($0 + ".") }
    }

    /// Önbellek klasörlerini "temizlenecek" ve "kullanımda" diye ikiye ayırır.
    private func split(_ urls: [URL], running: Set<String>) -> ([JunkItem], [JunkItem]) {
        let all = items(urls)
        return (all.filter { !Self.isInUse($0.url, running: running) }, all.filter { Self.isInUse($0.url, running: running) })
    }

    private func buildCategories(running: Set<String>) -> [JunkCategory] {
        let caches = children(of: home.appendingPathComponent("Library/Caches")).filter {
            let n = $0.lastPathComponent
            return !n.hasPrefix("com.apple.") && !Self.skipCacheNames.contains(n)
        }

        var result: [JunkCategory] = []

        var app = JunkCategory(id: "caches", icon: "shippingbox.fill")
        (app.items, app.inUse) = split(caches.filter { !Self.browserCaches.contains($0.lastPathComponent) }, running: running)
        result.append(app)

        var browser = JunkCategory(id: "browser", icon: "globe")
        (browser.items, browser.inUse) = split(caches.filter { Self.browserCaches.contains($0.lastPathComponent) }, running: running)
        result.append(browser)

        var logs = JunkCategory(id: "logs", icon: "doc.text.fill")
        logs.items = items(children(of: home.appendingPathComponent("Library/Logs")))
        result.append(logs)

        var dev = JunkCategory(id: "dev", icon: "hammer.fill")
        dev.items = items([".npm/_cacache", "Library/Developer/Xcode/DerivedData",
                           "Library/Developer/CoreSimulator/Caches", ".gradle/caches"]
            .map { home.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) })
        result.append(dev)

        var installers = JunkCategory(id: "installers", icon: "shippingbox.and.arrow.backward.fill", selected: false, toTrash: true)
        installers.items = items(children(of: home.appendingPathComponent("Downloads")).filter {
            ["dmg", "pkg", "mpkg"].contains($0.pathExtension.lowercased())
        })
        result.append(installers)

        var mail = JunkCategory(id: "mail", icon: "envelope.fill", selected: false, toTrash: true)
        let mailDir = home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if let content = try? fm.contentsOfDirectory(at: mailDir, includingPropertiesForKeys: nil) {
            mail.items = items(content)
        } else if fm.fileExists(atPath: home.appendingPathComponent("Library/Containers/com.apple.mail").path) {
            mail.unknownSize = true
        }
        result.append(mail)

        var trash = JunkCategory(id: "trash", icon: "trash.fill", selected: false)
        if let content = try? fm.contentsOfDirectory(at: home.appendingPathComponent(".Trash"), includingPropertiesForKeys: nil) {
            trash.items = items(content)
        } else {
            trash.unknownSize = true // macOS içeriği okumaya izin vermiyor
        }
        result.append(trash)

        return result
    }

    private func items(_ urls: [URL]) -> [JunkItem] {
        urls.map { JunkItem(url: $0, size: sizeOf($0)) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    private func children(of dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }
}
