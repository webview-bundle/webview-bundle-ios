import Foundation

// Wire payloads mirror @wvb/bridge and keep generated FFI code untouched.

extension SourceKind {
  var bridgeValue: String {
    switch self {
    case .builtin: return "builtin"
    case .remote: return "remote"
    }
  }
}

extension ManifestBundleItemStatus {
  var bridgeValue: String {
    switch self {
    case .current: return "current"
    case .previous: return "previous"
    case .staged: return "staged"
    case .orphan: return "orphan"
    }
  }
}

extension ManifestStageResultKind {
  var bridgeValue: String {
    switch self {
    case .staged: return "staged"
    case .inUse: return "in_use"
    }
  }
}

extension ManifestSetCurrentVersionResultKind {
  var bridgeValue: String {
    switch self {
    case .settled: return "settled"
    case .notExists: return "not_exists"
    case .versionNotExists: return "version_not_exists"
    }
  }
}

extension ManifestRemoveResultKind {
  var bridgeValue: String {
    switch self {
    case .removed: return "removed"
    case .notExists: return "not_exists"
    case .versionNotExists: return "version_not_exists"
    case .inUse: return "in_use"
    }
  }
}

extension WebviewBundleError: BridgeFailure {
  public var code: String? {
    switch self {
    case .CoreIo: return "core.io"
    case .CoreCompress: return "core.compress"
    case .CoreDecompress: return "core.decompress"
    case .CoreEncode: return "core.encode"
    case .CoreDecode: return "core.decode"
    case .CoreHttp: return "core.http"
    case .CoreHttpInvalidUri: return "core.http_invalid_uri"
    case .CoreCancelled: return "core.cancelled"
    case .CoreTimeout: return "core.timeout"
    case .CoreInvalidMagicNum: return "core.invalid_magic_num"
    case .CoreInvalidVersion: return "core.invalid_version"
    case .CoreInvalidHeaderChecksum: return "core.invalid_header_checksum"
    case .CoreInvalidIndexChecksum: return "core.invalid_index_checksum"
    case .CoreChecksumMismatch: return "core.checksum_mismatch"
    case .CoreBundleNotFound: return "core.bundle_not_found"
    case .CoreInvalidFilepath: return "core.invalid_filepath"
    case .CoreSerdeJson: return "core.serde_json"
    case .CoreCannotResolveProxyServer: return "core.cannot_resolve_proxy_server"
    case .CoreHttpClient: return "core.http_client"
    case .CoreRemoteHttp: return "core.remote_http"
    case .CoreBadRemoteResponse: return "core.bad_remote_response"
    case .CoreInvalidRemoteConfig: return "core.invalid_remote_config"
    case .CoreInvalidUpdaterConfig: return "core.invalid_updater_config"
    case .CoreInvalidIntegrity: return "core.invalid_integrity"
    case .CoreIntegrityRequired: return "core.integrity_required"
    case .CoreIntegrityVerifyFailed: return "core.integrity_verify_failed"
    case .CoreInvalidSignature: return "core.invalid_signature"
    case .CoreInvalidSignatureKey: return "core.invalid_signature_key"
    case .CoreExpectSignatureNotFound: return "core.expect_signature_not_found"
    case .CoreSignatureVerifyFailed: return "core.signature_verify_failed"
    case .CoreGeneric: return "core.generic"
    case .BindingInvalidHeaderName: return "invalid_header_name"
    case .BindingInvalidHeaderValue: return "invalid_header_value"
    case .BindingInvalidSignatureOptions: return "invalid_signature_options"
    }
  }
  public var message: String {
    switch self {
    case .CoreIo(let message): return message
    case .CoreCompress(let message): return message
    case .CoreDecompress(let message): return message
    case .CoreEncode(let message): return message
    case .CoreDecode(let message): return message
    case .CoreHttp(let message): return message
    case .CoreHttpInvalidUri(let message): return message
    case .CoreCancelled(let message): return message
    case .CoreTimeout(let message): return message
    case .CoreInvalidMagicNum(let message): return message
    case .CoreInvalidVersion(let message): return message
    case .CoreInvalidHeaderChecksum(let message): return message
    case .CoreInvalidIndexChecksum(let message): return message
    case .CoreChecksumMismatch(let message): return message
    case .CoreBundleNotFound(let message): return message
    case .CoreInvalidFilepath(let message): return message
    case .CoreSerdeJson(let message): return message
    case .CoreCannotResolveProxyServer(let message): return message
    case .CoreHttpClient(let message): return message
    case .CoreRemoteHttp(let message): return message
    case .CoreBadRemoteResponse(let message): return message
    case .CoreInvalidRemoteConfig(let message): return message
    case .CoreInvalidUpdaterConfig(let message): return message
    case .CoreInvalidIntegrity(let message): return message
    case .CoreIntegrityRequired(let message): return message
    case .CoreIntegrityVerifyFailed(let message): return message
    case .CoreInvalidSignature(let message): return message
    case .CoreInvalidSignatureKey(let message): return message
    case .CoreExpectSignatureNotFound(let message): return message
    case .CoreSignatureVerifyFailed(let message): return message
    case .CoreGeneric(let message): return message
    case .BindingInvalidHeaderName(let message): return message
    case .BindingInvalidHeaderValue(let message): return message
    case .BindingInvalidSignatureOptions(let message): return message
    }
  }
}

struct UpdaterResultPayload: Encodable {
  let type: String
  var code: String? = nil
  var message: String? = nil
}

extension UpdaterDownloadResultKind {
  var bridgePayload: UpdaterResultPayload {
    switch self {
    case .downloaded: return UpdaterResultPayload(type: "downloaded")
    case .error(let error):
      return UpdaterResultPayload(type: "error", code: error.code, message: error.message)
    }
  }
}

extension UpdaterInstallResultKind {
  var bridgePayload: UpdaterResultPayload {
    switch self {
    case .installed: return UpdaterResultPayload(type: "installed")
    case .stagedVersionNotMatched: return UpdaterResultPayload(type: "staged_version_not_matched")
    case .stagedBundleNotExists: return UpdaterResultPayload(type: "staged_bundle_not_exists")
    case .verifyFailed: return UpdaterResultPayload(type: "verify_failed")
    case .error(let error):
      return UpdaterResultPayload(type: "error", code: error.code, message: error.message)
    }
  }
}

extension UpdaterRollbackResultKind {
  var bridgePayload: UpdaterResultPayload {
    switch self {
    case .rolledBack: return UpdaterResultPayload(type: "rolled_back")
    case .previousVersionNotMatched:
      return UpdaterResultPayload(type: "previous_version_not_matched")
    case .previousBundleNotExists: return UpdaterResultPayload(type: "previous_bundle_not_exists")
    case .verifyFailed: return UpdaterResultPayload(type: "verify_failed")
    case .error(let error):
      return UpdaterResultPayload(type: "error", code: error.code, message: error.message)
    }
  }
}

struct ManifestVersionDataPayload: Encodable {
  let integrity: String?
  let metadata: [String: String]?

  init(_ value: ManifestVersionData) {
    integrity = value.integrity
    metadata = value.metadata
  }
}

struct BundleSourceVersionPayload: Encodable {
  let source: String
  let version: String

  init(_ value: BundleSourceVersion) {
    source = value.source.bridgeValue
    version = value.version
  }
}

struct ManifestBundleItemPayload: Encodable {
  let name: String
  let version: String
  let status: String
  let data: ManifestVersionDataPayload

  init(_ value: ManifestBundleItem) {
    name = value.name
    version = value.version
    status = value.status.bridgeValue
    data = ManifestVersionDataPayload(value.data)
  }
}

struct SourceListItemPayload: Encodable {
  let source: String
  let item: ManifestBundleItemPayload

  init(_ value: SourceListItem) {
    source = value.source.bridgeValue
    item = ManifestBundleItemPayload(value.item)
  }
}

struct ManifestStageResultPayload: Encodable {
  let name: String
  let version: String
  let kind: String

  init(_ value: ManifestStageResult) {
    name = value.name
    version = value.version
    kind = value.kind.bridgeValue
  }
}

struct ManifestSetCurrentVersionResultPayload: Encodable {
  let name: String
  let version: String
  let kind: String

  init(_ value: ManifestSetCurrentVersionResult) {
    name = value.name
    version = value.version
    kind = value.kind.bridgeValue
  }
}

struct ManifestRemoveResultPayload: Encodable {
  let name: String
  let version: String
  let kind: String

  init(_ value: ManifestRemoveResult) {
    name = value.name
    version = value.version
    kind = value.kind.bridgeValue
  }
}

struct ManifestPruneResultPayload: Encodable {
  let name: String
  let prunedVersions: [String]

  init(_ value: ManifestPruneResult) {
    name = value.name
    prunedVersions = value.prunedVersions
  }
}

struct BundleUpdatePayload: Encodable {
  let name: String
  let version: String
  let downloadUrl: String?
  let integrity: String?
  let metadata: [String: String]?

  init(_ value: BundleUpdate) {
    name = value.name
    version = value.version
    downloadUrl = value.downloadUrl
    integrity = value.integrity
    metadata = value.metadata
  }
}

struct UpdatePayload: Encodable {
  let id: String
  let createdAt: String
  let runtimeVersion: UInt8
  let bundles: [BundleUpdatePayload]
  let metadata: [String: String]?

  init(_ value: Update) {
    id = value.id
    createdAt = value.createdAt
    runtimeVersion = value.runtimeVersion
    bundles = value.bundles.map(BundleUpdatePayload.init)
    metadata = value.metadata
  }
}

struct UpdateSignaturePayload: Encodable {
  let keyId: String
  let sig: String
  let alg: String

  init(_ value: UpdateSignature) {
    keyId = value.keyId
    sig = value.sig
    alg = value.alg
  }
}

struct RemoteUpdateResponsePayload: Encodable {
  let update: UpdatePayload
  let etag: String?
  let signature: UpdateSignaturePayload?

  init(_ value: RemoteUpdateResponse) {
    update = UpdatePayload(value.update)
    etag = value.etag
    signature = value.signature.map(UpdateSignaturePayload.init)
  }
}

struct UpdaterDownloadResultPayload: Encodable {
  let name: String
  let version: String
  let integrity: String?
  let metadata: [String: String]?
  let result: UpdaterResultPayload

  init(_ value: UpdaterDownloadResult) {
    name = value.name
    version = value.version
    integrity = value.integrity
    metadata = value.metadata
    result = value.result.bridgePayload
  }
}

struct UpdaterInstallResultPayload: Encodable {
  let name: String
  let targetVersion: String?
  let installVersion: String?
  let result: UpdaterResultPayload

  init(_ value: UpdaterInstallResult) {
    name = value.name
    targetVersion = value.targetVersion
    installVersion = value.installVersion
    result = value.result.bridgePayload
  }
}

struct UpdaterRollbackResultPayload: Encodable {
  let name: String
  let targetVersion: String?
  let rollbackVersion: String?
  let result: UpdaterResultPayload

  init(_ value: UpdaterRollbackResult) {
    name = value.name
    targetVersion = value.targetVersion
    rollbackVersion = value.rollbackVersion
    result = value.result.bridgePayload
  }
}
