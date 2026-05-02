//
//  SchoologyTabView.swift
//  LHS Life
//

import SwiftUI

struct SchoologyTabView: View {
    @Bindable var webState: EmbeddedWebState
    var body: some View { EmbeddedWebView(webState: webState) }
}
