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

            // tel: / mailto: / dış siteler → sistem
            decisionHandler(.cancel)
            UIApplication.shared.open(target)
        }
    }
}
