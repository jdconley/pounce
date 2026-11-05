import DeclaredAgeRange
import Foundation
import PermissionKit
import PounceKit
import UIKit

/// The app-store age laws' "significant change" (spec §14.1): this release adds accounts, a time
/// zone and (soon) streaks. Where the law asks for it, a minor's parent approves through
/// PermissionKit before the new account features open, and an adult sees Apple's notice once.
/// Play itself never waits. Someone who installs this version agreed at download.
@MainActor
enum SignificantChangeGate {
    /// One id per significant change; a later one gets a new id.
    static let changeId = "accounts-2026-11"
    private static let key = "significantChange.\(changeId)"

    enum State: String {
        /// Asked and settled (approved, acknowledged, not required, or a new install).
        case done
        /// An existing player's first launch of this version: not decided yet.
        case owed
        /// A parent's approval is owed.
        case pending
    }

    /// At launch, before anything can upload: an existing player's accounts wait until `check`
    /// decides, and stay held while a parent's approval is pending.
    static func prepare(_ model: AppModel, defaults: UserDefaults = .standard) {
        if defaults.string(forKey: key) == nil, model.hadOwnerBeforeThisVersion {
            defaults.set(State.owed.rawValue, forKey: key)
        }
        let state = defaults.string(forKey: key).flatMap(State.init)
        model.account.heldForApproval = state == .owed || state == .pending
    }

    private static func settle(_ model: AppModel, defaults: UserDefaults) {
        defaults.set(State.done.rawValue, forKey: key)
        model.account.heldForApproval = false
    }

    static let updateDescription = String(
        localized: "Pounce now has accounts. Sign in with Apple to keep your games, settings and people on all your devices. Pounce also keeps your device's time zone, and soon the days you play together.",
        comment: "Shown by iOS when a parent approves, or an adult acknowledges, this significant update")

    /// Runs once per launch after the age check. Sets `heldForApproval` while a parent's yes is owed.
    static func check(_ model: AppModel, defaults: UserDefaults = .standard) async {
        #if DEBUG
        if PaceSetting.resolve(arguments: CommandLine.arguments, env: ProcessInfo.processInfo.environment).underTest {
            return settle(model, defaults: defaults)
        }
        #endif
        guard let band = model.ageBand else { return }
        let stored = defaults.string(forKey: key).flatMap(State.init)
        // A new install (nothing owed) agreed at download; a settled change stays settled.
        guard stored == .owed || stored == .pending else { return settle(model, defaults: defaults) }
        guard #available(iOS 26.4, *) else { return settle(model, defaults: defaults) }
        let features = await regulatoryFeatures()
        let action = SignificantChange.action(
            requiresConsent: features.contains(.significantAppChangeRequiresParentalConsent),
            requiresNotice: features.contains(.significantAppChangeRequiresAdultNotification),
            band: band, isNewInstall: false, done: false)
        switch action {
        case .none:
            settle(model, defaults: defaults)
        case .notifyAdult:
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                try? await AgeRangeService.shared.showSignificantUpdateAcknowledgment(
                    in: scene, updateDescription: updateDescription)
            }
            settle(model, defaults: defaults)
        case .askParent:
            model.account.heldForApproval = true
            let first = stored == .owed
            defaults.set(State.pending.rawValue, forKey: key)
            listen(model, defaults: defaults)
            if first, let presenter = UIApplication.shared.topViewController {
                let question = PermissionQuestion(
                    significantAppUpdateTopic: SignificantAppUpdateTopic(description: updateDescription))
                try? await AskCenter.shared.ask(question, in: presenter)
            }
        }
    }

    /// What the law where the person's account lives asks of this app (empty where it asks nothing).
    @available(iOS 26.4, *)
    nonisolated private static func regulatoryFeatures() async -> Set<AgeRangeService.RegulatoryFeature> {
        (try? await AgeRangeService.shared.requiredRegulatoryFeatures) ?? []
    }

    /// Waits for the parent's answer (it can come days later, on another launch).
    @available(iOS 26.4, *)
    private static func listen(_ model: AppModel, defaults: UserDefaults) {
        Task { @MainActor [weak model] in
            for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self) {
                guard response.choice.answer == .approval else { continue }
                defaults.set(State.done.rawValue, forKey: key)
                guard let model else { return }
                model.account.heldForApproval = false
                await model.account.uploadProfile()
                return
            }
        }
    }
}
