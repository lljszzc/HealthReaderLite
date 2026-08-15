import SwiftUI

// MARK: - 添加订阅

struct AddFeedSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var folderID: UUID?
    @State private var fetchFullText = false
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("添加订阅")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            field("RSS / Atom 链接", required: true) {
                TextField("https://example.com/feed.xml", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
            }

            field("名称（可选）") {
                TextField("留空则自动抓取", text: $titleText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("放入文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $folderID) {
                    Text("未分组").tag(UUID?.none)
                    ForEach(store.folders) { folder in
                        Text(folder.name).tag(Optional(folder.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Toggle(isOn: $fetchFullText) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动抓取全文")
                        .font(.system(size: 12, weight: .medium))
                    Text("适用于只提供摘要的网站（如少数派 sspai），打开后自动抓取文章页全文")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(working ? "添加中…" : "添加") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 320)
    }

    private func field<Content: View>(_ title: String, required: Bool = false,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(required ? "\(title) *" : title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func submit() {
        guard !working else { return }
        working = true
        errorMessage = nil
        let store = self.store
        let urlText = self.urlText
        let folderID = self.folderID
        let titleText = self.titleText
        let fetchFullText = self.fetchFullText
        Task {
            let result = await store.addFeed(urlString: urlText, folderID: folderID,
                                             title: titleText, fetchFullText: fetchFullText)
            working = false
            switch result {
            case .success:
                dismiss()
            case .failure(let message):
                errorMessage = message.localizedDescription
            }
        }
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AppSettings = .defaultSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Form {
                Section("自动更新") {
                    Picker("刷新间隔", selection: $draft.refreshMinutes) {
                        ForEach([5, 10, 15, 30, 60, 120], id: \.self) { m in
                            Text("每 \(m) 分钟").tag(m)
                        }
                    }
                }
                Section("久坐提醒") {
                    Toggle("启用久坐提醒", isOn: $draft.reminderEnabled)
                    Picker("提醒间隔", selection: $draft.reminderMinutes) {
                        ForEach([30, 45, 60, 90, 120], id: \.self) { m in
                            Text("每 \(m) 分钟").tag(m)
                        }
                    }
                    .disabled(!draft.reminderEnabled)
                    Toggle("提醒时播放提示音", isOn: $draft.reminderSound)
                        .disabled(!draft.reminderEnabled)
                    Toggle("菜单栏显示久坐进度环", isOn: $draft.reminderRingEnabled)
                        .disabled(!draft.reminderEnabled)
                }
                Section("阅读") {
                    Toggle("打开文章时自动标记为已读", isOn: $draft.autoMarkRead)
                }
                Section("数据") {
                    Button {
                        NSWorkspace.shared.open(Log.appSupportDir)
                    } label: {
                        Label("打开数据文件夹", systemImage: "folder")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Text("HealthReaderLite \(AppDelegate.version)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("完成") {
                    store.settings = draft
                    store.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440, height: 440)
        .onAppear {
            draft = store.settings
        }
    }
}