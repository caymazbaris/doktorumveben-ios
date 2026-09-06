import UIKit
import SwiftUI
import Capacitor

/// DVB-000124 — Capacitor şablonundaki `SceneDelegate`'in YERİNE geçer
/// (`scripts/inject-native-swift.mjs` her derlemede kopyalar).
///
/// ⚠ BU DOSYA OLMADAN NATIVE KATMAN HİÇ EKRANA GELMEZ. Sebebi ölçüldü:
///
/// Capacitor 8.5 iOS şablonu SAHNE (UIScene) yaşam döngüsüne geçti. Info.plist'e
/// `UIApplicationSceneManifest` eklendi ve şablon kendi `SceneDelegate`'ini
/// getiriyor; o da kökü doğrudan `CAPBridgeViewController()` yapıyor — yani siteyi
/// açan WebView. Sahne manifesti varken UIKit `AppDelegate.window`'u YOK SAYAR.
/// Bizim AppDelegate'imiz pencereyi kuruyordu ama o pencere hiç gösterilmiyordu.
///
/// SONUÇ: uygulama, native ekranlar derlenmiş ve içinde olmasına rağmen açılışta
/// doktorumveben.com'u gösteriyordu. Yani App Store 4.2'nin ("paketlenmiş web
/// sitesi") çözüldüğü sanılan durum, 8.5 sürümüyle birlikte sessizce geri gelmişti.
///
/// NASIL YAKALANDI: ekran görüntüsü koşusunun kalite kapısı. Altı karenin altısında
/// da native ekran yerine site metni çıktı ("Uygulamayı Yükle", "Anasayfa"), ve bir
/// ay önceki koşu aynı kareyi native çekmişti ("Hekim ara | ... | Konak"). Kod
/// tarafında hiçbir şey değişmemişti; değişen, depoda `package-lock.json`
/// OLMADIĞI için CI'nın çektiği Capacitor sürümüydü.
///
/// `SceneDelegateProxy` çağrıları KORUNDU: universal link ve custom scheme
/// yönlendirmeleri hâlâ Capacitor köprüsünden geçiyor.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        // Şablonda burası CAPBridgeViewController() idi.
        window.rootViewController = UIHostingController(rootView: DVBRootView())
        window.makeKeyAndVisible()
        self.window = window

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
