import Foundation
import PermissionKit
import PounceKit
import UIKit

/// Apple's "ask to communicate" for a kitten with Screen Time's Communication Limits (consent
/// design §2 layer 3, D3; plan decision 22). The handle for each person is `.custom(pairId)`.
/// Apple's answers (`knownHandles(in:)`) are the authority; `KittenStore.mirror` sends them up.
/// Without Communication Limits it only tells the server once that the parent's own list counts.
@MainActor
final class CommunicationLimitsBridge {
    private weak var model: AppModel?
    private var listening = false
    private var syncing = false

    init(model: AppModel) {
        self.model = model
    }

    /// The kitten's partners from the streak list: pair id, name and cat.
    private var partners: [(pair: String, name: String, cat: Int)] {
        (model?.streaks.pairs ?? []).map { ($0.pair, $0.partner.name, $0.partner.cat) }
    }

    /// Reads Apple's answers, mirrors them, and asks about anyone new. Kittens only, once linked.
    func sync() async {
        guard let model, model.ageBand == .kitten, model.kittens.status?.linked == true, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let limits = await model.communicationLimitsOn()
        let people = partners
        let known = limits ? await Self.known(people.map(\.pair)) : []
        let ask = await model.kittens.mirror(limits: limits, partners: people.map(\.pair), known: known)
        guard limits, !ask.isEmpty else { return }
        listen()
        for pair in ask {
            guard let person = people.first(where: { $0.pair == pair }) else { continue }
            await Self.ask(pair: pair, name: person.name, cat: person.cat)
        }
        model.kittens.noteAsked(ask)
    }

    /// A tap on a padlocked person: ask Apple again about them.
    func askAgain(pair: String) async {
        model?.kittens.forgetAsked(pair)
        await sync()
    }

    private static func handle(_ pair: String) -> CommunicationHandle { CommunicationHandle(value: pair, kind: .custom) }

    private static func known(_ pairs: [String]) async -> Set<String> {
        let handles = Set(pairs.map(handle))
        return Set(await CommunicationLimits.current.knownHandles(in: handles).map(\.value))
    }

    /// Apple's own sheet; the parent answers in Messages. The answer comes back through `listen`.
    private static func ask(pair: String, name: String, cat: Int) async {
        guard #available(iOS 26.2, *), let presenter = UIApplication.shared.topViewController else { return }
        var nameParts = PersonNameComponents()
        nameParts.nickname = name
        let info = CommunicationTopic.PersonInformation(
            handle: handle(pair), nameComponents: nameParts, avatarImage: UIImage(named: ArtName.cat(cat, .idle))?.cgImage)
        let question = PermissionQuestion(communicationTopic: CommunicationTopic(personInformation: [info], actions: [.connect]))
        // Throws without Communication Limits or Family Sharing; then nothing changes.
        try? await AskCenter.shared.ask(question, in: presenter)
    }

    /// Each answer, now or on a later launch (the app is woken for it), mirrors again.
    private func listen() {
        guard #available(iOS 26.2, *), !listening else { return }
        listening = true
        Task { @MainActor [weak self] in
            for await _ in AskCenter.shared.responses(for: CommunicationTopic.self) {
                await self?.sync()
            }
        }
    }

    /// At launch on a kitten's device: answers that arrived while the app wasn't running.
    func start() {
        guard model?.ageBand == .kitten else { return }
        listen()
    }
}
