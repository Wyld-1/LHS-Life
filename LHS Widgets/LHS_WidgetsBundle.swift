//
//  LaSalle_WidgetsBundle.swift
//  LaSalle Widgets
//
//  Created by Liam Lefohn on 5/1/26.
//

import WidgetKit
import SwiftUI

@main
struct LaSalle_WidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Temporarily isolated to diagnose Live Activity rendering issue.
        // Other widgets commented out per Apple Developer Forums workaround:
        // mixing widgets + Live Activity in bundle can silently suppress LA on device.
        // LaSalle_Widgets()
        // LaSalle_WidgetsControl()
        LaSalle_WidgetsLiveActivity()
    }
}
