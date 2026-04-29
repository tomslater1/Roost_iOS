//
//  RoostWidgetsBundle.swift
//  RoostWidgets
//
//  Entry point for the widget extension. Declares the set of widgets +
//  Live Activities that ship with Roost.
//

import SwiftUI
import WidgetKit

@main
struct RoostWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShoppingWidget()
        ShoppingLiveActivity()
    }
}
