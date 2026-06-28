import SwiftUI

struct ToDoView: View {
    var body: some View {
        ScrollView {
            Text("To Do")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("To Do")
    }
}

#Preview {
    NavigationStack {
        ToDoView()
    }
}
