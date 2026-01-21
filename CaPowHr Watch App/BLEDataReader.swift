//
//  BLEDataReader.swift
//  CaPowHr Watch App
//
//  A cursor-based reader for parsing BLE characteristic payloads.
//  All multi-byte reads are little-endian per Bluetooth SIG conventions.
//

import Foundation

/// Cursor-based reader for parsing BLE characteristic payloads.
/// Multi-byte reads are little-endian per Bluetooth SIG conventions.
struct BLEDataReader {
    private let data: Data
    private(set) var cursor: Int = 0

    init(_ data: Data) {
        self.data = data
    }

    /// Bytes remaining from current cursor position to end of data.
    var bytesRemaining: Int { data.count - cursor }

    mutating func readUInt8() -> UInt8? {
        guard data.count >= cursor + 1 else { return nil }
        defer { cursor += 1 }
        return data[cursor]
    }

    mutating func readUInt16LE() -> UInt16? {
        guard data.count >= cursor + 2 else { return nil }
        defer { cursor += 2 }
        return data.subdata(in: cursor..<(cursor + 2)).withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self))
        }
    }

    mutating func readInt16LE() -> Int16? {
        guard data.count >= cursor + 2 else { return nil }
        defer { cursor += 2 }
        return data.subdata(in: cursor..<(cursor + 2)).withUnsafeBytes {
            Int16(littleEndian: $0.loadUnaligned(as: Int16.self))
        }
    }

    mutating func readUInt32LE() -> UInt32? {
        guard data.count >= cursor + 4 else { return nil }
        defer { cursor += 4 }
        return data.subdata(in: cursor..<(cursor + 4)).withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
    }

    /// Reads a 24-bit unsigned integer (3 bytes, little-endian) as UInt32.
    mutating func readUInt24LE() -> UInt32? {
        guard data.count >= cursor + 3 else { return nil }
        let b0 = UInt32(data[cursor])
        let b1 = UInt32(data[cursor + 1])
        let b2 = UInt32(data[cursor + 2])
        cursor += 3
        return b0 | (b1 << 8) | (b2 << 16)
    }
}
