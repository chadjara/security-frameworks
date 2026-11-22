import SwiftUI
import UIKit

/// Type scale. Futura for display text and controls; SF Pro for reading; SF Mono for identifiers.
/// Every style scales with Dynamic Type.
enum Typeface {
    static let futuraBold = "Futura-Bold"
    static let futuraMedium = "Futura-Medium"
}

/// Description of one text style, used by the type specimen.
struct TypeStyle: Identifiable {
    let id: String
    let name: String
    let font: Font
    let spec: String
    let usage: String
}

extension Font {
    // Display: Futura
    static let dsLargeTitle = Font.custom(Typeface.futuraBold, size: 34, relativeTo: .largeTitle)
    static let dsTitle = Font.custom(Typeface.futuraBold, size: 28, relativeTo: .title)
    static let dsTitle2 = Font.custom(Typeface.futuraMedium, size: 22, relativeTo: .title2)
    static let dsTitle3 = Font.custom(Typeface.futuraMedium, size: 20, relativeTo: .title3)
    static let dsHeadline = Font.custom(Typeface.futuraMedium, size: 17, relativeTo: .headline)
    static let dsSectionHeader = Font.custom(Typeface.futuraMedium, size: 13, relativeTo: .footnote)
    static let dsButton = Font.custom(Typeface.futuraMedium, size: 17, relativeTo: .body)
    static let dsButtonSmall = Font.custom(Typeface.futuraMedium, size: 15, relativeTo: .subheadline)

    // Reading: SF Pro
    static let dsBody = Font.body
    static let dsCallout = Font.callout
    static let dsSubheadline = Font.subheadline
    static let dsFootnote = Font.footnote
    static let dsCaption = Font.caption

    // Identifiers: SF Mono
    static let dsRequirementID = Font.system(.subheadline, design: .monospaced).weight(.medium)
    static let dsRequirementIDLarge = Font.system(.title3, design: .monospaced).weight(.semibold)
    static let dsRequirementIDSmall = Font.system(.caption, design: .monospaced).weight(.medium)

    static let specimen: [TypeStyle] = [
        TypeStyle(id: "largeTitle", name: "Large Title", font: .dsLargeTitle, spec: "Futura Bold 34, scales with Large Title",
                  usage: "Top-level screen titles"),
        TypeStyle(id: "title", name: "Title", font: .dsTitle, spec: "Futura Bold 28, scales with Title",
                  usage: "Dashboard figures and report headings"),
        TypeStyle(id: "title2", name: "Title 2", font: .dsTitle2, spec: "Futura Medium 22, scales with Title 2",
                  usage: "Requirement titles in detail views"),
        TypeStyle(id: "title3", name: "Title 3", font: .dsTitle3, spec: "Futura Medium 20, scales with Title 3",
                  usage: "Sheet and card titles"),
        TypeStyle(id: "headline", name: "Headline", font: .dsHeadline, spec: "Futura Medium 17, scales with Headline",
                  usage: "Row titles and inline navigation titles"),
        TypeStyle(id: "sectionHeader", name: "Section Header", font: .dsSectionHeader,
                  spec: "Futura Medium 13, uppercase, scales with Footnote", usage: "List section headers"),
        TypeStyle(id: "button", name: "Button", font: .dsButton, spec: "Futura Medium 17, scales with Body",
                  usage: "Primary and secondary actions"),
    ]

    static let readingSpecimen: [TypeStyle] = [
        TypeStyle(id: "body", name: "Body", font: .dsBody, spec: "SF Pro 17", usage: "Questions and guidance"),
        TypeStyle(id: "callout", name: "Callout", font: .dsCallout, spec: "SF Pro 16", usage: "Notices and explanations"),
        TypeStyle(id: "subheadline", name: "Subheadline", font: .dsSubheadline, spec: "SF Pro 15", usage: "Secondary row text"),
        TypeStyle(id: "footnote", name: "Footnote", font: .dsFootnote, spec: "SF Pro 13", usage: "Sources and metadata"),
        TypeStyle(id: "caption", name: "Caption", font: .dsCaption, spec: "SF Pro 12", usage: "Chart labels"),
    ]
}

extension View {
    /// Futura section header styling for `List` sections.
    func dsSectionHeaderStyle() -> some View {
        self.font(.dsSectionHeader)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Color.dsTextSecondary)
    }
}

/// Applies Futura to navigation bar titles. UIKit fonts are scaled with UIFontMetrics so they respect
/// the Dynamic Type size at launch.
enum NavigationBarStyle {
    @MainActor
    static func apply() {
        let largeBase = UIFont(name: Typeface.futuraBold, size: 34) ?? .preferredFont(forTextStyle: .largeTitle)
        let inlineBase = UIFont(name: Typeface.futuraMedium, size: 17) ?? .preferredFont(forTextStyle: .headline)
        let large = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeBase)
        let inline = UIFontMetrics(forTextStyle: .headline).scaledFont(for: inlineBase)
        let proxy = UINavigationBar.appearance()
        proxy.largeTitleTextAttributes = [.font: large]
        proxy.titleTextAttributes = [.font: inline]
    }
}
