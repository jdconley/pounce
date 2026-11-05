@preconcurrency import Intents
import PounceKit
import UIKit
@preconcurrency import UserNotifications

/// How a push from a person becomes a communication notification (spec §12.5), shared by the
/// `PounceNotify` extension and (for the Debug `-demo-communication` screenshot) the app: an
/// `INSendMessageIntent` from the sender, their cat as the avatar, and the push's own title as
/// the conversation's name, so the title stays the person the push is for (§12.2).
enum Communication {
    static func intent(_ plan: CommunicationPlan, body: String, art: Bundle?) -> INSendMessageIntent {
        let avatar = Avatar.image(cat: plan.sender.cat, art: art)
        let sender = INPerson(
            personHandle: INPersonHandle(value: "pounce-cat:\(plan.sender.name):\(plan.sender.cat)", type: .unknown),
            nameComponents: nil, displayName: plan.sender.name, image: avatar,
            contactIdentifier: nil, customIdentifier: nil, isMe: false)
        let group = plan.groupName.map { INSpeakableString(spokenPhrase: $0) }
        let me = INPerson(
            personHandle: INPersonHandle(value: "pounce-me", type: .unknown), nameComponents: nil,
            displayName: plan.groupName, image: nil, contactIdentifier: nil, customIdentifier: nil, isMe: true)
        let intent = INSendMessageIntent(
            recipients: [me, sender], outgoingMessageType: .outgoingMessageText, content: body, speakableGroupName: group,
            conversationIdentifier: plan.conversation, serviceName: nil, sender: sender, attachments: nil)
        if group != nil, let avatar { intent.setImage(avatar, forParameterNamed: \.speakableGroupName) }
        return intent
    }

    /// The content updated from the intent (donated first, as iOS asks), or nil when this push
    /// isn't from a person or the update fails.
    static func content(for content: UNNotificationContent, art: Bundle?) -> UNNotificationContent? {
        guard let payload = PushPayload(userInfo: content.userInfo), let plan = CommunicationPlan.make(payload) else {
            return nil
        }
        let message = intent(plan, body: content.body, art: art)
        let interaction = INInteraction(intent: message, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        return try? content.updating(from: message)
    }
}

/// The sender's cat on a loud round tile, from the app's art (`cat<N>-idle`).
enum Avatar {
    /// One colour per cat, from the Loud Toy palette.
    private static let colors: [UIColor] = [
        UIColor(red: 1, green: 0.54, blue: 0, alpha: 1), UIColor(red: 0.48, green: 0.18, blue: 1, alpha: 1),
        UIColor(red: 0, green: 0.82, blue: 0.76, alpha: 1), UIColor(red: 1, green: 0.18, blue: 0.6, alpha: 1),
        UIColor(red: 0.18, green: 0.72, blue: 1, alpha: 1), UIColor(red: 0.61, green: 0.89, blue: 0.18, alpha: 1),
        UIColor(red: 1, green: 0.18, blue: 0.6, alpha: 1), UIColor(red: 0, green: 0.82, blue: 0.76, alpha: 1),
    ]
    private static let ink = UIColor(red: 0.106, green: 0.043, blue: 0.227, alpha: 1)

    static func image(cat: Int, art: Bundle?) -> INImage? {
        guard let picture = UIImage(named: "cat\(cat)-idle", in: art, compatibleWith: nil) else { return nil }
        let side: CGFloat = 240
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            colors[cat % colors.count].setFill()
            ctx.cgContext.fillEllipse(in: rect)
            picture.draw(in: rect.insetBy(dx: side * 0.1, dy: side * 0.1))
            ink.setStroke()
            ctx.cgContext.setLineWidth(side * 0.05)
            ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: side * 0.025, dy: side * 0.025))
        }
        return INImage(imageData: png)
    }
}
