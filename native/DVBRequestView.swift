import SwiftUI

/// DVB-000110 — ADAY HEKİM İÇİN NATIVE RANDEVU TALEBİ.
///
/// NEDEN VAR — App Store 4.2.2 reddinin ölçülen kök nedeni:
/// Yayındaki 165.985 hekimin 165.983'ü aday (05.09.2026 sayımı). Aday hekimde online
/// takvim olmadığı için tek eylem "Randevu Talebi"ydi ve o da DVBWebSheet ile WEB
/// açıyordu. Yani reviewer hangi hekime dokunursa dokunsun uygulamanın ANA eyleminde
/// tarayıcı görüyordu. Apple'ın 31.07.2026 tarihli reddi bunu birebir tarif ediyor:
/// "the app only includes links, images, or content aggregated from the Internet with
/// limited or no native functionality".
///
/// Bu ekran o akışı uygulamanın içine alır: hasta hiç web görmeden talebini bırakır.
///
/// DVB-000264/265 — aynı ekran FİYAT talebini de alır (`konu`) ve sitedeki kuralla BİREBİR aynı ÜYELİK şartını
/// uygular (kullanıcı, 30 Eyl 2026: "üyelik şartı koyalım, ad soyad mail adresi şehir ve telefon bilgisi girilsin").
/// Misafir bu bilgilerle hesap edinir; hesap şifresizdir, oturum AÇILMAZ (telefon doğrulanmadı). Sunucu
/// `uyelik_surumu=1` gören istemciye tam kuralı uygular — mağazadaki eski sürüm bu alanı göndermez ve eski
/// yoldan geçer (geçiş).
struct DVBRequestView: View {

    let doctorSlug: String
    let doctorName: String
    var konu: DVBTalepKonusu = .randevu

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: DVBSession
    @EnvironmentObject private var lock: DVBBiometricLock
    @ObservedObject private var secim = DVBKonumSecimi.shared

    @State private var ad = ""
    @State private var telefon = ""
    @State private var eposta = ""
    /// Şehir kimliği (sunucudaki `cities.id`). Varsayılan: arama ekranındaki konum/il seçimi.
    @State private var ilId: Int?
    @State private var iller: [DVBIl] = []
    @State private var sozlesme = false
    /// E-posta/telefon başka bir hesaba aitse (409 `hesap_var`): giriş düğmesi görünür.
    @State private var hesapVar = false
    @State private var girisAcik = false
    @State private var tercihTarih = Date()
    @State private var tarihSecili = false
    /// Varsayılan 'any' ("Fark etmez") — sunucudaki listenin ilk maddesi.
    /// Tipi String? DEĞİL String: Picker'ın tag tipiyle seçim tipi birebir aynı
    /// olmalı, yoksa SwiftUI seçimi sessizce hiç uygulamaz (derleme hatası vermez).
    @State private var tercihDilim: String = "any"
    @State private var ilkZiyaret = false
    @State private var not = ""
    @State private var riza = false

    @State private var gonderiliyor = false
    @State private var hata: String? = nil
    @State private var sonuc: DVBRequestResult? = nil

    /// AppointmentRequest::SLOTS ile BİREBİR aynı — anahtar VE etiket.
    ///
    /// ⚠ İlk yazışımda etiketleri kısaltmıştım ("Sabah") ve 'any' seçeneğini hiç
    /// koymamıştım. İkisi de sessiz kusurdu: hasta uygulamada "Sabah", sitede
    /// "Sabah (09:00-12:00)" görecekti — saat aralığı hastanın kararını etkileyen
    /// bilgidir. Sunucudaki liste tek kaynaktır; değişirse burası da değişmeli.
    private let dilimler: [(String, String)] = [
        ("any", "Fark etmez"),
        ("morning", "Sabah (09:00-12:00)"),
        ("afternoon", "Öğleden sonra (12:00-17:00)"),
        ("evening", "Akşam (17:00 sonrası)"),
    ]

    private var misafir: Bool { !session.isLoggedIn }

    private var gonderilebilir: Bool {
        let e = eposta.trimmingCharacters(in: .whitespaces)
        return ad.trimmingCharacters(in: .whitespaces).count >= 3
            && telefon.filter(\.isNumber).count >= 10
            && e.contains("@") && e.contains(".")
            && ilId != nil
            && riza
            && (!misafir || sozlesme)
            && !gonderiliyor
    }

    var body: some View {
        // ⚠ NavigationStack DEĞİL: o iOS 16+ ister. Depodaki diğer altı ekranın
        // tamamı NavigationView kullanıyor (DVBAccountView, DVBSearchView, ...),
        // yani proje daha düşük bir hedefe kurulu. Tek başıma NavigationStack
        // yazmak derlemeyi kırardı — hizayı bozmuyorum.
        NavigationView {
            Group {
                if let sonuc {
                    onayEkrani(sonuc)
                } else {
                    form
                }
            }
            .navigationTitle(sonuc != nil ? "Talebiniz Alındı" : (konu == .fiyat ? "Fiyat Talebi" : "Randevu Talebi"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sonuc == nil ? "Vazgeç" : "Kapat") { dismiss() }
                }
            }
        }
        // ⚠ DVB-000121 — iPAD'DE ŞART. NavigationView iPad'de varsayılan olarak
        // ÇİFT SÜTUNA düşer: solda form, sağda BOŞ bir bölme. Uygulama "yarısı
        // yüklenmemiş" gibi görünür. Depodaki diğer altı ekran bunu zaten
        // yapıyordu, burada eksikti — ve burası 4.2'yi çözen native talep formu,
        // yani incelemenin en çok baktığı ekran.
        .navigationViewStyle(.stack)
        .task { await hazirla() }
        // Mevcut hesaba takılan kişi burada giriş yapar; giriş olunca form hesap bilgileriyle dolar.
        .sheet(isPresented: $girisAcik, onDismiss: { hesapBilgisiniDoldur(); if session.isLoggedIn { hesapVar = false; hata = nil } }) {
            DVBAccountView()
                .environmentObject(session)
                .environmentObject(lock)
        }
    }

    /// Şehir listesi + ön-doldurma (girişli üyenin hesabı, arama ekranındaki konum seçimi).
    private func hazirla() async {
        hesapBilgisiniDoldur()
        if ilId == nil { ilId = secim.il?.id }
        iller = await DVBCografya.iller()
    }

    private func hesapBilgisiniDoldur() {
        guard let u = session.user else { return }
        if ad.isEmpty, let n = u.name { ad = n }
        // Yer tutucu adres (WhatsApp/aday hesabı) kişinin gerçek e-postası değil — forma yazılmaz (PlaceholderEmail::DOMAINS).
        if eposta.isEmpty, let m = u.email, !m.hasSuffix("@wa.doktorumveben.com"), !m.hasSuffix("@aday.doktorumveben.com") { eposta = m }
        if telefon.isEmpty, let p = u.phone { telefon = p }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                Text(doctorName).font(.headline)
                if konu == .fiyat {
                    // Tur 97 yasal bilgilendirme — sitedeki fiyat formuyla aynı metin.
                    (Text("Yasal bilgilendirme: ").bold()
                        + Text("Sağlık hizmeti ücretleri yasal düzenlemeler gereği internet sitemizde ve uygulamamızda paylaşılamamaktadır. Talebinizi bırakın; ücret bilgisi size özel olarak iletilsin."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("Bu hekimin çevrimiçi takvimi yok. Bilgilerinizi bırakın, ekibimiz sizi arayıp randevunuzu oluştursun.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if misafir {
                Section {
                    Text("Talep göndermek için üyelik gerekir. Aşağıdaki bilgilerle üyeliğiniz oluşturulur.")
                        .font(.footnote)
                    Button("Zaten üye misiniz? Giriş yapın") { girisAcik = true }
                        .font(.footnote.weight(.semibold))
                }
            }

            Section("Bilgileriniz") {
                TextField("Ad Soyad", text: $ad)
                    .textContentType(.name)
                    .autocorrectionDisabled()

                TextField("Cep telefonu", text: $telefon)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)

                TextField("E-posta", text: $eposta)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                // ⛔ Şehir sırası sunucudan gelir (City::ordered — İstanbul, İzmir, Ankara üstte); burada SIRALANMAZ.
                Picker("Şehir", selection: $ilId) {
                    Text("Seçin").tag(Int?.none)
                    ForEach(iller) { Text($0.name).tag(Int?.some($0.id)) }
                }
            }

            if konu == .randevu {
            Section("Tercihiniz (isteğe bağlı)") {
                Toggle("Tarih belirtmek istiyorum", isOn: $tarihSecili.animation())
                if tarihSecili {
                    DatePicker(
                        "Tercih ettiğim gün",
                        selection: $tercihTarih,
                        in: Date()...Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
                        displayedComponents: .date
                    )
                }

                // "Fark etmez" artık listenin kendi içinde ('any'), ayrı bir nil
                // seçeneği YOK — ikisi birlikte dururken aynı anlamda iki satır
                // görünüyordu ve hangisinin gönderildiği belirsizdi.
                Picker("Gün içi tercih", selection: $tercihDilim) {
                    ForEach(dilimler, id: \.0) { Text($0.1).tag($0.0) }
                }

                Toggle("İlk kez gideceğim", isOn: $ilkZiyaret)
            }
            }

            Section {
                // ⚠ `axis: .vertical` ve aralıklı `lineLimit(3...6)` iOS 16+ ister.
                // Hedef sürüm depoda sabit olmadığı için kapıyla veriyoruz; düşük
                // hedefte tek satırlık alan görünür ama DERLEME KIRILMAZ.
                if #available(iOS 16.0, *) {
                    TextField("Eklemek istedikleriniz", text: $not, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    TextField("Eklemek istedikleriniz", text: $not)
                }
            } header: {
                Text("Not (isteğe bağlı)")
            } footer: {
                // Sunucudaki web formuyla aynı uyarı — sağlık verisi serbest metne yazılmasın.
                Text("Lütfen sağlık bilgilerinizi buraya yazmayın; ekibimiz sizi arayacak.")
            }

            Section {
                Toggle(isOn: $riza) {
                    Text(misafir
                         ? "KVKK Aydınlatma Metni'ni okudum; Açık Rıza Metni kapsamında kişisel verilerimin işlenmesine ve talebim için benimle iletişime geçilmesine açık rıza veriyorum."
                         : "Talebimin iletilmesi için bilgilerimin işlenmesini onaylıyorum.")
                        .font(.footnote)
                }
                if misafir {
                    Toggle(isOn: $sozlesme) {
                        Text("Üyelik Sözleşmesi ve Gizlilik Politikası'nı okudum, kabul ediyorum.")
                            .font(.footnote)
                    }
                    // Metinler web'de; Safari'de açılır (yasal metin — uygulamanın ana akışı değil).
                    Link("KVKK Aydınlatma Metni", destination: DVBConfig.webBase.appendingPathComponent("sozlesmeler/kvkk-aydinlatma"))
                        .font(.footnote)
                    Link("Açık Rıza Metni", destination: DVBConfig.webBase.appendingPathComponent("sozlesmeler/acik-riza"))
                        .font(.footnote)
                    Link("Üyelik Sözleşmesi", destination: DVBConfig.webBase.appendingPathComponent("sozlesmeler/uyelik-sozlesmesi"))
                        .font(.footnote)
                }
            } footer: {
                if let hata {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hata).foregroundColor(.red)
                        if hesapVar {
                            Button("Giriş yap") { girisAcik = true }.font(.footnote.weight(.semibold))
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await gonder() }
                } label: {
                    HStack {
                        Spacer()
                        if gonderiliyor { ProgressView().padding(.trailing, 6) }
                        Text(gonderiliyor ? "Gönderiliyor…" : (misafir ? "Üye Ol ve Talebi Gönder" : "Talebi Gönder")).bold()
                        Spacer()
                    }
                }
                .disabled(!gonderilebilir)
            }
        }
    }

    // MARK: - Onay

    private func onayEkrani(_ s: DVBRequestResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(DVBTheme.brand)

            Text(s.message ?? "Talebiniz alındı.")
                .font(.headline)
                .multilineTextAlignment(.center)

            if let kod = s.request?.refCode {
                VStack(spacing: 4) {
                    Text("Talep numaranız").font(.caption).foregroundColor(.secondary)
                    Text(kod).font(.title3.monospaced().bold()).textSelection(.enabled)
                }
                .padding(.top, 4)
            }

            if s.uyelikAcildi == true {
                // Oturum AÇILMADI (telefon doğrulanmadı). Hesap şifresiz: "Parolamı unuttum" telefona kod gönderir.
                Text("Üyeliğiniz oluşturuldu. Hesabım › Parolamı unuttum adımıyla telefonunuza gelen kodla şifre belirleyip giriş yapabilirsiniz.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(DVBTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()
        }
        .padding(28)
    }

    // MARK: - Gönderim

    private func gonder() async {
        gonderiliyor = true
        hata = nil

        var govde: [String: Any] = [
            "name": ad.trimmingCharacters(in: .whitespaces),
            "phone": telefon,
            "email": eposta.trimmingCharacters(in: .whitespaces),
            "consent": true,
            "topic": konu.rawValue,
            // DVB-000265 — sunucu bu alanı gören istemciye TAM üyelik kuralını uygular (eski sürüm göndermez).
            "uyelik_surumu": 1,
        ]
        if let ilId { govde["city_id"] = ilId }
        if misafir { govde["terms"] = sozlesme }
        if konu == .randevu { govde["is_first_visit"] = ilkZiyaret }
        if konu == .randevu, tarihSecili {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = DVBTime.klinik
            f.dateFormat = "yyyy-MM-dd"
            govde["preferred_date"] = f.string(from: tercihTarih)
        }
        if konu == .randevu { govde["preferred_slot"] = tercihDilim }
        if !not.trimmingCharacters(in: .whitespaces).isEmpty {
            govde["note"] = not.trimmingCharacters(in: .whitespaces)
        }

        do {
            // Jeton gönderilir: girişli üyenin talebi ONA bağlanır (eski sürüm jetonsuz gönderiyordu).
            let cevap: DVBRequestResult = try await DVBAPI.shared.post(
                "doctors/\(doctorSlug)/request", body: govde, token: session.token
            )
            sonuc = cevap
        } catch DVBError.server(409, let mesaj) {
            // ⛔ Bu e-posta/telefon başka bir hesaba ait: hesap AÇILMADI. Kişi giriş yapıp tekrar gönderir.
            hesapVar = true
            hata = mesaj ?? "Bu e-posta ya da telefonla bir üyeliğiniz var. Giriş yapıp talebinizi gönderin."
        } catch {
            // 422 gövdesindeki sunucu mesajı DVBError.server içinde taşınıyor.
            hata = (error as? LocalizedError)?.errorDescription
                ?? "Talebiniz gönderilemedi. Lütfen tekrar deneyin."
        }

        gonderiliyor = false
    }
}
