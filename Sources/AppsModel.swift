import SwiftUI
import AppKit

struct AppEntry: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String?
    let version: String?
    var size: Int64 = -1
}

/// Uygulama kaldırıcı: uygulamayı ve ~/Library'deki artıklarını Çöp Kutusu'na taşır.
final class AppsModel: ObservableObject {
    @Published var apps: [AppEntry] = []
    @Published var loading = false
    @Published var selectedPath: String?
    @Published var leftovers: [JunkItem] = []
    @Published var findingLeftovers = false
    @Published var pendingRemove = false
    @Published var message: String?
    @Published var query = ""

    var filtered: [AppEntry] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    var selected: AppEntry? { apps.first { $0.path == selectedPath } }
    var removalTotal: Int64 { max(selected?.size ?? 0, 0) + leftovers.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { apps.reduce(0) { $0 + max($1.size, 0) } }

    func load() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var list: [AppEntry] = []
            for dir in ["/Applications", home.appendingPathComponent("Applications").path] {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                for n in names where n.hasSuffix(".app") {
                    let p = (dir as NSString).appendingPathComponent(n)
                    if p == Bundle.main.bundlePath { continue }
                    if (try? FileManager.default.destinationOfSymbolicLink(atPath: p)) != nil { continue }
                    let b = Bundle(path: p)
                    list.append(AppEntry(path: p, name: String(n.dropLast(4)), bundleID: b?.bundleIdentifier,
                                         version: b?.infoDictionary?["CFBundleShortVersionString"] as? String))
                }
            }
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.apps = list
                self.loading = false
            }
            for a in list {
                let s = sizeOf(URL(fileURLWithPath: a.path))
                DispatchQueue.main.async {
                    if let i = self.apps.firstIndex(where: { $0.path == a.path }) { self.apps[i].size = s }
                }
            }
            DispatchQueue.main.async { self.apps.sort { $0.size > $1.size } }
        }
    }

    func select(_ app: AppEntry) {
        selectedPath = app.path
        pendingRemove = false
        message = nil
        leftovers = []
        findingLeftovers = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.findLeftovers(app)
            DispatchQueue.main.async {
                guard self.selectedPath == app.path else { return }
                self.leftovers = found
                self.findingLeftovers = false
            }
        }
    }

    func uninstall() {
        guard let app = selected else { return }
        guard pendingRemove else {
            pendingRemove = true
            return
        }
        pendingRemove = false
        for r in NSWorkspace.shared.runningApplications where r.bundleURL?.path == app.path { r.terminate() }
        let leftovers = self.leftovers
        let total = removalTotal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Finder ile silmek: root'a ait uygulamalarda macOS kendisi şifre sorar
            let esc = app.path.replacingOccurrences(of: "\"", with: "\\\"")
            let ok = runAppleScript("tell application \"Finder\" to delete (POSIX file \"\(esc)\" as alias)")
            var moved = 0, failed = 0
            if ok {
                for l in leftovers {
                    if Safety.refusal(l.url, gitCheck: true) != nil { failed += 1; continue }
                    do { try FileManager.default.trashItem(at: l.url, resultingItemURL: nil); moved += 1 } catch { failed += 1 }
                }
                ActivityStore.shared.recordTrash(total)
                self.apps.removeAll { $0.path == app.path }
                self.selectedPath = nil
                self.leftovers = []
                var msg = t("✓ \(app.name) Çöp Kutusu'na taşındı · \(moved) artık dosya", "✓ \(app.name) moved to Trash · \(moved) leftover files")
                if failed > 0 { msg += t(" · \(failed) korumalı öğe atlandı", " · \(failed) protected items skipped") }
                self.message = msg
            } else {
                self.message = t("\(app.name) kaldırılamadı. Finder'ı kontrol etme izni gerekebilir.", "Couldn't remove \(app.name). Finder control permission may be needed.")
            }
        }
    }

    static func findLeftovers(_ app: AppEntry) -> [JunkItem] {
        let fm = FileManager.default
        let lib = home.appendingPathComponent("Library")
        var candidates: [URL] = []
        if let bid = app.bundleID {
            candidates += [
                "Application Support/\(bid)", "Caches/\(bid)", "HTTPStorages/\(bid)", "HTTPStorages/\(bid).binarycookies",
                "WebKit/\(bid)", "Saved Application State/\(bid).savedState", "Containers/\(bid)",
                "Preferences/\(bid).plist", "Logs/\(bid)", "Cookies/\(bid).binarycookies",
            ].map { lib.appendingPathComponent($0) }
            for sub in ["Preferences", "Caches", "Containers", "Group Containers", "Application Scripts", "LaunchAgents", "HTTPStorages"] {
                let dir = lib.appendingPathComponent(sub)
                let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                candidates += names.filter { $0.contains(bid) }.map { dir.appendingPathComponent($0) }
            }
        }
        candidates += ["Application Support/\(app.name)", "Caches/\(app.name)", "Logs/\(app.name)"].map { lib.appendingPathComponent($0) }

        var seen = Set<String>()
        return candidates
            .filter { fm.fileExists(atPath: $0.path) && seen.insert($0.standardizedFileURL.path).inserted }
            .map { JunkItem(url: $0, size: sizeOf($0)) }
            .sorted { $0.size > $1.size }
    }
}
