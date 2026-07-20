import SwiftUI

struct CameraSpeakerControlsView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
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
                        ProgressView().controlSize(.small)
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
}
