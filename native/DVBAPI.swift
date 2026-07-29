import Foundation

/// Kullanıcıya gösterilebilir ağ hatası. Ham `URLError` metni hastaya gösterilmez.
enum DVBError: LocalizedError {
    case offline
    case unauthorized
    case forbidden
    case notFound
    case server(Int, String?)
    case decoding

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
            // Ağ katmanı hatası — hastaya teknik metin göstermeyiz.
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
