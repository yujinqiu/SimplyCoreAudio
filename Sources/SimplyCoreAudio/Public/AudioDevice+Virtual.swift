//
//  AudioDevice+Virtual.swift
//  File
//
//  Created by knight on 7/30/21.
//

import CoreAudio
import Foundation

// MARK: - Aggregate Device Functions

public extension AudioDevice {
    /// - Returns: `true` if this device is an aggregate one, `false` otherwise.
    var isVirtual: Bool {
        guard let transportType = transportType else {
            return false
        }
        return transportType == .virtual
    }
}
