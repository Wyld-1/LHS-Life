//
//  LaSalle_WidgetsLiveActivity.swift
//  LaSalle Widgets
//
//  Created by Liam Lefohn on 5/1/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LaSalle_WidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LaSalle_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaSalle_WidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension LaSalle_WidgetsAttributes {
    fileprivate static var preview: LaSalle_WidgetsAttributes {
        LaSalle_WidgetsAttributes(name: "World")
    }
}

extension LaSalle_WidgetsAttributes.ContentState {
    fileprivate static var smiley: LaSalle_WidgetsAttributes.ContentState {
        LaSalle_WidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LaSalle_WidgetsAttributes.ContentState {
         LaSalle_WidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LaSalle_WidgetsAttributes.preview) {
   LaSalle_WidgetsLiveActivity()
} contentStates: {
    LaSalle_WidgetsAttributes.ContentState.smiley
    LaSalle_WidgetsAttributes.ContentState.starEyes
}
