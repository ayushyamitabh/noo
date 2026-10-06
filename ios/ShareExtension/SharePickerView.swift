import SwiftUI

/// State behind the share sheet's folder picker.
@MainActor
final class ShareModel: ObservableObject {
  enum Stage: Equatable {
    case preparing
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

  let account: SharedAccount?

  /// Set by the view controller: what each button actually does.
  var onUpload: () -> Void = {}
  var onSaveForLater: () -> Void = {}
  var onCancel: () -> Void = {}

  init(account: SharedAccount?) {
    self.account = account
  }

  var currentFolderName: String {
    path == "/" ? "All files" : (path as NSString).lastPathComponent
  }

  var fileCountText: String {
    items.count == 1 ? "1 file" : "\(items.count) files"
  }

  func open(_ path: String) async {
    guard let account else { return }
    self.path = path
    isLoadingFolders = true
    folderError = nil
    defer { isLoadingFolders = false }
    do {
      folders = try await DavClient.listFolders(account: account, path: path)
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
    case .picking:
      folderList
    }
  }

  private var folderList: some View {
    List {
      Section(header: Text(model.account?.displayName ?? "")) {
        if model.path != "/" {
          Button {
            Task { await model.openParent() }
          } label: {
            Label("Up to \((model.path as NSString).deletingLastPathComponent == "/" ? "All files" : ((model.path as NSString).deletingLastPathComponent as NSString).lastPathComponent)", systemImage: "arrow.turn.left.up")
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
      if model.stage == .picking || model.stage == .noAccount {
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
