import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════════════════════════
// DVB-000497 — TALEP ÖNCESİ TAKVİMLİ UZMAN ÖNERİSİ (web: DVB-000486 öneri ekranı).
//
// Kullanıcı (24 Kas 2026): "randevu ve fiyat talebinde öncelikli olarak o alandaki takvimi olan uzmanlardan önersin yine de
// o uzman için talep et gibi bi adımdan sonra o talep gelsin" → "tüm işlevleri uygulamaya ekle".
//
// Takvimi kapalı hekimde "Randevu Talep Et" / "Fiyat Talep Et" önce bu sayfayı açar: aynı ilde, aynı branş ağacında online
// randevu verebilen uzmanlar (sunucu seçer: GET doctors/{slug}/request-suggestions, web'le aynı servis). Uzmana dokununca
// profili açılır (Randevu Al / Fiyat Talep Et orada). "Yine de … talep et" mevcut formu AYNEN açar.
// Öneri yoksa, ağ hatasında ya da eski sunucuda (uç yok → 404) form doğrudan açılır — kişi hiçbir durumda takılmaz.
// Metinler sunucudan gelir (il adının "İzmir'de" gibi ekini sunucu doğru çekiyor); gelmezse aşağıdaki yedekler.
// ═══════════════════════════════════════════════════════════════════════════════════════════════════

struct DVBTalepOnerisi: Decodable {
    let title: String?
    let intro: String?
    let devam: String?
    let devamNotu: String?
    let data: [Kart]
    /// DVB-000503 — hekim talep almıyor (devlet kurumu / aile hekimi): "Yine de talep et" yok, form açılmaz; MHRS bağlantısı.
    let talepKapali: Bool?
    let mhrsUrl: String?

    enum CodingKeys: String, CodingKey {
        case title, intro, data
        case devam = "continue"
        case devamNotu = "continue_note"
        case talepKapali = "request_closed"
        case mhrsUrl = "mhrs_url"
    }

    struct Kart: Decodable, Identifiable {
        let slug: String
        let name: String?
        let specialty: String?
        let avatar: String?
        let district: String?
        let place: String?
        let experience: Int?

        var id: String { slug }

        /// Profil ekranı DVBDoctor ister; kart alanları aynı anlamda.
        var hekim: DVBDoctor {
            DVBDoctor(slug: slug, name: name, specialty: specialty, avatar: avatar, rating: nil, ratingCount: nil,
                      isVerified: nil, district: district, experience: experience, distanceKm: nil, bookingOpen: true)
        }
    }
}

@MainActor
struct DVBTalepOnerisiView: View {

    let doctorSlug: String
    let doctorName: String
    let konu: DVBTalepKonusu

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: DVBSession
    @EnvironmentObject private var lock: DVBBiometricLock

    @State private var oneri: DVBTalepOnerisi?
    /// true → mevcut talep formu (öneri yok / hata / "Yine de … talep et").
    @State private var formaGec = false

    var body: some View {
        if formaGec {
            DVBRequestView(doctorSlug: doctorSlug, doctorName: doctorName, konu: konu)
        } else {
            NavigationView {
                Group {
                    if let oneri {
                        liste(oneri)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle(konu == .fiyat ? "Fiyat Talebi" : "Randevu Talebi")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgeç") { dismiss() }
                    }
                }
            }
            // DVB-000121 — iPad'de çift sütuna düşmesin (DVBRequestView ile aynı).
            .navigationViewStyle(.stack)
            .task { await yukle() }
        }
    }

    private func liste(_ o: DVBTalepOnerisi) -> some View {
        List {
            Section {
                Text(o.intro ?? "\(doctorName) online randevu takvimini henüz açmadı. Aynı alanda online randevu verebilen uzmanlardan uygun saati hemen seçebilirsiniz.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } header: {
                Text(o.title ?? "Hemen randevu alabileceğiniz uzmanlar")
            }

            Section {
                ForEach(o.data) { k in
                    NavigationLink(destination: DVBDoctorDetailView(doctor: k.hekim)) {
                        satir(k)
                    }
                }
            } header: {
                if o.talepKapali == true && !o.data.isEmpty { Text("Hemen randevu alabileceğiniz uzmanlar") }
            } footer: {
                if o.talepKapali == true && o.data.isEmpty {
                    Text("Bu bölgede şu an aynı alanda online randevu verebilen uzman bulunmuyor.")
                }
            }

            if o.talepKapali == true {
                // DVB-000503 — talep formu yok; yerine MHRS.
                Section {
                    Button {
                        if let url = URL(string: o.mhrsUrl ?? DVBTalepKapaliKarti.mhrsYedek) { openURL(url) }
                    } label: {
                        Label("MHRS'den randevu al", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
            Section {
                Button {
                    formaGec = true
                } label: {
                    Text(o.devam ?? "Yine de \(doctorName) için \(konu == .fiyat ? "fiyat" : "randevu") talep et")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(o.devamNotu ?? (konu == .fiyat
                    ? "Ücret bilgisi yasal düzenlemeler gereği sitede yayınlanmaz; talebinizle size özel iletilir."
                    : "Talebinizi ekibimiz alır ve sizi arayarak bu uzmanla randevunuzu oluşturmaya çalışır."))
            }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func satir(_ k: DVBTalepOnerisi.Kart) -> some View {
        HStack(spacing: 12) {
            DVBAvatar(url: k.avatar, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(k.name ?? "—").font(.headline).lineLimit(2)
                if let s = k.specialty {
                    Text(s).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                }
                if let yer = k.place ?? k.district {
                    Label(yer, systemImage: "mappin.and.ellipse").font(.caption).foregroundColor(.secondary)
                }
                DVBOnlineRandevuEtiketi()
            }
        }
        .padding(.vertical, 4)
    }

    private func yukle() async {
        guard oneri == nil, !formaGec else { return }
        do {
            let o: DVBTalepOnerisi = try await DVBAPI.shared.get(
                "doctors/\(doctorSlug)/request-suggestions", query: ["topic": konu.rawValue])
            // DVB-000503 — talep alınmayan hekimde öneri boş olsa da sayfa uyarıyla açılır; form ASLA açılmaz.
            if o.data.isEmpty && o.talepKapali != true { formaGec = true } else { oneri = o }
        } catch {
            // İptal (sayfa kapanırken) hata değil; diğer her durumda kişi formu görür.
            if !Task.isCancelled { formaGec = true }
        }
    }
}

/// DVB-000497 — "Online randevu" etiketi (web'deki yeşil rozetin karşılığı): randevuya açık hekim kartında.
struct DVBOnlineRandevuEtiketi: View {
    /// Açık zeminde koyu yeşil (web'deki emerald-700, küçük yazıda okunur), koyu zeminde sistem yeşili.
    private static let renk = Color(UIColor { iz in
        iz.userInterfaceStyle == .dark ? .systemGreen : UIColor(red: 0x04 / 255, green: 0x78 / 255, blue: 0x57 / 255, alpha: 1)
    })

    var body: some View {
        Label("Online randevu", systemImage: "calendar")
            .font(.caption2.weight(.semibold))
            .foregroundColor(Self.renk)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Self.renk.opacity(0.12))
            .clipShape(Capsule())
    }
}
