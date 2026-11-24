import FrameworkKit
import SwiftUI

struct SettingsView: View {
    var selection: Binding<AppRoute?>?

    var body: some View {
        Group {
            if let selection {
                List(selection: selection) { rows }
            } else {
                List { rows }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
    }

    @ViewBuilder
    private var rows: some View {
        Section {
            NavigationLink(value: AppRoute.settings(.dataStorage)) {
                Label("Data and Privacy", systemImage: "lock.shield")
            }
        } header: {
            SectionHeader("Data")
        }
        Section {
            NavigationLink(value: AppRoute.settings(.about)) {
                Label("About", systemImage: "info.circle")
            }
            Link(destination: AppLinks.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: AppLinks.website) {
                Label("Website and Support", systemImage: "safari")
            }
        }
        #if DEBUG
        Section {
            NavigationLink(value: AppRoute.settings(.typeSpecimen)) { Label("Type Specimen", systemImage: "textformat") }
            NavigationLink(value: AppRoute.settings(.colorTokens)) { Label("Colors and Metrics", systemImage: "paintpalette") }
            NavigationLink(value: AppRoute.settings(.components)) { Label("Components", systemImage: "square.grid.2x2") }
            NavigationLink(value: AppRoute.settings(.content)) { Label("Framework Content", systemImage: "books.vertical") }
        } header: {
            SectionHeader("Design system (debug builds)")
        }
        #endif
    }
}

struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .about: AboutView()
        case .dataStorage: DataPrivacyView()
        #if DEBUG
        case .typeSpecimen: TypeSpecimenView()
        case .colorTokens: ColorTokensView()
        case .components: ComponentGalleryView()
        case .content: ContentOverviewView()
        #endif
        }
    }
}

struct DataPrivacyView: View {
    @AppStorage(AppDirectories.excludeFromBackupKey) private var excludeFromBackup = true

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Stored only on this device").font(.dsHeadline)
                        Text("Assessments, notes, and evidence never leave this device unless you export them. The app has no accounts, servers, analytics, or tracking.")
                            .font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                    }
                } icon: {
                    Image(systemName: "iphone").foregroundStyle(Color.dsAccent)
                }
                Label {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Encrypted when locked").font(.dsHeadline)
                        Text("Your data uses iOS complete data protection, so it cannot be read while the device is locked.")
                            .font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                    }
                } icon: {
                    Image(systemName: "lock").foregroundStyle(Color.dsAccent)
                }
            }

            Section {
                Link(destination: AppLinks.privacyPolicy) {
                    Label("Read the Privacy Policy", systemImage: "hand.raised")
                }
            }

            Section {
                Toggle("Exclude from device backups", isOn: $excludeFromBackup)
                    .onChange(of: excludeFromBackup) { _, _ in AppDirectories.applyBackupExclusion() }
            } footer: {
                Text("When on, assessment data is left out of iCloud and computer backups of this device, so it stays on this device only. If the device is lost or replaced, data that is not in an exported backup cannot be recovered.")
                    .font(.dsFootnote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data and Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @Environment(ContentLibrary.self) private var library

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "FrameworkApp")
                        .font(.dsTitle2)
                    Text(version).font(.dsFootnote.monospacedDigit()).foregroundStyle(Color.dsTextSecondary)
                }
                .padding(.vertical, DS.Space.xxs)
            }

            Section {
                Text("This app is independent and is not affiliated with, sponsored by, or endorsed by the National Institute of Standards and Technology (NIST).")
                    .font(.dsBody)
                Text("It is a self-assessment aid. Using it does not certify your organization, and its results are not a compliance attestation or an official assessment.")
                    .font(.dsBody)
            } header: {
                SectionHeader("Independence")
            }

            Section {
                ForEach(library.entries) { entry in
                    if let fw = library.framework(entry.id) {
                        let s = fw.document.source
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fw.document.title).font(.dsBody)
                            Text([fw.document.publicationId, s.catalogVersion.map { "Release \($0)" },
                                  s.retrieved.prefix(10).isEmpty ? nil : "Retrieved \(s.retrieved.prefix(10))"]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.dsFootnote)
                                .foregroundStyle(Color.dsTextSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Framework text, baselines, and mappings come from NIST's machine-readable OSCAL data and the NIST Cybersecurity and Privacy Reference Tool. Mappings are limited to those NIST publishes.")
                    .font(.dsFootnote)
                    .foregroundStyle(Color.dsTextSecondary)
            } header: {
                SectionHeader("Content sources")
            }

            Section {
                Text("Plain-language questions, explanations, and suggested next steps were written for this app. They are not NIST text. NIST's own wording is always available under NIST text on each requirement.")
                    .font(.dsBody)
            } header: {
                SectionHeader("Plain-language content")
            }

            Section {
                Link(destination: AppLinks.website) {
                    Label("Website and Support", systemImage: "safari")
                }
                Link(destination: AppLinks.privacyPolicy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            } header: {
                SectionHeader("More information")
            } footer: {
                Text("Links open in your browser. The app itself does not connect to the internet.")
                    .font(.dsFootnote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.about")
    }
}
