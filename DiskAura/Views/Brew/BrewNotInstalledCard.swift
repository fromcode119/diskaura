import SwiftUI

/// Homebrew absent. A first-class state with an explanation — an empty package list would imply
/// "you have nothing installed", which is a different and wrong message.
struct BrewNotInstalledCard: View {
    let accent: Color
    let onOpenWebsite: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 84, height: 84)
                Image(systemName: "shippingbox").font(.system(size: 34)).foregroundColor(accent)
            }
            VStack(spacing: 6) {
                Text("Homebrew isn't installed").font(Theme.TypeScale.title)
                Text("Homebrew is the package manager DiskAura manages here. Install it first, then "
                     + "come back — your packages, updates and reclaimable space appear automatically.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            Button { onOpenWebsite() } label: {
                Label("Open brew.sh", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.pill(accent))
            Text("DiskAura doesn't install Homebrew for you — that script needs admin rights and "
                 + "should come from Homebrew itself, not from us.")
                .font(.system(size: 10.5)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
