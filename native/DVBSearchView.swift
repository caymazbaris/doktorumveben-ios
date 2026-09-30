import SwiftUI

struct DVBSpecialty: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
}

/// Tur 235 — Hekim arama. Giriş GEREKTİRMEZ; uygulamayı ilk açan (ve App Store
/// denetçisi) hemen gerçek içerik görür.
@MainActor
struct DVBSearchView: View {

    @State private var query = ""
    @State private var specialties: [DVBSpecialty] = []
    @State private var selectedSpecialty: DVBSpecialty?
    @State private var doctors: [DVBDoctor] = []
    @State private var toplam: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    // DVB-000264 — il/ilçe filtresi + konumdan otomatik il/ilçe.
    @StateObject private var secim = DVBKonumSecimi.shared
    @ObservedObject private var konum = DVBKonum.shared
    @State private var filtreAcik = false
    // DVB-000268 — sitedeki diğer filtreler.
    @ObservedObject private var filtre = DVBAramaFiltresi.shared
    // DVB-000269 — hekimden bağımsız talep ("Doktor Bul").
    @State private var doktorBulAcik = false
    @EnvironmentObject private var session: DVBSession
    @EnvironmentObject private var lock: DVBBiometricLock
    /// İlk açılışta konumu YALNIZ BİR KEZ kendiliğinden iste (her sekme dönüşünde sormasın).
    @AppStorage("dvb.konumIlkSoruldu") private var konumIlkSoruldu = false

    var body: some View {
        NavigationView {
            // ═══════════════════════════════════════════════════════════════════════
            // DVB-000158 — KAPSAYICI HER DURUMDA `List`. Durum ekranları listenin İÇİNDE.
            //
            // Önce böyle değildi: dışta bir `Group` vardı ve içi duruma göre DEĞİŞİYORDU —
            // yükleniyorken `ProgressView` (kaydırılamaz), liste gelince `List`
            // (kaydırılabilir). Büyük başlık ve `.searchable` iOS'ta bir KAYDIRMA
            // GÖRÜNÜMÜNE tutunur; içerik kaydırılamaz bir görünümken tutunacak yer yoktur
            // ve sonradan `List` gelince bağ yeniden kurulmuyor. Sonuç: "Hekim ara" başlığı
            // liste gelir gelmez KAYBOLUYOR, yerinde boş bir alan kalıyordu (kullanıcı ekran
            // kaydı gönderdi, sekme değiştirip dönünce de gelmiyordu).
            //
            // Kapsayıcıyı sabitlemek kök nedeni ortadan kaldırır: kaydırma görünümünün
            // kimliği hiç değişmez.
            //
            // ⚠ Başlığı `.inline` yapmak da semptomu kapatırdı ama diğer sekmeler
            // (Randevularım, Bildirimler) büyük başlık kullanıyor — tutarsız bir ekran
            // bırakır ve asıl nedeni gizlerdi.
            //
            // Not: `DVBAppointmentsView` aynı `safeAreaInset + navigationTitle` desenini
            // kullanıyor ama orada `.searchable` YOK; başlığın orada kaybolmamasının sebebi
            // bu. Oraya arama eklenirse aynı tuzak orada da açılır.
            // ═══════════════════════════════════════════════════════════════════════
            List {
                // DVB-000269 — kullanıcı: "Doktordan bağımsız randevu talep et kısmı yapalım şehir branş vs ile talep
                // edebilsin". Listenin en üstünde; hekim seçmeden talep bırakmanın yolu.
                Button {
                    doktorBulAcik = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.title2)
                            .foregroundColor(DVBTheme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hekim seçmeden talep bırakın").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                            Text("Branşı ve şehri söyleyin, size uygun hekimi biz bulalım.").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(DVBTheme.brand.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)

                if loading && doctors.isEmpty {
                    ProgressView("Hekimler getiriliyor…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .listRowSeparator(.hidden)
                } else if let error, doctors.isEmpty {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Liste alınamadı", message: error) {
                        reload()
                    }
                    .frame(minHeight: 220)
                    .listRowSeparator(.hidden)
                } else if doctors.isEmpty {
                    DVBStateView(
                        icon: "magnifyingglass",
                        title: "Sonuç yok",
                        message: secim.ilce != nil
                            ? "Bu ilçede sonuç yok. Filtreden ilçeyi \"Tümü\" yapmayı deneyin."
                            : "Farklı bir isim, branş ya da şehir deneyin."
                    )
                    .frame(minHeight: 220)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(doctors) { doctor in
                        NavigationLink(destination: DVBDoctorDetailView(doctor: doctor)) {
                            DVBDoctorRow(doctor: doctor)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    konumSatiri
                    specialtyChips
                }
                .background(.bar)
            }
            // "Hekim ara" geri düğmesi/erişilebilirlik için başlık olarak KALIR; ekranda logonun altında görünmez.
            .navigationTitle("Hekim ara")
            // DVB-000264 — logo başlıkta. Büyük başlık yerine satır içi: logo + her zaman görünen arama kutusu +
            // konum + branş çipleri zaten dikey alanı dolduruyor; üstüne büyük başlık listeyi ekranın yarısına iterdi.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { DVBZilDugmesi() }
                ToolbarItem(placement: .principal) { DVBBrandLogo() }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        filtreAcik = true
                    } label: {
                        Image(systemName: secim.il == nil && filtre.etkinSayisi == 0
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filtrele")
                }
            }
            // ⛔ DVB-000264 — `.navigationBarDrawer(displayMode: .always)`: varsayılan yerleşimde iOS arama kutusunu
            // AŞAĞI ÇEKİLENE KADAR GİZLER. Kullanıcı: "Hekim ara bandı kayıp aşağıya kaydırınca geliyor sadece".
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Hekim adı ara")
            .onChange(of: query) { _ in debouncedReload() }
            // Sayfa "Uygula" ile de kaydırılarak da kapansa liste seçimle HİZALANSIN (etiket başka, liste başka kalmasın).
            .sheet(isPresented: $doktorBulAcik) {
                DVBDoktorBulView().environmentObject(session).environmentObject(lock)
            }
            .sheet(isPresented: $filtreAcik, onDismiss: reload) {
                DVBFiltreSayfasi(secim: secim, konum: konum) {}
            }
            .task {
                await loadSpecialties()
                await ilkKonum()
                if doctors.isEmpty { reload() }
            }
        }
        .navigationViewStyle(.stack)
    }

    /// Konum / il-ilçe satırı + sonuç sayısı. Dokununca filtre sayfası açılır.
    private var konumSatiri: some View {
        Button {
            filtreAcik = true
        } label: {
            HStack(spacing: 6) {
                if konum.calisiyor {
                    ProgressView().scaleEffect(0.8)
                    Text("Konumunuz bulunuyor…")
                } else if let ozet = secim.ozet {
                    Image(systemName: secim.konumdan ? "location.fill" : "mappin.and.ellipse")
                        .foregroundColor(DVBTheme.brand)
                    Text(ozet).fontWeight(.semibold).foregroundColor(.primary)
                } else {
                    Image(systemName: "location").foregroundColor(DVBTheme.brand)
                    Text("Tüm Türkiye · Şehir seçin").foregroundColor(.primary)
                }
                if filtre.etkinSayisi > 0 {
                    Text("· \(filtre.etkinSayisi) filtre").foregroundColor(DVBTheme.brand)
                }
                Spacer(minLength: 8)
                if let toplam, !loading {
                    Text("\(toplam.formatted()) hekim").foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }

    /// Kullanıcı (30 Eyl 2026): "konum isteyip ona göre il ilçeyi belirlesin otomatik". İlk açılışta, seçim yoksa
    /// ve daha önce sorulmadıysa konum istenir; red/hata sessizce "Tüm Türkiye"ye düşer (ekran boş kalmaz).
    private func ilkKonum() async {
        guard secim.il == nil, !konumIlkSoruldu, !konum.reddedildi else { return }
        konumIlkSoruldu = true
        guard let yer = await konum.konumAl(), let eslesme = await DVBCografya.esle(yer) else { return }
        secim.il = eslesme.0
        secim.ilce = eslesme.1
        secim.konumdan = true
    }

    private var specialtyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tümü", active: selectedSpecialty == nil) {
                    selectedSpecialty = nil
                    reload()
                }
                ForEach(specialties) { s in
                    chip(title: s.name, active: selectedSpecialty?.id == s.id) {
                        selectedSpecialty = selectedSpecialty?.id == s.id ? nil : s
                        reload()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? DVBTheme.brand : Color(.secondarySystemBackground))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Veri

    private func loadSpecialties() async {
        // Uç sarmalayıcısız DÜZ dizi döndürüyor (DoctorApiController::specialties).
        if let list: [DVBSpecialty] = try? await DVBAPI.shared.get("specialties") {
            specialties = list
        }
    }

    /// Her tuşa basışta istek atmayalım: son yazımdan 350 ms sonra ara.
    private func debouncedReload() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { reload() }
        }
    }

    private func reload() {
        searchTask?.cancel()
        searchTask = Task {
            loading = true
            error = nil
            defer { loading = false }

            var params: [String: String] = [:]
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { params["q"] = q }
            if let slug = selectedSpecialty?.slug { params["specialty"] = slug }
            if let il = secim.il { params["city"] = il.slug }
            if let ilce = secim.ilce { params["district"] = ilce.slug }
            params.merge(filtre.parametreler) { _, yeni in yeni }

            do {
                let page: DVBDoctorPage = try await DVBAPI.shared.get("doctors", query: params)
                if !Task.isCancelled {
                    doctors = page.data
                    toplam = page.meta?.total
                }
            } catch {
                // DVB-000264 — İPTAL (sekme değişimi/yeniden çizim) hata DEĞİL: ekrandakini koru, "internet yok" deme.
                if !Task.isCancelled, let mesaj = DVBError.mesaj(error) {
                    doctors = []
                    toplam = nil
                    self.error = mesaj
                }
            }
        }
    }
}

// MARK: - Satır

struct DVBDoctorRow: View {
    let doctor: DVBDoctor

    var body: some View {
        HStack(spacing: 12) {
            DVBAvatar(url: doctor.avatar, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(doctor.name ?? "—")
                        .font(.headline)
                        .lineLimit(1)
                    if doctor.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(DVBTheme.brand)
                    }
                }
                if let specialty = doctor.specialty {
                    Text(specialty)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if let district = doctor.district {
                        Label(district, systemImage: "mappin.and.ellipse")
                    }
                    if let count = doctor.ratingCount, count > 0, let rating = doctor.rating {
                        Label(String(format: "%.1f (%d)", rating, count), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Uzak avatar; yoksa baş harf. `AsyncImage` iOS 15'ten beri var, ek paket gerekmez.
struct DVBAvatar: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "person.fill").foregroundColor(.secondary)
        }
    }
}
