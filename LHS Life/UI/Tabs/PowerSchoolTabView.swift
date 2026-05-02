//
//  PowerSchoolTabView.swift
//  LHS Life
//

import SwiftUI

struct PowerSchoolTabView: View {
    @Bindable var webState: EmbeddedWebState
    var body: some View { EmbeddedWebView(webState: webState) }
}
