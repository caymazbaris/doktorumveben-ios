import UIKit
import SwiftUI
import Capacitor
import UserNotifications

/// Tur 235 — Uygulamanın girişi. Capacitor şablonundaki AppDelegate'in YERİNE geçer
/// (`scripts/prepare-native-ios.mjs` her derlemede kopyalar).
///
/// FARK: kök görünüm artık `Main.storyboard`daki `CAPBridgeViewController` (yani
/// siteyi açan WebView) DEĞİL, native `DVBRootView`. Web yalnız gerektiği yerde
/// sheet olarak açılır. Info.plist'ten `UIMainStoryboardFile` bu yüzden kaldırılır —
/// aksi hâlde UIKit ikinci bir pencere kökü kurar ve iki kök çakışır.
///
/// Capacitor `import`u ve aşağıdaki proxy çağrıları KORUNDU: universal link /
/// custom scheme yönlendirmeleri hâlâ bu köprüden geçiyor.
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // DVB-000124 — SAHNE VARSA PENCEREYİ BURADA KURMA.
        // Capacitor 8.5'ten beri Info.plist'te UIApplicationSceneManifest var; o
        // durumda UIKit AppDelegate.window'u yok sayar ve kökü SceneDelegate kurar
        // (bkz. SceneDelegate.swift). Burada da bir pencere kurmak iki kök yaratır:
        // biri hiç gösterilmez, ama makeKeyAndVisible sahne penceresiyle yarışır.
        // Manifest yoksa (eski şablon) eski yol aynen çalışmaya devam eder.
        let sahneYasamDongusu = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
        if !sahneYasamDongusu {
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = UIHostingController(rootView: DVBRootView())
            window.makeKeyAndVisible()
            self.window = window
        }

        // DVB-000109 — bildirim delegesi açılışta bağlanır (ön planda gösterim + dokunuş).
        // Kayıt (izin + registerForRemoteNotifications) burada DEĞİL, girişten sonra (DVBSession).
        UNUserNotificationCenter.current().delegate = DVBPushDelegesi.shared
        return true
    }

    // DVB-000109 — APNs cihaz jetonu (doğrudan APNs; Firebase yok).
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        DVBPush.jetonGeldi(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simülatörde ve entitlement'sız derlemede beklenen durum; ürün akışı etkilenmez.
        NSLog("[DVB push] APNs kaydı başarısız: %@", error.localizedDescription)
    }

    func applicationWillResignActive(_ application: UIApplication) {}

    func applicationDidEnterBackground(_ application: UIApplication) {}

    func applicationWillEnterForeground(_ application: UIApplication) {}

    func applicationDidBecomeActive(_ application: UIApplication) {}

    func applicationWillTerminate(_ application: UIApplication) {}

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return ApplicationDelegateProxy.shared.application(
            application, continue: userActivity, restorationHandler: restorationHandler
        )
    }
}
