import SwiftUI

enum AppTheme {
    static let coral = Color(red: 0.96, green: 0.35, blue: 0.38)
    static let purple = Color(red: 0.44, green: 0.31, blue: 0.71)
    static let mint = Color(red: 0.33, green: 0.74, blue: 0.70)
    static let sunshine = Color(red: 1.00, green: 0.73, blue: 0.28)
    static let background = Color(red: 1.00, green: 0.97, blue: 0.91)
}

struct FamJamHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image("FamilyHero")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.purple)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}
