import Foundation
import zlib

/// Minimal ZIP (compression method **store** only) for bundling tax-prep exports without third-party dependencies.
enum TaxPrepZipArchive {
    /// Each entry uses a flat filename (no path separators) for broad reader compatibility.
    static func makeZip(entries: [(fileName: String, data: Data)], to destinationURL: URL) throws {
        guard !entries.isEmpty else {
            throw NSError(domain: "TaxPrepZip", code: 1, userInfo: [NSLocalizedDescriptionKey: "No files to zip."])
        }

        var localParts = [Data]()
        var centralParts = [Data]()
        var offset: UInt32 = 0

        for entry in entries {
            let name = entry.fileName.replacingOccurrences(of: "/", with: "-")
            guard let nameData = name.data(using: .utf8), !nameData.isEmpty, nameData.count <= UInt16.max else {
                throw NSError(domain: "TaxPrepZip", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid zip entry name."])
            }
            let payload = entry.data
            let uSize = UInt32(payload.count)
            let crcFull = payload.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return uLong(0) }
                return crc32(0, base, uInt(truncatingIfNeeded: payload.count))
            }
            let crc = UInt32(truncatingIfNeeded: crcFull)

            var local = Data()
            local.appendUInt32(0x0403_4b50) // PK\003\004
            local.appendUInt16(20) // version needed
            local.appendUInt16(0) // flags
            local.appendUInt16(0) // compression = store
            local.appendUInt16(0) // mod time
            local.appendUInt16(0) // mod date
            local.appendUInt32(crc)
            local.appendUInt32(uSize) // compressed
            local.appendUInt32(uSize) // uncompressed
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0) // extra len
            local.append(nameData)
            local.append(payload)

            let localOffset = offset
            offset += UInt32(local.count)

            var central = Data()
            central.appendUInt32(0x0201_4b50) // PK\001\002
            central.appendUInt16(20) // version made by
            central.appendUInt16(20) // version needed
            central.appendUInt16(0) // flags
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(uSize)
            central.appendUInt32(uSize)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0) // extra
            central.appendUInt16(0) // comment
            central.appendUInt16(0) // disk start
            central.appendUInt16(0) // internal attrs
            central.appendUInt32(0) // external attrs
            central.appendUInt32(localOffset)
            central.append(nameData)

            localParts.append(local)
            centralParts.append(central)
        }

        var out = Data()
        for p in localParts { out.append(p) }

        let centralOffset = UInt32(out.count)
        for p in centralParts { out.append(p) }

        let centralSize = centralParts.reduce(0) { $0 + $1.count }
        let entryCount = UInt16(entries.count)

        out.appendUInt32(0x0605_4b50) // EOCD
        out.appendUInt16(0)
        out.appendUInt16(0)
        out.appendUInt16(entryCount)
        out.appendUInt16(entryCount)
        out.appendUInt32(UInt32(centralSize))
        out.appendUInt32(centralOffset)
        out.appendUInt16(0) // comment len

        try out.write(to: destinationURL, options: .atomic)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
