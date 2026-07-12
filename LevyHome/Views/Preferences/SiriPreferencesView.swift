import AppIntents
import Intents
import SwiftUI
import UIKit

struct SiriPreferencesView: View {
    @ObservedObject var authorizationService: SiriAuthorizationService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        InfoPanel(title: "Siri", subtitle: nil, systemImage: "waveform") {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: statusIcon)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(statusTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(statusDetail)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                    }

                    Spacer()
                }

                actionButton

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Voice request format")
                        .font(.subheadline.weight(.semibold))
                    Text("Ask Siri to add one item at a time to Shopping or To Do in Levy Home. More exact examples will appear after device validation.")
                        .font(.footnote)
                        .foregroundStyle(AppColors.mutedText)
                }

                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
            }
        }
        .onAppear { authorizationService.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                authorizationService.refresh()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch authorizationService.status {
        case .notDetermined:
            Button("Enable Siri") {
                authorizationService.requestAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        case .denied, .restricted:
            Button("Open Settings") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                UIApplication.shared.open(settingsURL)
            }
            .buttonStyle(.bordered)
        case .authorized:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    private var statusIcon: String {
        switch authorizationService.status {
        case .authorized: return "checkmark.circle.fill"
        case .notDetermined: return "waveform"
        case .denied, .restricted: return "exclamationmark.triangle.fill"
        @unknown default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch authorizationService.status {
        case .authorized: return AppColors.success
        case .notDetermined: return AppColors.accent
        case .denied, .restricted: return AppColors.warning
        @unknown default: return AppColors.mutedText
        }
    }

    private var statusTitle: String {
        switch authorizationService.status {
        case .authorized: return "Siri is ready"
        case .notDetermined: return "Enable Siri"
        case .denied: return "Siri access is off"
        case .restricted: return "Siri access is restricted"
        @unknown default: return "Siri status unavailable"
        }
    }

    private var statusDetail: String {
        switch authorizationService.status {
        case .authorized: return "You can use Siri with Levy Home."
        case .notDetermined: return "Allow Siri to use Levy Home for shared lists."
        case .denied: return "Turn on Siri access in Settings to use Levy Home with Siri."
        case .restricted: return "Siri access is limited by this iPhone’s settings."
        @unknown default: return "Open Settings to review Siri access."
        }
    }
}
