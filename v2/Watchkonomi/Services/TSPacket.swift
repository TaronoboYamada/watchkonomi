import Foundation

enum TSParser {
    static let packetSize = 188

    static func extractPackets(pending: inout Data) -> [Data] {
        var packets: [Data] = []
        while pending.count >= packetSize {
            if pending[0] != 0x47 {
                pending.removeSubrange(0..<1)
                continue
            }
            let packet = pending.prefix(packetSize)
            pending.removeSubrange(0..<packetSize)
            packets.append(Data(packet))
        }
        return packets
    }

    static func extractPTS(from packet: Data) -> Double? {
        guard packet.count >= packetSize else { return nil }
        let afc = (packet[3] >> 4) & 0x03
        var offset = 4
        if afc == 2 || afc == 3 {
            guard packet.count > 4 else { return nil }
            let afLength = Int(packet[4])
            offset = 5 + afLength
        }
        guard packet.count >= offset + 13 else { return nil }
        let p = Data(packet[offset...])
        guard p[0] == 0x00, p[1] == 0x00, p[2] == 0x01 else { return nil }
        let ptsDtsFlags = (p[6] >> 4) & 0x03
        let headerLength = Int(p[7])
        guard ptsDtsFlags == 0x2 || ptsDtsFlags == 0x3, headerLength >= 5 else { return nil }
        let b0 = p[8]
        let b1 = p[9]
        let b2 = p[10]
        let b3 = p[11]
        let b4 = p[12]
        let raw = (UInt64((b0 & 0x0E) >> 1) << 30)
            | (UInt64(b1) << 22)
            | (UInt64(b2 >> 1) << 15)
            | (UInt64(b3) << 7)
            | (UInt64(b4) >> 1)
        return Double(raw) / 90000.0
    }
}
