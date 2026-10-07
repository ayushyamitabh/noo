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
  @Published var isLoadingFolders = false
  @Published var folderError: String?
  /// A short explanation shown under the list - e.g. hidden folders stayed
  /// hidden because the unlock was cancelled.
  @Published var notice: String?
  @Published private(set) var selected: SharedAccount?

  /// The sheet's two toggles. They start at the app's own setting for the
  /// chosen account and can be changed for this share only.
  @Published private(set) var hiddenFilter: HiddenFilter = .hide
  @Published private(set) var storageFilter: StorageFilter = .cloud

  /// Every child folder of [path], unfiltered; the toggles filter it live.
  @Published private var allFolders: [DavFolder] = []
  /// Mount points of external storage seen so far. Only the mount's root is
  /// flagged by the server, so anything under one of these is external too.
  private var externalRoots: Set<String> = []

  let shared: SharedAccounts?

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

  // MARK: - Folders, filtered by the toggles

  private func isExternal(_ folder: DavFolder) -> Bool {
    folder.isExternal
      || externalRoots.contains { folder.path == $0 || folder.path.hasPrefix($0 + "/") }
  }

  private var visibleFolders: [DavFolder] {
    allFolders.filter { hiddenFilter.shows(path: $0.path) && storageFilter.shows(isExternal: isExternal($0)) }
  }

  /// Internal folders - and, for "All", the external ones are listed apart.
  var internalFolders: [DavFolder] { visibleFolders.filter { !isExternal($0) } }
  var externalFolders: [DavFolder] { visibleFolders.filter { isExternal($0) } }

  // MARK: - Accounts

  /// With several accounts the list comes first; with one it goes straight
  /// to its folders.
  func start() async {
    guard let shared, let first = shared.accounts.first else {
      stage = .noAccount
      return
    }
    NSLog("[ShareExtension] %d account(s), active=%@", shared.accounts.count, shared.active?.id ?? "none")
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
  /// The toggles start at that account's own app settings; hidden folders
  /// are behind the app's "lock hidden files" unlock.
  func select(_ account: SharedAccount) async {
    guard let shared else { return }
    notice = nil
    var wantedHidden = HiddenFilter(raw: account.hiddenFilter)

    // Every selection asks again, like the app does for every switch - no
    // unlock is remembered. If one action needs both unlocks, one prompt
    // covers both.
    let needs = shared.unlockNeeds(choosing: account, showing: wantedHidden)
    if needs.needsPrompt {
      let reason = needs.switchesAccount
        ? "Unlock to upload to \(account.displayName)" : "Unlock to show hidden folders"
      if await !DeviceAuth.authenticate(reason: reason) {
        guard !needs.switchesAccount else {
          notice = "Unlock to upload to a different account."
          stage = .chooseAccount
          return
        }
        wantedHidden = .hide
        notice = "Hidden folders are locked, so they're not shown."
      }
    }
    NSLog("[ShareExtension] selected %@ (hidden=%@ storage=%@)", account.id, wantedHidden.rawValue, account.storageScope)
    selected = account
    externalRoots = []
    storageFilter = StorageFilter(raw: account.storageScope)
    hiddenFilter = wantedHidden
    stage = .picking
    await open("/")
  }

  // MARK: - Toggles

  /// Turning hidden folders *on* is what the app locks; going back to
  /// hiding them never exposes anything, and neither does switching
  /// between the two revealing modes.
  func setHiddenFilter(_ filter: HiddenFilter) async {
    guard filter != hiddenFilter else { return }
    if shared?.needsUnlockToChangeHidden(from: hiddenFilter, to: filter) == true {
      guard await DeviceAuth.authenticate(reason: "Unlock to show hidden folders") else {
        notice = "Hidden folders are locked, so they're not shown."
        return
      }
    }
    notice = nil
    hiddenFilter = filter
    await open("/")
  }

  func setStorageFilter(_ filter: StorageFilter) async {
    guard filter != storageFilter else { return }
    notice = nil
    storageFilter = filter
    await open("/")
  }

  // MARK: - Browsing

  /// A toggle can leave you inside a folder it now hides, so changing one
  /// always returns to the top - same as [open] with "/".
  func open(_ path: String) async {
    guard let account = selected else { return }
    self.path = path
    isLoadingFolders = true
    folderError = nil
    defer { isLoadingFolders = false }
    do {
      allFolders = try await DavClient.listFolders(account: account, path: path)
      externalRoots.formUnion(allFolders.filter(\.isExternal).map(\.path))
    } catch {
      allFolders = []
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
  @State private var externalExpanded = true

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

  // MARK: Folders

  private var folderList: some View {
    List {
      Section(header: accountHeader, footer: model.notice.map { Text($0) }) {
        filterRow
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
        } else if model.internalFolders.isEmpty && model.externalFolders.isEmpty {
          Text("No folders here").foregroundColor(.secondary)
        } else {
          ForEach(model.internalFolders, id: \.path) { folderRow($0) }
        }
      }
      // "All" keeps external storage in its own group, like the app's list.
      if !model.isLoadingFolders, model.folderError == nil, !model.externalFolders.isEmpty {
        Section {
          DisclosureGroup(isExpanded: $externalExpanded) {
            ForEach(model.externalFolders, id: \.path) { folderRow($0) }
          } label: {
            Label("External storage (\(model.externalFolders.count))", systemImage: "externaldrive")
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private func folderRow(_ folder: DavFolder) -> some View {
    Button {
      Task { await model.open(folder.path) }
    } label: {
      Label(folder.name, systemImage: folder.isExternal ? "externaldrive" : "folder")
    }
  }

  /// The two toggles, as menus - Hidden folders and External storage each
  /// start at the app's setting and can be changed for this share.
  private var filterRow: some View {
    HStack(spacing: 8) {
      Menu {
        Picker("Hidden folders", selection: hiddenBinding) {
          Text("Hide hidden folders").tag(HiddenFilter.hide)
          Text("Only hidden folders").tag(HiddenFilter.only)
          Text("Show all").tag(HiddenFilter.include)
        }
      } label: {
        chip("eye", "Hidden", hiddenTitle)
      }
      Menu {
        Picker("External storage", selection: storageBinding) {
          Text("Cloud only").tag(StorageFilter.cloud)
          Text("Only external storage").tag(StorageFilter.external)
          Text("All + external storage").tag(StorageFilter.all)
        }
      } label: {
        chip("externaldrive", "Storage", storageTitle)
      }
      Spacer()
    }
    .buttonStyle(.borderless)
  }

  private func chip(_ icon: String, _ name: String, _ value: String) -> some View {
    Label("\(name): \(value)", systemImage: icon)
      .font(.footnote.weight(.medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Capsule().fill(Color(.secondarySystemFill)))
  }

  private var hiddenBinding: Binding<HiddenFilter> {
    Binding(get: { model.hiddenFilter }, set: { value in Task { await model.setHiddenFilter(value) } })
  }

  private var storageBinding: Binding<StorageFilter> {
    Binding(get: { model.storageFilter }, set: { value in Task { await model.setStorageFilter(value) } })
  }

  private var hiddenTitle: String {
    switch model.hiddenFilter {
    case .hide: return "Hide"
    case .only: return "Only"
    case .include: return "All"
    }
  }

  private var storageTitle: String {
    switch model.storageFilter {
    case .cloud: return "Cloud"
    case .external: return "External"
    case .all: return "All"
    }
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
