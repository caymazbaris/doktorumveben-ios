import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000272 — HEKİM MODU, 4. AŞAMA: MESAJLAR VE BİLDİRİMLER.
//
// Kullanıcı (30 Eyl 2026): "tamam mesajlar ve bildirimler aşamasına geç".
//
// MESAJLAR: web "Mesajlar" ile aynı görünürlük sunucuda (HekimSohbetleri). WhatsApp yazışmalarını şu an merkez ekip
// yürütüyor (DVB-000222) — uygulama onları göstermez, yanıtlatmaz; sunucu da reddeder.
//
// BİLDİRİMLER: hekim bildirimleri `/panel/...` adreslerine gider; uygulamanın web görünümünde panel oturumu yok,
// dokununca giriş sayfası çıkıyordu. Sunucu bilinen adresleri `target` olarak verir (sohbet, ajanda, sorular, hasta
// kartı, tahsilat) → yerli ekran açılır; bilinmeyen adres eskisi gibi web sayfasıdır. Eşleme kuralı SUNUCUDA tek yerde
// (HekimMesajApiController::hedef) — istemcide ikinci kopya yok; push dokunuşu da hedefi bildirim listesinden bulur.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Modeller

struct DVBHekimSohbetOzet: Decodable, Identifiable {
    let id: Int
    let name: String?
    let lastMessage: String?
    let lastFrom: String?
    let lastMessageAt: Date?
    let unread: Int

    enum CodingKeys: String, CodingKey {
        case id, name, unread
        case lastMessage = "last_message"
        case lastFrom = "last_from"
        case lastMessageAt = "last_message_at"
    }
}

struct DVBHekimSohbetListesi: Decodable {
    let data: [DVBHekimSohbetOzet]
    let whatsappNote: String?

    enum CodingKeys: String, CodingKey {
        case data
        case whatsappNote = "whatsapp_note"
    }
}

struct DVBHekimMesaj: Decodable, Identifiable {
    let id: Int
    let from: String
    let body: String
    let channel: String?
    let createdAt: Date?

    var bendenMi: Bool { from == "doctor" }

    enum CodingKeys: String, CodingKey {
        case id, from, body, channel
        case createdAt = "created_at"
    }
}

private struct DVBHekimSohbetCevabi: Decodable {
    let conversation: Baslik
    let messages: [DVBHekimMesaj]
    struct Baslik: Decodable { let id: Int; let name: String? }
}

private struct DVBHekimYanitCevabi: Decodable { let message: DVBHekimMesaj }

/// Bildirimin uygulamadaki yerli hedefi (sunucu üretir).
struct DVBHekimHedef: Decodable, Hashable {
    let screen: String
    let id: Int?
}

/// `sheet(item:)` için kimlik: aynı hedef iki kez açılabilsin.
struct DVBHedefSunumu: Identifiable {
    let id = UUID()
    let hedef: DVBHekimHedef
}

// MARK: - Sohbet

struct DVBHekimSohbetView: View {
    let sohbetId: Int
    let ad: String

    @EnvironmentObject private var session: DVBSession

    @State private var mesajlar: [DVBHekimMesaj] = []
    @State private var baslik: String?
    @State private var metin = ""
    @State private var yuklendi = false
    @State private var gonderiliyor = false
    @State private var hata: String?
    @State private var gonderimHatasi: String?

    var body: some View {
        VStack(spacing: 0) {
            if let hata, !yuklendi {
                DVBStateView(icon: "bubble.left.and.exclamationmark.bubble.right", title: "Sohbet açılamadı", message: hata) {
                    Task { await yukle() }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(mesajlar) { m in
                                balon(m).id(m.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: mesajlar.count) { _ in
                        if let son = mesajlar.last { withAnimation { proxy.scrollTo(son.id, anchor: .bottom) } }
                    }
                    .onAppear {
                        if let son = mesajlar.last { proxy.scrollTo(son.id, anchor: .bottom) }
                    }
                }
                Divider()
                yazmaAlani
            }
        }
        .navigationTitle(baslik ?? ad)
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
    }

    private func balon(_ m: DVBHekimMesaj) -> some View {
        HStack {
            if m.bendenMi { Spacer(minLength: 40) }
            VStack(alignment: m.bendenMi ? .trailing : .leading, spacing: 3) {
                Text(m.body)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(m.bendenMi ? DVBTheme.brand : Color(.secondarySystemBackground))
                    .foregroundColor(m.bendenMi ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 4) {
                    if m.channel == "whatsapp" { Text("WhatsApp") }
                    if let t = m.createdAt { Text(DVBSaat.gun(t, "d MMM HH:mm")) }
                }
                .font(.caption2).foregroundColor(.secondary)
            }
            if !m.bendenMi { Spacer(minLength: 40) }
        }
    }

    private var yazmaAlani: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let gonderimHatasi {
                Text(gonderimHatasi).font(.caption).foregroundColor(.red)
            }
            HStack(spacing: 8) {
                TextField("Mesajınız", text: $metin)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await gonder() } }
                Button { Task { await gonder() } } label: {
                    Image(systemName: "paperplane.fill").font(.title3)
                }
                .disabled(gonderiliyor || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Gönder")
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBHekimSohbetCevabi = try await DVBAPI.shared.get("my/doctor/conversations/\(sohbetId)", token: token)
            mesajlar = c.messages
            baslik = c.conversation.name
            yuklendi = true
            hata = nil
            await session.hekimiYukle()   // sunucu okundu saydı → rozetler düşsün
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func gonder() async {
        let govde = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !govde.isEmpty, !gonderiliyor, let token = session.token else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            let c: DVBHekimYanitCevabi = try await DVBAPI.shared.post(
                "my/doctor/conversations/\(sohbetId)/reply", body: ["body": govde], token: token
            )
            mesajlar.append(c.message)
            metin = ""
            gonderimHatasi = nil
        } catch {
            if let m = DVBError.mesaj(error) { gonderimHatasi = m }
        }
    }
}

// MARK: - Bildirim hedefini yerli ekranda aç

struct DVBHekimHedefSayfasi: View {
    let hedef: DVBHekimHedef

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch hedef.screen {
        case "conversation":
            kapatilabilir { DVBHekimSohbetView(sohbetId: hedef.id ?? 0, ad: "Mesaj") }
        case "patient":
            kapatilabilir { DVBHekimHastaKartView(hastaId: hedef.id ?? 0, ad: "Hasta") }
        case "messages":
            DVBHekimTaleplerView(baslangic: .mesajlar)
        case "questions":
            DVBHekimTaleplerView(baslangic: .sorular)
        case "payments":
            DVBHekimTahsilatView()
        default:
            DVBHekimAjandaView()
        }
    }

    private func kapatilabilir<Icerik: View>(@ViewBuilder _ icerik: () -> Icerik) -> some View {
        NavigationView {
            icerik()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                }
        }
        .navigationViewStyle(.stack)
    }
}
