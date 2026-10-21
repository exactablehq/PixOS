import Foundation

public struct MotionPhotoBuilder: Sendable {
    public static func buildMotionPhoto(
        imageURL: URL,
        videoURL: URL,
        outputURL: URL
    ) throws {
        guard let imageData = try? Data(contentsOf: imageURL),
              let videoData = try? Data(contentsOf: videoURL) else {
            throw NSError(
                domain: "PixOS.MotionPhotoBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read image or video data"]
            )
        }

        let isJPEG = imageURL.pathExtension.lowercased() == "jpg" || imageURL.pathExtension.lowercased() == "jpeg"
        let isHEIC = imageURL.pathExtension.lowercased() == "heic"

        let videoLength = videoData.count
        let imageMime = isHEIC ? "image/heic" : "image/jpeg"

        // Generate standardized XMP string
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
              Camera:MotionPhotoPresentationTimestampUs="0"
              GCamera:MotionPhoto="1"
              GCamera:MicroVideo="1"
              GCamera:MicroVideoVersion="1"
              GCamera:MicroVideoOffset="\(videoLength)"
              GCamera:MicroVideoPresentationTimestampUs="0">
              <Container:Directory>
                <rdf:Seq>
                  <rdf:li rdf:parseType="Resource">
                    <Item:Mime>\(imageMime)</Item:Mime>
                    <Item:Semantic>Primary</Item:Semantic>
                    <Item:Length>\(imageData.count)</Item:Length>
                  </rdf:li>
                  <rdf:li rdf:parseType="Resource">
                    <Item:Mime>video/mp4</Item:Mime>
                    <Item:Semantic>MotionPhoto</Item:Semantic>
                    <Item:Length>\(videoLength)</Item:Length>
                  </rdf:li>
                </rdf:Seq>
              </Container:Directory>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """

        var finalData = Data()

        if isJPEG {
            // Embed APP1 XMP into JPEG
            finalData = embedXMPInJPEG(imageData: imageData, xmpString: xmpString)
            finalData.append(videoData)
        } else {
            // For HEIC or other container formats:
            // Google Photos reads Motion Photo data appended with trailing offset or standard container
            finalData = imageData
            finalData.append(videoData)
        }

        try finalData.write(to: outputURL, options: .atomic)

        // Preserve original filesystem creation and modification timestamps
        if let attrs = try? FileManager.default.attributesOfItem(atPath: imageURL.path) {
            var newAttrs: [FileAttributeKey: Any] = [:]
            if let cDate = attrs[.creationDate] { newAttrs[.creationDate] = cDate }
            if let mDate = attrs[.modificationDate] { newAttrs[.modificationDate] = mDate }
            try? FileManager.default.setAttributes(newAttrs, ofItemAtPath: outputURL.path)
        }
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
