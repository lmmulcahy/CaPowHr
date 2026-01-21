//
//  FitnessDeviceType.swift
//  CaPowHr Watch App
//
//  Represents the type of fitness equipment detected via FTMS characteristics.
//

import Foundation

/// The type of fitness equipment detected based on FTMS characteristic subscriptions.
enum FitnessDeviceType: String {
    /// No device type has been determined yet.
    case unknown
    /// Indoor bike (detected via Indoor Bike Data characteristic 0x2AD2).
    case bike
    /// Treadmill (detected via Treadmill Data characteristic 0x2ACD).
    case treadmill
}

/// The type of workout to start, based on device and user selection.
enum WorkoutType {
    /// Indoor cycling workout (for bikes).
    case indoorCycle
    /// Indoor running workout (for treadmills).
    case indoorRun
    /// Indoor walking workout (for treadmills).
    case indoorWalk
}
