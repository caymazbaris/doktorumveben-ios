import SwiftUI

/// Tur 235 — Hesap sekmesi: giriş, üyelik bilgisi, belgeler ve App Store 5.1.1(v)
/// gereği UYGULAMA İÇİNDEN hesap silme.
@MainActor
struct DVBAccountView: View {

    @EnvironmentObject private var session: DVBSession

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var webSheet: DVBIdentifiableURL?

    var body: some View {
        NavigationView {
            Group {
                if session.isLoggedIn { signedIn } else { signedOut }
            }
            .navigationTitle("Hesabım")
            .sheet(item: $webSheet) { item in
                DVBWebSheet(url: item.url, title: "Doktorumveben")
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

            Section("Sağlık kayıtlarım") {
                NavigationLink(destination: DVBDocumentsView()) {
                    Label("Belgelerim", systemImage: "doc.text")
                }
                NavigationLink(destination: DVBConsentsView()) {
                    Label("Onam formlarım", systemImage: "signature")
                }
            }

            Section("Hesap") {
                Button {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("hesabim/profil"))
                } label: {
                    Label("Profil bilgilerim", systemImage: "person.text.rectangle")
                }
                Button {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("gizlilik"))
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

    private var signedOut: some View {
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

            Section {
                Button("Üye ol") {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("uye-ol"))
                }
                Button("Parolamı unuttum") {
                    webSheet = .init(url: DVBConfig.webBase.appendingPathComponent("sifremi-unuttum"))
                }
            } footer: {
                Text("Apple ile giriş bir sonraki sürümde uygulama içinde olacak; şimdilik üye ol ekranından kullanabilirsiniz.")
            }
        }
    }

    // MARK: - Eylemler

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            self.error = (error as? DVBError)?.errorDescription ?? "Giriş yapılamadı."
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
