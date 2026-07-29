// Tur 241 — Mağaza ekran görüntülerini OCR'layıp metni build log'una yazar.
//
// Neden: ekipte iPhone/Mac yok; görüntüleri üreten CI dışında kimse pikselleri
// göremiyor (Codemagic artifact indirmesi oturum kimliği istiyor). Bu betik
// Apple'ın kendi Vision motoruyla her kareden metni çıkarıp log'a basar, böylece
// "ekranda gerçekten hekim adı ve saat var mı, yoksa hata durumu mu çizilmiş"
// sorusu indirme yapmadan KESİN olarak yanıtlanır.
//
// Kullanım: swift scripts/ocr-shots.swift <png> [<png> ...]
// Not: `swift` yorumlayıcı kipinde çalışır; Xcode kurulu Mac'te ek bağımlılık yok.

import Foundation
import Vision
import AppKit

let yollar = Array(CommandLine.arguments.dropFirst())

if yollar.isEmpty {
    print("[ocr] Dosya verilmedi.")
    exit(0)
}

for yol in yollar {
    print("")
    print("=== OCR: \((yol as NSString).lastPathComponent) ===")

    guard let img = NSImage(contentsOfFile: yol),
          let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let cg = bmp.cgImage
    else {
        print("[ocr] HATA: görüntü açılamadı → \(yol)")
        continue
    }

    print("[ocr] boyut: \(cg.width)x\(cg.height)")

    let istek = VNRecognizeTextRequest()
    istek.recognitionLevel = .accurate
    // Türkçe önce: hekim adları ve "Randevu al" gibi arayüz metinleri Türkçe.
    istek.recognitionLanguages = ["tr-TR", "en-US"]
    istek.usesLanguageCorrection = true

    let isleyici = VNImageRequestHandler(cgImage: cg, options: [:])
    do {
        try isleyici.perform([istek])
    } catch {
        print("[ocr] HATA: Vision çalışmadı → \(error.localizedDescription)")
        continue
    }

    let satirlar = (istek.results ?? []).compactMap { $0.topCandidates(1).first?.string }

    if satirlar.isEmpty {
        print("[ocr] UYARI: hiç metin bulunamadı (boş/siyah ekran olabilir)")
    } else {
        print("[ocr] \(satirlar.count) metin parçası:")
        print(satirlar.joined(separator: " | "))
    }
}

print("")
print("[ocr] bitti.")
