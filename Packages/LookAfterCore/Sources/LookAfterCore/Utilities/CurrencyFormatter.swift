import Foundation

/// Formats monetary amounts using the user's selected currency symbol.
public enum CurrencyFormatter {
    
    public static var symbol: String {
        UserDefaults.standard.string(forKey: "appCurrencySymbol") ?? "₹"
    }
    
    public static func format(_ amount: Double) -> String {
        String(format: "\(symbol)%.2f", amount)
    }
}
