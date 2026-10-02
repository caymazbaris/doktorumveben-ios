import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000270 — HEKİM MODU, 2. AŞAMA: HASTALAR VE TALEPLER.
//
// Kullanıcı (30 Eyl 2026): "tamam hastalar ve talepler aşamasına geç". Kapsam kararı: "Merkez modeli kalsın" — sitedeki
// randevu/fiyat talepleri merkez ekipte kalır; buradaki "Talepler" hekimin kendi panelinde gördükleri: bekleyen iptal
// talepleri + Gelen Sorular.
//
// Görünürlük sunucuda (web CRM ile aynı servis); hangi sekmenin çıkacağı `my/doctor` → `features`. Her liste/kart
// açılışı sunucuda KVKK erişim kaydına düşer — istemcide önbellek YOK (hasta verisi cihazda kalıcı tutulmaz).
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Modeller

struct DVBHekimHastaOzet: Decodable, Identifiable {
    let id: Int
    let name: String?
    let phone: String?
    let patientNo: String?
    let isPrivate: Bool?
    let appointmentsCount: Int?
    let lastVisit: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, phone
        case patientNo = "patient_no"
        case isPrivate = "is_private"
        case appointmentsCount = "appointments_count"
        case lastVisit = "last_visit"
    }
}

private struct DVBHekimHastaSayfasi: Decodable {
    let data: [DVBHekimHastaOzet]
    let page: Int
    let lastPage: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case data, page, total
        case lastPage = "last_page"
    }
}

struct DVBHekimHastaNotu: Decodable, Identifiable {
    let id: Int
    let type: String?
    let typeLabel: String?
    let body: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, body
        case typeLabel = "type_label"
        case createdAt = "created_at"
    }
}

struct DVBHekimHastaKarti: Decodable {
    let id: Int
    let name: String?
    let phone: String?
    let email: String?
    let isPrivate: Bool?
    let patientNo: String?
    let age: Int?
    let gender: String?
    let city: String?
    let stats: Sayilar?
    let tags: [Etiket]?
    let notes: [DVBHekimHastaNotu]?
    let appointments: [Randevu]?

    struct Sayilar: Decodable {
        let completed: Int?
        let noShow: Int?
        let cancelled: Int?
        let reliability: Int?

        enum CodingKeys: String, CodingKey {
            case completed, cancelled, reliability
            case noShow = "no_show"
        }
    }

    struct Etiket: Decodable, Hashable {
        let name: String
        let color: String?
    }

    struct Randevu: Decodable, Identifiable {
        let id: Int
        let startsAt: Date?
        let status: String?
        let statusLabel: String?
        let service: String?

        enum CodingKeys: String, CodingKey {
            case id, status, service
            case startsAt = "starts_at"
            case statusLabel = "status_label"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, age, gender, city, stats, tags, notes, appointments
        case isPrivate = "is_private"
        case patientNo = "patient_no"
    }
}

private struct DVBHekimHastaKartCevabi: Decodable { let patient: DVBHekimHastaKarti }
private struct DVBHekimNotCevabi: Decodable { let note: DVBHekimHastaNotu }

struct DVBHekimSoru: Decodable, Identifiable {
    let slug: String
    let title: String?
    let body: String?
    let directed: Bool?
    let createdAt: Date?
    let myAnswer: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, body, directed
        case createdAt = "created_at"
        case myAnswer = "my_answer"
    }
}

private struct DVBHekimSorular: Decodable {
    let pending: [DVBHekimSoru]
    let answered: [DVBHekimSoru]
}

private enum DVBTarih {
    static func kisa(_ d: Date?) -> String {
        guard let d else { return "—" }
        return DVBSaat.gun(d, "d MMM yyyy")
    }
}

// MARK: - Hastalarım

struct DVBHekimHastalarView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var hastalar: [DVBHekimHastaOzet] = []
    @State private var sayfa = 0
    @State private var sonSayfa = 1
    @State private var toplam = 0
    @State private var arama = ""
    @State private var yukleniyor = false
    @State private var hata: String?

    /// DVB-000109 — bildirimden gelen hasta kartı bu sekmenin kendi gezinmesinde açılır.
    @ObservedObject private var gezinme = DVBGezinme.shared
    @State private var bildirimHastasi: Int?

    var body: some View {
        NavigationView {
            List {
                if let hata, hastalar.isEmpty {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Hastalar alınamadı", message: hata) {
                        Task { await yenile() }
                    }
                } else if !yukleniyor && hastalar.isEmpty {
                    Text(arama.isEmpty ? "Henüz kayıtlı hastanız yok." : "Aramaya uyan hasta yok.")
                        .foregroundColor(.secondary)
                } else {
                    Section {
                        ForEach(hastalar) { h in
                            NavigationLink(destination: DVBHekimHastaKartView(hastaId: h.id, ad: h.name ?? "Hasta")) {
                                satir(h)
                            }
                            .onAppear {
                                if h.id == hastalar.last?.id { Task { await sonrakiSayfa() } }
                            }
                        }
                        if yukleniyor { ProgressView().frame(maxWidth: .infinity) }
                    } footer: {
                        if toplam > 0 { Text("\(toplam) hasta") }
                    }
                }
            }
            .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ad, telefon veya hasta no")
            .refreshable { await yenile() }
            .navigationTitle("Hastalarım")
            // DVB-000109 — bildirimden gelen hasta kartı: listeden dokunulmuş gibi bu yığına itilir.
            .background(
                NavigationLink(
                    destination: DVBHekimHastaKartView(hastaId: bildirimHastasi ?? 0, ad: "Hasta"),
                    isActive: Binding(get: { bildirimHastasi != nil }, set: { if !$0 { bildirimHastasi = nil } })
                ) { EmptyView() }
                .hidden()
            )
            .onReceive(gezinme.$hasta) { id in
                guard let id else { return }
                bildirimHastasi = id
                gezinme.hasta = nil
            }
            // Yazarken her harfte istek atılmasın: 350 ms bekle; yeni harf gelirse önceki görev iptal olur.
            .task(id: arama) {
                try? await Task.sleep(nanoseconds: arama.isEmpty ? 0 : 350_000_000)
                if Task.isCancelled { return }
                await yenile()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func satir(_ h: DVBHekimHastaOzet) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(h.name ?? "—").font(.subheadline.weight(.semibold))
                if h.isPrivate == true {
                    Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary)
                        .accessibilityLabel("Gizli hasta")
                }
            }
            HStack(spacing: 10) {
                if let no = h.patientNo { Text(no) }
                Text("\(h.appointmentsCount ?? 0) randevu")
                if let son = h.lastVisit { Text("Son: \(DVBTarih.kisa(son))") }
            }
            .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func yenile() async {
        sayfa = 0; sonSayfa = 1
        await yukle(sayfa: 1, sifirla: true)
    }

    private func sonrakiSayfa() async {
        guard !yukleniyor, sayfa < sonSayfa else { return }
        await yukle(sayfa: sayfa + 1, sifirla: false)
    }

    private func yukle(sayfa hedef: Int, sifirla: Bool) async {
        guard let token = session.token else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        var q = ["page": String(hedef)]
        let temiz = arama.trimmingCharacters(in: .whitespaces)
        if !temiz.isEmpty { q["q"] = temiz }
        do {
            let s: DVBHekimHastaSayfasi = try await DVBAPI.shared.get("my/doctor/patients", query: q, token: token)
            hastalar = sifirla ? s.data : hastalar + s.data
            sayfa = s.page; sonSayfa = s.lastPage; toplam = s.total
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Hasta kartı

struct DVBHekimHastaKartView: View {
    let hastaId: Int
    let ad: String

    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL

    @State private var kart: DVBHekimHastaKarti?
    @State private var hata: String?
    @State private var notAcik = false

    var body: some View {
        List {
            if let k = kart {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(k.name ?? ad).font(.title3.bold())
                            if k.isPrivate == true {
                                Label("Gizli", systemImage: "lock.fill").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        let alt = [k.patientNo, k.age.map { "\($0) yaş" }, k.gender, k.city].compactMap { $0 }
                        if !alt.isEmpty {
                            Text(alt.joined(separator: " · ")).font(.subheadline).foregroundColor(.secondary)
                        }
                        if let etiketler = k.tags, !etiketler.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(etiketler, id: \.self) { e in
                                    Text(e.name).font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(DVBTheme.brand.opacity(0.12)).foregroundColor(DVBTheme.brand)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let tel = k.phone, !tel.isEmpty {
                    Section("İletişim") {
                        Button { if let u = URL(string: "tel:+\(tel.filter(\.isNumber))") { openURL(u) } } label: {
                            Label(tel, systemImage: "phone")
                        }
                        Button { if let u = URL(string: "https://wa.me/\(tel.filter(\.isNumber))") { openURL(u) } } label: {
                            Label("WhatsApp'tan yaz", systemImage: "message")
                        }
                        if let e = k.email, !e.isEmpty {
                            Button { if let u = URL(string: "mailto:\(e)") { openURL(u) } } label: {
                                Label(e, systemImage: "envelope")
                            }
                        }
                    }
                }

                if let s = k.stats {
                    Section("Geçmiş") {
                        HStack {
                            sayi("Tamamlanan", s.completed ?? 0, .primary)
                            sayi("Gelmedi", s.noShow ?? 0, (s.noShow ?? 0) > 0 ? .red : .primary)
                            sayi("İptal", s.cancelled ?? 0, .primary)
                            if let g = s.reliability { sayi("Güvenilirlik", g, g >= 80 ? DVBTheme.accent : .orange, sonek: "%") }
                        }
                    }
                }

                Section {
                    if let notlar = k.notes, !notlar.isEmpty {
                        ForEach(notlar) { n in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(n.typeLabel ?? "").font(.caption.weight(.semibold)).foregroundColor(DVBTheme.brand)
                                    Spacer()
                                    Text(DVBTarih.kisa(n.createdAt)).font(.caption).foregroundColor(.secondary)
                                }
                                Text(n.body ?? "").font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    } else {
                        Text("Henüz not yok.").foregroundColor(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Notlar")
                        Spacer()
                        Button { notAcik = true } label: { Label("Not ekle", systemImage: "plus") }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                    }
                }

                if let randevular = k.appointments, !randevular.isEmpty {
                    Section("Randevular") {
                        ForEach(randevular) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.startsAt.map { DVBSaat.gun($0, "d MMM yyyy HH:mm") } ?? "—").font(.subheadline)
                                    if let s = r.service { Text(s).font(.caption).foregroundColor(.secondary) }
                                }
                                Spacer()
                                Text(r.statusLabel ?? "").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else if let hata {
                DVBStateView(icon: "exclamationmark.triangle", title: "Hasta kartı açılamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await yukle() }
        .task { await yukle() }
        .sheet(isPresented: $notAcik) {
            DVBHekimNotFormu(hastaId: hastaId) { yeni in
                if let k = kart {
                    // Sunucudan dönen notu başa ekle; kartı yeniden çekmeye gerek yok.
                    kart = DVBHekimHastaKarti(id: k.id, name: k.name, phone: k.phone, email: k.email, isPrivate: k.isPrivate,
                                              patientNo: k.patientNo, age: k.age, gender: k.gender, city: k.city, stats: k.stats,
                                              tags: k.tags, notes: [yeni] + (k.notes ?? []), appointments: k.appointments)
                }
            }
            .environmentObject(session)
        }
    }

    private func sayi(_ etiket: String, _ deger: Int, _ renk: Color, sonek: String = "") -> some View {
        VStack(spacing: 2) {
            Text("\(deger)\(sonek)").font(.headline).foregroundColor(renk).monospacedDigit()
            Text(etiket).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBHekimHastaKartCevabi = try await DVBAPI.shared.get("my/doctor/patients/\(hastaId)", token: token)
            kart = c.patient
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private struct DVBHekimNotFormu: View {
    let hastaId: Int
    var eklendi: (DVBHekimHastaNotu) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var metin = ""
    @State private var tur = "general"
    @State private var gonderiliyor = false
    @State private var hata: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Tür", selection: $tur) {
                        Text("Genel").tag("general")
                        Text("Sağlık").tag("health")
                        Text("Finans").tag("finance")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextEditor(text: $metin).frame(minHeight: 140)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not yalnız sizin panelinizde görünür; hastaya gönderilmez.")
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }
            }
            .navigationTitle("Not ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await kaydet() } }
                        .disabled(gonderiliyor || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            let c: DVBHekimNotCevabi = try await DVBAPI.shared.post(
                "my/doctor/patients/\(hastaId)/notes",
                body: ["body": metin.trimmingCharacters(in: .whitespacesAndNewlines), "type": tur],
                token: token
            )
            eklendi(c.note)
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Talepler (iptal talepleri + Gelen Sorular)

/// DVB-000272 — "Talepler" sekmesi "Gelen Kutusu" oldu: iOS alt çubuğu 5 sekmeden fazlasını "Diğer" menüsüne saklıyor
/// (Hesabım kayboluyordu); Mesajlar ayrı sekme olsaydı 6 olurdu. Hastadan gelen her şey tek yerde: Mesajlar · İptaller ·
/// Sorular. Bölümler sunucunun `features` bilgisine göre görünür.
enum DVBGelenBolum: Hashable { case mesajlar, iptal, sorular }

struct DVBHekimTaleplerView: View {
    /// Bildirimden açılınca gösterilecek bölüm (yoksa ilk açık bölüm).
    var baslangic: DVBGelenBolum? = nil

    @EnvironmentObject private var session: DVBSession

    @State private var secilen: DVBGelenBolum?
    @State private var sohbetler: [DVBHekimSohbetOzet] = []
    @State private var whatsappNotu: String?
    @State private var iptaller: [DVBHekimRandevu] = []
    @State private var bekleyenSorular: [DVBHekimSoru] = []
    @State private var yanitladiklarim: [DVBHekimSoru] = []
    @State private var yukleniyor = false
    @State private var hata: String?
    @State private var yanitlanan: DVBHekimSoru?

    /// DVB-000109 — bildirimden gelen sohbet bu sekmenin kendi gezinmesinde açılır (ayrı sayfa değil).
    @ObservedObject private var gezinme = DVBGezinme.shared
    @State private var bildirimSohbeti: Int?

    private var sorularAcik: Bool { session.hekim?.sorularAcik ?? false }
    private var mesajlarAcik: Bool { session.hekim?.mesajlarAcik ?? false }

    private var bolumler: [DVBGelenBolum] {
        (mesajlarAcik ? [.mesajlar] : []) + [.iptal] + (sorularAcik ? [.sorular] : [])
    }

    private var bolum: DVBGelenBolum {
        let aday = secilen ?? baslangic ?? bolumler.first ?? .iptal
        return bolumler.contains(aday) ? aday : (bolumler.first ?? .iptal)
    }

    var body: some View {
        NavigationView {
            List {
                if bolumler.count > 1 {
                    Picker("Bölüm", selection: Binding(get: { bolum }, set: { secilen = $0 })) {
                        ForEach(bolumler, id: \.self) { b in
                            switch b {
                            case .mesajlar: Text(okunmamisMesaj > 0 ? "Mesajlar (\(okunmamisMesaj))" : "Mesajlar").tag(b)
                            case .iptal: Text("İptaller").tag(b)
                            case .sorular: Text("Sorular").tag(b)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if let hata {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Gelen kutusu alınamadı", message: hata) {
                        Task { await yukle() }
                    }
                } else {
                    switch bolum {
                    case .mesajlar: mesajBolumu
                    case .iptal: iptalBolumu
                    case .sorular: soruBolumu
                    }
                }
            }
            .refreshable { await yukle() }
            .navigationTitle("Gelen Kutusu")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { DVBZilDugmesi() } }
            .task(id: bolum) { await yukle() }
            // Sohbet açılıp okununca rozet değişir → liste de tazelensin (geri dönüşte okunmamış sayısı bayat kalmasın).
            .onChange(of: session.hekim?.unreadMessages) { _ in
                if bolum == .mesajlar { Task { await yukle() } }
            }
            .sheet(item: $yanitlanan) { soru in
                DVBHekimYanitFormu(soru: soru) { Task { await yukle() } }
                    .environmentObject(session)
            }
            // DVB-000109 — bildirimden gelen sohbet: listeden dokunulmuş gibi bu yığına itilir (geri tuşu Gelen Kutusu'na).
            .background(
                NavigationLink(
                    destination: DVBHekimSohbetView(sohbetId: bildirimSohbeti ?? 0, ad: bildirimSohbetAdi),
                    isActive: Binding(get: { bildirimSohbeti != nil }, set: { if !$0 { bildirimSohbeti = nil } })
                ) { EmptyView() }
                .hidden()
            )
            .onReceive(gezinme.$gelenBolum) { b in
                guard let b else { return }
                secilen = b
                gezinme.gelenBolum = nil
            }
            .onReceive(gezinme.$sohbet) { id in
                guard let id else { return }
                secilen = .mesajlar
                bildirimSohbeti = id
                gezinme.sohbet = nil
            }
        }
        .navigationViewStyle(.stack)
    }

    private var bildirimSohbetAdi: String {
        sohbetler.first(where: { $0.id == bildirimSohbeti })?.name ?? "Mesaj"
    }

    private var okunmamisMesaj: Int { session.hekim?.unreadMessages ?? 0 }

    @ViewBuilder private var mesajBolumu: some View {
        Section {
            if yukleniyor && sohbetler.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if sohbetler.isEmpty {
                Text("Henüz hasta mesajı yok.").foregroundColor(.secondary)
            } else {
                ForEach(sohbetler) { s in
                    NavigationLink(destination: DVBHekimSohbetView(sohbetId: s.id, ad: s.name ?? "Hasta")) {
                        sohbetSatiri(s)
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hastaların sitedeki ve uygulamadaki güvenli mesajları. Yanıtınız hastaya bildirim olarak gider.")
                if let not = whatsappNotu { Text(not) }
            }
        }
    }

    private func sohbetSatiri(_ s: DVBHekimSohbetOzet) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(s.unread > 0 ? DVBTheme.brand : Color.clear).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(s.name ?? "Hasta").font(.subheadline.weight(s.unread > 0 ? .semibold : .regular))
                    Spacer()
                    if let t = s.lastMessageAt { Text(DVBSaat.gun(t, "d MMM HH:mm")).font(.caption).foregroundColor(.secondary) }
                }
                if let son = s.lastMessage {
                    Text((s.lastFrom == "doctor" ? "Siz: " : "") + son)
                        .font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
            }
            if s.unread > 0 {
                Text("\(s.unread)").font(.caption2.weight(.bold)).foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(DVBTheme.brand).clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var iptalBolumu: some View {
        Section {
            if yukleniyor && iptaller.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if iptaller.isEmpty {
                Text("Bekleyen iptal talebi yok.").foregroundColor(.secondary)
            } else {
                ForEach(iptaller) { r in
                    NavigationLink(destination: DVBHekimRandevuDetayView(randevuId: r.id, ozet: r) { Task { await yukle() } }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.patientName ?? "—").font(.subheadline.weight(.semibold))
                            Text(r.startsAt.map { DVBSaat.gun($0, "d MMMM EEEE HH:mm") } ?? "—")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        } footer: {
            Text("Hasta randevusunu iptal etmek istedi. Randevuya dokunup talebi onaylayabilirsiniz.")
        }
    }

    @ViewBuilder private var soruBolumu: some View {
        Section("Yanıt bekleyen") {
            if yukleniyor && bekleyenSorular.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if bekleyenSorular.isEmpty {
                Text("Yanıt bekleyen soru yok.").foregroundColor(.secondary)
            } else {
                ForEach(bekleyenSorular) { s in
                    Button { yanitlanan = s } label: { soruSatiri(s, yanit: nil) }
                        .buttonStyle(.plain)
                }
            }
        }
        if !yanitladiklarim.isEmpty {
            Section("Yanıtladıklarım") {
                ForEach(yanitladiklarim) { s in soruSatiri(s, yanit: s.myAnswer) }
            }
        }
    }

    private func soruSatiri(_ s: DVBHekimSoru, yanit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(s.title ?? "").font(.subheadline.weight(.semibold))
                Spacer()
                if s.directed == true {
                    Text("Size").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DVBTheme.brand.opacity(0.12)).foregroundColor(DVBTheme.brand)
                        .clipShape(Capsule())
                }
            }
            Text(s.body ?? "").font(.caption).foregroundColor(.secondary).lineLimit(3)
            if let yanit {
                Text(yanit).font(.caption).lineLimit(3)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DVBTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func yukle() async {
        guard let token = session.token else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            switch bolum {
            case .mesajlar:
                let l: DVBHekimSohbetListesi = try await DVBAPI.shared.get("my/doctor/conversations", token: token)
                sohbetler = l.data
                whatsappNotu = l.whatsappNote
            case .iptal:
                let l: DVBHekimRandevuListesi = try await DVBAPI.shared.get("my/doctor/cancel-requests", token: token)
                iptaller = l.data
            case .sorular:
                let s: DVBHekimSorular = try await DVBAPI.shared.get("my/doctor/questions", token: token)
                bekleyenSorular = s.pending
                yanitladiklarim = s.answered
            }
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private struct DVBHekimYanitFormu: View {
    let soru: DVBHekimSoru
    var yanitlandi: () -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var metin = ""
    @State private var gonderiliyor = false
    @State private var hata: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Soru") {
                    Text(soru.title ?? "").font(.subheadline.weight(.semibold))
                    Text(soru.body ?? "").font(.subheadline)
                }
                Section {
                    TextEditor(text: $metin).frame(minHeight: 160)
                } header: {
                    Text("Yanıtınız")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Yanıtınız Doktora Sor sayfasında adınızla herkese açık yayınlanır.")
                        if let hata { Text(hata).foregroundColor(.red) }
                    }
                }
            }
            .navigationTitle("Yanıtla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Yayınla") { Task { await gonder() } }
                        .disabled(gonderiliyor || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func gonder() async {
        guard let token = session.token else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            let _: DVBMessage = try await DVBAPI.shared.post(
                "my/doctor/questions/\(soru.slug)/answer",
                body: ["body": metin.trimmingCharacters(in: .whitespacesAndNewlines)],
                token: token
            )
            yanitlandi()
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
