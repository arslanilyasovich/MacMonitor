import SwiftUI
import AppKit

// MARK: - Sistem Çöpü

struct CleanupView: View {
    @ObservedObject var c: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(title: t("Sistem Çöpü", "System Junk"),
                               subtitle: t("Önbellekler, günlükler, geliştirici artıkları, kurulum dosyaları ve Çöp Kutusu. Apple'ın sistem önbelleklerine dokunulmaz.",
                                           "Caches, logs, developer leftovers, installers and the Trash. Apple's system caches are never touched."))
                    if c.busy && c.cats.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text(t("Taranıyor…", "Scanning…")).foregroundStyle(Theme.secondary) }
                    }
                    ForEach($c.cats) { $cat in
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: $cat.selected).toggleStyle(.checkbox).labelsHidden()
                                    Image(systemName: cat.icon).font(.system(size: 20)).foregroundStyle(Theme.accent).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.title).font(.system(size: 14, weight: .semibold))
                                        Text(cat.note).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                        if cat.id == "mail" && cat.unknownSize {
                                            LinkButton(title: t("Tam Disk Erişimi ver", "Grant Full Disk Access")) {
                                                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                                            }
                                        }
                                        if !cat.inUse.isEmpty {
                                            let size = fmtBytes(cat.inUse.reduce(0) { $0 + $1.size })
                                            Text(t("\(cat.inUse.count) öğe (\(size)) atlandı — uygulaması açık. Kapatıp yeniden tarayınca temizlenebilir.",
                                                   "\(cat.inUse.count) items (\(size)) skipped — their app is open. Quit it and rescan to clean."))
                                                .font(.system(size: 11)).foregroundStyle(Theme.warn)
                                        }
                                    }
                                    Spacer()
                                    Text(cat.unknownSize ? "?" : fmtBytes(cat.size))
                                        .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                    Button { c.toggleExpanded(cat.id) } label: {
                                        Image(systemName: c.expanded.contains(cat.id) ? "chevron.up" : "chevron.down")
                                            .frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.secondary)
                                    .disabled(cat.items.isEmpty && cat.inUse.isEmpty)
                                }
                                if c.expanded.contains(cat.id) {
                                    VStack(spacing: 5) {
                                        ForEach(cat.items.prefix(cat.id == "dev" ? 100 : 30)) { item in
                                            let on = Binding<Bool>(
                                                get: { !cat.excluded.contains(item.id) },
                                                set: { v in if v { $cat.wrappedValue.excluded.remove(item.id) } else { $cat.wrappedValue.excluded.insert(item.id) } })
                                            HStack(alignment: .top, spacing: 8) {
                                                Toggle("", isOn: on).toggleStyle(.checkbox).labelsHidden().controlSize(.small)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    HStack(spacing: 6) {
                                                        Text(item.dev?.name ?? item.url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                                        if item.dev?.caution == true { RiskTag(text: t("dikkat", "caution"), color: Theme.warn) }
                                                    }
                                                    if let d = item.dev {
                                                        Text(d.note).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2)
                                                    }
                                                }
                                                Spacer()
                                                Text(fmtBytes(item.size)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                                                Button { revealInFinder(item.url) } label: { Image(systemName: "magnifyingglass").font(.system(size: 11)) }
                                                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).help(t("Finder'da göster", "Show in Finder"))
                                            }
                                            .opacity(cat.excluded.contains(item.id) ? 0.55 : 1)
                                        }
                                        ForEach(cat.inUse) { item in
                                            HStack {
                                                Text(item.dev?.name ?? item.url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                                Text(t("kullanımda", "in use")).font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                                    .background(Capsule().fill(Theme.warn.opacity(0.18))).foregroundStyle(Theme.warn)
                                                Spacer()
                                                Text(fmtBytes(item.size)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                                            }
                                        }
                                        if cat.id != "dev" && cat.items.count > 30 {
                                            Text(t("+\(cat.items.count - 30) öğe daha", "+\(cat.items.count - 30) more items"))
                                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                        }
                                    }
                                    .padding(.leading, 62)
                                }
                            }
                        }
                    }
                }
                .padding(28)
            }
            HStack(spacing: 12) {
                if let r = c.lastResult { Text(r).font(.system(size: 13)).foregroundStyle(Theme.good) }
                Spacer()
                SecondaryButton(title: c.busy ? t("Çalışıyor…", "Working…") : t("Yeniden tara", "Rescan"), disabled: c.busy) { c.scan() }
                PrimaryButton(title: t("Temizle · ", "Clean · ") + fmtBytes(c.selectedTotal),
                              disabled: c.busy || (c.selectedTotal == 0 && !c.trashSelected)) { c.clean() }
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(Color.black.opacity(0.25))
        }
        .onAppear { if c.cats.isEmpty { c.scan() } }
    }
}

/// Küçük renkli etiket: "dikkat", "kullanımda", "çalışıyor"…
struct RiskTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18))).foregroundStyle(color)
    }
}

// MARK: - Dağınıklık

struct ClutterView: View {
    @ObservedObject var cl: ClutterModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        PageHeader(title: t("Dağınıklık", "My Clutter"),
                                   subtitle: t("İndirilenler, Masaüstü, Belgeler ve Filmler'deki büyük, eski ve kopya dosyalar. Silinenler Çöp Kutusu'na gider.",
                                               "Large, old and duplicate files in Downloads, Desktop, Documents and Movies. Removed files go to the Trash."))
                        Picker("", selection: $cl.tab) {
                            Text(t("Büyük Dosyalar", "Large Files")).tag(0)
                            Text(t("Kopyalar", "Duplicates")).tag(1)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    }
                    if cl.scanning {
                        HStack { ProgressView().controlSize(.small); Text(t("Dosyalar taranıyor…", "Scanning files…")).foregroundStyle(Theme.secondary) }
                    }
                    if cl.tab == 0 {
                        Card(padding: 8) {
                            VStack(spacing: 0) {
                                if cl.big.isEmpty && !cl.scanning {
                                    Text(t("100 MB üstü dosya bulunamadı.", "No files over 100 MB found.")).foregroundStyle(Theme.secondary).padding()
                                }
                                ForEach(cl.big) { f in FileRow(f: f, cl: cl) }
                            }
                        }
                    } else {
                        if cl.dups.isEmpty && !cl.scanning {
                            Card { Text(t("Kopya dosya bulunamadı.", "No duplicates found.")).foregroundStyle(Theme.secondary) }
                        }
                        ForEach(cl.dups) { g in
                            Card(padding: 8) {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Text(g.files.first?.url.lastPathComponent ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Spacer()
                                        Text(t("\(g.files.count) kopya · \(fmtBytes(g.waste)) israf", "\(g.files.count) copies · \(fmtBytes(g.waste)) wasted"))
                                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                                    }
                                    .padding(8)
                                    ForEach(g.files) { f in FileRow(f: f, cl: cl) }
                                }
                            }
                        }
                    }
                }
                .padding(28)
            }
            HStack {
                if let m = cl.message { Text(m).font(.system(size: 13)).foregroundStyle(Theme.good) }
                Spacer()
                SecondaryButton(title: cl.scanning ? t("Taranıyor…", "Scanning…") : t("Yeniden tara", "Rescan"), disabled: cl.scanning) { cl.scan() }
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(Color.black.opacity(0.25))
        }
        .onAppear { if !cl.scannedOnce && !cl.scanning { cl.scan() } }
    }
}

struct FileRow: View {
    let f: FileEntry
    @ObservedObject var cl: ClutterModel

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(path: f.url.path, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.url.lastPathComponent).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                Text(f.url.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "~"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.head)
            }
            .help(f.url.path)
            if f.isOld {
                Text(t("6+ ay açılmadı", "Unused 6+ months")).font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.warn.opacity(0.18)))
                    .foregroundStyle(Theme.warn)
            }
            Spacer()
            Text(fmtBytes(f.size)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.secondary)
            Button { revealInFinder(f.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help(t("Finder'da göster", "Show in Finder"))
            Button { cl.trash(f) } label: { Image(systemName: "trash").foregroundStyle(Theme.bad) }
                .buttonStyle(.plain).help(t("Çöp Kutusu'na taşı (geri alınabilir)", "Move to Trash (undoable)"))
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
    }
}

// MARK: - Koruma

struct ProtectionView: View {
    @ObservedObject var sec: SecurityModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    PageHeader(title: t("Koruma", "Protection"),
                               subtitle: t("macOS güvenlik ayarlarını ve başlangıç öğeleri ile uygulamaların imzalarını kontrol eder. Kırık (crack) ve imzasız yazılımları yakalar. Gerçek zamanlı antivirüs değildir — o işi Apple'ın XProtect'i yapar.",
                                           "Checks macOS security settings and the signatures of launch items and apps. Catches cracked and unsigned software. Not a real-time antivirus — Apple's XProtect does that."))
                    if sec.scanning {
                        ProgressView().controlSize(.small)
                    } else {
                        SecondaryButton(title: t("Yeniden tara", "Rescan")) { sec.scan() }
                    }
                }
                Card {
                    VStack(spacing: 0) {
                        ForEach(sec.checks) { c in
                            HStack(spacing: 12) {
                                Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(c.ok ? Theme.good : Theme.warn)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(.system(size: 13, weight: .semibold))
                                    Text(c.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                if !c.ok, let url = c.fixURL {
                                    SecondaryButton(title: t("Ayarları Aç", "Open Settings")) { openSettings(url) }
                                }
                            }
                            .padding(.vertical, 8)
                            if c.id != sec.checks.last?.id { Divider().overlay(Theme.stroke) }
                        }
                    }
                }
                itemsSection(t("Başlangıç öğeleri ve arka plan servisleri", "Launch items and background services"),
                             sec.items.filter { $0.kindKey != "app" })
                itemsSection(t("Uygulama imzaları", "App signatures"), sec.items.filter { $0.kindKey == "app" })
            }
            .padding(28)
        }
    }

    private func itemsSection(_ title: String, _ items: [SignedItem]) -> some View {
        let bad = items.filter { !$0.ok }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(bad == 0 ? t("Hepsi doğrulandı", "All verified") : t("\(bad) uyarı", "\(bad) warnings")).font(.system(size: 12))
                    .foregroundStyle(bad == 0 ? Theme.good : Theme.warn)
            }
            Card(padding: 8) {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        Text(sec.scanning ? t("Kontrol ediliyor…", "Checking…") : t("Öğe yok", "No items")).foregroundStyle(Theme.secondary).padding(8)
                    }
                    ForEach(items.sorted { !$0.ok && $1.ok }) { item in
                        HStack(spacing: 10) {
                            AppIcon(path: item.iconPath, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text("\(item.kind) · \(item.signer)").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                            Spacer()
                            if item.ok {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good)
                            } else {
                                Text(item.note).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.warn)
                                Button { revealInFinder(URL(fileURLWithPath: item.path)) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.plain).help(t("Finder'da göster", "Show in Finder"))
                            }
                        }
                        .padding(.vertical, 6).padding(.horizontal, 6)
                    }
                }
            }
        }
    }
}

// MARK: - Performans

struct PerformanceView: View {
    @ObservedObject var sys: SystemModel
    @ObservedObject var ui: UIModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: t("Performans", "Performance"),
                           subtitle: t("Bellek kullanımı, ağır uygulamalar ve bakım görevleri.", "Memory usage, heavy apps and maintenance tasks."))
                Card(padding: 20) { MemoryDetailView(sys: sys) }
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("Bakım Görevleri", "Maintenance")).font(.system(size: 16, weight: .semibold))
                        task("purge", t("RAM'i boşalt", "Free up RAM"),
                             t("Disk önbelleği için ayrılmış belleği serbest bırakır.", "Releases memory held for disk cache."))
                        task("dns", t("DNS önbelleğini temizle", "Flush DNS cache"),
                             t("Siteler açılmıyor veya yanlış adrese gidiyorsa işe yarar.", "Helps when sites won't load or resolve wrongly."))
                        task("spotlight", t("Spotlight dizinini yeniden oluştur", "Reindex Spotlight"),
                             t("Arama bozuksa kullan. Yeniden dizinleme bir süre CPU kullanır.", "Use if search is broken. Reindexing uses CPU for a while."))
                        HStack {
                            if let r = sys.maintenanceResult { Text(r).font(.system(size: 13)).foregroundStyle(Theme.good) }
                            else { Text(t("Yönetici şifresi istenir.", "Requires your admin password.")).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                            Spacer()
                            PrimaryButton(title: sys.maintenanceRunning ? t("Çalışıyor…", "Running…") : t("Seçilenleri Çalıştır", "Run Selected"),
                                          disabled: ui.maintTasks.isEmpty || sys.maintenanceRunning) {
                                sys.runMaintenance(ui.maintTasks)
                            }
                        }
                    }
                }
                Card(padding: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("Giriş öğeleri", "Login items")).font(.system(size: 16, weight: .semibold))
                            Text(t("Açılışta kendiliğinden başlayan uygulamaları macOS ayarlarından yönet.", "Manage apps that open at login in macOS Settings."))
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        SecondaryButton(title: t("Giriş Öğeleri'ni Aç", "Open Login Items")) {
                            openSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func task(_ id: String, _ title: String, _ note: String) -> some View {
        let binding = Binding<Bool>(
            get: { ui.maintTasks.contains(id) },
            set: { on in if on { ui.maintTasks.insert(id) } else { ui.maintTasks.remove(id) } })
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - Uygulama Kaldırıcı

struct AppsView: View {
    @ObservedObject var apps: AppsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: t("Uygulama Kaldırıcı", "Uninstaller"),
                       subtitle: t("Uygulamayı ve Kitaplık'taki artık dosyalarını birlikte kaldırır. Hepsi Çöp Kutusu'na gider.",
                                   "Removes an app together with its leftover files in Library. Everything goes to the Trash."))
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)
            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    TextField(t("Uygulama ara", "Search apps"), text: $apps.query).textFieldStyle(.roundedBorder)
                    if apps.loading { ProgressView().controlSize(.small) }
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(apps.filtered) { a in
                                Button { apps.select(a) } label: {
                                    HStack(spacing: 10) {
                                        AppIcon(path: a.path, size: 28)
                                        Text(a.name).font(.system(size: 13)).lineLimit(1)
                                        Spacer()
                                        Text(a.size < 0 ? "…" : fmtBytes(a.size))
                                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                                    }
                                    .padding(.vertical, 5).padding(.horizontal, 8)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(apps.selectedPath == a.path ? Theme.accent.opacity(0.14) : .clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(width: 330)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.25)))
                .padding(.leading, 28).padding(.bottom, 28)

                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if apps.apps.isEmpty { apps.load() } }
    }

    @ViewBuilder private var detail: some View {
        if let a = apps.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        AppIcon(path: a.path, size: 76)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.name).font(.system(size: 22, weight: .bold))
                            Text(a.bundleID ?? "—").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            Text(t("Sürüm", "Version") + " \(a.version ?? "?") · \(a.size < 0 ? "…" : fmtBytes(a.size))")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Text(t("Kaldırılacaklar", "Will be removed")).font(.system(size: 15, weight: .semibold))
                    Card(padding: 10) {
                        VStack(spacing: 4) {
                            row(URL(fileURLWithPath: a.path), max(a.size, 0))
                            if apps.findingLeftovers { ProgressView().controlSize(.small).padding(6) }
                            ForEach(apps.leftovers) { l in row(l.url, l.size) }
                        }
                    }
                    HStack {
                        if let m = apps.message { Text(m).font(.system(size: 13)).foregroundStyle(Theme.warn) }
                        Spacer()
                        PrimaryButton(title: apps.pendingRemove ? t("Emin misin? Kaldır", "Sure? Remove")
                                          : t("Kaldır · ", "Remove · ") + fmtBytes(apps.removalTotal)) {
                            apps.uninstall()
                        }
                    }
                    Text(t("Uygulama ve artık dosyaları Çöp Kutusu'na taşınır; vazgeçersen oradan geri alabilirsin.",
                           "The app and its leftovers are moved to the Trash; restore them from there if you change your mind."))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "square.grid.2x2").font(.system(size: 48)).foregroundStyle(Theme.secondary)
                Text(t("Kaldırmak istediğin uygulamayı soldan seç", "Pick an app on the left to remove")).foregroundStyle(Theme.secondary)
                if let m = apps.message { Text(m).font(.system(size: 13)).foregroundStyle(Theme.good) }
                Spacer()
            }
        }
    }

    private func row(_ url: URL, _ size: Int64) -> some View {
        HStack(spacing: 10) {
            AppIcon(path: url.path, size: 22)
            Text(url.path.replacingOccurrences(of: home.path, with: "~"))
                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(fmtBytes(size)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
    }
}
