//
//  AudioDevice+Aggregate.swift
//
//  Created by Ryan Francesconi on 2/24/21.
//

import CoreAudio
import Foundation

// MARK: - Aggregate Device Functions

public extension AudioDevice {
    @available(*, deprecated, renamed: "isAggregate")
    /// - Returns: `true` if this device is an aggregate one, `false` otherwise.
    /// This implement has bug when we create aggregate device but not sublist.
    var isAggregateDevice: Bool {
        guard let aggregateDevices = ownedAggregateDevices else { return false }
        return !aggregateDevices.isEmpty
    }
    
    var isAggregate: Bool {
        guard let transportType = transportType else {
            return false
        }
        return transportType == .aggregate
    }

    /// All the subdevices of this aggregate device
    ///
    /// - Returns: An array of `AudioDevice` objects.
    var ownedAggregateDevices: [AudioDevice]? {
        guard let ownedObjectIDs = ownedObjectIDs else { return nil }
        return ownedObjectIDs.compactMap { AudioDevice.lookup(by: $0) }
    }

    /// All the subdevices of this aggregate device that support input
    ///
    /// - Returns: An array of `AudioDevice` objects.
    var ownedAggregateInputDevices: [AudioDevice]? {
        ownedAggregateDevices?.filter {
            guard let channels = $0.layoutChannels(scope: .input) else { return false }
            return channels > 0
        }
    }

    /// All the subdevices of this aggregate device that support output
    ///
    /// - Returns: An array of `AudioDevice` objects.
    var ownedAggregateOutputDevices: [AudioDevice]? {
        ownedAggregateDevices?.filter {
            guard let channels = $0.layoutChannels(scope: .output) else { return false }
            return channels > 0
        }
    }
}
