import SwiftUI

/// State behind the share sheet's account and folder pickers.
@MainActor
final class ShareModel: ObservableObject {
  enum Stage: Equatable {
    case preparing
    case chooseAccount
    case picking
    case uploading
    case noAccount
    case failed(String)
  }

  @Published var stage: Stage = .preparing
  @Published var items: [SharedItem] = []
  @Published var path = "/"
  @Published var folders: [DavFolder] = []
  @Published var isLoadingFolders = false
  @Published var folderError: String?
  /// A short explanation shown under the list - e.g. hidden folders stayed
  /// hidden because the unlock was cancelled.
  @Published var notice: String?
  @Published private(set) var selected: SharedAccount?

  let shared: SharedAccounts?

  /// One successful unlock covers every gate for the rest of this sheet.
  private var unlocked = false
  private var hidden: HiddenFilter = .hide

  /// Set by the view controller: what each button actually does.
  var onUpload: () -> Void = {}
  var onSaveForLater: () -> Void = {}
  var onCancel: () -> Void = {}

  init(shared: SharedAccounts?) {
    self.shared = shared
  }

  var accounts: [SharedAccount] { shared?.accounts ?? [] }
  var canChangeAccount: Bool { accounts.count > 1 }
  var activeAccountId: String? { shared?.active?.id }

  var currentFolderName: String {
    path == "/" ? "All files" : (path as NSString).lastPathComponent
  }

  var fileCountText: String {
    items.count == 1 ? "1 file" : "\(items.count) files"
  }

  /// With several accounts the list comes first; with one it goes straight
  /// to its folders.
  func start() async {
    guard let shared, let first = shared.accounts.first else {
      stage = .noAccount
      return
    }
    if shared.accounts.count > 1 {
      stage = .chooseAccount
    } else {
      await select(first)
    }
  }

  func showAccounts() {
    notice = nil
    stage = .chooseAccount
  }

  /// Uploading to an account other than the one the app is on is "switching"
  /// in the app's terms, so it asks for the same unlock when the app does.
  /// Hidden folders follow the account's own app setting, behind the app's
  /// "lock hidden files" unlock.
  func select(_ account: SharedAccount) async {
    guard let shared else { return }
    notice = nil
    if account.id != shared.active?.id, shared.needsUnlockToSwitchAccount {
      guard await unlock("Unlock to upload to \(account.displayName)") else {
        notice = "Unlock to upload to a different account."
        stage = .chooseAccount
        return
      }
    }
    selected = account
    hidden = HiddenFilter(raw: account.hiddenFilter)
    if hidden != .hide, shared.needsUnlockForHidden {
      if await !unlock("Unlock to show hidden folders") {
        hidden = .hide
        notice = "Hidden folders are locked, so they're not shown."
      }
    }
    stage = .picking
    await open("/")
  }

  private func unlock(_ reason: String) async -> Bool {
    if unlocked { return true }
    let ok = await DeviceAuth.authenticate(reason: reason)
    if ok { unlocked = true }
    return ok
  }

  func open(_ path: String) async {
    guard let account = selected else { return }
    self.path = path
    isLoadingFolders = true
    folderError = nil
    defer { isLoadingFolders = false }
    do {
      folders = try await DavClient.listFolders(account: account, path: path, hidden: hidden)
    } catch {
      folders = []
      folderError = error.localizedDescription
    }
  }

  func openParent() async {
    let parent = (path as NSString).deletingLastPathComponent
    await open(parent.isEmpty ? "/" : parent)
  }
}

struct SharePickerView: View {
  @ObservedObject var model: ShareModel

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .background(Color(.systemBackground))
  }

  private var header: some View {
    HStack {
      Button("Cancel", action: model.onCancel)
      Spacer()
      Text("Upload to Noo").font(.headline)
      Spacer()
      // Balances Cancel so the title stays centred.
      Button("Cancel", action: {}).hidden()
    }
    .padding(.horizontal)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var content: some View {
    switch model.stage {
    case .preparing:
      centered { ProgressView("Preparing \(model.items.isEmpty ? "" : model.fileCountText)…") }
    case .uploading:
      centered {
        VStack(spacing: 8) {
          ProgressView()
          Text("Uploading \(model.fileCountText) in the background").font(.subheadline)
        }
      }
    case .noAccount:
      centered {
        Text("Sign in to Noo first, then share again. You can also save these files and choose a folder from inside Noo.")
          .multilineTextAlignment(.center)
          .foregroundColor(.secondary)
          .padding()
      }
    case .failed(let message):
      centered {
        Text(message).multilineTextAlignment(.center).foregroundColor(.secondary).padding()
      }
    case .chooseAccount:
      accountList
    case .picking:
      folderList
    }
  }

  private var accountList: some View {
    List {
      Section(
        header: Text("Upload \(model.fileCountText) to which account?"),
        footer: model.notice.map { Text($0) }
      ) {
        ForEach(model.accounts) { account in
          Button {
            Task { await model.select(account) }
          } label: {
            HStack {
              Label(account.displayName, systemImage: "person.crop.circle")
              Spacer()
              if account.id == model.activeAccountId {
                Text("Active").font(.caption).foregroundColor(.secondary)
              }
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private var folderList: some View {
    List {
      Section(
        header: accountHeader,
        footer: model.notice.map { Text($0) }
      ) {
        if model.path != "/" {
          Button {
            Task { await model.openParent() }
          } label: {
            Label("Up to \(parentName)", systemImage: "arrow.turn.left.up")
          }
        }
        if model.isLoadingFolders {
          HStack { Spacer(); ProgressView(); Spacer() }
        } else if let error = model.folderError {
          Text(error).foregroundColor(.secondary)
        } else if model.folders.isEmpty {
          Text("No folders here").foregroundColor(.secondary)
        } else {
          ForEach(model.folders, id: \.path) { folder in
            Button {
              Task { await model.open(folder.path) }
            } label: {
              Label(folder.name, systemImage: "folder")
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private var accountHeader: some View {
    HStack {
      Text(model.selected?.displayName ?? "")
      Spacer()
      if model.canChangeAccount {
        Button("Change account") { model.showAccounts() }
          .font(.caption)
      }
    }
  }

  private var parentName: String {
    let parent = (model.path as NSString).deletingLastPathComponent
    return parent.isEmpty || parent == "/" ? "All files" : (parent as NSString).lastPathComponent
  }

  private var footer: some View {
    VStack(spacing: 8) {
      if model.stage == .picking {
        Button(action: model.onUpload) {
          Text("Upload \(model.fileCountText) to \(model.currentFolderName)")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isLoadingFolders)
      }
      if model.stage == .picking || model.stage == .chooseAccount || model.stage == .noAccount {
        Button("Choose a folder later in Noo", action: model.onSaveForLater)
          .font(.subheadline)
      }
    }
    .padding()
  }

  private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack { Spacer(); content(); Spacer() }.frame(maxWidth: .infinity)
  }
}
