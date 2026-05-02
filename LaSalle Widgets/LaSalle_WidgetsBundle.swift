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
        LaSalle_Widgets()
        LaSalle_WidgetsControl()
        LaSalle_WidgetsLiveActivity()
    }
}
