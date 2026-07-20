import SwiftUI

struct CameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: CameraViewModel
    @State private var isFullscreen = false

    init(cameraService: CameraService) {
        _viewModel = StateObject(wrappedValue: CameraViewModel(service: cameraService))
    }

    var body: some View {
        ZStack {
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

            if viewModel.audioMenuState == .visible {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.closeSpeakerControls() }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CameraSpeakerControlsView(viewModel: viewModel)
                    }
                }
                .padding(.trailing, AppSpacing.screen)
                .padding(.bottom, 128)
            }
        }
        .appScreenChrome()
        .task { await viewModel.start() }
        .onDisappear {
            if !isFullscreen {
                Task { await viewModel.stop() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                Task { await viewModel.stop() }
            }
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            CameraFullscreenView(viewModel: viewModel) {
                isFullscreen = false
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
        .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .onTapGesture { isFullscreen = true }
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
            Button {
                Task { await viewModel.openSpeakerControls() }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .frame(width: 58, height: 58)
                    .background(AppColors.insetPanelBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Camera speaker controls")
            .accessibilityHint("Opens camera speaker volume controls")
            cameraControlButton(systemImage: "mic.fill", label: "Two-way talk")
        }
        .frame(width: 82)
    }

    private var speakerVolumePopover: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Camera speaker volume")
                        .font(.headline)
                        .foregroundStyle(AppColors.text)
                    Text("Controls the camera speaker, not phone playback or microphone sensitivity.")
                        .font(.caption)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    viewModel.closeSpeakerControls()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.mutedText)
                        .frame(width: 28, height: 28)
                        .background(AppColors.insetPanelBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close camera speaker controls")
            }

            if viewModel.isLoadingSpeakerVolume {
                HStack(spacing: AppSpacing.small) {
                    ProgressView()
                    Text("Reading camera speaker volume…")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                }
            } else {
                Slider(
                    value: Binding(
                        get: { Double(viewModel.speakerVolumeDraft) },
                        set: { viewModel.speakerVolumeDraft = Int($0.rounded()) }
                    ),
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            Task { await viewModel.applySpeakerVolume() }
                        }
                    }
                )
                .tint(AppColors.accent)
                .disabled(viewModel.isSavingSpeakerVolume)
                .accessibilityLabel("Camera speaker volume")
                .accessibilityValue("\(viewModel.speakerVolumeDraft) percent")
                .accessibilityHint("Controls the camera speaker. It does not control phone playback or microphone sensitivity.")

                HStack {
                    Text("0")
                    Spacer()
                    if viewModel.isSavingSpeakerVolume {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("\(viewModel.speakerVolumeDraft)%")
                    }
                    Spacer()
                    Text("100")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.mutedText)
            }
        }
        .frame(width: 292)
        .padding(AppSpacing.large)
        .background(AppColors.panelBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
        .shadow(color: AppColors.surfaceShadow.opacity(0.55), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
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
