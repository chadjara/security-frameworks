import DesignTokens
import SwiftUI

/// CGFloat accessors for the spacing and radius scales.
enum DS {
    enum Space {
        static let xxs = CGFloat(Spacing.xxs)
        static let xs = CGFloat(Spacing.xs)
        static let s = CGFloat(Spacing.s)
        static let m = CGFloat(Spacing.m)
        static let l = CGFloat(Spacing.l)
        static let xl = CGFloat(Spacing.xl)
        static let xxl = CGFloat(Spacing.xxl)
    }

    enum Corner {
        static let small = CGFloat(Radius.small)
        static let medium = CGFloat(Radius.medium)
        static let large = CGFloat(Radius.large)
    }
}
