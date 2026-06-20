import Foundation

// MARK: - Command arguments (Decodable)

struct BundleNameArgs: Decodable {
  let bundleName: String
}

struct BundleVersionArgs: Decodable {
  let bundleName: String
  let version: String
}

struct OptionalVersionArgs: Decodable {
  let bundleName: String
  let version: String?
}

struct ChannelArgs: Decodable {
  let channel: String?
}

struct BundleChannelArgs: Decodable {
  let bundleName: String
  let channel: String?
}

// MARK: - Response payloads (Encodable)

extension BundleSourceKind {
  /// `"builtin"` / `"remote"`, matching the web `BundleSourceKind` string union.
  var bridgeValue: String {
    switch self {
    case .builtin: return "builtin"
    case .remote: return "remote"
    }
  }
}

struct ManifestMetadataPayload: Encodable {
  let etag: String?
  let integrity: String?
  let signature: String?
  let lastModified: String?

  init(_ metadata: BundleManifestMetadata) {
    etag = metadata.etag
    integrity = metadata.integrity
    signature = metadata.signature
    lastModified = metadata.lastModified
  }
}

struct SourceVersionPayload: Encodable {
  let type: String
  let version: String

  init(_ value: BundleSourceVersion) {
    type = value.kind.bridgeValue
    version = value.version
  }
}

struct ListBundleItemPayload: Encodable {
  let type: String
  let name: String
  let version: String
  let current: Bool
  let metadata: ManifestMetadataPayload

  init(_ item: ListBundleItem) {
    type = item.kind.bridgeValue
    name = item.name
    version = item.version
    current = item.current
    metadata = ManifestMetadataPayload(item.metadata)
  }
}

struct ListRemoteBundlePayload: Encodable {
  let name: String
  let version: String

  init(_ info: ListRemoteBundleInfo) {
    name = info.name
    version = info.version
  }
}

struct RemoteBundlePayload: Encodable {
  let name: String
  let version: String
  let etag: String?
  let integrity: String?
  let signature: String?
  let lastModified: String?

  init(_ info: RemoteBundleInfo) {
    name = info.name
    version = info.version
    etag = info.etag
    integrity = info.integrity
    signature = info.signature
    lastModified = info.lastModified
  }
}

struct UpdateInfoPayload: Encodable {
  let name: String
  let version: String
  let localVersion: String?
  let isAvailable: Bool
  let etag: String?
  let integrity: String?
  let signature: String?
  let lastModified: String?

  init(_ info: BundleUpdateInfo) {
    name = info.name
    version = info.version
    localVersion = info.localVersion
    isAvailable = info.isAvailable
    etag = info.etag
    integrity = info.integrity
    signature = info.signature
    lastModified = info.lastModified
  }
}

#if canImport(WebKit)
  struct WebViewBundleBridge: BridgeHandlers {
    private let source: BundleSource
    private let remote: Remote?
    private let updater: Updater?

    init(wvb: WebViewBundle) {
      self.source = wvb.source
      self.remote = wvb.remote
      self.updater = wvb.updater
    }

    func register(on bridge: Bridge) {
      registerSource(on: bridge)
      registerRemote(on: bridge)
      registerUpdater(on: bridge)
    }

    private func registerSource(on bridge: Bridge) {
      let source = self.source
      bridge.handler("sourceListBundles") { _ in
        try await BridgeCodec.jsonObject(source.listBundles().map(ListBundleItemPayload.init))
      }
      bridge.handler("sourceLoadVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        guard let version = try await source.loadVersion(bundleName: args.bundleName) else {
          return nil
        }
        return try BridgeCodec.jsonObject(SourceVersionPayload(version))
      }
      bridge.handler("sourceUpdateVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        try await source.updateVersion(bundleName: args.bundleName, version: args.version)
        return nil
      }
      bridge.handler("sourceResolveFilepath") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await source.resolveFilepath(bundleName: args.bundleName)
      }
      bridge.handler("sourceGetBuiltinBundleFilepath") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        return try source.getBuiltinBundleFilepath(
          bundleName: args.bundleName, version: args.version)
      }
      bridge.handler("sourceGetRemoteBundleFilepath") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        return try source.getRemoteBundleFilepath(
          bundleName: args.bundleName, version: args.version)
      }
      bridge.handler("sourceLoadBuiltinMetadata") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        guard
          let metadata = try await source.loadBuiltinMetadata(
            bundleName: args.bundleName, version: args.version)
        else { return nil }
        return try BridgeCodec.jsonObject(ManifestMetadataPayload(metadata))
      }
      bridge.handler("sourceLoadRemoteMetadata") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        guard
          let metadata = try await source.loadRemoteMetadata(
            bundleName: args.bundleName, version: args.version)
        else { return nil }
        return try BridgeCodec.jsonObject(ManifestMetadataPayload(metadata))
      }
      bridge.handler("sourceUnloadDescriptor") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return source.unloadDescriptor(bundleName: args.bundleName)
      }
      bridge.handler("sourceRemoveRemoteBundle") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        return try await source.removeRemoteBundle(
          bundleName: args.bundleName, version: args.version)
      }
      bridge.handler("sourceRemoteRetainedVersions") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await source.remoteRetainedVersions(bundleName: args.bundleName)
      }
      bridge.handler("sourcePruneRemoteBundles") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await source.pruneRemoteBundles(bundleName: args.bundleName)
      }
    }

    private func registerRemote(on bridge: Bridge) {
      let remote = self.remote
      func require() throws -> Remote {
        guard let remote else {
          throw BridgeError(code: "remote_not_initialized", message: "remote is not initialized.")
        }
        return remote
      }
      bridge.handler("remoteListBundles") { params in
        let args = try BridgeCodec.decode(params, as: ChannelArgs.self)
        return try await BridgeCodec.jsonObject(
          require().listBundles(channel: args.channel).map(ListRemoteBundlePayload.init))
      }
      bridge.handler("remoteGetInfo") { params in
        let args = try BridgeCodec.decode(params, as: BundleChannelArgs.self)
        return try await BridgeCodec.jsonObject(
          RemoteBundlePayload(require().getInfo(bundleName: args.bundleName, channel: args.channel))
        )
      }
      bridge.handler("remoteDownload") { params in
        let args = try BridgeCodec.decode(params, as: BundleChannelArgs.self)
        let result = try await require().download(
          bundleName: args.bundleName, channel: args.channel)
        return try BridgeCodec.jsonObject(RemoteBundlePayload(result.info))
      }
      bridge.handler("remoteDownloadVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        let result = try await require().downloadVersion(
          bundleName: args.bundleName, version: args.version)
        return try BridgeCodec.jsonObject(RemoteBundlePayload(result.info))
      }
    }

    private func registerUpdater(on bridge: Bridge) {
      let updater = self.updater
      func require() throws -> Updater {
        guard let updater else {
          throw BridgeError(code: "updater_not_initialized", message: "updater is not initialized.")
        }
        return updater
      }
      bridge.handler("updaterListRemotes") { _ in
        try await BridgeCodec.jsonObject(require().listRemotes().map(ListRemoteBundlePayload.init))
      }
      bridge.handler("updaterGetUpdate") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await BridgeCodec.jsonObject(
          UpdateInfoPayload(require().getUpdate(bundleName: args.bundleName)))
      }
      bridge.handler("updaterDownload") { params in
        let args = try BridgeCodec.decode(params, as: OptionalVersionArgs.self)
        let info = try await require().downloadUpdate(
          bundleName: args.bundleName, version: args.version)
        return try BridgeCodec.jsonObject(RemoteBundlePayload(info))
      }
      bridge.handler("updaterInstall") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        try await require().install(bundleName: args.bundleName, version: args.version)
        return nil
      }
    }
  }
#endif
