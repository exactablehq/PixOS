import Foundation
import ImageIO
import CoreGraphics
import AVFoundation

public struct MotionPhotoBuilder: Sendable {
    public static func buildMotionPhoto(
        imageURL: URL,
        videoURL: URL,
        outputURL: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: imageURL.path),
              FileManager.default.fileExists(atPath: videoURL.path) else {
            throw NSError(
                domain: "PixOS.MotionPhotoBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read image or video file at specified path"]
            )
        }

        let isJPEG = ["jpg", "jpeg"].contains(imageURL.pathExtension.lowercased())
        let jpegData: Data

        if isJPEG {
            guard let rawJpeg = try? Data(contentsOf: imageURL), rawJpeg.count > 4 else {
                throw NSError(
                    domain: "PixOS.MotionPhotoBuilder",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Corrupted JPEG image data"]
                )
            }
            jpegData = rawJpeg
        } else {
            // Transcode HEIC or other image format to 98% high-fidelity JPEG preserving all EXIF & metadata
            guard let converted = convertToJPEG(imageURL: imageURL) else {
                throw NSError(
                    domain: "PixOS.MotionPhotoBuilder",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to transcode \(imageURL.pathExtension) image to JPEG"]
                )
            }
            jpegData = converted
        }

        guard let videoData = try? Data(contentsOf: videoURL), !videoData.isEmpty else {
            throw NSError(
                domain: "PixOS.MotionPhotoBuilder",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read companion video data"]
            )
        }

        let videoLength = videoData.count

        // Extract presentation timestamp (in microseconds) from companion video
        let presentationTimestampUs = extractPresentationTimestampUs(videoURL: videoURL)

        // Generate standards-compliant Google Camera XMP string
        let xmpString = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
              xmlns:Container="http://ns.google.com/photos/1.0/container/"
              xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
              xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
              Camera:MotionPhoto="1"
              Camera:MotionPhotoVersion="1"
              Camera:MotionPhotoPresentationTimestampUs="\(presentationTimestampUs)"
              GCamera:MotionPhoto="1"
              GCamera:MicroVideo="1"
              GCamera:MicroVideoVersion="1"
              GCamera:MicroVideoOffset="\(videoLength)"
              GCamera:MicroVideoPresentationTimestampUs="\(presentationTimestampUs)">
              <Container:Directory>
                <rdf:Seq>
                  <rdf:li rdf:parseType="Resource">
                    <Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Padding="0"/>
                  </rdf:li>
                  <rdf:li rdf:parseType="Resource">
                    <Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="\(videoLength)" Item:Padding="0"/>
                  </rdf:li>
                </rdf:Seq>
              </Container:Directory>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """

        // Embed APP1 XMP into the JPEG data
        var finalData = embedXMPInJPEG(imageData: jpegData, xmpString: xmpString)

        // Append companion video stream bytes
        finalData.append(videoData)

        try finalData.write(to: outputURL, options: .atomic)

        // Preserve original filesystem creation and modification timestamps
        if let attrs = try? FileManager.default.attributesOfItem(atPath: imageURL.path) {
            var newAttrs: [FileAttributeKey: Any] = [:]
            if let cDate = attrs[.creationDate] { newAttrs[.creationDate] = cDate }
            if let mDate = attrs[.modificationDate] { newAttrs[.modificationDate] = mDate }
            try? FileManager.default.setAttributes(newAttrs, ofItemAtPath: outputURL.path)
        }
    }

    private static func convertToJPEG(imageURL: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }

        var options: [CFString: Any] = metadata
        options[kCGImageDestinationLossyCompressionQuality] = 0.98
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    private static func extractPresentationTimestampUs(videoURL: URL) -> Int64 {
        let asset = AVURLAsset(url: videoURL)
        let durationSec = CMTimeGetSeconds(asset.duration)

        // Apple Live Photos typically have ~3.0s total duration, with still image captured around 1.5s
        var timestampUs: Int64 = durationSec.isFinite && durationSec > 0
            ? Int64((durationSec / 2.0) * 1_000_000.0)
            : 1_500_000

        // Inspect QuickTime metadata tracks for still-image-time tag if embedded by iOS Camera
        for item in asset.metadata {
            if let key = item.commonKey?.rawValue, key.localizedCaseInsensitiveContains("still") {
                if let num = item.numberValue {
                    let extracted = Int64(num.doubleValue * 1_000_000.0)
                    if extracted > 0 {
                        timestampUs = extracted
                    }
                }
            }
        }

        return max(500_000, timestampUs)
    }

    private static func embedXMPInJPEG(imageData: Data, xmpString: String) -> Data {
        guard let xmpData = xmpString.data(using: .utf8) else {
            return imageData
        }

        let header = "http://ns.adobe.com/xap/1.0/\0".data(using: .utf8)!
        let payload = header + xmpData
        let length = UInt16(payload.count + 2)

        var app1 = Data([0xFF, 0xE1])
        app1.append(UInt8(length >> 8))
        app1.append(UInt8(length & 0xFF))
        app1.append(payload)

        // Find SOI marker (0xFF, 0xD8)
        guard imageData.count > 4, imageData[0] == 0xFF, imageData[1] == 0xD8 else {
            return imageData
        }

        var result = Data()
        result.append(contentsOf: [0xFF, 0xD8])
        result.append(app1)
        result.append(imageData.subdata(in: 2..<imageData.count))
        return result
    }
}
