import SwiftUI
import CoreSyncEngine
import AppKit

public final class SwipeCleanViewModel: ObservableObject {
    @Published public var dragOffset: CGSize = .zero
    @Published public var isProcessingPurge: Bool = false
    @Published public var purgeFeedbackMessage: String? = nil
    @Published public var showingConfirmAllDelete: Bool = false
    @Published public var thumbnails: [String: NSImage] = [:]

    public init() {}

    public func loadThumbnail(for item: MediaItem, sourceManager: PhotoKitSourceManager) {
        guard thumbnails[item.id] == nil else { return }
        Task {
            if let image = await sourceManager.loadThumbnailImage(for: item.id) {
                await MainActor.run {
                    self.thumbnails[item.id] = image
                }
            }
        }
    }
}

public struct ICloudSwipeCleanView: View {
    @ObservedObject var orchestrator: SyncOrchestrator
    @ObservedObject var vm: SwipeCleanViewModel
    var onDismiss: () -> Void

    public init(
        orchestrator: SyncOrchestrator,
        vm: SwipeCleanViewModel? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.orchestrator = orchestrator
        self.vm = vm ?? SwipeCleanViewModel()
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider().opacity(0.3)

                // Main Deck Area
                ZStack {
                    if orchestrator.triageQueue.isEmpty {
                        emptyDeckView
                    } else {
                        cardDeckView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)

                Divider().opacity(0.3)

                // Bottom Action Bar
                bottomActionControls
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            }
        }
        .frame(minWidth: 720, minHeight: 680)
        .onAppear {
            orchestrator.populateTriageQueue()
        }
        .background(
            KeyboardEventReceiver(
                onLeftArrow: { swipeTopCard(delete: true) },
                onRightArrow: { swipeTopCard(delete: false) },
                onUndo: { orchestrator.undoLastSwipe() }
            )
        )
        .alert("Purge All Synced from iCloud?", isPresented: $vm.showingConfirmAllDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Mark All for Deletion", role: .destructive) {
                orchestrator.markAllSyncedForDeletion()
            }
        } message: {
            Text("This will mark all \(orchestrator.triageQueue.count) remaining synced items for deletion from your iCloud Photo Library. Apple Photos will ask for final confirmation before moving them to Recently Deleted.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("iCloud Space Reclaimer")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("TINDER TRIAGE")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.18))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                    Text("Swipe Right to KEEP in iCloud • Swipe Left to DELETE from iCloud")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Metrics
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("iCloud Space to Free")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: orchestrator.totalICloudBytesFreed, countStyle: .file))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Marked to Purge")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(orchestrator.markedForICloudDeletion.count) items")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Triage")
            }
        }
    }

    // MARK: - Card Deck View

    private var cardDeckView: some View {
        ZStack {
            let items = Array(orchestrator.triageQueue.prefix(3).enumerated())

            ForEach(items.reversed(), id: \.element.id) { index, item in
                let isTopCard = (index == 0)

                SwipeCardView(
                    item: item,
                    thumbnail: vm.thumbnails[item.id],
                    dragOffset: isTopCard ? vm.dragOffset : .zero
                )
                .scaleEffect(isTopCard ? 1.0 : (1.0 - CGFloat(index) * 0.04))
                .offset(y: isTopCard ? 0 : CGFloat(index) * 12)
                .opacity(isTopCard ? 1.0 : (1.0 - Double(index) * 0.2))
                .allowsHitTesting(isTopCard)
                .onAppear {
                    vm.loadThumbnail(for: item, sourceManager: orchestrator.photoKitManager)
                }
                .gesture(
                    isTopCard ? DragGesture()
                        .onChanged { value in
                            vm.dragOffset = value.translation
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 130
                            if value.translation.width > threshold {
                                completeSwipe(item: item, delete: false)
                            } else if value.translation.width < -threshold {
                                completeSwipe(item: item, delete: true)
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    vm.dragOffset = .zero
                                }
                            }
                        } : nil
                )
            }
        }
    }

    private func swipeTopCard(delete: Bool) {
        guard let topItem = orchestrator.triageQueue.first else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            vm.dragOffset = CGSize(width: delete ? -400 : 400, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completeSwipe(item: topItem, delete: delete)
        }
    }

    private func completeSwipe(item: MediaItem, delete: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if delete {
                orchestrator.swipeDelete(item: item)
            } else {
                orchestrator.swipeKeep(item: item)
            }
            vm.dragOffset = .zero
        }
    }

    // MARK: - Empty Deck View

    private var emptyDeckView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.green)
            }

            VStack(spacing: 6) {
                Text("All Synced Items Reviewed!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("All photos in queue have been triaged. Your Pixel has original copies safe in Google Photos.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if !orchestrator.markedForICloudDeletion.isEmpty {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.red)
                        Text("\(orchestrator.markedForICloudDeletion.count) items ready to purge from iCloud (\(ByteCountFormatter.string(fromByteCount: orchestrator.totalICloudBytesFreed, countStyle: .file)))")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)

                    Button(action: executePurge) {
                        HStack(spacing: 8) {
                            if vm.isProcessingPurge {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text("Purge \(orchestrator.markedForICloudDeletion.count) Items from iCloud Now")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(vm.isProcessingPurge)
                }
                .padding(.top, 10)
            } else {
                Text("No items marked for iCloud deletion. All copies kept in iCloud.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
            }

            if let msg = vm.purgeFeedbackMessage {
                Text(msg)
                    .font(.caption.bold())
                    .foregroundColor(.green)
                    .padding(.top, 4)
            }

            Button("Done & Return to Dashboard", action: onDismiss)
                .buttonStyle(.bordered)
                .padding(.top, 16)
        }
        .padding(32)
    }

    // MARK: - Bottom Action Controls

    private var bottomActionControls: some View {
        HStack(spacing: 20) {
            // Delete / Left Button
            Button(action: { swipeTopCard(delete: true) }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Delete from iCloud")
                            .font(.system(size: 12, weight: .bold))
                        Text("Left Arrow (←)")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(Color.red.opacity(0.85))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(orchestrator.triageQueue.isEmpty)

            // Undo Button
            Button(action: { orchestrator.undoLastSwipe() }) {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 22))
                    Text("Undo (Z)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(orchestrator.markedForICloudDeletion.isEmpty && orchestrator.markedToKeepInICloud.isEmpty)
            .help("Undo previous swipe")

            // Keep / Right Button
            Button(action: { swipeTopCard(delete: false) }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Keep in iCloud")
                            .font(.system(size: 12, weight: .bold))
                        Text("Right Arrow (→)")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(Color.green.opacity(0.85))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(orchestrator.triageQueue.isEmpty)

            Spacer()

            // Purge Marked Button
            if !orchestrator.markedForICloudDeletion.isEmpty {
                Button(action: executePurge) {
                    HStack(spacing: 6) {
                        if vm.isProcessingPurge {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "flame.fill")
                        }
                        Text("Purge \(orchestrator.markedForICloudDeletion.count) from iCloud")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(vm.isProcessingPurge)
            }

            if !orchestrator.triageQueue.isEmpty {
                Button(action: { vm.showingConfirmAllDelete = true }) {
                    Text("Nuke All Synced")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Mark all remaining synced items for iCloud deletion")
            }
        }
    }

    private func executePurge() {
        vm.isProcessingPurge = true
        vm.purgeFeedbackMessage = nil
        Task {
            do {
                let deletedCount = try await orchestrator.purgeMarkedICloudAssets()
                await MainActor.run {
                    self.vm.isProcessingPurge = false
                    self.vm.purgeFeedbackMessage = "Successfully purged \(deletedCount) items from your iCloud Photo Library!"
                }
            } catch {
                await MainActor.run {
                    self.vm.isProcessingPurge = false
                    self.vm.purgeFeedbackMessage = "Error purging items: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Swipe Card View

private struct SwipeCardView: View {
    let item: MediaItem
    let thumbnail: NSImage?
    let dragOffset: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)

            VStack(spacing: 0) {
                // Media Preview
                ZStack {
                    Color.black.opacity(0.08)

                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipped()
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: item.mediaType == .video ? "video.fill" : "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text(item.filename)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Live Photo & Synced Badges
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Safe on Pixel")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                            .cornerRadius(6)

                            Spacer()

                            if item.isLivePhoto {
                                Text("LIVE PHOTO")
                                    .font(.system(size: 9, weight: .heavy))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.yellow.opacity(0.85))
                                    .foregroundColor(.black)
                                    .cornerRadius(4)
                            } else if item.mediaType == .video {
                                Text("VIDEO")
                                    .font(.system(size: 9, weight: .heavy))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)

                    // Dynamic Stamps
                    if dragOffset.width > 20 {
                        keepStamp
                    } else if dragOffset.width < -20 {
                        trashStamp
                    }
                }
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                // Card Bottom Metadata
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.filename)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        if let date = item.creationDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.formattedSize)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("iCloud space")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
            }
        }
        .frame(width: 480, height: 460)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(borderColor, lineWidth: 2)
        )
        .rotationEffect(.degrees(Double(dragOffset.width / 18)))
        .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
    }

    private var borderColor: Color {
        if dragOffset.width > 20 {
            let opacity = Double(min(1.0, dragOffset.width / 120))
            return Color.green.opacity(opacity)
        } else if dragOffset.width < -20 {
            let opacity = Double(min(1.0, -dragOffset.width / 120))
            return Color.red.opacity(opacity)
        } else {
            return Color.primary.opacity(0.08)
        }
    }

    private var keepStamp: some View {
        VStack {
            HStack {
                Text("KEEP IN ICLOUD")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green, lineWidth: 3))
                    .rotationEffect(.degrees(-15))
                    .opacity(min(1.0, Double(dragOffset.width / 120)))
                Spacer()
            }
            Spacer()
        }
        .padding(24)
    }

    private var trashStamp: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PURGE ICLOUD")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red, lineWidth: 3))
                    Text("Free \(item.formattedSize)")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
                .rotationEffect(.degrees(15))
                .opacity(min(1.0, Double(-dragOffset.width / 120)))
            }
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Keyboard Event Receiver for macOS

private struct KeyboardEventReceiver: NSViewRepresentable {
    var onLeftArrow: () -> Void
    var onRightArrow: () -> Void
    var onUndo: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onUndo = onUndo
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
        nsView.onUndo = onUndo
    }

    class KeyView: NSView {
        var onLeftArrow: (() -> Void)?
        var onRightArrow: (() -> Void)?
        var onUndo: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 123 { // Left arrow
                onLeftArrow?()
            } else if event.keyCode == 124 { // Right arrow
                onRightArrow?()
            } else if event.keyCode == 6 || (event.modifierFlags.contains(.command) && event.keyCode == 6) { // 'Z'
                onUndo?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
