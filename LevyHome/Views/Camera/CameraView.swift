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
                    .frame(maxWidth: .infinity)

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
            if newPhase == .active {
                Task { await viewModel.start() }
            } else {
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
        RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
            .fill(Color.black)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        if let frame = viewModel.latestFrame {
                            Image(uiImage: frame)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
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
                                Button {
                                    isFullscreen = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(AppColors.text)
                                        .frame(width: 50, height: 50)
                                        .background(.white.opacity(0.92), in: Circle())
                                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open fullscreen camera")
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
                }
            }
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
        ZStack {
            portraitPTZButton(.up, systemImage: "chevron.up")
                .offset(y: -72)
            portraitPTZButton(.left, systemImage: "chevron.left")
                .offset(x: -72)
            portraitPTZButton(.right, systemImage: "chevron.right")
                .offset(x: 72)
            portraitPTZButton(.down, systemImage: "chevron.down")
                .offset(y: 72)
        }
        .frame(width: 236, height: 236)
    }

    private func portraitPTZButton(_ direction: CameraPanTiltDirection, systemImage: String) -> some View {
        Button {
            Task { await viewModel.move(direction) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(AppColors.text)
                .frame(width: 86, height: 86)
                .background(AppColors.panelBackground, in: Circle())
                .overlay {
                    Circle().stroke(cameraControlGold, lineWidth: 3)
                }
                .shadow(color: AppColors.surfaceShadow, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.movingDirection != nil || viewModel.sessionState != .live)
        .opacity(viewModel.movingDirection != nil || viewModel.sessionState != .live ? 0.48 : 1)
        .accessibilityLabel(direction.accessibilityLabel)
    }

    private var secondaryControls: some View {
        VStack(spacing: 20) {
            Button {
                Task { await viewModel.openSpeakerControls() }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(AppColors.text)
                    .frame(width: 72, height: 72)
                    .background(AppColors.panelBackground, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 2) }
                    .shadow(color: AppColors.surfaceShadow, radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Camera speaker controls")
            .accessibilityHint("Opens camera speaker volume controls")
            cameraControlButton(systemImage: "mic.fill", label: "Two-way talk")
        }
        .frame(width: 76)
    }

    private var cameraControlGold: Color {
        Color(red: 0.80, green: 0.59, blue: 0.13)
    }

    private func cameraControlButton(systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 27, weight: .medium))
            .foregroundStyle(AppColors.mutedText)
            .frame(width: 72, height: 72)
            .background(AppColors.panelBackground, in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 2) }
            .shadow(color: AppColors.surfaceShadow, radius: 10, y: 5)
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
