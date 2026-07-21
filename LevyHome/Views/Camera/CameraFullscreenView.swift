import SwiftUI

struct CameraFullscreenView: View {
    @ObservedObject var viewModel: CameraViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = viewModel.latestFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                VStack(spacing: AppSpacing.medium) {
                    ProgressView().tint(.white)
                    Text(fullscreenStatus)
                        .foregroundStyle(.white)
                }
            }

            controls

            if viewModel.audioMenuState == .visible {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.closeSpeakerControls() }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CameraSpeakerControlsView(viewModel: viewModel)
                    }
                }
                .padding(.trailing, 56)
                .padding(.bottom, 88)
            }
        }
        .statusBarHidden()
        .onAppear { CameraOrientation.lockLandscape() }
        .onDisappear { CameraOrientation.lockPortrait() }
    }

    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: closeFullscreen) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.46), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close fullscreen camera")
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.top, AppSpacing.large)

            Spacer()

            HStack(alignment: .bottom) {
                compactPanTiltPad
                Spacer()
                compactSecondaryControls
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var compactPanTiltPad: some View {
        VStack(spacing: 4) {
            compactPTZButton(.up, image: "chevron.up")
            HStack(spacing: 4) {
                compactPTZButton(.left, image: "chevron.left")
                Circle().fill(.black.opacity(0.38)).frame(width: 38, height: 38)
                compactPTZButton(.right, image: "chevron.right")
            }
            compactPTZButton(.down, image: "chevron.down")
        }
    }

    private func compactPTZButton(_ direction: CameraPanTiltDirection, image: String) -> some View {
        Button {
            Task { await viewModel.move(direction) }
        } label: {
            Image(systemName: image)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.46), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.movingDirection != nil || viewModel.sessionState != .live)
        .opacity(viewModel.movingDirection != nil || viewModel.sessionState != .live ? 0.5 : 1)
        .accessibilityLabel(direction.accessibilityLabel)
    }

    private var compactSecondaryControls: some View {
        HStack(spacing: AppSpacing.medium) {
            Button {
                Task { await viewModel.openSpeakerControls() }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.46), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Camera speaker controls")

            Image(systemName: "mic.fill")
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.46), in: Circle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Two-way talk")
                .accessibilityHint("Unavailable until a secure talkback transport is proven")
        }
    }

    private var fullscreenStatus: String {
        switch viewModel.sessionState {
        case .connecting: "Connecting…"
        case .unavailable: "Camera unavailable"
        case .placeholder, .live: "Waiting for video…"
        }
    }

    private func closeFullscreen() {
        CameraOrientation.lockPortrait()
        onClose()
    }
}
