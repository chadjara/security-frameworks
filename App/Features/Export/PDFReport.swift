import Charts
import CoreText
import DesignTokens
import FrameworkKit
import SwiftUI
import UIKit

/// A printable assessment report: cover, summary with charts, next steps, and requirement details.
/// Uses the design system's type (Futura headings, SF body, SF Mono IDs) and light-mode colors.
@MainActor
struct PDFReport {
    let assessment: Assessment
    let frameworks: [Framework]
    let graph: MappingGraph?
    var options = ExportOptions()

    private var builder: ReportBuilder { ReportBuilder(assessment: assessment, frameworks: frameworks, options: options) }

    func render() throws -> URL {
        let data = makeData()
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let scope = frameworks.count == 1 ? " \(frameworks[0].document.shortName)" : ""
        return try ExportFiles.write(data, named: "\(BackupService.safeFileName(assessment.name))\(scope) Report \(stamp).pdf")
    }

    func makeData() -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(assessment.name) security assessment",
            kCGPDFContextCreator as String: "FrameworkApp \(BackupService.appVersion)",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: PDFCanvas.pageRect, format: format)
        return renderer.pdfData { ctx in
            let canvas = PDFCanvas(context: ctx, header: assessment.name)
            drawCover(canvas)
            if options.summary || options.nextSteps { canvas.beginPage() }
            if options.summary { drawSummary(canvas) }
            if options.nextSteps { drawNextSteps(canvas) }
            if options.requirementDetails { drawDetails(canvas) }
        }
    }

    // MARK: Sections

    private func drawCover(_ c: PDFCanvas) {
        c.beginPage(showHeader: false)
        c.cursorY = 180
        c.text(PDFStyle.label("SECURITY SELF-ASSESSMENT"), after: 10)
        c.text(PDFStyle.title(assessment.name), after: 6)
        if !assessment.organization.isEmpty { c.text(PDFStyle.subtitle(assessment.organization), after: 18) }
        c.text(PDFStyle.body("Generated \(Date.now.formatted(date: .long, time: .shortened))", color: PDFStyle.secondary), after: 24)
        for fw in frameworks {
            let scope = ScopeDescription.short(assessment.scope(for: fw.id), framework: fw)
            c.text(PDFStyle.keyValue(fw.document.shortName, fw.hasBaselines ? scope : fw.document.publicationId, width: c.contentWidth), after: 4)
        }
        if options.notes && !assessment.notes.isEmpty {
            c.space(14)
            c.text(PDFStyle.label("ASSESSMENT NOTES"), after: 4)
            c.text(PDFStyle.body(String(assessment.notes.prefix(1200))), after: 0)
        }
        c.cursorY = PDFCanvas.pageRect.height - PDFCanvas.margin - 120
        c.rule()
        c.text(PDFStyle.small(PDFStyle.disclaimer), after: 0)
    }

    private func drawSummary(_ c: PDFCanvas) {
        c.text(PDFStyle.heading("Summary"), after: 12)
        for fw in frameworks {
            let statuses = assessment.statusMap(frameworkID: fw.id)
            let scope = assessment.scope(for: fw.id)
            let progress = ProgressSummary(ids: fw.requirementsInScope(scope).map(\.id), statuses: statuses)
            c.keepTogether(220)
            c.text(PDFStyle.subheading(fw.document.shortName), after: 4)
            c.text(PDFStyle.big("\(Int((progress.fractionImplemented * 100).rounded()))% implemented"), after: 6)
            c.image(snapshot(StatusBreakdownBar(progress: progress).frame(width: c.contentWidth, height: 14)), height: 14, after: 6)
            c.text(PDFStyle.body("\(progress.implemented) implemented · \(progress.inProgress) in progress · \(progress.notStarted) not started · \(progress.notApplicable) not applicable", color: PDFStyle.secondary), after: 10)

            let groups = fw.progressByTopGroup(scope: scope, statuses: statuses)
            c.text(PDFStyle.label("BY \(fw.document.groupLevels.first?.singular.uppercased() ?? "GROUP")"), after: 4)
            for g in groups {
                let p = g.progress
                c.text(PDFStyle.keyValue("\(g.group.displayId)  \(g.group.title)",
                                         "\(p.implemented)/\(p.applicable) · \(Int((p.fractionImplemented * 100).rounded()))%",
                                         width: c.contentWidth), after: 2)
            }
            if !fw.document.tiers.isEmpty && options.profile {
                c.space(8)
                c.text(PDFStyle.label("CURRENT VS TARGET PROFILE"), after: 4)
                for s in ProfileAnalysis.summarize(fw, facts: assessment.factsMap(frameworkID: fw.id)) {
                    c.text(PDFStyle.keyValue("\(s.groupID)  \(s.title)", "\(s.achieved) of \(s.targeted) targeted outcomes", width: c.contentWidth), after: 2)
                }
                let tier = { (n: Int?) -> String in
                    guard let n, let t = fw.document.tiers.first(where: { $0.number == n }) else { return "Not set" }
                    return "Tier \(t.number): \(t.title)"
                }
                c.space(4)
                c.text(PDFStyle.keyValue("Current tier", tier(assessment.csfCurrentTier), width: c.contentWidth), after: 2)
                c.text(PDFStyle.keyValue("Target tier", tier(assessment.csfTargetTier), width: c.contentWidth), after: 2)
            }
            if fw.hasBaselines {
                c.space(8)
                c.text(PDFStyle.label("SP 800-53B BASELINE COVERAGE"), after: 4)
                for row in fw.progressByBaseline(statuses: statuses) {
                    c.text(PDFStyle.keyValue("\(row.baseline.title) baseline", "\(row.progress.implemented)/\(row.progress.applicable) implemented", width: c.contentWidth), after: 2)
                }
            }
            c.space(18)
        }
    }

    private func drawNextSteps(_ c: PDFCanvas) {
        let steps = NextStepsEngine.rank(frameworks: frameworks, scopes: assessment.scopes,
                                         facts: assessment.allFacts(), graph: graph)
        guard !steps.isEmpty else { return }
        c.keepTogether(160)
        c.text(PDFStyle.heading("What to do next"), after: 4)
        c.text(PDFStyle.body("The highest-priority open requirements across all frameworks in this report.", color: PDFStyle.secondary), after: 10)
        for step in steps.prefix(15) {
            guard let fw = frameworks.first(where: { $0.id == step.ref.frameworkID }),
                  let r = fw.requirement(step.ref.requirementID) else { continue }
            c.keepTogether(44)
            c.text(PDFStyle.requirementLine(fw.document.shortName + "  " + r.displayId, r.title), after: 1)
            let reasons = step.reasons.map(NextStepRow.text).joined(separator: " · ")
            c.text(PDFStyle.small(reasons.isEmpty ? step.status.title : "\(step.status.title) · \(reasons)"), after: 8)
        }
        c.space(10)
    }

    private func drawDetails(_ c: PDFCanvas) {
        let rows = builder.rows()
        for fw in frameworks {
            let fwRows = rows.filter { $0.framework.id == fw.id }
            c.beginPage()
            c.text(PDFStyle.heading("\(fw.document.shortName) requirements"), after: 4)
            c.text(PDFStyle.body(options.requirements.detail, color: PDFStyle.secondary), after: 12)
            guard !fwRows.isEmpty else {
                c.text(PDFStyle.body("No requirements match.", color: PDFStyle.secondary), after: 8)
                continue
            }
            let byGroup = Dictionary(grouping: fwRows, by: { $0.requirement.groupId })
            for group in fw.leafGroups {
                guard let groupRows = byGroup[group.id], !groupRows.isEmpty else { continue }
                c.keepTogether(70)
                let path = (fw.ancestors(ofGroup: group.id).map(\.title) + [group.title]).joined(separator: " · ")
                c.text(PDFStyle.label("\(group.displayId)  \(path.uppercased())"), after: 6)
                for row in groupRows { drawRequirement(row, canvas: c) }
                c.space(8)
            }
        }
    }

    private func drawRequirement(_ row: ExportRow, canvas c: PDFCanvas) {
        let r = row.requirement
        let response = row.response
        let status = row.status
        c.keepTogether(40)
        c.text(PDFStyle.requirementLine(r.displayId, r.title), after: 1)
        var meta = [status.title]
        if !row.inScope { meta.append("Outside scope") }
        if options.ownership {
            if let owner = response?.owner, !owner.isEmpty { meta.append("Owner: \(owner)") }
            if let date = response?.targetDate { meta.append("Target: \(date.formatted(date: .abbreviated, time: .omitted))") }
        }
        if options.profile && !row.framework.document.tiers.isEmpty, let priority = response?.priority {
            meta.append("\(priority.title) priority")
        }
        c.text(PDFStyle.status(meta.joined(separator: " · "), status: status), after: 2)
        if options.nistText {
            let values = options.parameters ? assessment.parameterValueMap(frameworkID: row.framework.id) : [:]
            let statement = StatementText.plain(r, in: row.framework, values: values)
            if !statement.isEmpty { c.text(PDFStyle.indented(statement, color: PDFStyle.secondary), after: 3) }
        }
        if options.notApplicableReasons, status == .notApplicable, let reason = response?.notApplicableReason, !reason.isEmpty {
            c.text(PDFStyle.indented("Not applicable because: \(reason)"), after: 2)
        }
        if options.notes, let notes = response?.notes, !notes.isEmpty {
            c.text(PDFStyle.indented(notes), after: 2)
        }
        if options.parameters {
            let params = builder.parameterLines(row)
            if !params.isEmpty { c.text(PDFStyle.indented(params.joined(separator: "\n")), after: 2) }
        }
        if options.evidence {
            let evidence = builder.evidenceLines(row)
            if !evidence.isEmpty {
                c.text(PDFStyle.indented(evidence.map { "Evidence · \($0)" }.joined(separator: "\n"), color: PDFStyle.secondary), after: 2)
            }
        }
        c.space(8)
    }

    private func snapshot<V: View>(_ view: V) -> UIImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

// MARK: - Canvas

/// Minimal page layout over Core Text: a cursor that flows text across pages, with header and footer.
@MainActor
final class PDFCanvas {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72 dpi
    static let margin: CGFloat = 54

    let context: UIGraphicsPDFRendererContext
    let header: String
    var cursorY: CGFloat = 0
    private(set) var pageNumber = 0

    init(context: UIGraphicsPDFRendererContext, header: String) {
        self.context = context
        self.header = header
    }

    var contentWidth: CGFloat { Self.pageRect.width - 2 * Self.margin }
    private var bottomLimit: CGFloat { Self.pageRect.height - Self.margin - 18 }
    var remaining: CGFloat { bottomLimit - cursorY }

    func beginPage(showHeader: Bool = true) {
        context.beginPage()
        pageNumber += 1
        cursorY = Self.margin
        guard showHeader else { return }
        let headerText = NSAttributedString(string: header, attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: PDFStyle.secondary])
        headerText.draw(at: CGPoint(x: Self.margin, y: Self.margin - 24))
        let footer = NSAttributedString(string: "Self-assessment. Not a certification.    Page \(pageNumber)",
                                        attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: PDFStyle.secondary])
        let size = footer.size()
        footer.draw(at: CGPoint(x: Self.pageRect.width - Self.margin - size.width, y: Self.pageRect.height - Self.margin + 6))
    }

    func space(_ points: CGFloat) {
        cursorY += points
        if cursorY > bottomLimit { beginPage() }
    }

    /// Starts a new page unless at least `height` points remain.
    func keepTogether(_ height: CGFloat) {
        if remaining < height { beginPage() }
    }

    func rule() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: Self.margin, y: cursorY))
        path.addLine(to: CGPoint(x: Self.margin + contentWidth, y: cursorY))
        PDFStyle.rule.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        cursorY += 10
    }

    func image(_ image: UIImage, height: CGFloat, after: CGFloat) {
        keepTogether(height)
        image.draw(in: CGRect(x: Self.margin, y: cursorY, width: contentWidth, height: height))
        cursorY += height + after
    }

    /// Draws attributed text at the cursor, continuing onto new pages as needed.
    func text(_ string: NSAttributedString, after: CGFloat) {
        guard string.length > 0, let cg = UIGraphicsGetCurrentContext() else { return }
        let setter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        var start = 0
        var freshPageAttempts = 0
        while start < string.length {
            if remaining < 14 { beginPage() }
            var fit = CFRange()
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(location: start, length: 0), nil,
                CGSize(width: contentWidth, height: remaining), &fit)
            if fit.length == 0 {
                freshPageAttempts += 1
                if freshPageAttempts > 1 { return } // a single line taller than a page; give up rather than loop
                beginPage()
                continue
            }
            freshPageAttempts = 0
            let height = ceil(size.height)
            cg.saveGState()
            cg.textMatrix = .identity
            cg.translateBy(x: 0, y: Self.pageRect.height)
            cg.scaleBy(x: 1, y: -1)
            let rect = CGRect(x: Self.margin, y: Self.pageRect.height - cursorY - height, width: contentWidth, height: height)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: fit.length), CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, cg)
            cg.restoreGState()
            cursorY += height
            start += fit.length
            if start < string.length { beginPage() }
        }
        cursorY += after
    }
}

// MARK: - Styles

/// Report typography and colors, derived from the design system (light appearance for print).
@MainActor
enum PDFStyle {
    static func color(_ token: ColorToken) -> UIColor {
        UIColor(red: token.light.red, green: token.light.green, blue: token.light.blue, alpha: 1)
    }

    static let primary = color(Palette.textPrimary)
    static let secondary = color(Palette.textSecondary)
    static let accent = color(Palette.accent)
    static let rule = UIColor(white: 0.85, alpha: 1)

    static func futura(_ bold: Bool, _ size: CGFloat) -> UIFont {
        UIFont(name: bold ? Typeface.futuraBold : Typeface.futuraMedium, size: size) ?? .boldSystemFont(ofSize: size)
    }

    private static func paragraph(spacing: CGFloat = 2, indent: CGFloat = 0, tab: CGFloat? = nil) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = spacing
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        if let tab { p.tabStops = [NSTextTab(textAlignment: .right, location: tab)] }
        return p
    }

    static func title(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: futura(true, 30), .foregroundColor: primary, .paragraphStyle: paragraph(spacing: 4)])
    }

    static func subtitle(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: futura(false, 16), .foregroundColor: secondary])
    }

    static func heading(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: futura(true, 20), .foregroundColor: primary])
    }

    static func subheading(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: futura(false, 14), .foregroundColor: accent])
    }

    static func big(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: futura(true, 18), .foregroundColor: primary])
    }

    static func label(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: futura(false, 8.5), .foregroundColor: secondary, .kern: 0.6])
    }

    static func body(_ s: String, color: UIColor = primary) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: color, .paragraphStyle: paragraph()])
    }

    static func small(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: secondary, .paragraphStyle: paragraph()])
    }

    static func indented(_ s: String, color: UIColor = primary) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 9.5), .foregroundColor: color, .paragraphStyle: paragraph(indent: 12)])
    }

    static func keyValue(_ key: String, _ value: String, width: CGFloat) -> NSAttributedString {
        let s = NSMutableAttributedString(string: key, attributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: primary, .paragraphStyle: paragraph(tab: width)])
        s.append(NSAttributedString(string: "\t" + value, attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: secondary, .paragraphStyle: paragraph(tab: width)]))
        return s
    }

    static func requirementLine(_ id: String, _ title: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: id + "  ", attributes: [.font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: accent, .paragraphStyle: paragraph()])
        s.append(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: primary, .paragraphStyle: paragraph()]))
        return s
    }

    static func status(_ s: String, status: RequirementStatus) -> NSAttributedString {
        let token: ColorToken
        switch status {
        case .notStarted: token = Palette.statusNotStarted
        case .inProgress: token = Palette.statusInProgress
        case .implemented: token = Palette.statusImplemented
        case .notApplicable: token = Palette.statusNotApplicable
        }
        return NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: color(token), .paragraphStyle: paragraph(indent: 12)])
    }

    static let disclaimer = "This report is a self-assessment prepared with FrameworkApp. It is not a certification, an audit, or a compliance attestation. FrameworkApp is independent and is not affiliated with or endorsed by the National Institute of Standards and Technology (NIST). Framework text comes from NIST publications; plain-language guidance in the app was written for the app and is not NIST text."
}
