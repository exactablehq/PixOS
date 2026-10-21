import Foundation
import CoreImage
import AppKit

public struct QRCodeGenerator: Sendable {
    public static func generateQRCode(from string: String, size: CGSize = CGSize(width: 200, height: 200)) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputCIImage = filter.outputImage else { return nil }

        let scaleX = size.width / outputCIImage.extent.size.width
        let scaleY = size.height / outputCIImage.extent.size.height
        let transformed = outputCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let rep = NSCIImageRep(ciImage: transformed)
        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
