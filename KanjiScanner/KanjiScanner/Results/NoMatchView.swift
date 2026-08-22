import SwiftUI

/// Shown when OCR recognized a character but it has no dictionary entry —
/// e.g. a proper noun or non-standard character (US-6 AC).
struct NoMatchView: View {
    let token: String

    var body: some View {
        VStack(spacing: 12) {
            Text(token)
                .font(.system(size: 64))
            Text("No dictionary entry found")
                .font(.title3)
                .bold()
            Text("This character was recognized but doesn't have an entry in the dictionary.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}
