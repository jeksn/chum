import AppKit
import Foundation
import SwiftUI
import ChumCore

struct AppChooserView: View {
    let onSelect: (AppChooserItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var apps: [AppChooserItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if filtered.isEmpty {
                Text("No matching apps")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            appIcon(for: item)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .lineLimit(1)
                                if let bundleID = item.bundleIdentifier {
                                    Text(bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 520)
        .background(.regularMaterial)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let found = AppScanner.installedApps()
                DispatchQueue.main.async {
                    apps = found
                    isLoading = false
                }
            }
        }
    }

    private var filtered: [AppChooserItem] {
        FuzzyMatch.ranked(apps, query: query) { $0.name }
    }

    @ViewBuilder
    private func appIcon(for item: AppChooserItem) -> some View {
        if let nsImage = item.icon {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
