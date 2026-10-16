import SwiftUI
import CryptoKit

struct FileEntry: Identifiable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let lastUsed: Date?
    var isOld: Bool {
        guard let d = lastUsed else { return false }
        return d < Date().addingTimeInterval(-180 * 86_400)
    }
}

struct DupGroup: Identifiable {
    let id: String
    var files: [FileEntry]
    var size: Int64 { files.first?.size ?? 0 }
    var waste: Int64 { size * Int64(max(files.count - 1, 0)) }
}

/// Dağınıklık: büyük/eski dosyalar ve birebir aynı (kopya) dosyalar.
final class ClutterModel: ObservableObject {
    @Published var big: [FileEntry] = []
    @Published var dups: [DupGroup] = []
    @Published var scanning = false
    @Published var scannedOnce = false
    @Published var message: String?
    @Published var tab = 0

    var dupWaste: Int64 { dups.reduce(0) { $0 + $1.waste } }

    static let roots = ["Downloads", "Desktop", "Documents", "Movies"]
    // Kod projelerinin içindeki binlerce küçük dosyayla uğraşmamak için
    static let skipDirs: Set<String> = ["node_modules", "venv", "__pycache__", "build", "DerivedData", "Pods", "site-packages", "dist", "target"]

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .contentAccessDateKey]
            var all: [FileEntry] = []
            outer: for root in Self.roots {
                guard let e = fm.enumerator(at: home.appendingPathComponent(root), includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in e {
                    guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                    if v.isDirectory == true {
                        if Self.skipDirs.contains(url.lastPathComponent) { e.skipDescendants() }
                        continue
                    }
                    guard v.isRegularFile == true, let s = v.totalFileAllocatedSize, s >= 1_000_000 else { continue }
                    all.append(FileEntry(url: url, size: Int64(s), lastUsed: v.contentAccessDate))
                    if all.count > 100_000 { break outer }
                }
            }

            let big = Array(all.filter { $0.size >= 100_000_000 }.sorted { $0.size > $1.size }.prefix(60))

            // Kopyalar: önce boyuta göre grupla, sadece aynı boyuttakilerin içeriğini karşılaştır
            var bySize: [Int64: [FileEntry]] = [:]
            for f in all { bySize[f.size, default: []].append(f) }
            var groups: [DupGroup] = []
            for (_, files) in bySize where files.count > 1 {
                var byHash: [String: [FileEntry]] = [:]
                for f in files {
                    if let h = Self.hash(f.url) { byHash[h, default: []].append(f) }
                }
                for (h, fs) in byHash where fs.count > 1 { groups.append(DupGroup(id: h, files: fs)) }
            }
            groups.sort { $0.waste > $1.waste }

            DispatchQueue.main.async {
                self.big = big
                self.dups = groups
                self.scanning = false
                self.scannedOnce = true
            }
        }
    }

    func trash(_ f: FileEntry) {
        do {
            try FileManager.default.trashItem(at: f.url, resultingItemURL: nil)
            ActivityStore.shared.record(f.size)
            big.removeAll { $0.url == f.url }
            for i in dups.indices { dups[i].files.removeAll { $0.url == f.url } }
            dups.removeAll { $0.files.count < 2 }
            message = t("✓ \(f.url.lastPathComponent) Çöp Kutusu'na taşındı", "✓ \(f.url.lastPathComponent) moved to Trash")
        } catch {
            message = t("Taşınamadı: \(f.url.lastPathComponent)", "Couldn't move: \(f.url.lastPathComponent)")
        }
    }

    static func hash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var done = false
        while !done {
            autoreleasepool {
                let d = h.readData(ofLength: 1 << 20)
                if d.isEmpty { done = true } else { hasher.update(data: d) }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
