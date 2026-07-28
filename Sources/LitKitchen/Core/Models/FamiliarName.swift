import Foundation

public extension String {
    /// The name to address someone by, from a kitchen's display name.
    ///
    /// Taking the first word — which is what every call site did — produces
    /// **"Doña"** for "Doña Chuy", **"Chef"** for "Chef Danny", and **"The"**
    /// for "The Bagel Guy". An honorific is a form of address, not a name, and
    /// "Message Doña" reads like a sentence someone forgot to finish.
    ///
    /// So: a leading honorific or article is kept with the word it belongs to,
    /// and everything else still shortens. "Yolanda C." stays "Yolanda", which
    /// is the whole point of shortening in the first place.
    ///
    /// Spanish titles are in the list because this market is bilingual and the
    /// cooks most likely to be called *Doña* or *Tía* are exactly the ones the
    /// app is for — getting their name wrong on every screen is not a small
    /// thing.
    var familiarName: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return trimmed }

        let carried: Set<String> = [
            // Spanish
            "doña", "dona", "don", "señora", "senora", "señor", "senor",
            "sra", "sra.", "sr", "sr.", "tía", "tia", "tío", "tio",
            "abuela", "abuelo", "mamá", "mama", "papá", "papa",
            // English
            "chef", "mr", "mr.", "mrs", "mrs.", "ms", "ms.", "miss",
            "nana", "grandma", "auntie", "aunt", "uncle",
            // Articles — "The Bagel Guy" is not "The"
            "the", "la", "el", "los", "las"
        ]

        return carried.contains(first.lowercased()) ? trimmed : String(first)
    }
}
