import Foundation
import SwiftUI

/// Shared navigation state so both the main window and the menu-bar extra can drive which
/// tab is showing — e.g. the menu bar's "Review in Cleanup" jumps straight to that module.
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: SidebarTab = .scan
}
