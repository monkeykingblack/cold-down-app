import Foundation

/// Locale-aware formatting shared by every view. Temperatures stay in Celsius because thresholds are entered in °C.
enum DisplayFormat {
    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }

    static func temperature(_ celsius: Double?, placeholder: String = String(localized: "Unavailable")) -> String {
        celsius.map { temperature($0) } ?? placeholder
    }

    static func speed(_ value: Int?, unit: String) -> String {
        value.map { "\($0.formatted()) \(unit)" } ?? String(localized: "Unavailable")
    }
}
