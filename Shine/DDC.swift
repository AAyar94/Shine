//
//  DDC.swift
//  Shine
//
//  DDC/CI access to external displays on Apple Silicon via the private
//  IOAVService I2C API. Symbols are resolved at runtime with dlsym so the
//  app still launches (with DDC reported unavailable) if the API moves.
//

import Foundation
import IOKit

// MARK: - VCP feature codes (VESA MCCS)

enum VCP {
    static let brightness: UInt8 = 0x10
    static let contrast: UInt8 = 0x12
    static let volume: UInt8 = 0x62
    static let mute: UInt8 = 0x8D
}

// MARK: - Private IOAVService function types

private typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> UnsafeMutableRawPointer?
private typealias I2CWriteFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn
private typealias I2CReadFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn
private typealias CopyEDIDFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Unmanaged<CFData>?>?) -> IOReturn

private func loadSymbol<T>(_ name: String, as type: T.Type) -> T? {
    guard let ptr = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name) else { return nil }
    return unsafeBitCast(ptr, to: T.self)
}

// MARK: - EDID identity used to match an I2C port to a CGDisplay

struct EDIDIdentity {
    let vendorID: UInt16   // big-endian bytes 8-9, matches CGDisplayVendorNumber
    let productID: UInt16  // little-endian bytes 10-11, matches CGDisplayModelNumber
    let serial: UInt32     // little-endian bytes 12-15, matches CGDisplaySerialNumber

    init?(edid data: Data) {
        guard data.count >= 16 else { return nil }
        vendorID = UInt16(data[8]) << 8 | UInt16(data[9])
        productID = UInt16(data[11]) << 8 | UInt16(data[10])
        serial = UInt32(data[15]) << 24 | UInt32(data[14]) << 16 | UInt32(data[13]) << 8 | UInt32(data[12])
    }
}

// MARK: - DDCPort

/// One external display's DDC/CI channel (a DCPAVServiceProxy with Location == External).
final class DDCPort {
    private static let createWithService = loadSymbol("IOAVServiceCreateWithService", as: CreateWithServiceFn.self)
    private static let writeI2C = loadSymbol("IOAVServiceWriteI2C", as: I2CWriteFn.self)
    private static let readI2C = loadSymbol("IOAVServiceReadI2C", as: I2CReadFn.self)
    private static let copyEDID = loadSymbol("IOAVServiceCopyEDID", as: CopyEDIDFn.self)

    /// Whether the private IOAVService API is available on this machine.
    static var isSupported: Bool {
        createWithService != nil && writeI2C != nil && readI2C != nil
    }

    private static let i2cAddress: UInt32 = 0x37
    private static let ddcDataAddress: UInt32 = 0x51

    private let avService: UnsafeMutableRawPointer
    let identity: EDIDIdentity?

    private init(avService: UnsafeMutableRawPointer) {
        self.avService = avService
        var identity: EDIDIdentity? = nil
        if let copyEDID = Self.copyEDID {
            var edid: Unmanaged<CFData>? = nil
            if copyEDID(avService, &edid) == KERN_SUCCESS, let data = edid?.takeRetainedValue() as Data? {
                identity = EDIDIdentity(edid: data)
            }
        }
        self.identity = identity
    }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(avService).release()
    }

    /// Enumerates the DDC ports of all currently connected external displays.
    static func externalPorts() -> [DDCPort] {
        guard let createWithService else { return [] }
        var ports: [DDCPort] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("DCPAVServiceProxy"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            let location = IORegistryEntryCreateCFProperty(service, "Location" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External" else { continue }
            guard let av = createWithService(kCFAllocatorDefault, service) else { continue }
            ports.append(DDCPort(avService: av))
        }
        return ports
    }

    // MARK: DDC/CI protocol

    /// Sets a VCP feature value (e.g. brightness) on the monitor.
    @discardableResult
    func write(_ code: UInt8, value: UInt16) -> Bool {
        guard let writeI2C = Self.writeI2C else { return false }
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ UInt8(Self.ddcDataAddress) ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]

        for _ in 0..<2 {
            let result = packet.withUnsafeMutableBufferPointer {
                writeI2C(avService, Self.i2cAddress, Self.ddcDataAddress,
                         $0.baseAddress, UInt32($0.count))
            }
            if result == KERN_SUCCESS { return true }
            usleep(10_000)
        }
        return false
    }

    /// Reads a VCP feature's current and maximum value from the monitor.
    func read(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C = Self.writeI2C, let readI2C = Self.readI2C else { return nil }

        for attempt in 0..<4 {
            if attempt > 0 { usleep(20_000) }

            var request: [UInt8] = [0x82, 0x01, code, 0]
            request[3] = 0x6E ^ UInt8(Self.ddcDataAddress) ^ request[0] ^ request[1] ^ request[2]
            let wrote = request.withUnsafeMutableBufferPointer {
                writeI2C(avService, Self.i2cAddress, Self.ddcDataAddress,
                         $0.baseAddress, UInt32($0.count))
            }
            guard wrote == KERN_SUCCESS else { continue }
            usleep(20_000)

            var reply = [UInt8](repeating: 0, count: 11)
            let readResult = reply.withUnsafeMutableBufferPointer {
                readI2C(avService, Self.i2cAddress, Self.ddcDataAddress,
                        $0.baseAddress, UInt32($0.count))
            }
            guard readResult == KERN_SUCCESS else { continue }

            // Reply: [addr, len, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, checksum]
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { continue }
            var checksum: UInt8 = 0x50
            for i in 0..<10 { checksum ^= reply[i] }
            guard checksum == reply[10] else { continue }

            let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            return (current, maxValue == 0 ? 100 : maxValue)
        }
        return nil
    }
}
