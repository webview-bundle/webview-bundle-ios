import Foundation
import SwiftUI
import WebKit
import WebViewBundle

@MainActor
final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate {
  @Published var status: String = "loading"
  let webView: WKWebView
  private var wvb: WebViewBundle?

  private static let entryURL = URL(string: "testapp://testbed.wvb")!

  override init() {
    var buildError: String?
    do {
      let instance = try WebViewBundle.configure(
        WebViewBundleConfig(
          protocols: [.bundle(scheme: "testapp")],
          updater: WebViewBundleUpdaterConfig(
            remote: WebViewBundleRemoteConfig(endpoint: "https://playground-remote.wvb.dev")
          )
        ))
      self.wvb = instance
      let config = WKWebViewConfiguration()
      instance.install(on: config)
      self.webView = WKWebView(frame: .zero, configuration: config)
    } catch {
      self.wvb = nil
      self.webView = WKWebView()
      buildError = "ERROR build \(error)"
    }
    super.init()
    webView.navigationDelegate = self
    if #available(iOS 16.4, *) {
      webView.isInspectable = true
    }
    if let buildError {
      print("error: \(buildError)")
    }
  }

  func start() {
    guard wvb != nil else { return }
    webView.load(URLRequest(url: Self.entryURL))
  }

  func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error
  ) {
    print("ERROR nav \(error.localizedDescription)")
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Swift.Error
  ) {
    print("ERROR provisional \(error.localizedDescription)")
  }
}

struct WebViewContainer: UIViewRepresentable {
  let webView: WKWebView
  func makeUIView(context: Context) -> WKWebView { webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
  @StateObject private var model = WebViewModel()

  var body: some View {
    VStack(spacing: 0) {
      WebViewContainer(webView: model.webView)
    }
    .onAppear { model.start() }
  }
}
