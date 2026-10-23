import SwiftUI
import AppKit

struct JunkItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    var dev: DevCache? = nil
}

/// Bilinen geliştirici önbelleği: ne olduğu, silinince ne olacağı ve riski.
struct DevCache {
    let path: String        // ev klasörüne göre
    let name: String
    let tr: String
    let en: String
    var caution = false     // yeniden indirmesi uzun sürer ya da kurulu sürümleri siler: varsayılan seçili değil
    var owner: String? = nil // açıkken önbelleğine dokunulmayan uygulama (küçük harf ad ya da kimlik)
    var note: String { t(tr, en) }
}

struct JunkCategory: Identifiable {
    let id: String
    let icon: String
    var items: [JunkItem] = []
    var selected = true
    var toTrash = false      // kullanıcı dosyaları silinmez, Çöp Kutusu'na taşınır
    var unknownSize = false
    var inUse: [JunkItem] = []   // açık uygulamalara ait olduğu için bu taramada atlananlar
    var excluded: Set<String> = []  // kullanıcının tek tek seçimini kaldırdığı öğeler
    var chosen: [JunkItem] { items.filter { !excluded.contains($0.id) } }
    var size: Int64 { chosen.reduce(0) { $0 + $1.size } }

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
        case "dev": return t("npm, pnpm, pip, uv, Cargo, Xcode, VS Code… Araçlar gerekince yeniden indirir. Sarı etiketliler varsayılan seçili değil.",
                             "npm, pnpm, pip, uv, Cargo, Xcode, VS Code… Tools re-download as needed. Yellow-tagged ones aren't selected by default.")
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

    // Bilinen geliştirici önbellekleri. Hepsi araçların kendisinin yeniden oluşturduğu dosyalar;
    // kurulu sürümler, modeller ve simülatörler "dikkat" olarak işaretli ve varsayılan seçili değil.
    static let devCatalog: [DevCache] = [
        DevCache(path: ".npm/_cacache", name: "npm", tr: "İndirilen paketler, npm install yeniden indirir", en: "Downloaded packages, npm install fetches them again"),
        DevCache(path: "Library/Caches/Yarn", name: "Yarn", tr: "Paket önbelleği", en: "Package cache"),
        DevCache(path: "Library/pnpm/store", name: "pnpm store", tr: "Paylaşılan paket deposu. Projeler bağlantılı kullandığı için açılan yer görünenden az olabilir", en: "Shared package store. Projects hard-link it, so less space may be freed than shown"),
        DevCache(path: "Library/Caches/pnpm", name: "pnpm", tr: "Paket önbelleği", en: "Package cache"),
        DevCache(path: ".bun/install/cache", name: "Bun", tr: "Paket önbelleği", en: "Package cache"),
        DevCache(path: "Library/Caches/deno", name: "Deno", tr: "Modül önbelleği", en: "Module cache"),
        DevCache(path: "Library/Caches/node-gyp", name: "node-gyp", tr: "Node başlık dosyaları, gerekince indirilir", en: "Node headers, downloaded when needed"),
        DevCache(path: "Library/Caches/typescript", name: "TypeScript", tr: "Tip tanımları önbelleği", en: "Type definitions cache"),
        DevCache(path: "Library/Caches/pip", name: "pip", tr: "İndirilen Python paketleri", en: "Downloaded Python packages"),
        DevCache(path: ".cache/uv", name: "uv", tr: "Python paket önbelleği", en: "Python package cache"),
        DevCache(path: "Library/Caches/pypoetry", name: "Poetry", tr: "Python paket önbelleği", en: "Python package cache"),
        DevCache(path: ".conda/pkgs", name: "Conda", tr: "İndirilen paket arşivleri", en: "Downloaded package archives"),
        DevCache(path: "Library/Caches/go-build", name: "Go build", tr: "Derleme önbelleği", en: "Build cache"),
        DevCache(path: "go/pkg/mod/cache", name: "Go modules", tr: "İndirilen modül arşivleri", en: "Downloaded module archives"),
        DevCache(path: ".cargo/registry/cache", name: "Cargo", tr: "İndirilen Rust paket arşivleri", en: "Downloaded Rust crate archives"),
        DevCache(path: ".gradle/caches", name: "Gradle", tr: "Bağımlılık ve derleme önbelleği", en: "Dependency and build cache"),
        DevCache(path: ".gradle/wrapper/dists", name: "Gradle Wrapper", tr: "İndirilen Gradle sürümleri", en: "Downloaded Gradle versions"),
        DevCache(path: ".m2/repository", name: "Maven", tr: "İndirilen Java kütüphaneleri", en: "Downloaded Java libraries"),
        DevCache(path: ".ivy2/cache", name: "SBT/Ivy", tr: "Bağımlılık önbelleği", en: "Dependency cache"),
        DevCache(path: ".cache/bazel", name: "Bazel", tr: "Derleme önbelleği", en: "Build cache"),
        DevCache(path: ".composer/cache", name: "Composer", tr: "PHP paket önbelleği", en: "PHP package cache"),
        DevCache(path: ".nuget/packages", name: "NuGet", tr: ".NET paketleri", en: ".NET packages"),
        DevCache(path: ".pub-cache", name: "Flutter/Pub", tr: "Dart paketleri", en: "Dart packages"),
        DevCache(path: ".bundle/cache", name: "Bundler", tr: "Ruby paket önbelleği", en: "Ruby gem cache"),
        DevCache(path: "Library/Caches/Homebrew", name: "Homebrew", tr: "İndirilen kurulum dosyaları", en: "Downloaded bottles"),
        DevCache(path: "Library/Caches/CocoaPods", name: "CocoaPods", tr: "Pod önbelleği", en: "Pod cache"),
        DevCache(path: "Library/Caches/org.swift.swiftpm", name: "Swift PM", tr: "İndirilen Swift paketleri", en: "Downloaded Swift packages"),
        DevCache(path: "Library/Caches/org.carthage.CarthageKit", name: "Carthage", tr: "Bağımlılık önbelleği", en: "Dependency cache"),
        DevCache(path: "Library/Developer/Xcode/DerivedData", name: "Xcode DerivedData", tr: "Derleme çıktıları, Xcode yeniden derler", en: "Build output, Xcode rebuilds it", owner: "com.apple.dt.xcode"),
        DevCache(path: "Library/Developer/Xcode/Products", name: "Xcode Products", tr: "Derlenmiş ürünler", en: "Built products", owner: "com.apple.dt.xcode"),
        DevCache(path: "Library/Developer/Xcode/iOS DeviceSupport", name: "iOS DeviceSupport", tr: "Cihaz sembolleri, cihaz takılınca yeniden oluşur", en: "Device symbols, rebuilt when a device connects", owner: "com.apple.dt.xcode"),
        DevCache(path: "Library/Developer/Xcode/UserData/Previews", name: "Xcode Previews", tr: "SwiftUI önizleme verisi", en: "SwiftUI preview data", owner: "com.apple.dt.xcode"),
        DevCache(path: "Library/Developer/CoreSimulator/Caches", name: "Simulator Caches", tr: "Simülatör önbelleği", en: "Simulator cache", owner: "com.apple.iphonesimulator"),
        DevCache(path: "Library/Logs/CoreSimulator", name: "Simulator Logs", tr: "Simülatör günlükleri", en: "Simulator logs", owner: "com.apple.iphonesimulator"),
        DevCache(path: "Library/Application Support/Code/CachedData", name: "VS Code", tr: "Derlenmiş eklenti önbelleği", en: "Compiled extension cache", owner: "com.microsoft.vscode"),
        DevCache(path: "Library/Application Support/Code/CachedExtensionVSIXs", name: "VS Code VSIX", tr: "İndirilen eklenti paketleri", en: "Downloaded extension packages", owner: "com.microsoft.vscode"),
        DevCache(path: "Library/Application Support/Code/Cache", name: "VS Code Cache", tr: "Tarayıcı motoru önbelleği", en: "Browser engine cache", owner: "com.microsoft.vscode"),
        DevCache(path: "Library/Application Support/Code/logs", name: "VS Code Logs", tr: "Günlük dosyaları", en: "Log files", owner: "com.microsoft.vscode"),
        DevCache(path: "Library/Application Support/Antigravity/CachedData", name: "Antigravity", tr: "Derlenmiş eklenti önbelleği", en: "Compiled extension cache", owner: "antigravity"),
        DevCache(path: "Library/Application Support/Antigravity/Cache", name: "Antigravity Cache", tr: "Tarayıcı motoru önbelleği", en: "Browser engine cache", owner: "antigravity"),
        DevCache(path: "Library/Application Support/Antigravity/logs", name: "Antigravity Logs", tr: "Günlük dosyaları", en: "Log files", owner: "antigravity"),
        DevCache(path: "Library/Application Support/Cursor/CachedData", name: "Cursor", tr: "Derlenmiş eklenti önbelleği", en: "Compiled extension cache", owner: "cursor"),
        DevCache(path: "Library/Application Support/Cursor/Cache", name: "Cursor Cache", tr: "Tarayıcı motoru önbelleği", en: "Browser engine cache", owner: "cursor"),
        DevCache(path: ".cache/prisma", name: "Prisma", tr: "İndirilen motor dosyaları", en: "Downloaded engines"),
        DevCache(path: ".cache/puppeteer", name: "Puppeteer", tr: "İndirilen test tarayıcıları, yeniden indirmek uzun sürer", en: "Downloaded test browsers, slow to re-download", caution: true),
        DevCache(path: "Library/Developer/Xcode/Archives", name: "Xcode Archives", tr: "Yayınladığın sürümlerin arşivleri, geri gelmez", en: "Archives of builds you shipped, not recoverable", caution: true),
        DevCache(path: "Library/Developer/CoreSimulator/Devices", name: "Simulators", tr: "Simülatörler ve içindeki uygulama verileri", en: "Simulators and their app data", caution: true, owner: "com.apple.iphonesimulator"),
        DevCache(path: ".android/avd", name: "Android Emulators", tr: "Emülatörler ve içindeki veriler", en: "Emulators and their data", caution: true),
        DevCache(path: ".cache/huggingface", name: "Hugging Face", tr: "İndirilen yapay zekâ modelleri, büyük indirme", en: "Downloaded AI models, large re-download", caution: true),
        DevCache(path: ".ollama/models", name: "Ollama", tr: "Yerel yapay zekâ modelleri, büyük indirme", en: "Local AI models, large re-download", caution: true, owner: "ollama"),
        DevCache(path: ".nvm/versions", name: "nvm", tr: "Kurulu Node sürümleri", en: "Installed Node versions", caution: true),
        DevCache(path: ".pyenv/versions", name: "pyenv", tr: "Kurulu Python sürümleri", en: "Installed Python versions", caution: true),
        DevCache(path: ".rustup/toolchains", name: "rustup", tr: "Kurulu Rust sürümleri", en: "Installed Rust toolchains", caution: true),
    ]

    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func scan() {
        guard !busy else { return }
        busy = true
        lastResult = nil
        // Yeniden taramada kullanıcının seçimleri korunur; yeni çıkan öğeler varsayılan seçimiyle gelir
        let previous = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, ($0.selected, $0.excluded, Set($0.items.map(\.id)))) })
        // Açık uygulamaların önbelleğini silmek onları bozabilir: kimliklerini ve adlarını şimdi topla
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.compactMap { $0.bundleIdentifier?.lowercased() } + apps.compactMap { $0.localizedName?.lowercased() })
        DispatchQueue.global(qos: .userInitiated).async {
            var cats = self.buildCategories(running: running)
            for i in cats.indices {
                guard let (sel, excl, seen) = previous[cats[i].id] else { continue }
                cats[i].selected = sel
                cats[i].excluded = Set(cats[i].items.map(\.id).filter { seen.contains($0) ? excl.contains($0) : cats[i].excluded.contains($0) })
            }
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
            var freed: Int64 = 0, trashed: Int64 = 0
            var skipped = 0
            var emptyTrash = false
            let freeBefore = volumeFreeBytes()
            for c in targets {
                if c.id == "trash" {
                    emptyTrash = true
                    freed += c.size
                    continue
                }
                for item in c.chosen {
                    if Safety.refusal(item.url, gitCheck: true) != nil { skipped += 1; continue }
                    do {
                        if c.toTrash {
                            try self.fm.trashItem(at: item.url, resultingItemURL: nil)
                            trashed += item.size
                        } else {
                            try self.fm.removeItem(at: item.url)
                            freed += item.size
                        }
                    } catch {
                        skipped += 1
                    }
                }
            }
            DispatchQueue.main.async {
                if emptyTrash, !runAppleScript("tell application \"Finder\" to empty trash") { skipped += 1 }
                // Gerçekten açılan yer: silmeden önceki ve sonraki boş alan farkı (yerel anlık görüntüler tutuyorsa az çıkabilir)
                let real = max(0, volumeFreeBytes() - freeBefore)
                ActivityStore.shared.record(freed)
                ActivityStore.shared.recordTrash(trashed)
                var msg = t("✓ \(fmtBytes(freed)) temizlendi", "✓ \(fmtBytes(freed)) cleaned")
                if freed > 0 { msg += t(" · diskte \(fmtBytes(real)) boşaldı", " · \(fmtBytes(real)) freed on disk") }
                if trashed > 0 { msg += t(" · \(fmtBytes(trashed)) Çöp Kutusu'na taşındı", " · \(fmtBytes(trashed)) moved to Trash") }
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
            return !n.hasPrefix("com.apple.") && !Self.skipCacheNames.contains(n) && !Self.devCachePaths.contains($0.path)
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
        for d in Self.devCatalog {
            let url = home.appendingPathComponent(d.path)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = sizeOf(url)
            guard size > 0 else { continue }
            let item = JunkItem(url: url, size: size, dev: d)
            if let o = d.owner, running.contains(where: { $0 == o || $0.hasPrefix(o) }) { dev.inUse.append(item) }
            else { dev.items.append(item) }
        }
        dev.items.sort { $0.size > $1.size }
        dev.excluded = Set(dev.items.filter { $0.dev?.caution == true }.map(\.id))
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

    private static let devCachePaths = Set(devCatalog.map { home.appendingPathComponent($0.path).path })

    private func items(_ urls: [URL]) -> [JunkItem] {
        urls.map { JunkItem(url: $0, size: sizeOf($0)) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    private func children(of dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }
}
