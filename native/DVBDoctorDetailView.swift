import SwiftUI

/// `GET /doctors/{slug}` yanıtı. Fiyat KASITLI yok — fiyat hiçbir public yüzeyde
/// yayınlanmaz (yasal), sunucu da göndermez.
struct DVBDoctorDetail: Decodable {
    let doctor: Detail
    let reviews: [Review]

    struct Detail: Decodable {
        let slug: String
        let name: String?
        let specialty: String?
        let avatar: String?
        let rating: Double?
        let ratingCount: Int?
        let isVerified: Bool?
        let district: String?
        let experience: Int?
        let about: String?
        let educationSchool: String?
        // Tur 241 KRİTİK: sunucu bunu DİZİ gönderiyor (["Türkçe"]). Burada `String?`
        // yazılıydı; JSONDecoder diziyi String'e çözemeyip FIRLATIYOR ve tek bu alan
        // yüzünden DVBDoctorDetail'in TAMAMI çözümlenemiyordu → profil ekranı her
        // hekimde "Sunucudan beklenmeyen bir yanıt geldi" hatasına düşüyordu.
        // (Alan şu an hiçbir yerde gösterilmiyor; kullanılmayan bir alan bütün ekranı
        // götürdü. Tipini sunucuyla aynı tutun — String'e geri çevirmeyin.)
        let languages: [String]?
        let specialties: [String]?
        let locations: [Location]?
        let appointmentTypes: [ServiceItem]?
        let isBookingClosed: Bool?
        let requestPath: String?
        let whatsappPath: String?
        /// DVB-000264 — sunucu söyler (web ile aynı kural). Eski sunucuda alan yok → nil.
        let whatsappAvailable: Bool?

        struct Location: Decodable {
            let name: String?
            let address: String?
            let district: String?
        }

        struct ServiceItem: Decodable, Identifiable {
            let id: Int
            let name: String?
            let duration: Int?
            let channel: String?
            let preparation: String?
        }

        enum CodingKeys: String, CodingKey {
            case slug, name, specialty, avatar, rating, district, experience, about, languages, specialties, locations
            case ratingCount = "rating_count"
            case isVerified = "is_verified"
            case educationSchool = "education_school"
            case appointmentTypes = "appointment_types"
            case isBookingClosed = "is_booking_closed"
            case requestPath = "request_path"
            case whatsappPath = "whatsapp_path"
            case whatsappAvailable = "whatsapp_available"
        }
    }

    struct Review: Decodable, Identifiable {
        let author: String?
        let rating: Int?
        let comment: String?
        var id: String { (author ?? "-") + (comment ?? "") }
    }
}

/// Tur 235 — Native hekim profili.
/// Tur 238 (Faz 3): randevu adımı da native oldu; artık WKWebView'a düşmüyor.
@MainActor
struct DVBDoctorDetailView: View {

    let doctor: DVBDoctor

    @State private var detail: DVBDoctorDetail?
    @State private var error: String?
    /// Açık talep sayfasının konusu (randevu | fiyat); nil = kapalı.
    @State private var talepKonusu: DVBTalepKonusu?

    @EnvironmentObject private var session: DVBSession
    @EnvironmentObject private var lock: DVBBiometricLock

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let error {
                    DVBStateView(icon: "wifi.exclamationmark", title: "Profil alınamadı", message: error) {
                        Task { await load() }
                    }
                } else if let d = detail?.doctor {
                    if d.isBookingClosed == true {
                        // DVB-000264 — bu bilgi eskiden alt çubuğun İÇİNDEYDİ ve çubuğu büyütüyordu.
                        Label("Online takvim kapalı — talebinizi bırakın, ekibimiz sizi arayıp randevunuzu oluştursun.",
                              systemImage: "phone.arrow.up.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DVBTheme.brand.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if let about = d.about, !about.isEmpty {
                        section("Hakkında") { Text(about).font(.body) }
                    }
                    if let school = d.educationSchool, !school.isEmpty {
                        section("Eğitim") { Text(school).font(.body) }
                    }
                    if let services = d.appointmentTypes, !services.isEmpty {
                        section("Hizmetler") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(services) { s in
                                    HStack {
                                        Text(s.name ?? "—")
                                        Spacer()
                                        if let dk = s.duration {
                                            Text("\(dk) dk").foregroundColor(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                    if let locations = d.locations, !locations.isEmpty {
                        section("Adres") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(locations.enumerated()), id: \.offset) { _, l in
                                    if let address = l.address, !address.isEmpty {
                                        Text(address).font(.subheadline)
                                    } else if let district = l.district {
                                        Text(district).font(.subheadline).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if let reviews = detail?.reviews, !reviews.isEmpty {
                        section("Değerlendirmeler") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(reviews) { r in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 3) {
                                            // Aralık DEĞİŞKEN: ForEach'e doğrudan Range vermek
                                            // SwiftUI'da çalışma anında uyarı üretir → dizi ver.
                                            ForEach(Array(0 ..< max(0, min(5, r.rating ?? 0))), id: \.self) { _ in
                                                Image(systemName: "star.fill").font(.caption2)
                                                    .foregroundColor(.orange)
                                            }
                                            Text(r.author ?? "").font(.caption).foregroundColor(.secondary)
                                        }
                                        if let c = r.comment { Text(c).font(.subheadline) }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { bookingBar }
        .navigationTitle(doctor.name ?? "Hekim")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // DVB-000110 — ARTIK WEB AÇMIYOR. Önceden burada DVBWebSheet vardı ve aday
        // hekimlerde (yayındaki hekimlerin %100'ü) uygulamanın ANA eylemi tarayıcıya
        // düşüyordu; Apple'ın 31.07.2026 tarihli 4.2.2 reddi tam bunu tarif ediyor.
        // Talep artık native formda alınıyor (POST /doctors/{slug}/request).
        .sheet(item: $talepKonusu) { konu in
            DVBRequestView(
                doctorSlug: doctor.slug,
                doctorName: detail?.doctor.name ?? doctor.name ?? "Hekim",
                konu: konu
            )
            // Sayfalar ortam nesnelerini her iOS sürümünde kendiliğinden almaz; talep formu oturumu (ön-doldurma,
            // jeton) ve "Giriş yap" için kilidi kullanır.
            .environmentObject(session)
            .environmentObject(lock)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            DVBAvatar(url: doctor.avatar, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(doctor.name ?? "—").font(.title3.bold())
                if let s = doctor.specialty { Text(s).foregroundColor(.secondary) }
                HStack(spacing: 12) {
                    if let d = doctor.district {
                        Label(d, systemImage: "mappin.and.ellipse")
                    }
                    if let y = detail?.doctor.experience ?? doctor.experience, y > 0 {
                        Label("\(y) yıl", systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    /// Tur 240 — App Store 4.2.2: takvimi kapalı hekimde (aday VEYA `booking_closed`
    /// gerçek hesap) artık `/slots`'a hiç GİTMİYORUZ — web'deki AYNI kural
    /// (`Doctor::isBookingClosed()`) burada da uygulanır. Sunucudan bilgi gelene kadar
    /// (ilk an) canlı randevu varsayılır — eski davranış, kullanıcı beklemeden tıklarsa
    /// zaten DVBBookingView kendi 404'ünü zarifçe karşılar.
    ///
    /// ⛔ DVB-000264 — kullanıcı (30 Eyl 2026): "randevu talep et kısmı çok büyük whatsapp az görünüyor ücret talep
    /// et butonu hiç yok". Eskiden: iki satır açıklama + tam genişlik düğme + YAZISIZ 52pt yeşil kare. Şimdi tek
    /// satırda ana eylem, altında YAZILI iki eşit düğme (Fiyat Talep Et + WhatsApp). Açıklama sayfa içeriğine taşındı.
    private var bookingBar: some View {
        let kapali = detail?.doctor.isBookingClosed == true
        // Eski sunucu bayrağı göndermez → eski davranış: takvimi kapalıda merkezî hat her zaman vardı.
        let whatsappVar = (detail?.doctor.whatsappAvailable ?? kapali)
            && DVBDoctorDetailView.absoluteWebURL(detail?.doctor.whatsappPath) != nil

        return VStack(spacing: 8) {
            if kapali {
                Button {
                    talepKonusu = .randevu
                } label: {
                    Label("Randevu Talep Et", systemImage: "calendar.badge.plus")
                        .anaDugme(DVBTheme.brand)
                }
            } else {
                NavigationLink(destination: DVBBookingView(doctor: doctor)) {
                    Label("Randevu Al", systemImage: "calendar")
                        .anaDugme(DVBTheme.brand)
                }
            }

            HStack(spacing: 8) {
                Button {
                    talepKonusu = .fiyat
                } label: {
                    Label("Fiyat Talep Et", systemImage: "turkishlirasign.circle")
                        .ikincilDugme(DVBTheme.fiyat)
                }
                if whatsappVar {
                    Button {
                        if let url = DVBDoctorDetailView.absoluteWebURL(detail?.doctor.whatsappPath) {
                            openURL(url)
                        }
                    } label: {
                        Label("WhatsApp", systemImage: "message.fill")
                            .ikincilDugme(DVBTheme.whatsapp, dolu: true)
                    }
                }
            }
            // Sunucudan bilgi gelmeden fiyat/WhatsApp gösterme: hangi hekim olduğu, takvim durumu henüz bilinmiyor.
            .opacity(detail == nil ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    /// Sunucudan gelen GÖRECELİ yol ("/randevu-talebi/slug") → tam URL. Yol yoksa nil
    /// (buton devre dışı kalır, çökme olmaz).
    static func absoluteWebURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: DVBConfig.webBase.absoluteString + path)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        do {
            detail = try await DVBAPI.shared.get("doctors/\(doctor.slug)")
            error = nil
        } catch {
            // DVB-000264 — İPTAL (sekme değişimi/yeniden çizim) hata DEĞİL: ekrandakini koru, "internet yok" deme.
            if let mesaj = DVBError.mesaj(error) { self.error = mesaj }
        }
    }
}

/// DVB-000264 — talep sayfasının konusu. Sunucudaki `topic` ile BİREBİR aynı anahtar.
enum DVBTalepKonusu: String, Identifiable {
    case randevu
    case fiyat

    var id: String { rawValue }
}

private extension View {
    /// Ana eylem: tam genişlik, 48pt. (Eskiden 14pt dolgu + başlık yazısı ~52pt'ti ve üstünde iki satır metin vardı.)
    func anaDugme(_ renk: Color) -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(renk)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// İkincil eylem: yarım genişlik, 42pt, YAZILI (eskiden WhatsApp yazısız bir simgeydi).
    func ikincilDugme(_ renk: Color, dolu: Bool = false) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(dolu ? renk : renk.opacity(0.1))
            .foregroundColor(dolu ? .white : renk)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
