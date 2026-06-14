import Foundation
import Testing

@testable import WebViewBundle

@Suite("WebViewBundle")
struct WebViewBundleTests {
    /// Builds a one-bundle source on disk: a `.wvb` with the given entries plus a
    /// manifest pinning it as the current remote version. Returns the source.
    private func makeSource(
        bundleName: String = "app",
        version: String = "1.0.0",
        entries: [(path: String, data: Data, contentType: String)]
    ) throws -> BundleSource {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wvb-test-\(UUID().uuidString)")
        let remote = tmp.appendingPathComponent("remote")
        let builtin = tmp.appendingPathComponent("builtin")
        let bundleDir = remote.appendingPathComponent(bundleName)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: builtin, withIntermediateDirectories: true)

        let manifest = #"{"manifestVersion":1,"entries":{"\#(bundleName)":{"versions":{"\#(version)":{}},"currentVersion":"\#(version)"}}}"#
        try Data(manifest.utf8).write(to: remote.appendingPathComponent("manifest.json"))

        let builder = BundleBuilder(version: nil)
        for entry in entries {
            _ = try builder.insertEntry(
                path: entry.path,
                data: entry.data,
                contentType: entry.contentType,
                headers: nil
            )
        }
        let bundle = try builder.build(options: nil)
        let bytes = try writeBundleToBytes(bundle: bundle)
        try bytes.write(to: bundleDir.appendingPathComponent("\(bundleName)_\(version).wvb"))

        return BundleSource(config: BundleSourceConfig(
            builtinDir: builtin.path,
            remoteDir: remote.path,
            builtinManifestFilepath: nil,
            remoteManifestFilepath: nil
        ))
    }

    @Test("BundleUrlHandler serves an entry as 200")
    func bundleHandlerServesEntry() async throws {
        let html = "<!DOCTYPE html><title>hi</title>"
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data(html.utf8), contentType: "text/html")
        ])
        let handler: any WebViewBundleRequestHandler = BundleUrlHandler(source: source)

        let response = try await handler.handle(
            method: .get,
            uri: "app://app.wvb/index.html",
            headers: nil
        )

        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == html)
        #expect(response.headers["content-type"]?.contains("text/html") == true)
    }

    @Test("Missing entry returns 404")
    func missingEntryIs404() async throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        let handler: any WebViewBundleRequestHandler = BundleUrlHandler(source: source)

        let response = try await handler.handle(
            method: .get,
            uri: "app://app.wvb/missing.html",
            headers: nil
        )

        #expect(response.status == 404)
    }

    @Test("Facade exposes its schemes")
    func facadeSchemes() throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        let wvb = try WebViewBundle(
            source: source,
            protocols: [.bundle(scheme: "app"), .local(scheme: "local", hosts: ["myapp": "http://localhost:8080"])]
        )

        #expect(wvb.schemes == ["app", "local"])
        #expect(wvb.remote == nil)
        #expect(wvb.updater == nil)
    }

    @Test("Duplicate scheme throws instead of trapping")
    func duplicateSchemeThrows() throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        #expect(throws: WebViewBundleError.duplicateScheme("app")) {
            _ = try WebViewBundle(
                source: source,
                protocols: [.bundle(scheme: "app"), .bundle(scheme: "app")]
            )
        }
    }

    @Test("Empty scheme throws instead of trapping")
    func emptySchemeThrows() throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        #expect(throws: WebViewBundleError.emptyScheme) {
            _ = try WebViewBundle(source: source, protocols: [.bundle(scheme: "")])
        }
    }

    @Test("Invalid scheme throws instead of trapping")
    func invalidSchemeThrows() throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        #expect(throws: WebViewBundleError.invalidScheme("1app")) {
            _ = try WebViewBundle(source: source, protocols: [.bundle(scheme: "1app")])
        }
    }

    @Test("Reserved scheme throws instead of trapping")
    func reservedSchemeThrows() throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        #expect(throws: WebViewBundleError.reservedScheme("https")) {
            _ = try WebViewBundle(source: source, protocols: [.bundle(scheme: "https")])
        }
    }

    @Test("Case-insensitive duplicate scheme throws")
    func caseInsensitiveDuplicateSchemeThrows() throws {
        let source = try makeSource(entries: [
            (path: "/index.html", data: Data("ok".utf8), contentType: "text/html")
        ])
        #expect(throws: WebViewBundleError.duplicateScheme("App")) {
            _ = try WebViewBundle(
                source: source,
                protocols: [.bundle(scheme: "app"), .bundle(scheme: "App")]
            )
        }
    }

    @Test("HttpMethod maps from request strings")
    func httpMethodFrom() {
        #expect(HttpMethod.from("get") == .get)
        #expect(HttpMethod.from("POST") == .post)
        #expect(HttpMethod.from(nil) == .get)
        #expect(HttpMethod.from("weird") == .get)
    }
}
