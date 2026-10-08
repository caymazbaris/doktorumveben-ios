import SwiftUI
import PhotosUI
import QuickLook

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000343 — dosya araçları: fotoğraf seçici (profil fotoğrafı) ve PDF önizleme (fatura).
//
// · Fotoğraf: PHPicker kullanılır — fotoğraf arşivine ERİŞİM İZNİ İSTEMEZ (seçici ayrı süreçte çalışır, uygulama yalnız
//   seçilen görseli alır); bu yüzden Info.plist'e yeni izin metni gerekmez. Görsel sunucuya gitmeden önce küçültülür.
// · PDF: QuickLook önizlemesi; paylaş düğmesiyle kaydet/yazdır/gönder iOS'un kendisinden.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBFotoSecici: UIViewControllerRepresentable {
    /// Üst ekran sayfayı kapatır (ör. `fotoAcik = false`); seçim olsa da olmasa da çağrılır.
    var kapat: () -> Void
    var secildi: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var ayar = PHPickerConfiguration()
        ayar.filter = .images
        ayar.selectionLimit = 1
        let p = PHPickerViewController(configuration: ayar)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    final class Koordinator: NSObject, PHPickerViewControllerDelegate {
        let ust: DVBFotoSecici
        init(_ ust: DVBFotoSecici) { self.ust = ust }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            ust.kapat()
            guard let saglayici = results.first?.itemProvider, saglayici.canLoadObject(ofClass: UIImage.self) else { return }
            let geri = ust.secildi
            saglayici.loadObject(ofClass: UIImage.self) { nesne, _ in
                guard let resim = nesne as? UIImage else { return }
                DispatchQueue.main.async { geri(resim) }
            }
        }
    }
}

enum DVBGorsel {
    /// Uzun kenarı en çok `enFazla` piksel, JPEG %82 — sunucu sınırı 4 MB; telefon fotoğrafı 12 MP gelir.
    static func jpeg(_ resim: UIImage, enFazla: CGFloat = 1600) -> Data? {
        let oran = min(1, enFazla / max(resim.size.width, resim.size.height))
        let hedef = CGSize(width: resim.size.width * oran, height: resim.size.height * oran)
        let ciz = UIGraphicsImageRenderer(size: hedef)
        let kucuk = ciz.image { _ in resim.draw(in: CGRect(origin: .zero, size: hedef)) }
        return kucuk.jpegData(compressionQuality: 0.82)
    }
}

/// PDF (ya da başka belge) önizleme — sayfa olarak sunulur; sol üstte Kapat, sağ üstte iOS paylaş menüsü.
struct DVBBelgeOnizleme: UIViewControllerRepresentable {
    let dosya: URL
    /// Üst ekran sayfayı kapatır (ör. `onizlenen = nil`).
    var kapat: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        let kapat = context.coordinator.kapat
        ql.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in kapat() })
        return UINavigationController(rootViewController: ql)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(dosya: dosya, kapat: kapat) }

    final class Koordinator: NSObject, QLPreviewControllerDataSource {
        let dosya: URL
        let kapat: () -> Void
        init(dosya: URL, kapat: @escaping () -> Void) {
            self.dosya = dosya
            self.kapat = kapat
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            dosya as NSURL
        }
    }
}

/// Sayfa olarak açılacak yerel dosya (sheet(item:) için kimlikli sarmal).
struct DVBYerelDosya: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
