//
//  AppNavigationCoordinator.swift
//  LHS Life
//
//  Bridges App Intents (which run out-of-process from the UI) to
//  AppTabContainer's tab selection. An intent sets `pendingTab`;
//  AppTabContainer observes it and switches tabs, then clears it.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationCoordinator {
    static let shared = AppNavigationCoordinator()
    var pendingTab: AppTab?
    private init() {}
}
