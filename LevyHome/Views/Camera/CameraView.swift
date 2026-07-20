import SwiftUI

struct CameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: CameraViewModel

    init(cameraService: CameraService) {
        _viewModel = StateObject(wrappedValue: CameraViewModel(service: cameraService))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                AppScreenHeader(title: "Camera")

                videoCard

                HStack(alignment: .center, spacing: AppSpacing.xLarge) {
                    panTiltPad
                    secondaryControls
                }

                if let errorMessage = viewModel.errorMessage {
                    errorCard(errorMessage)
                }
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.xLarge * 3)
        }
        .appScreenChrome()
        .task { await viewModel.start() }
        .onDisappear { Task { await viewModel.stop() } }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                Task { await viewModel.stop() }
            }
        }
    }

    private var videoCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .fill(Color.black)

            if let frame = viewModel.latestFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                videoStateContent
            }

            VStack {
                HStack {
                    Label(statusLabel, systemImage: statusImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.medium)
                        .padding(.vertical, AppSpacing.small)
                        .background(.black.opacity(0.48), in: Capsule())
                    Spacer()
                }
                Spacer()
                HStack {
                    Text("Kids Room")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                    Spacer()
                }
            }
            .padding(AppSpacing.large)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kids Room camera")
        .accessibilityValue(statusLabel)
    }

    @ViewBuilder
    private var videoStateContent: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: statusImage)
                .font(.system(size: 34, weight: .medium))

            Text(statusLabel)
                .font(.headline)

            if case let .unavailable(message) = viewModel.sessionState {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.78))

                Button("Try Again") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding(AppSpacing.xLarge)
    }

    private var panTiltPad: some View {
        VStack(spacing: AppSpacing.small) {
            ptzButton(.up, systemImage: "chevron.up")
            HStack(spacing: AppSpacing.small) {
                ptzButton(.left, systemImage: "chevron.left")
                Circle()
                    .fill(AppColors.accentSoft)
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.accent))
                    .accessibilityHidden(true)
                ptzButton(.right, systemImage: "chevron.right")
            }
            ptzButton(.down, systemImage: "chevron.down")
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.large)
        .background(AppColors.panelBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private func ptzButton(_ direction: CameraPanTiltDirection, systemImage: String) -> some View {
        Button {
            Task { await viewModel.move(direction) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.text)
                .frame(width: 58, height: 58)
                .background(AppColors.insetPanelBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.movingDirection != nil || viewModel.sessionState != .live)
        .opacity(viewModel.movingDirection != nil || viewModel.sessionState != .live ? 0.48 : 1)
        .accessibilityLabel(direction.accessibilityLabel)
    }

    private var secondaryControls: some View {
        VStack(spacing: AppSpacing.large) {
            cameraControlButton(systemImage: "speaker.wave.2.fill", label: "Camera speaker controls")
            cameraControlButton(systemImage: "mic.fill", label: "Two-way talk")
        }
        .frame(width: 82)
    }

    private func cameraControlButton(systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(AppColors.mutedText)
            .frame(width: 58, height: 58)
            .background(AppColors.insetPanelBackground, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint("Available in a later camera stage")
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppColors.critical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.large)
            .background(AppColors.criticalSoft, in: RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
    }

    private var statusLabel: String {
        switch viewModel.sessionState {
        case .placeholder: "Not connected"
        case .connecting: "Connecting"
        case .live: "Live"
        case .unavailable: "Unavailable"
        }
    }

    private var statusImage: String {
        switch viewModel.sessionState {
        case .placeholder, .connecting: "video"
        case .live: "video.fill"
        case .unavailable: "video.slash"
        }
    }
}

#Preview {
    NavigationStack {
        CameraView(cameraService: CameraService(
            apiClient: APIClient(baseURL: URL(string: "https://example.com")!),
            cameraAccessToken: nil
        ))
    }
}
