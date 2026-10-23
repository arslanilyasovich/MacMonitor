import Foundation
import Darwin

/// Projelerin içindeki yeniden üretilebilir klasörler: node_modules, venv, Rust target, .next…
struct ProjectArtifact: Identifiable {
    var id: String { url.path }
    let url: URL
    let project: URL
    let type: String
    let size: Int64
    let lastActive: Date
    let running: Bool       // projeden çalışan bir işlem var: botlar, sunucular
    let blocked: String?    // güvenlik kontrolünün reddetme sebebi
    var name: String { url.lastPathComponent }
    var ageDays: Int { max(0, Int(Date().timeIntervalSince(lastActive) / 86_400)) }
    var reinstall: Bool { ProjectsModel.envNames.contains(name) || name == ".tox" }
    var usable: Bool { !running && blocked == nil }

    var note: String {
        switch name {
        case "node_modules": return t("npm install ile geri gelir", "Restored with npm install")
        case ".venv", "venv", "env": return t("Python ortamı. pip install -r requirements.txt ile yeniden kurulur", "Python environment. Recreate with pip install -r requirements.txt")
        case "target": return t("Derleme çıktısı, bir sonraki derlemede oluşur", "Build output, recreated on next build")
        case "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache": return t("Araç önbelleği, kendiliğinden oluşur", "Tool cache, recreated automatically")
        default: return t("Derleme çıktısı ya da önbellek, yeniden oluşturulur", "Build output or cache, regenerated")
        }
    }
}

final class ProjectsModel: ObservableObject {
    @Published var items: [ProjectArtifact] = []
    @Published var selected: Set<String> = []
    @Published var scanning = false
    @Published var scannedOnce = false
    @Published var message: String?

    static let minAgeDays = 30
    static let envNames: Set<String> = [".venv", "venv", "env"]

    var selectedSize: Int64 { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }
    /// 30 günden uzun süredir dokunulmamış ve güvenle taşınabilecek olanlar
    var staleSize: Int64 { items.filter { $0.usable && $0.ageDays >= Self.minAgeDays }.reduce(0) { $0 + $1.size } }

    private struct Kind {
        let label: String
        let markers: [String]       // proje kökünde bu dosyalardan biri varsa
        let artifacts: [String]
        var repoOnly: [String] = [] // genel adlar (build, dist, bin): sadece git deposunda ve .gitignore'daysa
    }

    private static let kinds: [Kind] = [
        Kind(label: "Node.js", markers: ["package.json"],
             artifacts: ["node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular", ".open-next"],
             repoOnly: ["dist", "build"]),
        Kind(label: "Python", markers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile"],
             artifacts: [".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox"]),
        Kind(label: "Rust", markers: ["Cargo.toml"], artifacts: ["target"]),
        Kind(label: "Swift", markers: ["Package.swift"], artifacts: [".build"]),
        Kind(label: "Gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], artifacts: [".gradle"], repoOnly: ["build"]),
        Kind(label: "Maven", markers: ["pom.xml"], artifacts: ["target"]),
        Kind(label: "Flutter", markers: ["pubspec.yaml"], artifacts: [".dart_tool"], repoOnly: ["build"]),
        Kind(label: ".NET", markers: [".sln", ".csproj", ".fsproj"], artifacts: [], repoOnly: ["bin", "obj"]),
    ]

    // İçine hiç girilmeyen klasörler: sistem, paket ve sürüm kontrolü klasörleri
    private static let noDescend: Set<String> = ["Library", "Applications", "Pictures", "Music", "Movies", "Public", "node_modules", ".git"]
    private static let scanRoots = ["Desktop", "Documents", "Developer", "Projects", "Code", "repos", "src", "workspace", "dev", "Development"]

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = nil
        let prevSelected = selected, prevSeen = Set(items.map(\.id))
        DispatchQueue.global(qos: .userInitiated).async {
            let busyPaths = Self.processPaths()
            var found: [(URL, URL, String)] = []
            var roots = Self.scanRoots.map { home.appendingPathComponent($0) }
            // Doğrudan ev klasöründe duran projeler (ör. ~/algotrade)
            let homeStd: Set<String> = Set(Self.scanRoots + ["Library", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"])
            roots += ((try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") && !homeStd.contains($0.lastPathComponent) && Self.isDir($0) }
            for r in roots where Self.isDir(r) { Self.walk(r, depth: 0, into: &found) }

            var result: [ProjectArtifact] = []
            var activity: [URL: Date] = [:] // bir projede birden çok artık olabilir: son değişikliği bir kez hesapla
            for (url, project, type) in found {
                let size = sizeOf(url)
                guard size >= 1_000_000 else { continue } // 1 MB altı uğraşmaya değmez
                let running = busyPaths.contains { $0.hasPrefix(project.path + "/") }
                result.append(ProjectArtifact(url: url, project: project, type: type, size: size,
                                              lastActive: activity[project] ?? { let d = Self.lastActivity(project); activity[project] = d; return d }(),
                                              running: running, blocked: Safety.refusal(url, gitCheck: true)))
            }
            result.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.items = result
                // Varsayılan seçim: 30+ gündür dokunulmamış, çalışmayan, ortam olmayan (venv'ler yeniden kurulum ister)
                self.selected = Set(result.filter { a in
                    guard a.usable else { return false }
                    if prevSeen.contains(a.id) { return prevSelected.contains(a.id) }
                    return a.ageDays >= Self.minAgeDays && !a.reinstall
                }.map(\.id))
                self.scanning = false
                self.scannedOnce = true
            }
        }
    }

    func trashSelected() {
        let targets = items.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        let busyPaths = Self.processPaths() // taramadan sonra başlamış olabilir: yeniden bak
        var moved = 0, skipped = 0, bytes: Int64 = 0
        for a in targets {
            if busyPaths.contains(where: { $0.hasPrefix(a.project.path + "/") }) || Safety.refusal(a.url, gitCheck: true) != nil {
                skipped += 1
                continue
            }
            do {
                try FileManager.default.trashItem(at: a.url, resultingItemURL: nil)
                moved += 1
                bytes += a.size
            } catch { skipped += 1 }
        }
        ActivityStore.shared.recordTrash(bytes)
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        selected = selected.filter { id in items.contains { $0.id == id } }
        var msg = t("✓ \(moved) klasör Çöp Kutusu'na taşındı (\(fmtBytes(bytes))). Yer, Çöp Kutusu boşaltılınca açılır.",
                    "✓ \(moved) folders moved to Trash (\(fmtBytes(bytes))). Space is freed when you empty the Trash.")
        if skipped > 0 { msg += t(" · \(skipped) öğe atlandı (çalışıyor/korumalı)", " · \(skipped) skipped (running/protected)") }
        message = msg
    }

    // MARK: Tarama

    private static func walk(_ dir: URL, depth: Int, into found: inout [(URL, URL, String)]) {
        guard depth <= 6 else { return }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) else { return }
        let names = Set(children.map(\.lastPathComponent))
        var claimed: Set<String> = []
        let inRepo = names.contains(".git") || repoRoot(of: dir) != nil

        for k in kinds where matches(k, names) {
            for a in k.artifacts + (inRepo ? k.repoOnly : []) where names.contains(a) && !claimed.contains(a) {
                let url = dir.appendingPathComponent(a)
                if isDir(url) {
                    claimed.insert(a)
                    found.append((url, dir, k.label))
                }
            }
        }
        // Python ortamı: hangi projede olursa olsun, içinde pyvenv.cfg varsa gerçek bir ortamdır
        for e in envNames where names.contains(e) && !claimed.contains(e) {
            let url = dir.appendingPathComponent(e)
            if fm.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) {
                claimed.insert(e)
                found.append((url, dir, "Python"))
            }
        }

        for c in children {
            let n = c.lastPathComponent
            guard !claimed.contains(n), !noDescend.contains(n), !n.hasPrefix("."),
                  let v = try? c.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                  v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { continue }
            walk(c, depth: depth + 1, into: &found)
        }
    }

    // ".sln" gibi uzantılar dosya adının sonuna, diğerleri tam ada bakar
    private static func matches(_ k: Kind, _ names: Set<String>) -> Bool {
        k.markers.contains { m in m.hasPrefix(".") ? names.contains { $0.hasSuffix(m) } : names.contains(m) }
    }

    private static func repoRoot(of dir: URL) -> URL? {
        var d = dir
        while d.path.hasPrefix(home.path + "/") {
            if FileManager.default.fileExists(atPath: d.appendingPathComponent(".git").path) { return d }
            d = d.deletingLastPathComponent()
        }
        return nil
    }

    /// Projede en son ne zaman bir dosya değişti (artık klasörleri ve .git hariç, en fazla 3 seviye).
    private static func lastActivity(_ project: URL) -> Date {
        var newest = Date.distantPast
        var budget = 3000
        func visit(_ dir: URL, _ depth: Int) {
            guard budget > 0, let kids = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { return }
            for k in kids {
                budget -= 1
                let n = k.lastPathComponent
                if skipActivity.contains(n) || envNames.contains(n) { continue }
                guard let v = try? k.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]) else { continue }
                if let d = v.contentModificationDate, d > newest { newest = d }
                if v.isDirectory == true, depth < 3 { visit(k, depth + 1) }
            }
        }
        visit(project, 0)
        return newest == .distantPast ? Date() : newest
    }

    // Son değişiklik hesaplanırken bakılmayanlar: artıkların kendisi ve araçların sürekli dokunduğu klasörler
    private static let skipActivity: Set<String> = Set(kinds.flatMap { $0.artifacts + $0.repoOnly })
        .union([".git", "__pycache__", ".DS_Store", ".idea", ".vscode"])

    private static func isDir(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Çalışan işlemlerin program yolu ve çalışma klasörü: bir projenin içindeyse o proje "çalışıyor" sayılır.
    static func processPaths() -> [String] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var paths: [String] = []
        var buf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(max(got, 0))) where pid > 0 {
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { paths.append(String(cString: buf)) }
            var vpi = proc_vnodepathinfo()
            if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 {
                let cwd = withUnsafePointer(to: &vpi.pvi_cdir.vip_path) {
                    String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
                }
                if !cwd.isEmpty { paths.append(cwd + "/") }
            }
        }
        return paths
    }
}
