import SwiftUI

/// `GET /doctors/{slug}/slots` yanıtı.
///
/// Sunucu `type` içinde `price` de gönderiyor ama BURADA KASITLI OKUNMUYOR:
/// fiyat hiçbir public yüzeyde yayınlanmaz (yasal kural). Decodable bilinmeyen
/// anahtarları yok saydığı için alanı hiç tanımlamamak yeterli.
struct DVBSlotsResponse: Decodable {
    let type: ServiceType
    /// "2026-08-01" → ["2026-08-01T09:00:00+03:00", …]
    let slots: [String: [String]]

    struct ServiceType: Decodable {
        let id: Int
        let name: String?
        let duration: Int?
    }
}

/// `POST /doctors/{slug}/book` yanıtı.
struct DVBBookingResponse: Decodable {
    let appointment: Booked

    struct Booked: Decodable {
        let no: String?
        let startsAt: Date?
        let status: String?
        let preparation: String?

        enum CodingKeys: String, CodingKey {
            case no, status, preparation
            case startsAt = "starts_at"
        }
    }
}

/// Tur 238 (Faz 3) — RANDEVU ALMA ARTIK NATIVE.
///
/// Apple 4.2 reddinin çekirdeği buydu: uygulamanın tek gerçek işi olan "randevu al"
/// adımı WKWebView'da açılıyordu, yani uygulama sitenin kabuğu gibi davranıyordu.
/// Artık gün/saat seçimi, hasta formu ve onay ekranı tamamen SwiftUI; üstüne
/// cihazın kendi yetenekleri geliyor (takvime yazma + yerel hatırlatma), ki bunlar
/// bir web sayfasının yapamayacağı şeyler.
@MainActor
struct DVBBookingView: View {

    let doctor: DVBDoctor

    @EnvironmentObject private var session: DVBSession
    @Environment(\.presentationMode) private var presentation
    @Environment(\.openURL) private var openURL

    // Tur 240 — savunma katmanı: DVBDoctorDetailView artık isBookingClosed==true'da
    // buraya HİÇ girmiyor, ama slotlar başka bir sebeple (hizmet henüz tanımsız,
    // tamamen dolu takvim) boş dönerse yine de çıkmaz sokak bırakmayalım.
    @State private var showRequestSheet = false

    // Slotlar
    @State private var response: DVBSlotsResponse?
    @State private var yukleniyor = true
    @State private var hata: String?

    // Seçim
    @State private var seciliGun: String?
    @State private var seciliSlot: String?

    // Form
    @State private var ad = ""
    @State private var soyad = ""
    @State private var telefon = ""
    @State private var eposta = ""
    @State private var ilkGorusme = true
    @State private var gonderiliyor = false
    @State private var formHatasi: String?

    // Sonuç
    @State private var sonuc: DVBBookingResponse.Booked?

    var body: some View {
        Group {
            if let sonuc {
                DVBBookingDoneView(doctor: doctor, booked: sonuc) {
                    presentation.wrappedValue.dismiss()
                }
            } else if yukleniyor {
                ProgressView("Uygun saatler alınıyor…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let hata {
                DVBStateView(icon: "calendar.badge.exclamationmark", title: "Takvim açılamadı", message: hata) {
                    Task { await slotlariGetir() }
                }
            } else if gunler.isEmpty {
                VStack(spacing: 16) {
                    DVBStateView(
                        icon: "calendar",
                        title: "Şu an uygun saat yok",
                        message: "Bu hekimin önümüzdeki günlerde açık saati görünmüyor. Talebinizi iletin, sizi arayalım."
                    )
                    VStack(spacing: 10) {
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
                            if let url = DVBBookingView.absoluteWebURL("/whatsapp/randevu/\(doctor.slug)") {
                                openURL(url)
                            }
                        } label: {
                            Label("WhatsApp'tan yaz", systemImage: "message.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0x25 / 255, green: 0xD3 / 255, blue: 0x66 / 255))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 24)
                }
            } else {
                secimVeForm
            }
        }
        .navigationTitle("Randevu al")
        .navigationBarTitleDisplayMode(.inline)
        .task { await slotlariGetir() }
        .onAppear(perform: kullanicidanDoldur)
        .sheet(isPresented: $showRequestSheet) {
            if let url = DVBBookingView.absoluteWebURL("/randevu-talebi/\(doctor.slug)") {
                DVBWebSheet(url: url, title: "Randevu Talebi")
            }
        }
    }

    static func absoluteWebURL(_ path: String) -> URL? {
        URL(string: DVBConfig.webBase.absoluteString + path)
    }

    // MARK: - Gövde

    private var secimVeForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let t = response?.type {
                    HStack(spacing: 8) {
                        Image(systemName: "stethoscope").foregroundColor(DVBTheme.brand)
                        Text(t.name ?? "Muayene").font(.subheadline.weight(.semibold))
                        if let dk = t.duration {
                            Text("· \(dk) dk").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }

                bolum("Gün") { gunSeridi }

                if let gun = seciliGun, let saatler = response?.slots[gun], !saatler.isEmpty {
                    bolum("Saat") { saatIzgarasi(saatler) }
                }

                if seciliSlot != nil {
                    bolum("Bilgileriniz") { form }
                }
            }
            .padding(20)
        }
    }

    private var gunSeridi: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(gunler, id: \.self) { gun in
                    let secili = gun == seciliGun
                    Button {
                        seciliGun = gun
                        seciliSlot = nil
                    } label: {
                        VStack(spacing: 2) {
                            Text(gunAdi(gun)).font(.caption2)
                            Text(gunNumarasi(gun)).font(.headline)
                            Text("\(response?.slots[gun]?.count ?? 0) saat")
                                .font(.system(size: 10))
                                .foregroundColor(secili ? .white.opacity(0.85) : .secondary)
                        }
                        .frame(width: 64, height: 68)
                        .background(secili ? DVBTheme.brand : Color.secondary.opacity(0.12))
                        .foregroundColor(secili ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func saatIzgarasi(_ saatler: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
            ForEach(saatler, id: \.self) { iso in
                let secili = iso == seciliSlot
                Button {
                    seciliSlot = iso
                    formHatasi = nil
                } label: {
                    Text(saatEtiketi(iso))
                        .font(.subheadline.weight(secili ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(secili ? DVBTheme.brand : Color.secondary.opacity(0.12))
                        .foregroundColor(secili ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var form: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                alan("Ad", text: $ad, content: .name)
                alan("Soyad", text: $soyad, content: .familyName)
            }
            alan("Cep telefonu", text: $telefon, content: .telephoneNumber, keyboard: .phonePad)
            alan("E-posta (opsiyonel)", text: $eposta, content: .emailAddress, keyboard: .emailAddress)

            // Tur 222 — web ve WhatsApp akışında da sorulan soru; hekim hazırlığı buna göre.
            Toggle("Bu hekimle ilk görüşmem", isOn: $ilkGorusme)
                .tint(DVBTheme.brand)
                .padding(.top, 2)

            if let formHatasi {
                Text(formHatasi)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await gonder() }
            } label: {
                HStack {
                    if gonderiliyor { ProgressView().tint(.white) }
                    Text(gonderiliyor ? "Gönderiliyor…" : "Randevuyu oluştur")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DVBTheme.brand)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(gonderiliyor)
            .padding(.top, 4)

            Text("Randevunuz hekim onayına düşer; onaylandığında bildirim alırsınız.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func alan(_ baslik: String, text: Binding<String>,
                      content: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(baslik).font(.caption).foregroundColor(.secondary)
            TextField("", text: text)
                .textContentType(content)
                .keyboardType(keyboard)
                // `.none` kısaltması Optional.none ile karışabildiği için tip AÇIK yazılır.
                .autocapitalization(keyboard == .emailAddress ? UITextAutocapitalizationType.none : .words)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func bolum<Content: View>(_ baslik: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(baslik).font(.headline)
            content()
        }
    }

    // MARK: - Veri

    private var gunler: [String] {
        // Sunucu boş günleri de gönderebiliyor; saat içermeyen günü göstermeyiz.
        (response?.slots ?? [:]).filter { !$0.value.isEmpty }.keys.sorted()
    }

    private func slotlariGetir() async {
        yukleniyor = true
        do {
            let r: DVBSlotsResponse = try await DVBAPI.shared.get("doctors/\(doctor.slug)/slots", query: ["days": "14"])
            response = r
            hata = nil
            seciliGun = r.slots.filter { !$0.value.isEmpty }.keys.sorted().first
        } catch DVBError.notFound {
            // Hekimin tanımlı/aktif hizmeti yoksa sunucu 404 döner — bu "takvim kapalı" demek.
            response = DVBSlotsResponse(type: .init(id: 0, name: nil, duration: nil), slots: [:])
            hata = nil
        } catch {
            hata = (error as? DVBError)?.errorDescription ?? "Bilinmeyen hata."
        }
        yukleniyor = false
    }

    private func kullanicidanDoldur() {
        guard ad.isEmpty, let u = session.user else { return }
        let parcalar = (u.name ?? "").split(separator: " ")
        if parcalar.count >= 2 {
            ad = String(parcalar.dropLast().joined(separator: " "))
            soyad = String(parcalar[parcalar.count - 1])
        } else {
            ad = u.name ?? ""
        }
        telefon = u.phone ?? ""
        eposta = u.email ?? ""
    }

    private func gonder() async {
        guard let slot = seciliSlot, let serviceId = response?.type.id, serviceId > 0 else { return }

        // Sunucu tarafı zaten doğruluyor; burada erken uyarmak hastayı ağ turundan kurtarır.
        guard ad.trimmingCharacters(in: .whitespaces).count >= 2,
              soyad.trimmingCharacters(in: .whitespaces).count >= 2 else {
            formHatasi = "Ad ve soyadınızı yazın."
            return
        }
        guard DVBBookingView.gecerliCep(telefon) else {
            formHatasi = "Geçerli bir cep telefonu girin (5xx xxx xx xx)."
            return
        }

        gonderiliyor = true
        formHatasi = nil
        var govde: [String: Any] = [
            "service_id": serviceId,
            "slot": slot,
            "first_name": ad.trimmingCharacters(in: .whitespaces),
            "last_name": soyad.trimmingCharacters(in: .whitespaces),
            "phone": telefon,
            "is_first_visit": ilkGorusme,
        ]
        if !eposta.trimmingCharacters(in: .whitespaces).isEmpty {
            govde["email"] = eposta.trimmingCharacters(in: .whitespaces)
        }

        do {
            let r: DVBBookingResponse = try await DVBAPI.shared.post(
                "doctors/\(doctor.slug)/book", body: govde, token: session.token
            )
            sonuc = r.appointment
        } catch {
            // 409 = slot kapılmış. Kullanıcıyı boş bırakmayıp takvimi tazeliyoruz.
            formHatasi = (error as? DVBError)?.errorDescription ?? "Randevu oluşturulamadı."
            seciliSlot = nil
            await slotlariGetir()
        }
        gonderiliyor = false
    }

    /// Sunucudaki `BookAppointmentRequest` kuralının istemci karşılığı.
    static func gecerliCep(_ ham: String) -> Bool {
        let rakam = ham.filter { $0.isNumber }
        let son10 = rakam.count >= 10 ? String(rakam.suffix(10)) : rakam
        return son10.count == 10 && son10.hasPrefix("5")
    }

    // MARK: - Biçimlendirme

    private static let gunCozucu: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func gunTarihi(_ gun: String) -> Date? { DVBBookingView.gunCozucu.date(from: gun) }

    private func gunAdi(_ gun: String) -> String {
        guard let d = gunTarihi(gun) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    private func gunNumarasi(_ gun: String) -> String {
        guard let d = gunTarihi(gun) else { return gun }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d"
        return f.string(from: d)
    }

    private func saatEtiketi(_ iso: String) -> String {
        guard let d = DVBBookingView.isoCozucu(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func isoCozucu(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }
}

/// Onay ekranı — randevu numarası + cihaz yetenekleri (takvim / hatırlatma).
@MainActor
struct DVBBookingDoneView: View {

    let doctor: DVBDoctor
    let booked: DVBBookingResponse.Booked
    let kapat: () -> Void

    @State private var takvimDurumu: String?
    @State private var hatirlatmaDurumu: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(DVBTheme.brand)
                    .padding(.top, 30)

                Text("Randevu talebiniz alındı")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                if let d = booked.startsAt {
                    Text(d.dvbLong).font(.headline)
                }
                Text(doctor.name ?? "").foregroundColor(.secondary)

                if let no = booked.no {
                    Text("Randevu no: \(no)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if let hazirlik = booked.preparation, !hazirlik.isEmpty {
                    Text(hazirlik)
                        .font(.subheadline)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let baslangic = booked.startsAt {
                    VStack(spacing: 10) {
                        eylem("Telefonumun takvimine ekle", ikon: "calendar.badge.plus", durum: takvimDurumu) {
                            Task {
                                takvimDurumu = await DVBCalendarKit.takvimeEkle(
                                    baslik: "\(doctor.name ?? "Hekim") randevusu",
                                    baslangic: baslangic,
                                    not: booked.no.map { "Doktorumveben · Randevu no \($0)" }
                                )
                            }
                        }
                        eylem("Bir gün önce hatırlat", ikon: "bell.badge", durum: hatirlatmaDurumu) {
                            Task {
                                hatirlatmaDurumu = await DVBCalendarKit.hatirlatmaKur(
                                    baslik: "Yarın randevunuz var",
                                    govde: "\(doctor.name ?? "Hekim") · \(baslangic.dvbLong)",
                                    randevuZamani: baslangic,
                                    kimlik: booked.no ?? UUID().uuidString
                                )
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                Button("Kapat", action: kapat)
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
            }
            .padding(24)
        }
    }

    private func eylem(_ baslik: String, ikon: String, durum: String?, aksiyon: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: aksiyon) {
                HStack {
                    Image(systemName: ikon)
                    Text(baslik)
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if let durum {
                Text(durum)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
