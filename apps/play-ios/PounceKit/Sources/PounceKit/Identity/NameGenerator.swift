/// Cat-ish default display names for new local people.
public enum NameGenerator {
    public static let names: [String] = [
        "Mochi", "Biscuit", "Pickle", "Waffles", "Noodle", "Muffin", "Pudding", "Tofu", "Peanut", "Pepper",
        "Ginger", "Whiskers", "Bean", "Cocoa", "Sprout", "Dumpling", "Nugget", "Pretzel", "Sushi", "Toast",
        "Cricket", "Maple", "Olive", "Pumpkin", "Marble", "Button", "Clover", "Pixel", "Meatball", "Oreo",
        "Taco", "Mango", "Kiwi", "Biggles", "Fluffy", "Sprinkles", "Turnip", "Bagel", "Cinnamon", "Pancake",
        "Zigzag", "Mittens", "Snickers", "Gizmo", "Pebbles", "Truffle", "Jellybean", "Churro",
    ]

    public static func random<G: RandomNumberGenerator>(using g: inout G) -> String {
        names.randomElement(using: &g) ?? "Mochi"
    }
}
