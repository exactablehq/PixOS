import SwiftUI

public struct OnboardingView: View {
    var onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Welcome to PixOS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Text("Bypass iCloud limits using your Google Pixel's free unlimited original backup.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)

            // 3 Step Cards
            HStack(spacing: 16) {
                StepCard(
                    number: "1",
                    icon: "iphone.gen3",
                    title: "Connect iPhone",
                    subtitle: "Plug in your iPhone via Lightning/USB-C. Unlock your screen and tap 'Trust This Computer' if prompted.",
                    badgeColor: .blue
                )

                StepCard(
                    number: "2",
                    icon: "candybarphone",
                    title: "Connect Pixel",
                    subtitle: "Enable Developer Options & USB Debugging on your Pixel. Connect via USB or pair wirelessly over local Wi-Fi.",
                    badgeColor: .green
                )

                StepCard(
                    number: "3",
                    icon: "cloud.fill",
                    title: "Unlimited Cloud",
                    subtitle: "PixOS stages & pushes to /DCIM/iPhone/. Google Photos automatically uploads original quality photos for free!",
                    badgeColor: .purple
                )
            }
            .padding(.horizontal)

            Divider()

            // Pro Tip Alert
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Photos become Google Motion Photos")
                        .font(.subheadline.bold())
                    Text("PixOS packages your iPhone Live Photos with Google Camera XMP metadata so they play smoothly in Google Photos!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)

            // Dismiss Button
            Button(action: { onDismiss() }) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .frame(width: 680, height: 440)
        .padding()
    }
}

private struct StepCard: View {
    let number: String
    let icon: String
    let title: String
    let subtitle: String
    let badgeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text(number)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(badgeColor)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(badgeColor)
            }

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
