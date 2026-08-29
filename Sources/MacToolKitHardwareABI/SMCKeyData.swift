import Foundation

@frozen public struct SMCVersion {
    public var major: UInt8 = 0
    public var minor: UInt8 = 0
    public var build: UInt8 = 0
    public var reserved: UInt8 = 0
    public var release: UInt16 = 0

    public init() {}
}

@frozen public struct SMCPLimitData {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0

    public init() {}
}

@frozen public struct SMCKeyInfoData {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0

    public init() {}
}

/// Payload used by AppleSMC selector 2.
///
/// AppleSMC expects this exact 80-byte layout. `padding` is explicit because
/// Swift otherwise packs the three one-byte result fields before `data32`,
/// producing an incompatible 76-byte payload.
@frozen public struct SMCKeyData {
    public var key: UInt32 = 0
    public var vers = SMCVersion()
    public var pLimitData = SMCPLimitData()
    public var keyInfo = SMCKeyInfoData()
    public var padding: UInt16 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    public init() {}
}

public enum FanCommandSafety {
    public static func allows(
        index: Int,
        rpm: Int,
        fanCount: Int,
        minRPM: Int,
        maxRPM: Int
    ) -> Bool {
        guard (1...16).contains(fanCount),
              (0..<fanCount).contains(index),
              minRPM > 0,
              maxRPM >= minRPM else { return false }
        return (minRPM...maxRPM).contains(rpm)
    }
}
