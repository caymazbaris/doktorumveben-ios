import SwiftUI

/// Tur 235 — Hesap sekmesi: giriş, üyelik bilgisi, belgeler ve App Store 5.1.1(v)
/// gereği UYGULAMA İÇİNDEN hesap silme.
@MainActor
struct DVBAccountView: View {

    @EnvironmentObject private var session: DVBSession

    /// DVB-000111 — kilit ayarı köke bağlı; buradan yalnız açılıp kapatılır.
    @EnvironmentObject private var lock: DVBBiometricLock

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    /// DVB-000276 — şifre doğru, ikinci adım kodu bekleniyor (iki adım gereken hesap).
    @State private var ikinciAdim: DVBIkinciAdim?
    @State private var kod = ""
    @State private var kurtarmaKoduModu = false
    @State private var confirmDelete = false
    @State private var webSheet: DVBIdentifiableURL?
    /// DVB-000264 — bildirimler artık sekme değil; buradan da açılır.
    @State private var bildirimlerAcik = false

    /// DVB-000290 — bildirimden gelen hasta sohbeti (ya da Mesajlarım) bu sekmenin gezinmesinde açılır, web değil.
    @ObservedObject private var gezinme = DVBGezinme.shared
    @State private var bildirimSohbeti: Int?
    @State private var mesajlarAcik = false
    /// DVB-000286 — takvim hatası bildirimi hekimin takvim ekranını bu sekmede açar.
    @State private var takvimAcik = false

    var body: some View {
        NavigationView {
            Group {
                if session.isLoggedIn { signedIn } else { signedOut }
            }
            .navigationTitle("Hesabım")
            .sheet(item: $webSheet) { item in
                DVBWebSheet(url: item.url, title: "Doktorumveben")
            }
            .background(
                VStack {
                    NavigationLink(
                        destination: DVBHekimSohbetView(sohbetId: bildirimSohbeti ?? 0, ad: "Mesaj", hastaModu: true),
                        isActive: Binding(get: { bildirimSohbeti != nil }, set: { if !$0 { bildirimSohbeti = nil } })
                    ) { EmptyView() }
                    NavigationLink(destination: DVBHastaMesajlarView(), isActive: $mesajlarAcik) { EmptyView() }
                    NavigationLink(destination: DVBHekimTakvimView(), isActive: $takvimAcik) { EmptyView() }
                }
                .hidden()
            )
            .onReceive(gezinme.$takvim) { acik in
                guard acik else { return }
                takvimAcik = true
                gezinme.takvim = false
            }
            .onReceive(gezinme.$hastaSohbet) { id in
                guard let id else { return }
                bildirimSohbeti = id
                gezinme.hastaSohbet = nil
            }
            .onReceive(gezinme.$hastaMesajlar) { acik in
                guard acik else { return }
                mesajlarAcik = true
                gezinme.hastaMesajlar = false
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Girişli

    private var signedIn: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.user?.name ?? "Üyeliğiniz").font(.headline)
                    if let mail = session.user?.email {
                        Text(mail).font(.subheadline).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    bildirimlerAcik = true
                } label: {
                    HStack {
                        Label("Bildirimler", systemImage: "bell")
                        Spacer()
                        if session.unreadCount > 0 {
                            Text("\(session.unreadCount)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                }
                .foregroundColor(.primary)
                .sheet(isPresented: $bildirimlerAcik, onDismiss: { Task { await session.okunmamisiYenile() } }) {
                    DVBNotificationsView().environmentObject(session)
                }
            }

            // DVB-000266 — sitedeki üye alanının bölümleri (1. adım). Kullanıcı: "hesabım kısmında da sitede üyenin
            // profilinde olan herşey olmalı".
            Section("Hesabım") {
                // DVB-000290 — hastanın hekimleriyle yazışmaları (web /hesabim/mesajlar). Hekim kendi hasta mesajlarını
                // Gelen Kutusu'nda görür; burada kendi (hasta olarak) yazışmaları karışmasın diye yalnız hasta hesabında.
                if session.hekim == nil {
                    NavigationLink(destination: DVBHastaMesajlarView()) {
                        Label("Mesajlarım", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                NavigationLink(destination: DVBProfilView()) {
                    Label("Profil bilgilerim", systemImage: "person.text.rectangle")
                }
                NavigationLink(destination: DVBYakinlarView()) {
                    Label("Yakınlarım", systemImage: "person.2")
                }
                NavigationLink(destination: DVBFavorilerView()) {
                    Label("Favori hekimlerim", systemImage: "heart")
                }
                NavigationLink(destination: DVBYorumlarView()) {
                    Label("Değerlendirmelerim", systemImage: "star.bubble")
                }
                NavigationLink(destination: DVBOdemelerView()) {
                    Label("Ödemelerim", systemImage: "creditcard")
                }
            }

            // DVB-000343 — muhasebeci (salt okunur) hesap faturaları görür; Hekim bölümü ona kapalı olduğundan ayrı bölüm.
            if let hekim = session.hekim, hekim.readOnly == true, hekim.faturalarAcik {
                Section("Hekim") {
                    NavigationLink(destination: DVBHekimFaturalarView()) {
                        Label("Faturalar", systemImage: "doc.text")
                    }
                }
            }

            // DVB-000286 — hekimin takvim bağlantıları (Apple Takvim aboneliği, Google, durum). Muhasebe görünümünde yok.
            // DVB-000341 — hekimin günlük işleri: hasta talepleri, çalışma saatleri ve izinler, hizmetler (sunucu bayraklarıyla).
            if let hekim = session.hekim, hekim.readOnly != true {
                Section("Hekim") {
                    // DVB-000343 — profil düzenleme, muhasebe, e-Fatura.
                    if hekim.profilAcik {
                        NavigationLink(destination: DVBHekimProfilView()) {
                            Label("Profilim", systemImage: "person.crop.circle")
                        }
                    }
                    if hekim.muhasebeAcik {
                        NavigationLink(destination: DVBHekimMuhasebeView()) {
                            Label("Muhasebe", systemImage: "turkishlirasign.circle")
                        }
                    }
                    if hekim.faturalarAcik {
                        NavigationLink(destination: DVBHekimFaturalarView()) {
                            Label("Faturalar", systemImage: "doc.text")
                        }
                    }
                    if hekim.taleplerAcik {
                        NavigationLink(destination: DVBHekimTaleplerView()) {
                            Label("Hasta talepleri", systemImage: "tray.full")
                        }
                    }
                    if hekim.calismaSaatleriAcik {
                        NavigationLink(destination: DVBHekimCalismaSaatleriView()) {
                            Label("Çalışma saatleri ve izinler", systemImage: "clock")
                        }
                    }
                    if hekim.hizmetlerAcik {
                        NavigationLink(destination: DVBHekimHizmetlerView()) {
                            Label("Hizmetler", systemImage: "list.bullet.rectangle")
                        }
                    }
                    NavigationLink(destination: DVBHekimTakvimView()) {
                        Label("Takvim bağlantıları", systemImage: "calendar.badge.clock")
                    }
                }
            }

            Section("Sağlık kayıtlarım") {
                NavigationLink(destination: DVBDocumentsView()) {
                    Label("Belgelerim", systemImage: "doc.text")
                }
                NavigationLink(destination: DVBConsentsView()) {
                    Label("Onam formlarım", systemImage: "signature")
                }
            }

            // DVB-000279 — iki adımlı doğrulama (web ayar ekranlarıyla aynı kurallar; Android'de web sayfası).
            Section {
                NavigationLink(destination: DVBIkiAdimAyarView()) {
                    Label("İki adımlı doğrulama", systemImage: "lock.shield")
                }
            } header: {
                Text("Güvenlik")
            }

            // DVB-000111 — biyometrik kilit. Cihaz desteklemiyorsa bölüm HİÇ gösterilmez;
            // açılamayacak bir anahtar göstermek kullanıcıya "bozuk" hissi verir.
            if DVBBiometricLock.kullanilabilir().evet {
                Section {
                    Toggle(isOn: $lock.etkin) {
                        Label(
                            "\(DVBBiometricLock.kullanilabilir().ad) ile kilitle",
                            systemImage: "faceid"
                        )
                    }
                } footer: {
                    Text("Açıkken uygulama her açılışta ve arka plandan dönüşte kimliğinizi sorar. Bu bir ekran perdesidir; verileriniz sunucuda oturumunuzla korunur.")
                }
            }

            // DVB-000157 — SORUN BİLDİR. Kullanıcılar "uygulamada bildirecek yer yok" dedi;
            // talepler mağaza yorumundan ve WhatsApp'tan geliyordu ve hiçbiri kayda girmiyordu.
            //
            // ⚠ KENDİ BÖLÜMÜNDE duruyor, "Hesap"ın içine gömülmedi: aranan şey görünürlük.
            // Profil ayarlarının arasına koysaydık teknik olarak var ama pratikte yok olurdu —
            // bugüne kadarki durum tam olarak buydu (ekran vardı, panelin içindeydi).
            // ⚠ `Section("Başlık") { } footer: { }` DİYE BİR KURUCU YOK — Codemagik derlemesi
            // tam burada düştü (build 18): "cannot convert value of type 'String' to expected
            // argument type '() -> Content'". String başlık ile footer birlikte kullanılamıyor;
            // ikisi birden isteniyorsa header ve footer KAPANIŞ olarak verilir.
            // Dosyanın altındaki biyometri bölümü de aynı desende (başlıksız + footer).
            Section {
                Button {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("hesabim/sorun-bildir"))
                } label: {
                    Label("Sorun bildir", systemImage: "exclamationmark.bubble")
                }
            } header: {
                Text("Yardım")
            } footer: {
                Text("Çalışmayan bir şey ya da öneriniz varsa yazın. Her bildirim takip numarası alır ve durumunu aynı sayfadan izleyebilirsiniz.")
            }

            Section("Hesap") {
                // DVB-000266 — "Profil bilgilerim" yukarıda YEREL ekran. Burada sitenin sayfasını web penceresinde
                // açıyordu; uygulamanın oturumu o pencereye taşınmadığı için kişi giriş sayfası görüyordu.
                Button {
                    // DVB-000168 — sitede herkese açık /gizlilik YOK (o adres hekim panelinin içinde);
                    // hasta 404 görüyordu. Gerçek sayfa /sozlesmeler/gizlilik.
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("sozlesmeler/gizlilik"))
                } label: {
                    Label("Gizlilik ve KVKK", systemImage: "lock.shield")
                }
            }

            Section {
                Button("Çıkış yap") { session.signOut() }
                Button("Hesabımı sil", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Hesabınızı silmek kişisel bilgilerinizi kalıcı olarak kaldırır. Hekiminizde yasal saklama süresi boyunca tutulması gereken klinik kayıtlar bu işlemden etkilenmez.")
            }
            .disabled(busy)
        }
        .alert("Hesabınız silinsin mi?", isPresented: $confirmDelete) {
            Button("Vazgeç", role: .cancel) {}
            Button("Sil", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("Bu işlem geri alınamaz. Tüm cihazlardaki oturumunuz kapatılır.")
        }
    }

    // MARK: - Girişsiz

    @ViewBuilder private var signedOut: some View {
        if let adim = ikinciAdim {
            ikinciAdimFormu(adim)
        } else {
            sifreFormu
        }
    }

    /// DVB-000276 — İKİNCİ ADIM: web'deki kod ekranının uygulama karşılığı. Kod WhatsApp'a (olmazsa e-postaya) gider;
    /// 6 hane tamamlanınca kendiliğinden doğrulanır. Kurtarma kodu (XXXX-XXXX) aynı kutudan kabul edilir.
    private func ikinciAdimFormu(_ adim: DVBIkinciAdim) -> some View {
        Form {
            Section {
                Text(adim.mesaj).font(.subheadline)
                TextField(kurtarmaKoduModu ? "Kurtarma kodu (XXXX-XXXX)" : "6 haneli kod", text: $kod)
                    .textContentType(.oneTimeCode)
                    .keyboardType(kurtarmaKoduModu ? .asciiCapable : .numberPad)
                    // Tür AÇIK: yalın `.none` derleyicide Optional.none ile karışabilir.
                    .autocapitalization(kurtarmaKoduModu ? UITextAutocapitalizationType.allCharacters : UITextAutocapitalizationType.none)
                    .disableAutocorrection(true)
                    .font(.title3.monospacedDigit())
                    .onChange(of: kod) { yeni in
                        guard !kurtarmaKoduModu else { return }
                        let rakamlar = String(yeni.filter(\.isNumber).prefix(6))
                        if rakamlar != yeni { kod = rakamlar; return }
                        if rakamlar.count == 6, !busy { Task { await dogrula() } }
                    }
            } header: {
                Text("İki adımlı doğrulama")
            } footer: {
                if let error {
                    Text(error).foregroundColor(.red)
                } else {
                    Text("Hesabınızda iki adımlı doğrulama açık. Gelen kodu girin; kod birkaç dakika geçerlidir.")
                }
            }

            Section {
                Button {
                    Task { await dogrula() }
                } label: {
                    HStack {
                        if busy { ProgressView().padding(.trailing, 6) }
                        Text("Doğrula")
                    }
                }
                .disabled(busy || kod.trimmingCharacters(in: .whitespaces).count < (kurtarmaKoduModu ? 9 : 6))
            }

            Section {
                // DVB-000280 — bekleyen anahtarla yeniden gönderim: Apple ile girende de çalışır, şifre gerekmez.
                Button("Kodu tekrar gönder") { Task { await koduYenidenGonder() } }
                    .disabled(busy)
                Button(kurtarmaKoduModu ? "Doğrulama kodu gir" : "Kurtarma kodu kullan") {
                    kurtarmaKoduModu.toggle()
                    kod = ""
                    error = nil
                }
                Button("Vazgeç", role: .cancel) {
                    ikinciAdim = nil
                    kod = ""
                    password = ""
                    error = nil
                    kurtarmaKoduModu = false
                }
            }
        }
    }

    private var sifreFormu: some View {
        Form {
            Section {
                TextField("E-posta", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                SecureField("Parola", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Giriş")
            } footer: {
                if let error {
                    Text(error).foregroundColor(.red)
                }
            }

            Section {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if busy { ProgressView().padding(.trailing, 6) }
                        Text("Giriş yap")
                    }
                }
                .disabled(busy || email.isEmpty || password.isEmpty)
            }

            // Tur 241 — App Store 4.8: Apple ile giriş UYGULAMA İÇİNDE, e-posta/parola
            // ile EŞDEĞER konumda. Eskiden burada "sonraki sürümde gelecek, şimdilik
            // üye ol ekranını kullanın" yazıyordu ve kullanıcı WebView'a atılıyordu —
            // 1.0 reddinin bir numaralı gerekçesi tam buydu.
            Section {
                DVBAppleSignInButton(busy: $busy, error: $error, ikinciAdim: $ikinciAdim)
            } header: {
                Text("Ya da")
            } footer: {
                Text("Apple ile giriş yaparsanız e-postanızı gizli tutabilirsiniz; hesabınızı uygulama içinden her zaman silebilirsiniz.")
            }

            // Yönetici isteği (06.09.2026): "üye ol ve parolamı unuttum yazıları ortalansın".
            // Form satırı düğmeyi sola yaslar; frame(maxWidth: .infinity) satırın tam
            // genişliğini alır, .center onu ortalar. Dokunma alanı daralmasın diye
            // hizalama Text'e değil DÜĞMENİN kendisine veriliyor — yalnız yazıyı
            // ortalasaydık satırın kenarları tıklanmaya devam eder ama görsel olarak
            // düğmenin nerede bittiği belirsiz kalırdı.
            Section {
                Button {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("uye-ol"))
                } label: {
                    Text("Üye ol").frame(maxWidth: .infinity, alignment: .center)
                }
                Button {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("sifremi-unuttum"))
                } label: {
                    Text("Parolamı unuttum").frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    // MARK: - Eylemler

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            switch try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) {
            case .tamam:
                password = ""
                ikinciAdim = nil
            case .ikinciAdim(let adim):
                // DVB-000280 — yeniden gönderim bekleyen anahtarla yapılıyor; parolanın ekranda kalmasına gerek yok.
                password = ""
                ikinciAdim = adim
                kod = ""
            }
        } catch {
            self.error = (error as? DVBError)?.errorDescription ?? "Giriş yapılamadı."
        }
    }

    /// DVB-000280 — kodu yeniden gönder (yeni kod + tazelenmiş anahtar).
    private func koduYenidenGonder() async {
        guard let adim = ikinciAdim, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            ikinciAdim = try await session.ikinciAdimKoduYenidenGonder(adim)
            kod = ""
        } catch {
            self.error = (error as? DVBError)?.errorDescription ?? "Kod yeniden gönderilemedi."
        }
    }

    /// DVB-000276 — ikinci adım kodunu doğrula; başarıda oturum açılır ve ekran Hesabım'a döner.
    private func dogrula() async {
        guard let adim = ikinciAdim, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.ikinciAdimiDogrula(adim, kod: kod.trimmingCharacters(in: .whitespaces))
            password = ""
            kod = ""
            ikinciAdim = nil
            kurtarmaKoduModu = false
        } catch {
            self.error = (error as? DVBError)?.errorDescription ?? "Doğrulama yapılamadı."
            kod = ""
        }
    }

    private func deleteAccount() async {
        guard let token = session.token else { return }
        busy = true
        defer { busy = false }
        do {
            var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent("account"))
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["confirm": true])

            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200 ... 299).contains(code) {
                session.signOut()
            } else {
                let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                error = obj?["message"] as? String ?? "Hesap silinemedi."
            }
        } catch {
            self.error = DVBError.offline.errorDescription
        }
    }
}

// MARK: - Belgeler / Onamlar

struct DVBDocumentsView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var items: [DVBDocument] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                DVBStateView(icon: "wifi.exclamationmark", title: "Belgeler alınamadı", message: error)
            } else if items.isEmpty {
                DVBStateView(icon: "doc.text", title: "Belgeniz yok",
                             message: "Hekiminiz tahlil veya rapor yüklediğinde burada görünür.")
            } else {
                List(items) { d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title ?? "Belge").font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            if let c = d.categoryLabel { Text(c) }
                            if let s = d.humanSize { Text(s) }
                            if let created = d.createdAt { Text(created.dvbLong) }
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Belgelerim")
        .task { await load() }
    }

    private func load() async {
        defer { loading = false }
        guard let token = session.token else { return }
        do {
            let list: DVBList<DVBDocument> = try await DVBAPI.shared.get("my/documents", token: token)
            items = list.data
        } catch {
            self.error = (error as? DVBError)?.errorDescription
        }
    }
}

struct DVBConsent: Decodable, Identifiable {
    let id: Int
    let title: String?
    let doctor: String?
    let signedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, doctor
        case signedAt = "signed_at"
    }
}

struct DVBConsentsView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var items: [DVBConsent] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                DVBStateView(icon: "signature", title: "Onam formunuz yok")
            } else {
                List(items) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title ?? "Onam").font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            if let d = c.doctor { Text(d) }
                            if let s = c.signedAt { Text(s.dvbLong) }
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Onam formlarım")
        .task {
            defer { loading = false }
            guard let token = session.token else { return }
            if let list: DVBList<DVBConsent> = try? await DVBAPI.shared.get("my/consents", token: token) {
                items = list.data
            }
        }
    }
}
