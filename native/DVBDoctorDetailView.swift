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
        let languages: String?
        let specialties: [String]?
        let locations: [Location]?
        let appointmentTypes: [ServiceItem]?

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
        }
    }

    struct Review: Decodable, Identifiable {
        let author: String?
        let rating: Int?
        let comment: String?
        var id: String { (author ?? "-") + (comment ?? "") }
    }
}

/// Tur 235 — Native hekim profili. Randevu adımı web'de açılır (rezervasyon akışı
/// sunucu-render; native'e taşınması Faz 3'te). Böylece ilk sürümde bile hasta
/// randevusunu GERÇEKTEN alabiliyor.
struct DVBDoctorDetailView: View {

    let doctor: DVBDoctor

    @State private var detail: DVBDoctorDetail?
    @State private var error: String?
    @State private var showBooking = false

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
                                            ForEach(0 ..< max(0, min(5, r.rating ?? 0)), id: \.self) { _ in
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
        .sheet(isPresented: $showBooking) {
            DVBWebSheet(
                url: DVBConfig.webBase.appendingPathComponent("doktor/\(doctor.slug)"),
                title: doctor.name ?? "Randevu"
            )
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

    private var bookingBar: some View {
        Button {
            showBooking = true
        } label: {
            Text("Randevu al")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DVBTheme.brand)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
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
