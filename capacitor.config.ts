import type { CapacitorConfig } from '@capacitor/cli';

/**
 * Doktorumveben — iOS/Android native kabuk (Capacitor).
 * Yaklaşım: "hosted" — native WebView canlı doktorumveben.com'u açar (sunucu-render Blade
 * uygulaması olduğu için frontend bundle'lanmaz). Native katman push/paylaşım/durum çubuğu
 * ekler → Apple'ın "asgari işlevsellik" kuralını karşılamak için native APNs push şart.
 */
const config: CapacitorConfig = {
  appId: 'com.doktorumveben.app',
  appName: 'Doktorumveben',
  webDir: 'www',
  server: {
    url: 'https://doktorumveben.com/?source=ios',
    cleartext: false,
    // İnternet yoksa/istek başarısızsa beyaz ekran yerine markalı yerel sayfa (www/error.html).
    errorPath: 'error.html',
    // Uygulama içi gezinme yalnız kendi alan adımızda kalsın; dış linkler Safari'de açılır.
    allowNavigation: ['doktorumveben.com', '*.doktorumveben.com'],
  },
  ios: {
    contentInset: 'always',
    backgroundColor: '#ffffff',
    limitsNavigationsToAppBoundDomains: false,
    // Sunucu, native uygulamadan gelen trafiği bu imzayla ayırt eder (analitik/UX kararları).
    appendUserAgent: 'DoktorumvebenApp/1.0 (ios)',
  },
  android: {
    backgroundColor: '#ffffff',
  },
  plugins: {
    PushNotifications: { presentationOptions: ['badge', 'sound', 'alert'] },
    SplashScreen: { launchShowDuration: 600, backgroundColor: '#0891B2', showSpinner: false },
  },
};

export default config;
