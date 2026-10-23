import SwiftUI
import AppKit

// MARK: - Alan Haritası (Space Lens)

struct SpaceLensView: View {
    @ObservedObject var lens: SpaceLensModel

    private let palette: [Color] = [Theme.accent, Theme.accent2, Color(red: 0.6, green: 0.5, blue: 1.0),
                                    Theme.good, Theme.warn, Color(red: 1.0, green: 0.5, blue: 0.7)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    PageHeader(title: t("Alan Haritası", "Space Lens"),
                               subtitle: t("Hangi klasörün ne kadar yer kapladığını gör. Klasöre tıklayarak içine gir; silinenler Çöp Kutusu'na gider.",
                                           "See what takes up space. Click a folder to go inside; removed items go to the Trash."))
                    SecondaryButton(title: t("Yeniden hesapla", "Rescan"), disabled: lens.loading) { lens.rescan() }
                }
                // Konum çubuğu: ~ › Library › Caches
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(lens.path.enumerated()), id: \.offset) { i, url in
                            if i > 0 { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                            Button(i == 0 ? t("Ana klasör", "Home") : url.lastPathComponent) { lens.goTo(i) }
                                .buttonStyle(.plain)
                                .font(.system(size: 13, weight: i == lens.path.count - 1 ? .semibold : .regular))
                                .foregroundStyle(i == lens.path.count - 1 ? Color.white : Theme.accent)
                        }
                    }
                }
                HStack {
                    Text(t("Toplam: ", "Total: ") + fmtBytes(lens.total)).font(.system(size: 13, weight: .semibold))
                    if lens.loading {
                        ProgressView().controlSize(.small)
                        Text(t("Hesaplanıyor: ", "Calculating: ") + lens.progress).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let m = lens.message { Text(m).font(.system(size: 12)).foregroundStyle(Theme.good) }
                }
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 6) {
                    let maxSize = Double(lens.items.first?.size ?? 1)
                    ForEach(Array(lens.items.enumerated()), id: \.element.id) { i, item in
                        row(item, fraction: Double(item.size) / maxSize, color: palette[i % palette.count])
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
            }
        }
        .onAppear { if lens.items.isEmpty && !lens.loading { lens.load() } }
    }

    private func row(_ item: LensItem, fraction: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            AppIcon(path: item.url.path, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if item.isDir { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    Spacer()
                    Text(fmtBytes(item.size)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    if lens.total > 0 {
                        Text(String(format: "%.0f%%", Double(item.size) / Double(lens.total) * 100))
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).frame(width: 36, alignment: .trailing)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule().fill(LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * fraction))
                            .shadow(color: color.opacity(0.4), radius: 4)
                    }
                }
                .frame(height: 6)
            }
            Button { revealInFinder(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help(t("Finder'da göster", "Show in Finder"))
            Button { lens.trash(item) } label: {
                if lens.pendingTrash == item.id {
                    Text(t("Emin misin?", "Sure?")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.bad)
                } else {
                    Image(systemName: "trash").foregroundStyle(Theme.bad)
                }
            }
            .buttonStyle(.plain).help(t("Çöp Kutusu'na taşı", "Move to Trash"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .contentShape(Rectangle())
        .onTapGesture { lens.open(item) }
    }
}

// MARK: - Araçlarım

struct ToolsView: View {
    @ObservedObject var tm: TimeMachineModel
    @ObservedObject var leftovers: LeftoversModel
    @ObservedObject var ui: UIModel
    @ObservedObject var clutter: ClutterModel
    @ObservedObject var projects: ProjectsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: t("Araçlarım", "My Tools"),
                           subtitle: t("Mac'ini temiz, güvenli ve hızlı tutmak için araçlar.", "Your go-to tools for keeping your Mac clean, safe and running smoothly."))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    tool("hammer.circle.fill", Theme.good, t("Proje Artıkları", "Project Leftovers"),
                         t("Projelerdeki node_modules, venv, target gibi yeniden oluşturulabilen klasörler.", "Rebuildable folders in your projects: node_modules, venv, target and more."), t("Tara", "Scan")) {
                        ui.toolPage = "projects"
                        if !projects.scannedOnce { projects.scan() }
                    }
                    tool("wrench.and.screwdriver.fill", Theme.warn, t("Bakım Görevleri", "Maintenance Tasks"),
                         t("RAM boşalt, DNS ve Spotlight onarımı.", "Free RAM, flush DNS, repair Spotlight."), t("Aç", "Open")) {
                        ui.section = .performance
                    }
                    tool("doc.on.doc.fill", Theme.accent, t("Kopya Bulucu", "Duplicate Finder"),
                         t("Farklı yerlerde duran aynı dosyaları bul.", "Find identical files stored in different places."), t("Aç", "Open")) {
                        clutter.tab = 1
                        ui.section = .clutter
                    }
                    tool("lock.shield.fill", Theme.bad, t("Uygulama İzinleri", "App Permissions"),
                         t("Kamera, mikrofon, ekran kaydı ve diğer izinleri yönet.", "Manage camera, mic, screen recording and more."), t("Göster", "Show")) {
                        ui.toolPage = "permissions"
                    }
                    tool("folder.fill", Theme.good, t("Büyük ve Eski Dosyalar", "Large and Old Files"),
                         t("Yer kaplayan, kullanılmayan dosyaları bul.", "Find large, unused files taking up space."), t("Aç", "Open")) {
                        clutter.tab = 0
                        ui.section = .clutter
                    }
                    tool("shippingbox.fill", Theme.accent2, t("Uygulama Artıkları", "App Leftovers"),
                         t("Silinmiş uygulamalardan kalan dosyaları bul.", "Find files left behind by deleted apps."), t("Tara", "Scan")) {
                        ui.toolPage = "leftovers"
                        if !leftovers.scannedOnce { leftovers.scan() }
                    }
                    tool("clock.arrow.circlepath", Color(red: 1.0, green: 0.55, blue: 0.3), t("Time Machine Anlık Görüntüleri", "Time Machine Snapshots"),
                         t("Diskteki yerel anlık görüntüleri sil; yedeklerin etkilenmez.", "Remove local snapshots without affecting your backups."), t("Tara", "Scan")) {
                        ui.toolPage = "timemachine"
                        tm.load()
                    }
                }

                switch ui.toolPage {
                case "projects": projectsSection
                case "leftovers": leftoversSection
                case "timemachine": timeMachineSection
                case "permissions": permissionsSection
                default: EmptyView()
                }
            }
            .padding(28)
        }
    }

    private func tool(_ icon: String, _ color: Color, _ title: String, _ text: String, _ button: String, action: @escaping () -> Void) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11).fill(color.opacity(0.14)))
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack { Spacer(); SecondaryButton(title: button, action: action) }
            }
        }
        .frame(height: 190)
    }

    private var leftoversSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Uygulama Artıkları", "App Leftovers")).font(.system(size: 17, weight: .semibold))
                if leftovers.scanning { ProgressView().controlSize(.small) }
                Spacer()
                if !leftovers.items.isEmpty {
                    SecondaryButton(title: t("Tümünü seç", "Select all")) { leftovers.selected = Set(leftovers.items.map(\.id)) }
                }
                SecondaryButton(title: t("Yeniden tara", "Rescan"), disabled: leftovers.scanning) { leftovers.scan() }
                PrimaryButton(title: t("Çöpe taşı · ", "Move to Trash · ") + fmtBytes(leftovers.selectedSize),
                              disabled: leftovers.selected.isEmpty) { leftovers.trashSelected() }
            }
            Text(t("Kurulu olmayan uygulamalara ait görünen dosyalar. Emin olduklarını seç; hepsi Çöp Kutusu'na gider, gerekirse geri alabilirsin.",
                   "Files that seem to belong to apps that aren't installed. Pick the ones you're sure about; they go to the Trash and can be restored."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            if let m = leftovers.message { Text(m).font(.system(size: 12)).foregroundStyle(Theme.good) }
            Card(padding: 8) {
                VStack(spacing: 0) {
                    if leftovers.items.isEmpty {
                        Text(leftovers.scanning ? t("Taranıyor…", "Scanning…") : t("Artık dosya bulunamadı.", "No leftovers found."))
                            .foregroundStyle(Theme.secondary).padding(8)
                    }
                    ForEach(leftovers.items) { item in
                        let binding = Binding<Bool>(
                            get: { leftovers.selected.contains(item.id) },
                            set: { on in if on { leftovers.selected.insert(item.id) } else { leftovers.selected.remove(item.id) } })
                        HStack(spacing: 10) {
                            Toggle("", isOn: binding).toggleStyle(.checkbox).labelsHidden()
                            AppIcon(path: item.url.path, size: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.bundleID).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(item.url.path.replacingOccurrences(of: home.path, with: "~"))
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(fmtBytes(item.size)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                            Button { revealInFinder(item.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 6)
                    }
                }
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Proje Artıkları", "Project Leftovers")).font(.system(size: 17, weight: .semibold))
                if projects.scanning { ProgressView().controlSize(.small) }
                Spacer()
                if !projects.items.isEmpty {
                    SecondaryButton(title: t("\(ProjectsModel.minAgeDays)+ gün eskileri seç", "Select \(ProjectsModel.minAgeDays)+ days old")) {
                        projects.selected = Set(projects.items.filter { $0.usable && $0.ageDays >= ProjectsModel.minAgeDays }.map(\.id))
                    }
                }
                SecondaryButton(title: t("Yeniden tara", "Rescan"), disabled: projects.scanning) { projects.scan() }
                PrimaryButton(title: t("Çöpe taşı · ", "Move to Trash · ") + fmtBytes(projects.selectedSize),
                              disabled: projects.selected.isEmpty || projects.scanning) { projects.trashSelected() }
            }
            Text(t("Masaüstü, Belgeler ve ev klasöründeki projeler taranır. Çalışan bir programı olan projeler ve git'te takip edilen dosyalar atlanır. Varsayılan olarak sadece \(ProjectsModel.minAgeDays) günden uzun süredir dokunulmamış olanlar seçilir; Python ortamları (venv) yeniden kurulum istediği için seçilmez.",
                   "Projects in Desktop, Documents and your home folder are scanned. Projects with a running program and files tracked by git are skipped. Only folders untouched for \(ProjectsModel.minAgeDays)+ days are selected by default; Python environments (venv) need reinstalling, so they aren't."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let m = projects.message { Text(m).font(.system(size: 12)).foregroundStyle(Theme.good) }
            Card(padding: 8) {
                VStack(spacing: 0) {
                    if projects.items.isEmpty {
                        Text(projects.scanning ? t("Projeler taranıyor…", "Scanning projects…") : t("Proje artığı bulunamadı.", "No project leftovers found."))
                            .foregroundStyle(Theme.secondary).padding(8)
                    }
                    ForEach(projects.items) { a in
                        let binding = Binding<Bool>(
                            get: { projects.selected.contains(a.id) },
                            set: { on in if on { projects.selected.insert(a.id) } else { projects.selected.remove(a.id) } })
                        HStack(spacing: 10) {
                            Toggle("", isOn: binding).toggleStyle(.checkbox).labelsHidden().disabled(!a.usable)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(a.project.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(a.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.accent)
                                    Text(a.type).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    if a.running { RiskTag(text: t("çalışıyor", "running"), color: Theme.warn) }
                                    if let why = a.blocked { RiskTag(text: why, color: Theme.bad) }
                                    if a.reinstall && a.usable { RiskTag(text: t("yeniden kurulum", "reinstall"), color: Theme.warn) }
                                }
                                Text(a.note + " · " + t("son değişiklik \(a.ageDays) gün önce", "last changed \(a.ageDays) days ago"))
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Text(a.url.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "~"))
                                    .font(.system(size: 10)).foregroundStyle(Theme.secondary.opacity(0.8)).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(fmtBytes(a.size)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            Button { revealInFinder(a.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 6)
                        .opacity(a.usable ? 1 : 0.55)
                    }
                }
            }
        }
    }

    private var timeMachineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Time Machine Anlık Görüntüleri", "Time Machine Snapshots")).font(.system(size: 17, weight: .semibold))
                if tm.loading { ProgressView().controlSize(.small) }
                Spacer()
                PrimaryButton(title: t("Hepsini sil", "Delete all"), disabled: tm.snapshots.isEmpty) { tm.deleteAll() }
            }
            Text(t("macOS, Time Machine diski takılı değilken yedekleri geçici olarak bu diskte tutar. Bunları silmek harici yedeklerine dokunmaz. Yönetici şifresi istenir.",
                   "macOS keeps temporary snapshots on this disk when the backup drive isn't connected. Deleting them doesn't touch your real backups. Requires your admin password."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let m = tm.message { Text(m).font(.system(size: 12)).foregroundStyle(Theme.good) }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    if tm.loaded && tm.snapshots.isEmpty {
                        Label(t("Yerel anlık görüntü yok", "No local snapshots"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    }
                    ForEach(tm.snapshots, id: \.self) { s in
                        Label(s, systemImage: "clock").font(.system(size: 13).monospacedDigit())
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionsSection: some View {
        let panes: [(String, String, String)] = [
            ("externaldrive.fill", t("Tam Disk Erişimi", "Full Disk Access"), "Privacy_AllFiles"),
            ("accessibility", t("Erişilebilirlik", "Accessibility"), "Privacy_Accessibility"),
            ("rectangle.dashed.badge.record", t("Ekran ve Ses Kaydı", "Screen & Audio Recording"), "Privacy_ScreenCapture"),
            ("keyboard", t("Giriş İzleme", "Input Monitoring"), "Privacy_ListenEvent"),
            ("camera.fill", t("Kamera", "Camera"), "Privacy_Camera"),
            ("mic.fill", t("Mikrofon", "Microphone"), "Privacy_Microphone"),
            ("location.fill", t("Konum Servisleri", "Location Services"), "Privacy_LocationServices"),
            ("gearshape.2.fill", t("Otomasyon", "Automation"), "Privacy_Automation"),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text(t("Uygulama İzinleri", "App Permissions")).font(.system(size: 17, weight: .semibold))
            Text(t("Hangi uygulamanın neye erişebildiğini gözden geçir. Tanımadığın ya da artık kullanmadığın uygulamaların iznini kaldır — özellikle Tam Disk Erişimi, Erişilebilirlik ve Ekran Kaydı.",
                   "Review which apps can access what. Remove access for apps you don't recognize or no longer use — especially Full Disk Access, Accessibility and Screen Recording."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(panes, id: \.2) { icon, title, anchor in
                    Card {
                        HStack(spacing: 10) {
                            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
                            Text(title).font(.system(size: 13, weight: .medium))
                            Spacer()
                            SecondaryButton(title: t("Aç", "Open")) {
                                openSettings("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Etkinliğim

struct ActivityView: View {
    @ObservedObject var sys: SystemModel
    @ObservedObject var sec: SecurityModel
    @ObservedObject var cleaner: CleanerModel
    @ObservedObject var clutter: ClutterModel
    @ObservedObject var ui: UIModel
    @ObservedObject var projects: ProjectsModel
    @ObservedObject var store = ActivityStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: t("Etkinliğim", "My Activity"),
                           subtitle: t("Mac'inin genel durumu ve MacMonitor ile kazandıkların.", "Your Mac's overall state and what you've gained with MacMonitor."))
                HStack(spacing: 14) {
                    Card(padding: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(t("Mac Sağlığı", "Mac Health")).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            let issues = (sys.pressureLevel >= 2 ? 1 : 0) + (sec.issueCount > 0 ? 1 : 0)
                            Text(issues == 0 ? t("Mükemmel", "Excellent") : issues == 1 ? t("İyi", "Good") : t("Dikkat", "Fair"))
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(issues == 0 ? Theme.good : issues == 1 ? Theme.accent : Theme.warn)
                            Text(sys.machineName + (sys.chipName.isEmpty ? "" : " · \(sys.chipName)"))
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            Spacer(minLength: 10)
                            HStack {
                                Text(sys.diskName).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(t("\(fmtBytes(sys.diskTotal - sys.diskFree)) / \(fmtBytes(sys.diskTotal)) dolu", "\(fmtBytes(sys.diskTotal - sys.diskFree)) of \(fmtBytes(sys.diskTotal)) used"))
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            ProgressView(value: sys.diskTotal > 0 ? Double(sys.diskTotal - sys.diskFree) / Double(sys.diskTotal) : 0)
                                .tint(Theme.accent)
                            if let d = sys.diskForecastDays {
                                Label(t("Bu hızla disk ~\(d) gün sonra dolacak", "At this rate the disk is full in ~\(d) days"), systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 12)).foregroundStyle(d < 30 ? Theme.bad : Theme.warn)
                            }
                        }
                    }
                    VStack(spacing: 14) {
                        stat("arrow.down.circle.fill", Theme.good, fmtBytes(store.freedTotal), t("kalıcı olarak silindi", "permanently freed"))
                        stat("trash.fill", Theme.warn, fmtBytes(store.trashedTotal), t("Çöp Kutusu'na taşındı", "moved to Trash"))
                        stat("sparkles", Theme.accent, "\(store.cleanCount)", t("temizlik yapıldı", "cleanups done"))
                        stat("clock.fill", Theme.accent2, ago(store.lastClean), t("son temizlik", "last cleanup"))
                    }
                    .frame(width: 280)
                }
                .fixedSize(horizontal: false, vertical: true)

                let recs = recommendations(sys: sys, sec: sec, cleaner: cleaner, clutter: clutter, projects: projects)
                Text(t("\(recs.count) Öneri", "\(recs.count) Recommendations")).font(.system(size: 16, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(recs) { rec in
                        RecommendationCard(rec: rec) { r in
                            if r.id == "projects" {
                                ui.toolPage = "projects"
                                if !projects.scannedOnce { projects.scan() }
                            }
                            if let s = r.section { ui.section = s }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func stat(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit()
                    Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
        }
    }
}
