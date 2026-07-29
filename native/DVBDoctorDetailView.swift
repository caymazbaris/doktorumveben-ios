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
    @State private var showRequestSheet = false

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
        .sheet(isPresented: $showRequestSheet) {
            if let url = DVBDoctorDetailView.absoluteWebURL(detail?.doctor.requestPath) {
                DVBWebSheet(url: url, title: "Randevu Talebi")
            }
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
    private var bookingBar: some View {
        Group {
            if detail?.doctor.isBookingClosed == true {
                VStack(spacing: 8) {
                    Text("Online takvim kapalı — talebinizi bize iletin, sizi arayalım.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button {
                            showRequestSheet = true
                        } label: {
                            Text("Randevu Talep Et")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(DVBTheme.brand)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        Button {
                            if let url = DVBDoctorDetailView.absoluteWebURL(detail?.doctor.whatsappPath) {
                                openURL(url)
                            }
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.headline)
                                .frame(width: 52, height: 52)
                                .background(Color(red: 0x25 / 255, green: 0xD3 / 255, blue: 0x66 / 255))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            } else {
                NavigationLink(destination: DVBBookingView(doctor: doctor)) {
                    Text("Randevu al")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DVBTheme.brand)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
            self.error = (error as? DVBError)?.errorDescription ?? "Bilinmeyen hata."
        }
    }
}
