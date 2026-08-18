//
//  CrossPromoMenu.swift
//  CurrencyPal
//
//  A pointer to the other app that shares this one's premise: multi-currency,
//  offline, no subscription. Nothing else belongs here — a converter is not a
//  billboard, and one relevant link outperforms a list of unrelated ones.
//

import SwiftUI

enum CrossPromo {

    /// SuperFinans is still PREPARE_FOR_SUBMISSION. A link to an unreleased app
    /// opens an App Store error page, so the menu hides itself until this flips.
    /// Flip it the day the app goes live — nothing else needs changing.
    static let superFinansIsLive = false

    static let superFinansURL = URL(string: "https://apps.apple.com/app/id6759007613")!

    static var hasAnything: Bool { superFinansIsLive }
}

struct CrossPromoMenu: View {

    var body: some View {
        if CrossPromo.hasAnything {
            Menu {
                if CrossPromo.superFinansIsLive {
                    Link(destination: CrossPromo.superFinansURL) {
                        Label("SuperFinans — your freedom year", systemImage: "flag.checkered")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(Text("More from us"))
        }
    }
}
