import UIKit

/// Returns `name` if it's a real SF Symbol, otherwise a generic timer icon (an
/// unknown name would otherwise render as nothing).
func resolvedSymbolName(_ name: String?) -> String {
    if let name, UIImage(systemName: name) != nil { return name }
    return "timer"
}
