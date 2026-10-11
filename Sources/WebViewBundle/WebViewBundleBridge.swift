import Foundation

struct BundleNameArgs: Decodable { let bundleName: String }
struct BundleVersionArgs: Decodable {
  let bundleName: String
  let version: String
}
struct BundleNamesArgs: Decodable { let bundleNames: [String] }
struct ItemsArgs<T: Decodable>: Decodable { let items: [String: T] }
struct OptionsArgs<T: Decodable>: Decodable { let options: T? }
struct TargetsArgs: Decodable { let targets: [TargetArgs] }
struct TargetArgs: Decodable {
  let name: String
  let version: String?
}
struct RemoveArgs: Decodable {
  let bundleName: String
  let version: String
  let force: Bool?
}
struct StageArgs: Decodable {
  let bundleName: String
  let data: StageDataArgs
}
struct VersionDataArgs: Decodable {
  let integrity: String?
  let metadata: [String: String]?
  var native: ManifestVersionData { ManifestVersionData(integrity: integrity, metadata: metadata) }
}
struct StageDataArgs: Decodable {
  let version: String
  let data: VersionDataArgs?
  var native: ManifestStageData { ManifestStageData(version: version, data: data?.native) }
}
struct RemoveDataArgs: Decodable {
  let versions: [String]
  let force: Bool?
  var native: ManifestRemoveData { ManifestRemoveData(versions: versions, force: force) }
}
struct RemoteGetUpdateArgs: Decodable {
  let etag: String?
  let channel: String?
}
struct RemoteDownloadArgs: Decodable {
  let url: String
  let filepath: String
}
struct UpdaterGetUpdateArgs: Decodable { let expectSignatureKeyId: String? }
struct DownloadOptionsArgs: Decodable {
  let concurrency: UInt32?
  let timeout: UInt64?
}
struct BundleUpdateArgs: Decodable {
  let name: String
  let version: String
  let downloadUrl: String?
  let integrity: String?
  let metadata: [String: String]?
  var native: BundleUpdate {
    BundleUpdate(
      name: name, version: version, downloadUrl: downloadUrl,
      integrity: integrity, metadata: metadata)
  }
}
struct DownloadArgs: Decodable {
  let bundleUpdates: [BundleUpdateArgs]
  let options: DownloadOptionsArgs?
}

#if canImport(WebKit)
  struct WebViewBundleBridge: BridgeHandlers {
    private let source: Source
    private let remote: Remote?
    private let updater: Updater?

    init(wvb: WebViewBundle) {
      source = wvb.source
      remote = wvb.remote
      updater = wvb.updater
    }

    func register(on bridge: Bridge) {
      registerSource(on: bridge)
      registerRemote(on: bridge)
      registerUpdater(on: bridge)
    }

    private func registerSource(on bridge: Bridge) {
      let source = self.source
      bridge.handler("sourceListBundles") { _ in
        let value = try await source.listBundles()
        return try BridgeCodec.jsonObject(value.map(SourceListItemPayload.init))
      }
      bridge.handler("sourceListBuiltinBundles") { _ in
        let value = try await source.listBuiltinBundles()
        return try BridgeCodec.jsonObject(value.map(SourceListItemPayload.init))
      }
      bridge.handler("sourceListRemoteBundles") { _ in
        let value = try await source.listRemoteBundles()
        return try BridgeCodec.jsonObject(value.map(SourceListItemPayload.init))
      }
      bridge.handler("sourceGetVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        guard let value = try await source.getVersion(bundleName: args.bundleName) else {
          return nil
        }
        return try BridgeCodec.jsonObject(BundleSourceVersionPayload(value))
      }
      bridge.handler("sourceGetRemoteStagedVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await source.getRemoteStagedVersion(bundleName: args.bundleName)
      }
      bridge.handler("sourceGetRemotePreviousVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await source.getRemotePreviousVersion(bundleName: args.bundleName)
      }
      bridge.handler("sourceResolveFilepath") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return try await source.resolveFilepath(bundleName: args.bundleName)
      }
      bridge.handler("sourceUnload") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        return source.unload(bundleName: args.bundleName)
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
      bridge.handler("sourceGetBuiltinVersionData") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        guard
          let value = try await source.getBuiltinVersionData(
            bundleName: args.bundleName, version: args.version)
        else { return nil }
        return try BridgeCodec.jsonObject(ManifestVersionDataPayload(value))
      }
      bridge.handler("sourceGetRemoteVersionData") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        guard
          let value = try await source.getRemoteVersionData(
            bundleName: args.bundleName, version: args.version)
        else { return nil }
        return try BridgeCodec.jsonObject(ManifestVersionDataPayload(value))
      }
      bridge.handler("sourceUpdateRemoteVersion") { params in
        let args = try BridgeCodec.decode(params, as: BundleVersionArgs.self)
        let value = try await source.updateRemoteVersion(
          bundleName: args.bundleName, version: args.version)
        return try BridgeCodec.jsonObject(ManifestSetCurrentVersionResultPayload(value))
      }
      bridge.handler("sourceUpdateRemoteVersions") { params in
        let args = try BridgeCodec.decode(params, as: ItemsArgs<String>.self)
        let value = try await source.updateRemoteVersions(items: args.items)
        return try BridgeCodec.jsonObject(value.map(ManifestSetCurrentVersionResultPayload.init))
      }
      bridge.handler("sourceStageRemoteBundle") { params in
        let args = try BridgeCodec.decode(params, as: StageArgs.self)
        let value = try await source.stageRemoteBundle(
          bundleName: args.bundleName, data: args.data.native)
        return try BridgeCodec.jsonObject(ManifestStageResultPayload(value))
      }
      bridge.handler("sourceStageRemoteBundles") { params in
        let args = try BridgeCodec.decode(params, as: ItemsArgs<StageDataArgs>.self)
        let value = try await source.stageRemoteBundles(items: args.items.mapValues { $0.native })
        return try BridgeCodec.jsonObject(value.map(ManifestStageResultPayload.init))
      }
      bridge.handler("sourceRemoveRemoteBundles") { params in
        let args = try BridgeCodec.decode(params, as: ItemsArgs<RemoveDataArgs>.self)
        let value = try await source.removeRemoteBundles(items: args.items.mapValues { $0.native })
        return try BridgeCodec.jsonObject(value.map(ManifestRemoveResultPayload.init))
      }
      bridge.handler("sourceRemoveRemoteBundle") { params in
        let args = try BridgeCodec.decode(params, as: RemoveArgs.self)
        let value = try await source.removeRemoteBundle(
          bundleName: args.bundleName, version: args.version, force: args.force)
        return try BridgeCodec.jsonObject(ManifestRemoveResultPayload(value))
      }
      bridge.handler("sourcePruneRemoteBundle") { params in
        let args = try BridgeCodec.decode(params, as: BundleNameArgs.self)
        let value = try await source.pruneRemoteBundle(bundleName: args.bundleName)
        return try BridgeCodec.jsonObject(ManifestPruneResultPayload(value))
      }
      bridge.handler("sourcePruneRemoteBundles") { params in
        let args = try BridgeCodec.decode(params, as: BundleNamesArgs.self)
        let value = try await source.pruneRemoteBundles(bundleNames: args.bundleNames)
        return try BridgeCodec.jsonObject(value.map(ManifestPruneResultPayload.init))
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
      bridge.handler("remoteGetUpdate") { params in
        let args = try BridgeCodec.decode(params, as: OptionsArgs<RemoteGetUpdateArgs>.self)
        guard
          let response = try await require().getUpdate(
            options: args.options.map {
              RemoteGetUpdateOptions(etag: $0.etag, channel: $0.channel)
            })
        else { return nil }
        return try BridgeCodec.jsonObject(RemoteUpdateResponsePayload(response))
      }
      bridge.handler("remoteDownload") { params in
        let args = try BridgeCodec.decode(params, as: RemoteDownloadArgs.self)
        try await require().download(url: args.url, filepath: args.filepath)
        return nil
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
      bridge.handler("updaterGetUpdate") { params in
        let args = try BridgeCodec.decode(params, as: OptionsArgs<UpdaterGetUpdateArgs>.self)
        guard
          let update = try await require().getUpdate(
            options: args.options.map {
              UpdaterGetUpdateOptions(expectSignatureKeyId: $0.expectSignatureKeyId)
            })
        else { return nil }
        return try BridgeCodec.jsonObject(UpdatePayload(update))
      }
      bridge.handler("updaterDownload") { params in
        let args = try BridgeCodec.decode(params, as: DownloadArgs.self)
        let results = try await require().download(
          bundleUpdates: args.bundleUpdates.map { $0.native },
          options: args.options.map {
            UpdaterDownloadOptions(concurrency: $0.concurrency, timeout: $0.timeout)
          })
        return try BridgeCodec.jsonObject(results.map(UpdaterDownloadResultPayload.init))
      }
      bridge.handler("updaterInstall") { params in
        let args = try BridgeCodec.decode(params, as: TargetsArgs.self)
        let results = try await require().install(
          targets: args.targets.map {
            UpdaterInstallTarget(name: $0.name, version: $0.version)
          })
        return try BridgeCodec.jsonObject(results.map(UpdaterInstallResultPayload.init))
      }
      bridge.handler("updaterRollback") { params in
        let args = try BridgeCodec.decode(params, as: TargetsArgs.self)
        let results = try await require().rollback(
          targets: args.targets.map {
            UpdaterRollbackTarget(name: $0.name, version: $0.version)
          })
        return try BridgeCodec.jsonObject(results.map(UpdaterRollbackResultPayload.init))
      }
    }
  }
#endif
