import Foundation
import SwiftUI

private let keyBankroll = "ctt_bankroll"
private let keyUnitSize = "ctt_unit_size"
private let keyTargetAverage = "ctt_target_average"
private let keyAppleSignedIn = "ctt_apple_signed_in"
private let keyGoogleSignedIn = "ctt_google_signed_in"

final class SettingsStore: ObservableObject {
    @Published var bankroll: Int {
        didSet { UserDefaults.standard.set(bankroll, forKey: keyBankroll) }
    }
    @Published var unitSize: Int {
        didSet { UserDefaults.standard.set(unitSize, forKey: keyUnitSize) }
    }
    /// Target average win per session ($). Nil = not set.
    @Published var targetAveragePerSession: Double? {
        didSet {
            if let v = targetAveragePerSession {
                UserDefaults.standard.set(v, forKey: keyTargetAverage)
            } else {
                UserDefaults.standard.removeObject(forKey: keyTargetAverage)
            }
        }
    }
    @Published var isAppleSignedIn: Bool {
        didSet { UserDefaults.standard.set(isAppleSignedIn, forKey: keyAppleSignedIn) }
    }
    @Published var isGoogleSignedIn: Bool {
        didSet { UserDefaults.standard.set(isGoogleSignedIn, forKey: keyGoogleSignedIn) }
    }

    init() {
        let b = UserDefaults.standard.integer(forKey: keyBankroll)
        self.bankroll = b > 0 ? b : 2000
        let u = UserDefaults.standard.integer(forKey: keyUnitSize)
        self.unitSize = u > 0 ? u : 50
        if let v = UserDefaults.standard.object(forKey: keyTargetAverage) as? Double {
            self.targetAveragePerSession = v
        } else {
            self.targetAveragePerSession = nil
        }
        self.isAppleSignedIn = UserDefaults.standard.bool(forKey: keyAppleSignedIn)
        self.isGoogleSignedIn = UserDefaults.standard.bool(forKey: keyGoogleSignedIn)
    }
}
