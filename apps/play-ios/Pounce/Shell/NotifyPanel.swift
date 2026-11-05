import PounceKit
import SwiftUI

/// The notification settings (spec §12.6), in pictures and numerals, shared by the gear sheet and
/// the Us screen's gear: the bell for reminders ("your move" is unaffected) and the last-chance
/// moon; the reminder time as an Auto chip or two clock dials (weekdays, weekends); quiet hours as
/// a moon dial and a sun dial. Each band's defaults show until someone changes them (§14.1). A
/// kitten's device has only the local 17:00 reminder's bell.
struct NotifyPanel: View {
    @Environment(AppModel.self) private var model
    var scale: CGFloat = 1

    var body: some View {
        Group {
            if model.ageBand == .kitten {
                kitten
            } else {
                full(model.notifySettings)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var kitten: some View {
        HStack(spacing: 14 * scale) {
            FlagButton(icon: ArtName.iconBell, on: model.kittenDailyOn, color: Palette.magenta, size: 64 * scale,
                       label: "Daily reminder") {
                model.setKittenDaily(!model.kittenDailyOn)
            }
            .accessibilityIdentifier("notify.kitten")
            OutlinedText(KittenReminder.time.text, size: 30 * scale, fill: .white, width: 3)
                .opacity(model.kittenDailyOn ? 1 : 0.55)
                .accessibilityHidden(true)
        }
    }

    private func full(_ s: NotifySettings) -> some View {
        VStack(spacing: 16 * scale) {
            HStack(spacing: 18 * scale) {
                FlagButton(icon: ArtName.iconBell, on: s.reminders, color: Palette.magenta, size: 64 * scale,
                           label: "Reminders") {
                    model.setNotify(NotifyKey.reminders, .bool(!s.reminders))
                }
                .accessibilityIdentifier("notify.reminders")
                // Last chance is a reminder too: dimmed while the bell is off.
                FlagButton(icon: ArtName.Habit.iconLastChance, on: s.lastChance, color: Palette.violet,
                           size: 64 * scale, label: "Last chance") {
                    model.setNotify(NotifyKey.lastChance, .bool(!s.lastChance))
                }
                .opacity(s.reminders ? 1 : 0.55)
                .accessibilityIdentifier("notify.lastChance")
                FlagButton(icon: ArtName.Habit.iconAuto, on: s.auto, color: Palette.sky, size: 64 * scale, label: "Auto time") {
                    model.setNotify(NotifyKey.auto, .bool(!s.auto))
                }
                .accessibilityIdentifier("notify.auto")
            }
            if !s.auto {
                HStack(spacing: 18 * scale) {
                    ClockDial(icon: ArtName.Habit.iconWeekday, time: s.clamped(s.weekday), color: Palette.magenta,
                              side: 120 * scale, label: "Weekday reminder", clamp: s.clamped, id: "notify.weekday") {
                        model.setNotify(NotifyKey.weekday, $0.json)
                    }
                    ClockDial(icon: ArtName.Habit.iconWeekend, time: s.clamped(s.weekend), color: Palette.teal,
                              side: 120 * scale, label: "Weekend reminder", clamp: s.clamped, id: "notify.weekend") {
                        model.setNotify(NotifyKey.weekend, $0.json)
                    }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .opacity(s.reminders ? 1 : 0.55)
            }
            HStack(spacing: 18 * scale) {
                ClockDial(icon: ArtName.Habit.iconMoon, time: s.quietStart, color: Palette.violet, side: 120 * scale,
                          label: "Quiet hours start", id: "notify.quietStart") {
                    model.setNotify(NotifyKey.quietStart, $0.json)
                }
                ClockDial(icon: ArtName.Habit.iconSun, time: s.quietEnd, color: Palette.orange, side: 120 * scale,
                          label: "Quiet hours end", id: "notify.quietEnd") {
                    model.setNotify(NotifyKey.quietEnd, $0.json)
                }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.35).paced, value: s.auto)
    }
}

/// A round art toggle: loud when on, greyed violet when off; VoiceOver hears on or off.
struct FlagButton: View {
    let icon: String
    let on: Bool
    let color: Color
    var size: CGFloat = 60
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        ArtIconButton(icon: icon, color: on ? color : Palette.night, size: size, label: label, action: action)
            .saturation(on ? 1 : 0.35)
            .overlay(alignment: .bottomTrailing) {
                if on {
                    Image(ArtName.iconCheck).resizable().scaledToFit().frame(width: size * 0.34)
                        .offset(x: 4, y: 4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.5).paced, value: on)
            // One element (the check is part of the picture), still a button for VoiceOver.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(on ? "on" : "off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// A round clock face over the whole day: the hand points at the time (midnight at the top), the
/// numerals sit in the middle, the icon says which time it is. Drag around the ring to set it in
/// 15-minute steps; VoiceOver adjusts it 15 minutes at a time.
struct ClockDial: View {
    let icon: String
    let time: ClockTime
    let color: Color
    var side: CGFloat = 120
    let label: LocalizedStringKey
    /// Keeps a reminder where the server will use it (outside quiet hours).
    var clamp: (ClockTime) -> ClockTime = { $0 }
    /// The accessibility id: the face has it, the steppers `<id>.minus` and `<id>.plus`.
    let id: String
    let onChange: (ClockTime) -> Void

    @State private var dragging: ClockTime?

    private static let step = 15
    private var shown: ClockTime { dragging ?? time }

    var body: some View {
        VStack(spacing: side * 0.06) {
            face
            // A quarter hour back or on, for a precise time without dragging.
            HStack(spacing: side * 0.14) {
                stepper("chevron.left", -Self.step, id: "minus")
                stepper("chevron.right", Self.step, id: "plus")
            }
        }
    }

    private func stepper(_ systemName: String, _ delta: Int, id: String) -> some View {
        RoundIconButton(systemName: systemName, color: color, side: side * 0.3,
                        accessibilityLabel: delta > 0 ? "Later" : "Earlier") {
            step(delta)
        }
        .accessibilityIdentifier("\(self.id).\(id)")
    }

    private func step(_ delta: Int) {
        let next = clamp(ClockTime(minutes: time.minutes + delta))
        if next != time { onChange(next) }
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.mix(with: .white, by: 0.35), color], center: .center,
                                     startRadius: 4, endRadius: side * 0.6))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: max(3, side / 28)))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: side / 26)
            ForEach(0..<24, id: \.self) { h in
                Capsule()
                    .fill(Palette.ink.opacity(h % 6 == 0 ? 0.9 : 0.45))
                    .frame(width: h % 6 == 0 ? 4 : 2.5, height: side * (h % 6 == 0 ? 0.1 : 0.06))
                    .offset(y: -side * 0.39)
                    .rotationEffect(.degrees(Double(h) * 15))
            }
            Capsule()
                .fill(.white)
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2.5))
                .frame(width: side * 0.07, height: side * 0.3)
                .offset(y: -side * 0.17)
                .rotationEffect(.degrees(Double(shown.minutes) / 1440 * 360))
            OutlinedText(shown.text, size: side * 0.2, fill: .white, width: max(2, side / 45))
                .fixedSize()
                .offset(y: side * 0.16)
            Image(icon).resizable().scaledToFit().frame(width: side * 0.3)
                .offset(y: -side * 0.56)
        }
        .frame(width: side, height: side)
        .padding(.top, side * 0.2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let next = clamp(Self.time(at: g.location, side: side, top: side * 0.2))
                    if next != dragging { Haptics.shared.tick() }
                    dragging = next
                }
                .onEnded { _ in
                    if let dragging, dragging != time { onChange(dragging) }
                    dragging = nil
                })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(shown.text)
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? Self.step : -Self.step)
        }
        .accessibilityIdentifier(id)
    }

    /// The 15-minute step a point on the face points at, midnight at the top, clockwise.
    static func time(at point: CGPoint, side: CGFloat, top: CGFloat) -> ClockTime {
        let dx = point.x - side / 2
        let dy = point.y - top - side / 2
        var angle = atan2(dx, -dy) * 180 / .pi
        if angle < 0 { angle += 360 }
        let minutes = Int((angle / 360 * 1440 / Double(step)).rounded()) * step
        return ClockTime(minutes: minutes)
    }
}
