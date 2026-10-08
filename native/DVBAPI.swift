import Foundation

/// Kullanıcıya gösterilebilir ağ hatası. Ham `URLError` metni hastaya gösterilmez.
enum DVBError: LocalizedError {
    case offline
    case unauthorized
    case forbidden
    case notFound
    case server(Int, String?)
    case decoding

    /// DVB-000264 — ekranda gösterilecek metin; İPTAL için nil (gösterilmez). Ekranlar `catch` içinde bunu kullanır:
    /// `if let m = DVBError.mesaj(error) { self.error = m }`.
    static func mesaj(_ error: Error) -> String? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        return (error as? DVBError)?.errorDescription ?? "Bilinmeyen hata."
    }

    var errorDescription: String? {
        switch self {
        case .offline:
            return "İnternet bağlantısı yok gibi görünüyor. Bağlantınızı kontrol edip tekrar deneyin."
        case .unauthorized:
            return "Oturumunuzun süresi dolmuş. Lütfen tekrar giriş yapın."
        case .forbidden:
            return "Bu kayda erişim yetkiniz yok."
        case .notFound:
            return "Kayıt bulunamadı."
        case .server(_, let message):
            return message ?? "Sunucuya ulaşıldı ama işlem tamamlanamadı. Biraz sonra tekrar deneyin."
        case .decoding:
            return "Sunucudan beklenmeyen bir yanıt geldi. Uygulamayı güncellemeniz gerekebilir."
        }
    }
}

/// Tur 235 — Tur 234'te yazılan `/api/v1` yüzeyinin tek istemcisi.
///
/// Bağımlılık yok: yalnız Foundation. Ekstra paket eklemek CocoaPods çözümlemesini
/// ve dolayısıyla bulut derlemesini kırılgan yapardı (Mac olmadığı için her deneme
/// ~15 dakika).
actor DVBAPI {

    static let shared = DVBAPI()

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = DVBConfig.requestTimeout
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["User-Agent": DVBConfig.userAgentSuffix]
        session = URLSession(configuration: cfg)

        decoder = JSONDecoder()
        // Sunucu her tarihi ISO8601 + saat dilimi ofsetiyle gönderiyor (Resources).
        decoder.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            if let d = DVBAPI.iso.date(from: raw) { return d }
            if let d = DVBAPI.isoPlain.date(from: raw) { return d }
            throw DVBError.decoding
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Çekirdek

    /// - Parameter token: verilirse Bearer başlığı eklenir (auth'lu uçlar).
    func get<T: Decodable>(_ path: String, query: [String: String] = [:], token: String? = nil) async throws -> T {
        var comps = URLComponents(url: DVBConfig.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw DVBError.decoding }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req, token: token)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any] = [:], token: String? = nil) async throws -> T {
        var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await send(req, token: token)
    }

    /// DVB-000266 — PUT (profil, yakın güncelleme).
    func put<T: Decodable>(_ path: String, body: [String: Any] = [:], token: String? = nil) async throws -> T {
        var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent(path))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await send(req, token: token)
    }

    /// DVB-000343 — kısmi güncelleme (hekim profili: yalnız gönderilen alan değişir). Boşaltmak için değer `NSNull()`.
    func patch<T: Decodable>(_ path: String, body: [String: Any] = [:], token: String? = nil) async throws -> T {
        var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent(path))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await send(req, token: token)
    }

    /// DVB-000343 — ham yanıt (fatura PDF'i). Hata eşlemesi `send` ile aynı; gövde çözülmez, olduğu gibi döner.
    func veri(_ path: String, token: String? = nil) async throws -> Data {
        var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent(path))
        req.httpMethod = "GET"
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if (error as? URLError)?.code == .timedOut {
                throw DVBError.server(0, "Sunucu zamanında yanıt vermedi. Biraz sonra tekrar deneyin.")
            }
            throw DVBError.offline
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200...299: return data
        case 401: throw DVBError.unauthorized
        case 403: throw DVBError.forbidden
        case 404: throw DVBError.notFound
        case let kod:
            let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw DVBError.server(kod, msg?["message"] as? String)
        }
    }

    /// DVB-000343 — tek dosya yükleme (multipart/form-data; hekim profil fotoğrafı).
    func yukle<T: Decodable>(_ path: String, alan: String, dosya: Data, dosyaAdi: String, mime: String, token: String? = nil) async throws -> T {
        let sinir = "dvb-\(UUID().uuidString)"
        var govde = Data()
        govde.append("--\(sinir)\r\n".data(using: .utf8)!)
        govde.append("Content-Disposition: form-data; name=\"\(alan)\"; filename=\"\(dosyaAdi)\"\r\n".data(using: .utf8)!)
        govde.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        govde.append(dosya)
        govde.append("\r\n--\(sinir)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(sinir)", forHTTPHeaderField: "Content-Type")
        req.httpBody = govde
        return try await send(req, token: token)
    }

    /// DVB-000109 — gövdeli DELETE (cihaz jetonunu bırakma: sunucu jetonu gövdeden okur).
    func delete<T: Decodable>(_ path: String, body: [String: Any] = [:], token: String? = nil) async throws -> T {
        var req = URLRequest(url: DVBConfig.apiBase.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await send(req, token: token)
    }

    private func send<T: Decodable>(_ request: URLRequest, token: String?) async throws -> T {
        var req = request
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // ⛔ DVB-000264 — kullanıcı (30 Eyl 2026): "bildirimler bölümünde internet bağlantısı yok gibi görünüyor diyor
            // olduğu halde". Uç ölçüldü: 5 ms, HTTP 200. Neden: ağ katmanındaki HER hata "internet yok" sayılıyordu —
            // İPTAL edilen istek de. SwiftUI bir ekrandan ayrılırken (sekme değişimi, yeniden çizim) `.task`/
            // `.refreshable` görevini iptal eder; URLSession `URLError.cancelled` fırlatır ve ekran yalan söylerdi.
            // İptal ayrı bir hata: ekranlar onu GÖSTERMEZ (DVBError.mesaj → nil).
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if (error as? URLError)?.code == .timedOut {
                throw DVBError.server(0, "Sunucu zamanında yanıt vermedi. Biraz sonra tekrar deneyin.")
            }
            // Gerçek bağlantı hatası — hastaya teknik metin göstermeyiz.
            throw DVBError.offline
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw DVBError.decoding
            }
        case 401:
            throw DVBError.unauthorized
        case 403:
            throw DVBError.forbidden
        case 404:
            throw DVBError.notFound
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw DVBError.server(code, msg?["message"] as? String)
        }
    }
}
