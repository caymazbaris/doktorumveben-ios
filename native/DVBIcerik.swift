import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000353 — "DOKTORA SOR" ve "SAĞLIK REHBERİ" (hasta tarafı, okumak için giriş gerekmez).
//
// Kullanıcı (9 Eki 2026): "Doktora sor ve Sağlık rehberi: hasta çekmek için içerik" — "3 ve 4 ü yap".
//
// Veri ve kurallar sunucuda (IcerikApiController; web /doktora-sor ve /saglik-rehberi ile aynı):
// · yalnız yayınlanmış + herkese açık sorular; soranın adı kısaltılmış gelir ("Ayşe Y."), kimlik/telefon gelmez;
// · soru sormak için giriş şart; soru bir uzman yanıtlayana kadar yayınlanmaz (web formuyla aynı kayıt);
// · rehber: yalnız hekim onaylı makaleler; gövde sunucuda HTML'den sade bloklara çevrilir (iOS 15'te HTML yok),
//   satır içi yalnız **kalın**, *eğik*, [bağlantı](adres) — AttributedString(markdown:) ile;
// · makale sonu yönlendirmesi TEK hekime değil branş/il LİSTESİNE (tanıtım yönetmeliği m.5/f); inceleyen hekimin
//   profiline geçiş yalnız inceleme rozetinde. Fiyat, üstünlük ifadesi, satın alma/üyelik yönlendirmesi YOK.
// ⛔ Model tipleri burada: DVBModels.swift widget hedefiyle paylaşılır, oraya eklenmez.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Modeller

struct DVBSoruKarti: Decodable, Identifiable, Hashable {
    let slug: String
    let title: String
    let excerpt: String?
    let specialty: String?
    let author: String?
    let answerCount: Int?
    let views: Int?
    let createdAt: Date?
    let url: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, excerpt, specialty, author, views, url
        case answerCount = "answer_count"
        case createdAt = "created_at"
    }
}

private struct DVBSoruSayfasi: Decodable {
    let data: [DVBSoruKarti]
    let meta: DVBDoctorPage.Meta?
}

struct DVBSoruYaniti: Decodable, Identifiable {
    let id: Int
    let body: String
    let createdAt: Date?
    let doctor: DVBDoctor
    let profileVisible: Bool?

    enum CodingKeys: String, CodingKey {
        case id, body, doctor
        case createdAt = "created_at"
        case profileVisible = "profile_visible"
    }
}

struct DVBSoruDetayi: Decodable {
    let slug: String
    let title: String
    let body: String
    let specialty: String?
    let author: String?
    let answerCount: Int?
    let views: Int?
    let createdAt: Date?
    let url: String?
    let answers: [DVBSoruYaniti]

    enum CodingKeys: String, CodingKey {
        case slug, title, body, specialty, author, views, url, answers
        case answerCount = "answer_count"
        case createdAt = "created_at"
    }
}

private struct DVBSoruDetayCevabi: Decodable {
    let question: DVBSoruDetayi
}

private struct DVBSoruGonderCevabi: Decodable {
    let ok: Bool?
    let message: String?
}

struct DVBRehberBrans: Decodable, Identifiable, Hashable {
    let slug: String
    let name: String
    var id: String { slug }
}

struct DVBRehberKarti: Decodable, Identifiable, Hashable {
    let slug: String
    let title: String
    let summary: String?
    let specialties: [String]?
    let reviewerName: String?
    let updatedAt: Date?
    let url: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, summary, specialties, url
        case reviewerName = "reviewer_name"
        case updatedAt = "updated_at"
    }
}

private struct DVBRehberSayfasi: Decodable {
    let specialty: DVBRehberBrans?
    let data: [DVBRehberKarti]
    let meta: DVBDoctorPage.Meta?
}

/// Makale gövdesinin bir parçası: heading | paragraph | list | quote | image.
struct DVBRehberBlok: Decodable {
    let type: String
    let text: String?
    let plain: String?
    let level: Int?
    let ordered: Bool?
    let items: [Oge]?
    let url: String?
    let alt: String?

    struct Oge: Decodable {
        let text: String?
        let plain: String?
    }
}

struct DVBRehberMakalesi: Decodable {
    let slug: String
    let title: String
    let summary: String?
    let specialties: [String]?
    let updatedAt: Date?
    let url: String?
    let blocks: [DVBRehberBlok]
    let faqs: [Sss]?
    let sources: [Kaynak]?
    let reviewer: Inceleyen?
    let ctas: [Yonlendirme]?
    let notice: String?

    struct Sss: Decodable {
        let q: String
        let a: String
    }

    struct Kaynak: Decodable {
        let title: String
        let url: String
    }

    struct Inceleyen: Decodable {
        let name: String?
        let specialty: String?
        let reviewedAt: Date?
        let doctor: DVBDoctor?
        let profileVisible: Bool?

        enum CodingKeys: String, CodingKey {
            case name, specialty, doctor
            case reviewedAt = "reviewed_at"
            case profileVisible = "profile_visible"
        }
    }

    /// Listeleme sayfasına yönlendirme (branş ve/veya il); uygulama kendi hekim listesinde açar.
    struct Yonlendirme: Decodable {
        let label: String
        let specialty: String?
        let city: String?
        let url: String?
    }

    enum CodingKeys: String, CodingKey {
        case slug, title, summary, specialties, url, blocks, faqs, sources, reviewer, ctas, notice
        case updatedAt = "updated_at"
    }
}

private struct DVBRehberMakaleCevabi: Decodable {
    let article: DVBRehberMakalesi
}

// MARK: - Ortak biçim

enum DVBIcerikBicim {
    static let tarihBicimi: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static func tarih(_ d: Date?) -> String? {
        guard let d else { return nil }
        return tarihBicimi.string(from: d)
    }

    /// Sunucunun satır içi markdown'ı (kalın/eğik/bağlantı) → Text. Çözülemezse düz metin.
    static func metin(_ md: String?, _ duz: String?) -> Text {
        let ham = md ?? duz ?? ""
        let secenek = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: ham, options: secenek) {
            return Text(a)
        }
        return Text(duz ?? ham)
    }
}

/// Sayfa (sheet) seçimi: tek `.sheet(item:)` — aynı görünümde iki `.sheet` iOS 15'te güvenilmez.
private enum DVBIcerikSayfa: String, Identifiable {
    case soruSor
    case giris
    var id: String { rawValue }
}

// MARK: - Doktora sor: liste

struct DVBDoktoraSorView: View {
    @EnvironmentObject private var session: DVBSession
    @EnvironmentObject private var lock: DVBBiometricLock

    @State private var sorular: [DVBSoruKarti] = []
    @State private var sayfa = 0
    @State private var sonSayfa = 1
    @State private var toplam: Int?
    @State private var yukleniyor = false
    @State private var yuklendi = false
    @State private var hata: String?
    @State private var kapali = false
    @State private var istekNo = 0

    @State private var arama = ""
    @State private var aramaGorevi: Task<Void, Never>?
    @State private var branslar: [DVBSpecialty] = []
    @State private var bransId: Int?

    @State private var acikSayfa: DVBIcerikSayfa?
    @State private var sonAcilan: DVBIcerikSayfa?
    @State private var bilgi: String?

    private var bransSecenekleri: [DVBSecenek<Int>] {
        branslar.map { DVBSecenek(id: $0.id, ad: $0.name, populer: $0.popular == true) }
    }

    var body: some View {
        List {
            if kapali {
                DVBStateView(icon: "questionmark.bubble", title: "Doktora sor şu an kapalı",
                             message: "Bu bölüm geçici olarak kapalı. Daha sonra tekrar bakın.")
                    .frame(minHeight: 220)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    soruSorDugmesi
                    if let bilgi {
                        Label(bilgi, systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundColor(DVBTheme.accent)
                    }
                    if !branslar.isEmpty {
                        DVBAramaliSecici(baslik: "Branş", secenekler: bransSecenekleri, secili: $bransId, bosEtiket: "Tüm branşlar")
                    }
                } footer: {
                    Text("Uzmanlara sorun; yanıtlanan sorular herkese açık yayınlanır.")
                }

                Section {
                    liste
                } header: {
                    if let toplam, !sorular.isEmpty {
                        Text("\(toplam) soru")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Doktora sor")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sorularda ara")
        .onChange(of: arama) { _ in gecikmeliYenile() }
        .onChange(of: bransId) { _ in Task { await yukle(sayfaNo: 1) } }
        .refreshable { await yukle(sayfaNo: 1) }
        .task {
            if branslar.isEmpty { await branslariYukle() }
            if !yuklendi { await yukle(sayfaNo: 1) }
        }
        .sheet(item: $acikSayfa, onDismiss: {
            // Girişten dönüldü ve oturum açıldıysa soru formu kendiliğinden açılır.
            if sonAcilan == .giris && session.isLoggedIn { acikSayfa = .soruSor }
            sonAcilan = nil
        }) { s in
            switch s {
            case .soruSor:
                DVBSoruSorView(branslar: branslar, ilkBrans: bransId) { mesaj in bilgi = mesaj }
                    .environmentObject(session)
                    .environmentObject(lock)
            case .giris:
                DVBAccountView()
                    .environmentObject(session)
                    .environmentObject(lock)
            }
        }
    }

    private var soruSorDugmesi: some View {
        Button {
            let hedef: DVBIcerikSayfa = session.isLoggedIn ? .soruSor : .giris
            sonAcilan = hedef
            acikSayfa = hedef
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.title2)
                    .foregroundColor(DVBTheme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uzmana soru sorun").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                    Text(session.isLoggedIn
                         ? "Sorunuz bir uzman yanıtladığında yayınlanır."
                         : "Soru sormak için giriş yapın veya üye olun.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var liste: some View {
        if sorular.isEmpty && (yukleniyor || !yuklendi) && hata == nil {
            ProgressView("Sorular getiriliyor…").frame(maxWidth: .infinity, minHeight: 160)
        } else if sorular.isEmpty, let hata {
            DVBStateView(icon: "wifi.exclamationmark", title: "Sorular alınamadı", message: hata) {
                Task { await yukle(sayfaNo: 1) }
            }
            .frame(minHeight: 200)
        } else if sorular.isEmpty {
            DVBStateView(icon: "questionmark.bubble", title: "Soru bulunamadı",
                         message: arama.isEmpty && bransId == nil
                            ? "Henüz yayınlanmış soru yok. İlk soruyu siz sorun!"
                            : "Farklı bir kelime ya da branş deneyin.")
                .frame(minHeight: 200)
        } else {
            ForEach(sorular) { s in
                NavigationLink(destination: DVBSoruDetayView(slug: s.slug)) {
                    DVBSoruSatiri(s: s)
                }
                .onAppear {
                    if s.id == sorular.last?.id { Task { await sonrakiSayfa() } }
                }
            }
            if yukleniyor {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    private func gecikmeliYenile() {
        aramaGorevi?.cancel()
        aramaGorevi = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await yukle(sayfaNo: 1)
        }
    }

    private func sonrakiSayfa() async {
        guard !yukleniyor, sayfa < sonSayfa else { return }
        await yukle(sayfaNo: sayfa + 1)
    }

    private func branslariYukle() async {
        do {
            branslar = try await DVBAPI.shared.get("questions/specialties")
        } catch DVBError.notFound {
            kapali = true
        } catch {
            // Branş listesi gelmezse filtre gizli kalır; sorular yine listelenir.
        }
    }

    private func yukle(sayfaNo: Int) async {
        istekNo += 1
        let no = istekNo
        yukleniyor = true
        var q: [String: String] = ["page": String(sayfaNo)]
        let a = arama.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { q["q"] = a }
        if let bransId { q["specialty"] = String(bransId) }
        do {
            let c: DVBSoruSayfasi = try await DVBAPI.shared.get("questions", query: q)
            guard no == istekNo else { return }
            if sayfaNo == 1 {
                sorular = c.data
            } else {
                let mevcut = Set(sorular.map(\.slug))
                sorular += c.data.filter { !mevcut.contains($0.slug) }
            }
            sayfa = c.meta?.currentPage ?? sayfaNo
            sonSayfa = c.meta?.lastPage ?? sayfa
            toplam = c.meta?.total
            hata = nil
            kapali = false
        } catch DVBError.notFound {
            guard no == istekNo else { return }
            kapali = true
        } catch {
            guard no == istekNo else { return }
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yukleniyor = false
        yuklendi = true
    }
}

struct DVBSoruSatiri: View {
    let s: DVBSoruKarti

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            if let e = s.excerpt, !e.isEmpty {
                Text(e).font(.caption).foregroundColor(.secondary).lineLimit(3)
            }
            Text(ozet).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var ozet: String {
        let parcalar: [String?] = [
            s.specialty ?? "Genel",
            s.answerCount.map { "\($0) yanıt" },
            s.views.map { "\($0) görüntülenme" },
        ]
        return parcalar.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Doktora sor: soru detayı

struct DVBSoruDetayView: View {
    let slug: String

    @State private var soru: DVBSoruDetayi?
    @State private var hata: String?

    var body: some View {
        Group {
            if let soru {
                icerik(soru)
            } else if let hata {
                DVBStateView(icon: "questionmark.bubble", title: "Soru açılamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Soru")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ⚠ Araç çubuğunda öğe düzeyinde `if` iOS 16 ister — koşul öğenin İÇİNDE.
            ToolbarItem(placement: .primaryAction) {
                if let u = soru?.url, let url = URL(string: u) {
                    DVBPaylasDugmesi(url: url)
                }
            }
        }
        .task { if soru == nil { await yukle() } }
    }

    private func icerik(_ s: DVBSoruDetayi) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.title).font(.title3.bold())
                    Text(meta(s)).font(.caption).foregroundColor(.secondary)
                    Text(s.body)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            Section {
                if s.answers.isEmpty {
                    Text("Henüz yanıt yok.").foregroundColor(.secondary)
                } else {
                    ForEach(s.answers) { y in
                        DVBSoruYanitSatiri(y: y)
                    }
                }
            } header: {
                Text("Uzman yanıtları (\(s.answers.count))")
            } footer: {
                Text("Yanıtlar bilgilendirme amaçlıdır; tanı ve tedavi için mutlaka hekiminize başvurun.")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await yukle() }
    }

    private func meta(_ s: DVBSoruDetayi) -> String {
        let parcalar: [String?] = [
            s.author ?? "Ziyaretçi",
            s.specialty ?? "Genel",
            DVBIcerikBicim.tarih(s.createdAt),
            s.views.map { "\($0) görüntülenme" },
        ]
        return parcalar.compactMap { $0 }.joined(separator: " · ")
    }

    private func yukle() async {
        do {
            let c: DVBSoruDetayCevabi = try await DVBAPI.shared.get("questions/\(slug)")
            soru = c.question
            hata = nil
        } catch DVBError.notFound {
            hata = "Bu soru yayından kaldırılmış ya da bulunamadı."
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

struct DVBSoruYanitSatiri: View {
    let y: DVBSoruYaniti

    var body: some View {
        if y.profileVisible == true {
            // Web'deki "Profili gör →" bağlantısının karşılığı: hekim kartına dokununca profil açılır.
            NavigationLink(destination: DVBDoctorDetailView(doctor: y.doctor)) { satir(profilVar: true) }
        } else {
            satir(profilVar: false)
        }
    }

    private func satir(profilVar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                DVBAvatar(url: y.doctor.avatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(y.doctor.name ?? "Uzman").font(.subheadline.weight(.semibold))
                    if let b = y.doctor.specialty, !b.isEmpty {
                        Text(b).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Text(y.body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let t = DVBIcerikBicim.tarih(y.createdAt) {
                    Text(t).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if profilVar {
                    Text("Profili gör").font(.caption.weight(.semibold)).foregroundColor(DVBTheme.brand)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Doktora sor: soru sor

struct DVBSoruSorView: View {
    let branslar: [DVBSpecialty]
    var bitti: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var bransId: Int?
    @State private var baslik = ""
    @State private var metin = ""
    @State private var calisiyor = false
    @State private var hata: String?

    init(branslar: [DVBSpecialty], ilkBrans: Int?, bitti: @escaping (String) -> Void) {
        self.branslar = branslar
        self.bitti = bitti
        _bransId = State(initialValue: ilkBrans)
    }

    private var temizBaslik: String { baslik.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var temizMetin: String { metin.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hazir: Bool {
        !temizBaslik.isEmpty && !temizMetin.isEmpty && temizBaslik.count <= 160 && temizMetin.count <= 3000
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    if !branslar.isEmpty {
                        DVBAramaliSecici(
                            baslik: "Branş",
                            secenekler: branslar.map { DVBSecenek(id: $0.id, ad: $0.name, populer: $0.popular == true) },
                            secili: $bransId,
                            bosEtiket: "Seçin (isteğe bağlı)"
                        )
                    }
                    TextField("Soru başlığı", text: $baslik)
                } header: {
                    Text("Sorunuz")
                } footer: {
                    Text("Başlık en fazla 160 karakter (\(temizBaslik.count)/160).")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $metin)
                            .frame(minHeight: 160)
                        if metin.isEmpty {
                            Text("Sorunuzu ayrıntılı yazın…")
                                .foregroundColor(Color(.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text("Ayrıntı")
                } footer: {
                    Text("Sorunuz bir uzman yanıtladıktan sonra herkese açık yayınlanır; adınız kısaltılarak gösterilir (ör. “Ayşe Y.”). Telefon, T.C. kimlik numarası gibi kişisel bilgilerinizi yazmayın. Acil durumlarda 112’yi arayın.")
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle("Soru sor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await gonder() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Gönder").bold() }
                    }
                    .disabled(!hazir || calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func gonder() async {
        guard hazir, !calisiyor else { return }
        guard let token = session.token else {
            hata = "Soru sormak için giriş yapın."
            return
        }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["title": temizBaslik, "body": temizMetin]
        if let bransId { govde["specialty_id"] = bransId }
        do {
            let c: DVBSoruGonderCevabi = try await DVBAPI.shared.post("my/questions", body: govde, token: token)
            bitti(c.message ?? "Sorunuz alındı. Bir uzman yanıtladığında yayınlanacaktır.")
            dismiss()
        } catch DVBError.unauthorized {
            hata = "Oturumunuzun süresi dolmuş. Lütfen yeniden giriş yapın."
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Sağlık rehberi: liste

struct DVBSaglikRehberiView: View {
    @State private var makaleler: [DVBRehberKarti] = []
    @State private var sayfa = 0
    @State private var sonSayfa = 1
    @State private var yukleniyor = false
    @State private var yuklendi = false
    @State private var hata: String?
    @State private var istekNo = 0

    @State private var branslar: [DVBRehberBrans] = []
    @State private var secili: DVBRehberBrans?

    var body: some View {
        List {
            if !branslar.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        cip("Tümü", secili == nil) { secili = nil }
                        ForEach(branslar) { b in
                            cip(b.name, secili == b) { secili = b }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
            }

            if makaleler.isEmpty && (yukleniyor || !yuklendi) && hata == nil {
                ProgressView("Makaleler getiriliyor…")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowSeparator(.hidden)
            } else if makaleler.isEmpty, let hata {
                DVBStateView(icon: "wifi.exclamationmark", title: "Rehber alınamadı", message: hata) {
                    Task { await yukle(sayfaNo: 1) }
                }
                .frame(minHeight: 220)
                .listRowSeparator(.hidden)
            } else if makaleler.isEmpty {
                DVBStateView(icon: "book", title: "Henüz makale yok",
                             message: "Hekim onaylı rehber makaleleri eklendikçe burada görünecek.")
                    .frame(minHeight: 220)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(makaleler) { m in
                    NavigationLink(destination: DVBRehberMakaleView(slug: m.slug)) {
                        DVBRehberSatiri(m: m)
                    }
                    .onAppear {
                        if m.id == makaleler.last?.id { Task { await sonrakiSayfa() } }
                    }
                }
                if yukleniyor {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Sağlık rehberi")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: secili) { _ in Task { await yukle(sayfaNo: 1) } }
        .refreshable { await yukle(sayfaNo: 1) }
        .task {
            if branslar.isEmpty { await branslariYukle() }
            if !yuklendi { await yukle(sayfaNo: 1) }
        }
    }

    private func cip(_ ad: String, _ secik: Bool, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            Text(ad)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(secik ? Color.white : Color.primary)
                .background(secik ? DVBTheme.brand : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        // ⚠ Liste satırındaki birden çok düğme: stil verilmezse satıra dokunmak HEPSİNİ tetikler.
        .buttonStyle(.borderless)
    }

    private func sonrakiSayfa() async {
        guard !yukleniyor, sayfa < sonSayfa else { return }
        await yukle(sayfaNo: sayfa + 1)
    }

    private func branslariYukle() async {
        do {
            branslar = try await DVBAPI.shared.get("guide/specialties")
        } catch {
            // Çip şeridi gelmezse makaleler yine listelenir.
        }
    }

    private func yukle(sayfaNo: Int) async {
        istekNo += 1
        let no = istekNo
        yukleniyor = true
        var q: [String: String] = ["page": String(sayfaNo)]
        if let secili { q["specialty"] = secili.slug }
        do {
            let c: DVBRehberSayfasi = try await DVBAPI.shared.get("guide", query: q)
            guard no == istekNo else { return }
            if sayfaNo == 1 {
                makaleler = c.data
            } else {
                let mevcut = Set(makaleler.map(\.slug))
                makaleler += c.data.filter { !mevcut.contains($0.slug) }
            }
            sayfa = c.meta?.currentPage ?? sayfaNo
            sonSayfa = c.meta?.lastPage ?? sayfa
            hata = nil
        } catch {
            guard no == istekNo else { return }
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yukleniyor = false
        yuklendi = true
    }
}

struct DVBRehberSatiri: View {
    let m: DVBRehberKarti

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            if let s = m.summary, !s.isEmpty {
                Text(s).font(.caption).foregroundColor(.secondary).lineLimit(3)
            }
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill").foregroundColor(DVBTheme.accent)
                Text(alt).foregroundColor(.secondary)
            }
            .font(.caption2)
        }
        .padding(.vertical, 4)
    }

    private var alt: String {
        let parcalar: [String?] = [
            m.reviewerName.map { "Hekim onaylı · \($0)" } ?? "Hekim onaylı",
            DVBIcerikBicim.tarih(m.updatedAt),
        ]
        return parcalar.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Sağlık rehberi: makale

struct DVBRehberMakaleView: View {
    let slug: String

    @State private var m: DVBRehberMakalesi?
    @State private var hata: String?

    var body: some View {
        Group {
            if let m {
                icerik(m)
            } else if let hata {
                DVBStateView(icon: "book", title: "Makale açılamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Sağlık rehberi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let u = m?.url, let url = URL(string: u) {
                    DVBPaylasDugmesi(url: url)
                }
            }
        }
        .task { if m == nil { await yukle() } }
    }

    private func icerik(_ m: DVBRehberMakalesi) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(m.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                if let r = m.reviewer {
                    rozet(r, guncelleme: m.updatedAt)
                }

                ForEach(Array(m.blocks.enumerated()), id: \.offset) { _, b in
                    blok(b)
                }

                if let sss = m.faqs, !sss.isEmpty {
                    Text("Sık sorulan sorular").font(.title3.bold()).padding(.top, 8)
                    ForEach(Array(sss.enumerated()), id: \.offset) { _, f in
                        DisclosureGroup {
                            Text(f.a)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        } label: {
                            Text(f.q).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                if let k = m.sources, !k.isEmpty {
                    Text("Kaynaklar").font(.title3.bold()).padding(.top, 8)
                    ForEach(Array(k.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(i + 1).").foregroundColor(.secondary)
                            if let url = URL(string: s.url) {
                                Link(s.title, destination: url)
                            } else {
                                Text(s.title)
                            }
                        }
                        .font(.footnote)
                    }
                }

                if let y = m.ctas, !y.isEmpty {
                    yonlendirmeler(y)
                }

                Text(m.notice ?? "Bu içerik bilgilendirme amaçlıdır; tanı ve tedavi için mutlaka hekiminize başvurun.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Görünür inceleme rozeti (m.5/j). Hekim profiline geçiş YALNIZ burada (m.5/f).
    private func rozet(_ r: DVBRehberMakalesi.Inceleyen, guncelleme: Date?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundColor(DVBTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tıbbi olarak inceleyen").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                if r.profileVisible == true, let d = r.doctor {
                    NavigationLink(destination: DVBDoctorDetailView(doctor: d)) {
                        Text(r.name ?? "Hekim")
                            .font(.subheadline.weight(.semibold))
                            .underline()
                            .foregroundColor(DVBTheme.brand)
                    }
                } else {
                    Text(r.name ?? "Hekim").font(.subheadline.weight(.semibold))
                }
                if let b = r.specialty, !b.isEmpty {
                    Text(b).font(.caption)
                }
                Text(tarihler(r.reviewedAt, guncelleme)).font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DVBTheme.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tarihler(_ inceleme: Date?, _ guncelleme: Date?) -> String {
        let parcalar: [String?] = [
            DVBIcerikBicim.tarih(inceleme).map { "İnceleme tarihi: \($0)" },
            DVBIcerikBicim.tarih(guncelleme).map { "Son güncelleme: \($0)" },
        ]
        return parcalar.compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func blok(_ b: DVBRehberBlok) -> some View {
        switch b.type {
        case "heading":
            DVBIcerikBicim.metin(b.text, b.plain)
                .font((b.level ?? 2) <= 2 ? Font.title3.bold() : Font.headline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        case "list":
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((b.items ?? []).enumerated()), id: \.offset) { i, o in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(b.ordered == true ? "\(i + 1)." : "•").foregroundColor(.secondary)
                        DVBIcerikBicim.metin(o.text, o.plain)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case "quote":
            DVBIcerikBicim.metin(b.text, b.plain)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(Rectangle().fill(DVBTheme.brand.opacity(0.5)).frame(width: 3), alignment: .leading)
        case "image":
            if let u = b.url, let url = URL(string: u) {
                AsyncImage(url: url) { r in
                    r.resizable().scaledToFit()
                } placeholder: {
                    Color(.secondarySystemBackground).frame(height: 160)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(b.alt ?? "Görsel")
            }
        default:
            DVBIcerikBicim.metin(b.text, b.plain)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// m.5/f — tek hekime değil branş/il listesine; uygulamanın kendi hekim listesinde açılır.
    private func yonlendirmeler(_ y: [DVBRehberMakalesi.Yonlendirme]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bir uzmana danışmak ister misiniz?").font(.headline).foregroundColor(.white)
            Text("Size uygun doktor ve uzmanları inceleyip randevu alabilirsiniz.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            ForEach(Array(y.enumerated()), id: \.offset) { _, c in
                NavigationLink(destination: DVBIcerikHekimListesi(baslik: c.label, brans: c.specialty, il: c.city)) {
                    HStack {
                        Text(c.label).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(DVBTheme.brand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(DVBTheme.brand)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 8)
    }

    private func yukle() async {
        do {
            let c: DVBRehberMakaleCevabi = try await DVBAPI.shared.get("guide/\(slug)")
            m = c.article
            hata = nil
        } catch DVBError.notFound {
            hata = "Bu makale yayından kaldırılmış ya da bulunamadı."
        } catch {
            if let mesaj = DVBError.mesaj(error) { hata = mesaj }
        }
    }
}

// MARK: - Branş/il hekim listesi (makale sonu yönlendirmesi)

struct DVBIcerikHekimListesi: View {
    let baslik: String
    let brans: String?
    let il: String?

    @State private var hekimler: [DVBDoctor] = []
    @State private var sayfa = 0
    @State private var sonSayfa = 1
    @State private var yukleniyor = false
    @State private var yuklendi = false
    @State private var hata: String?

    var body: some View {
        List {
            if hekimler.isEmpty && (yukleniyor || !yuklendi) && hata == nil {
                ProgressView("Hekimler getiriliyor…")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowSeparator(.hidden)
            } else if hekimler.isEmpty, let hata {
                DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: hata) {
                    Task { await yukle(sayfaNo: 1) }
                }
                .frame(minHeight: 220)
                .listRowSeparator(.hidden)
            } else if hekimler.isEmpty {
                DVBStateView(icon: "magnifyingglass", title: "Sonuç yok", message: "Bu listede şu an hekim yok.")
                    .frame(minHeight: 220)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(hekimler) { d in
                    NavigationLink(destination: DVBDoctorDetailView(doctor: d)) {
                        DVBDoctorRow(doctor: d)
                    }
                    .onAppear {
                        if d.id == hekimler.last?.id { Task { await sonrakiSayfa() } }
                    }
                }
                if yukleniyor {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await yukle(sayfaNo: 1) }
        .task { if !yuklendi { await yukle(sayfaNo: 1) } }
    }

    private func sonrakiSayfa() async {
        guard !yukleniyor, sayfa < sonSayfa else { return }
        await yukle(sayfaNo: sayfa + 1)
    }

    private func yukle(sayfaNo: Int) async {
        yukleniyor = true
        var q: [String: String] = ["page": String(sayfaNo)]
        if let brans, !brans.isEmpty { q["specialty"] = brans }
        if let il, !il.isEmpty { q["city"] = il }
        do {
            let c: DVBDoctorPage = try await DVBAPI.shared.get("doctors", query: q)
            if sayfaNo == 1 {
                hekimler = c.data
            } else {
                let mevcut = Set(hekimler.map(\.slug))
                hekimler += c.data.filter { !mevcut.contains($0.slug) }
            }
            sayfa = c.meta?.currentPage ?? sayfaNo
            sonSayfa = c.meta?.lastPage ?? sayfa
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yukleniyor = false
        yuklendi = true
    }
}
