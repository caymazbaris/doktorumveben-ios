import UIKit
import SwiftUI
import Capacitor

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
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: DVBRootView())
        window.makeKeyAndVisible()
        self.window = window
        return true
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
