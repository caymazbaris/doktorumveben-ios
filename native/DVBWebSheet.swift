import SwiftUI
import WebKit

/// Tur 235 — Native ekranlardan açılan web sayfası (randevu adımı, yasal metinler,
/// profil düzenleme).
///
/// Uygulamanın KÖKÜ artık web değil: web yalnız sunucu-render olması gereken
/// sayfalar için, sunum katmanında (sheet) kullanılır. Bu ayrım App Store 4.2'nin
/// "siteden farkı ne" sorusunun cevabıdır.
///
/// GÜVENLİK: yalnız kendi alan adımızda gezinilir; dış bağlantılar sistem
/// tarayıcısına çıkar (kimlik avı yüzeyi açmayalım).
struct DVBWebSheet: View {
    let url: URL
    let title: String

    @Environment(\.presentationMode) private var presentation

    var body: some View {
        NavigationView {
            DVBWebContainer(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Kapat") { presentation.wrappedValue.dismiss() }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}

struct DVBWebContainer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = DVBConfig.userAgentSuffix

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {

        /// DVB-000120 — kimlik sağlayıcı alan adları. Buraya bir gezinme gelirse
        /// kullanıcı Safari'ye ATILMAZ; sessizce iptal edilir.
        ///
        /// NEDEN: 1.0 (13) "the user is taken to the default web browser to sign in
        /// or register" diye reddedildi. Zincir şuydu — web sayfasındaki düğme kendi
        /// alan adımıza bakıyor (/auth/apple), sheet onu "bizim" sayıp içeride
        /// açıyor, sunucu 302 ile appleid.apple.com'a yönlendiriyor ve aşağıdaki
        /// "dış alan adı" kolu kullanıcıyı Safari'ye gönderiyordu.
        ///
        /// ASIL DÜZELTME SUNUCUDA: uygulama içinde bu düğmeler artık hiç basılmıyor
        /// (NativeApp::allowsWebSocialLogin). Burası emniyet supabı: yarın başka bir
        /// sayfaya sosyal giriş eklenirse aynı reddi bir daha yemeyelim. Uygulamada
        /// Apple'ın kendi native düğmesi zaten var, kullanıcı seçeneksiz kalmıyor.
        private static let kimlikSaglayicilari = [
            "appleid.apple.com",
            "accounts.google.com",
            "www.facebook.com",
        ]

        private static func kimlikSaglayicisiMi(_ host: String) -> Bool {
            kimlikSaglayicilari.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let host = target.host ?? ""
            let ours = host == "doktorumveben.com" || host.hasSuffix(".doktorumveben.com")

            // about:blank / data: gibi şemalar ve kendi alan adımız içeride kalır.
            if ours || target.scheme == "about" {
                decisionHandler(.allow)
                return
            }

            // Kimlik sağlayıcıya çıkış: iptal et, Safari'yi AÇMA (bkz. yukarıdaki gerekçe).
            if Self.kimlikSaglayicisiMi(host) {
                decisionHandler(.cancel)
                return
            }

            // tel: / mailto: / dış siteler → sistem
            decisionHandler(.cancel)
            UIApplication.shared.open(target)
        }
    }
}
