import Foundation

enum TSTestPacketFactory {
    static func packet(pid: UInt16 = 0x100, continuity: UInt8 = 0, pusi: Bool = false, pts: Double? = nil) -> Data {
        var data = Data(capacity: 188)
        data.append(0x47)
        data.append((pusi ? 0x40 : 0x00) | UInt8((pid >> 8) & 0x1F))
        data.append(UInt8(pid & 0xFF))
        data.append(0x10 | (continuity & 0x0F))
        var payload = Data()
        if pusi == true, let pts {
            payload.append(contentsOf: [0x00, 0x00, 0x01, 0xE0, 0x00, 0x00, 0xA0, 0x05])
            payload.append(contentsOf: ptsBytes(pts))
        }
        while payload.count < 184 {
            payload.append(0xFF)
        }
        data.append(payload)
        return data
    }

    static func ptsBytes(_ pts: Double) -> [UInt8] {
        let p = UInt64((pts * 90000).rounded())
        return [
            0x21 | (UInt8((p >> 30) & 0x07) << 1),
            UInt8((p >> 22) & 0xFF),
            0x01 | (UInt8((p >> 15) & 0x7F) << 1),
            UInt8((p >> 7) & 0xFF),
            0x01 | (UInt8(p & 0x7F) << 1),
        ]
    }
}
