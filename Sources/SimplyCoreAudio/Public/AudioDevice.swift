//
//  AudioDevice.swift
//
//  Created by Ruben Nine on 7/7/15.
//

import CoreAudio
import Foundation
import os.log

/// This class represents an audio device managed by [Core Audio](https://developer.apple.com/documentation/coreaudio).
///
/// Devices may be physical or virtual. For a comprehensive list of supported types, please refer to `TransportType`.
public final class AudioDevice: AudioObject {
    // MARK: - Static Private Properties

    private static let deviceClassIDs: Set<AudioClassID> = [
        kAudioDeviceClassID,
        kAudioSubDeviceClassID,
        kAudioAggregateDeviceClassID,
        kAudioEndPointClassID,
        kAudioEndPointDeviceClassID,
    ]

    // MARK: - Internal Properties

    let hardware = AudioHardware()

    // MARK: - Private Properties

    private var cachedDeviceName: String?
    
    // BeMyEars 3.0 will fakeDeviceName
    public var fakeDeviceName: String?
    // Set fakeUID alis name to avoid common bug
    public var fakeUID: String? {
        return fakeDeviceName
    }
    
    private var isRegisteredForNotifications = false

    // MARK: - Lifecycle Functions

    /// Initializes an `AudioDevice` by providing a valid audio device identifier.
    ///
    /// - Parameter id: An audio device identifier.
    private init?(id: AudioObjectID) {
        super.init(objectID: id)

        guard let classID = classID, Self.deviceClassIDs.contains(classID) else { return nil }

        AudioObjectPool.shared.set(self, for: objectID)
        registerForNotifications()

        cachedDeviceName = super.name
    }
    
    // BeMyEars 2.0 we don't need specified device.
    public init(name: String? = nil) {
        self.fakeDeviceName = name
        super.init(objectID: AudioObjectID())
    }

    deinit {
        AudioObjectPool.shared.remove(objectID)
        unregisterForNotifications()
    }

    // MARK: - AudioObject Overrides

    /// The audio device's name as reported by Core Audio.
    ///
    /// - Returns: An audio device's name.
    override public var name: String { super.name ?? cachedDeviceName ?? "<Unknown Device Name>" }
}

// MARK: - Class Functions

public extension AudioDevice {
    /// Returns an `AudioDevice` by providing a valid audio device identifier.
    ///
    /// - Parameter id: An audio device identifier.
    ///
    /// - Note: If identifier is not valid, `nil` will be returned.
    static func lookup(by id: AudioObjectID) -> AudioDevice? {
        var instance: AudioDevice? = AudioObjectPool.shared.get(id)

        if instance == nil {
            instance = AudioDevice(id: id)
        }

        return instance
    }

    /// Returns an `AudioDevice` by providing a valid audio device unique identifier.
    ///
    /// - Parameter uid: An audio device unique identifier.
    ///
    /// - Note: If unique identifier is not valid, `nil` will be returned.
    static func lookup(by uid: String) -> AudioDevice? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: Element.main.asPropertyElement
        )

        var deviceID = kAudioObjectUnknown
        var cfUID = (uid as CFString)

        let status: OSStatus = withUnsafeMutablePointer(to: &cfUID) { cfUIDPtr in
            withUnsafeMutablePointer(to: &deviceID) { deviceIDPtr in
                var translation = AudioValueTranslation(
                    mInputData: cfUIDPtr,
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: deviceIDPtr,
                    mOutputDataSize: UInt32(MemoryLayout<AudioObjectID>.size)
                )

                return getPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       address: address,
                                       andValue: &translation)
            }
        }

        if noErr != status || deviceID == kAudioObjectUnknown {
            return nil
        }

        return lookup(by: deviceID)
    }
}

// MARK: - Private Functions

private extension AudioDevice {
    // MARK: - Notification Book-keeping

    func registerForNotifications() {
        if isRegisteredForNotifications {
            unregisterForNotifications()
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertySelectorWildcard,
            mScope: kAudioObjectPropertyScopeWildcard,
            mElement: kAudioObjectPropertyElementWildcard
        )

        if noErr != AudioObjectAddPropertyListener(id, &address, propertyListener, nil) {
            os_log("Unable to add property listener for %@.", description)
        } else {
            isRegisteredForNotifications = true
        }
    }

    func unregisterForNotifications() {
        guard isRegisteredForNotifications, isAlive else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertySelectorWildcard,
            mScope: kAudioObjectPropertyScopeWildcard,
            mElement: kAudioObjectPropertyElementWildcard
        )

        if noErr != AudioObjectRemovePropertyListener(id, &address, propertyListener, nil) {
            os_log("Unable to remove property listener for %@.", description)
        } else {
            isRegisteredForNotifications = false
        }
    }
}

// MARK: - CustomStringConvertible Conformance

extension AudioDevice: CustomStringConvertible {
    /// Returns a `String` representation of self.
    public var description: String {
        return "\(name) (\(id))"
    }
}

// MARK: - C Convention Functions

private func propertyListener(objectID: UInt32,
                              numInAddresses: UInt32,
                              inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
                              clientData: Optional<UnsafeMutableRawPointer>) -> Int32 {
    // Try to get audio object from the pool.
    guard let obj: AudioDevice = AudioObjectPool.shared.get(objectID) else { return kAudioHardwareBadObjectError }

    let address = inAddresses.pointee
    let notificationCenter = NotificationCenter.default

    switch address.mSelector {
    case kAudioDevicePropertyNominalSampleRate:
        notificationCenter.post(name: .deviceNominalSampleRateDidChange, object: obj)
    case kAudioDevicePropertyAvailableNominalSampleRates:
        notificationCenter.post(name: .deviceAvailableNominalSampleRatesDidChange, object: obj)
    case kAudioDevicePropertyClockSource:
        notificationCenter.post(name: .deviceClockSourceDidChange, object: obj)
    case kAudioObjectPropertyName:
        notificationCenter.post(name: .deviceNameDidChange, object: obj)
    case kAudioObjectPropertyOwnedObjects:
        notificationCenter.post(name: .deviceOwnedObjectsDidChange, object: obj)
    case kAudioDevicePropertyVolumeScalar:
        let userInfo: [AnyHashable: Any] = [
            "channel": address.mElement,
            "scope": Scope.from(address.mScope),
        ]

        notificationCenter.post(name: .deviceVolumeDidChange, object: obj, userInfo: userInfo)
    case kAudioDevicePropertyMute:
        let userInfo: [AnyHashable: Any] = [
            "channel": address.mElement,
            "scope": Scope.from(address.mScope),
        ]

        notificationCenter.post(name: .deviceMuteDidChange, object: obj, userInfo: userInfo)
    case kAudioDevicePropertyDeviceIsAlive:
        notificationCenter.post(name: .deviceIsAliveDidChange, object: obj)
    case kAudioDevicePropertyDeviceIsRunning:
        notificationCenter.post(name: .deviceIsRunningDidChange, object: obj)
    case kAudioDevicePropertyDeviceIsRunningSomewhere:
        notificationCenter.post(name: .deviceIsRunningSomewhereDidChange, object: obj)
    case kAudioDevicePropertyJackIsConnected:
        notificationCenter.post(name: .deviceIsJackConnectedDidChange, object: obj)
    case kAudioDevicePropertyPreferredChannelsForStereo:
        notificationCenter.post(name: .devicePreferredChannelsForStereoDidChange, object: obj)
    case kAudioDevicePropertyHogMode:
        notificationCenter.post(name: .deviceHogModeDidChange, object: obj)
    case kAudioDeviceProcessorOverload:
        notificationCenter.post(name: .deviceProcessorOverload, object: obj)
    case kAudioDevicePropertyIOStoppedAbnormally:
        notificationCenter.post(name: .deviceIOStoppedAbnormally, object: obj)

    default:
        break
    }

    return kAudioHardwareNoError
}
