// Offline simulator harness using the production View and ViewModel.
// Compile with the ios/ArcadeLinkClip/*.swift sources except ArcadeLinkClipApp.swift.
// Launch argument: loading, failure, cards-failure, expired, auth, or state-checks.
// hero-cache <image URL> verifies visible image loading and the cache across launches.
// Other scenes mock all ArcadeLink requests. state-checks verifies recovery/stale responses.
import SwiftUI
import Foundation

private final class PreviewProtocol: URLProtocol {
  static var scene = ProcessInfo.processInfo.arguments.dropFirst().first ?? "failure"
  static var starts = 0
  static var cardLoads = 0
  private var response: DispatchWorkItem?

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "link.neri.moe" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url!.path
    let scene = Self.scene
    if scene == "loading" { return }
    if path.hasSuffix("/start") { Self.starts += 1 }
    if path == "/api/cards" { Self.cardLoads += 1 }
    let fails = scene == "failure" && path.hasSuffix("/start") && Self.starts == 1 ||
      scene == "cards-failure" && path == "/api/cards" && Self.cardLoads == 1
    let work = DispatchWorkItem { [self] in
      if fails {
        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        return
      }
      let status = scene == "expired" ? 410 : 200
      let body: String
      if status == 410 {
        body = #"{"error":"本次会话已失效"}"#
      } else if path.hasSuffix("/start") {
        body = #"{"ticket":"preview","expiresIn":300,"machine":{"publicId":"preview","name":"舞萌","shop":{"name":"测试店铺","latitude":35,"longitude":139,"radiusMeters":80}}}"#
      } else if path == "/api/me" {
        body = scene == "auth" ? #"{"user":null}"# : #"{"user":{"id":"preview","username":"preview","displayName":"预览用户"}}"#
      } else {
        body = #"{"cards":[{"id":"1","label":"红黑卡","accessCode":"6958"}]}"#
      }
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
    response = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
  }
  override func stopLoading() { response?.cancel() }
}

@main
struct ClipPreviewApp: App {
  @StateObject private var model: MachineLoginViewModel
  @State private var checked = false
  @State private var heroHeight: CGFloat = 0

  init() {
    if PreviewProtocol.scene != "hero-cache" {
      URLProtocol.registerClass(PreviewProtocol.self)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PreviewProtocol.self]
    _model = StateObject(wrappedValue: MachineLoginViewModel(api: ArcadeLinkAPI(configuration: configuration)))
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if PreviewProtocol.scene == "hero-cache" {
          VStack {
            Text(heroHeight > 0 ? "Hero cache loaded" : "Waiting for hero")
            ClipHeroImage(url: URL(string: ProcessInfo.processInfo.arguments[2])!)
              .background {
                GeometryReader { geometry in
                  Color.clear
                    .onAppear { heroHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { heroHeight = $0 }
                }
              }
          }
        } else if checked { Text("State checks passed") } else { MachineLoginView().environmentObject(model) }
      }
      .task {
        if PreviewProtocol.scene == "state-checks" {
          await checkStates()
          checked = true
        } else if PreviewProtocol.scene != "hero-cache" {
          await model.start(shopCode: "preview", publicId: "preview")
        }
      }
    }
  }

  @MainActor private func checkStates() async {
    PreviewProtocol.scene = "failure"
    await model.start(shopCode: "preview", publicId: "preview")
    assert(model.state == .failed("网络连接失败，请检查网络后重试"))
    assert(model.errorMessage == nil)
    model.clearError()
    assert(model.state == .failed("网络连接失败，请检查网络后重试"))
    await model.start(shopCode: "preview", publicId: "preview")
    assert(model.state == .ready && model.cards.count == 1)

    PreviewProtocol.scene = "cards-failure"
    PreviewProtocol.cardLoads = 0
    await model.reloadCards()
    assert(model.state == .cardsFailed("网络连接失败，请检查网络后重试"))
    model.clearError()
    assert(model.state != .loadingCards)
    await model.reloadCards()
    assert(model.state == .ready)

    PreviewProtocol.scene = "expired"
    await model.start(shopCode: "preview", publicId: "preview")
    assert(model.state == .expired && model.errorMessage == nil)

    PreviewProtocol.scene = "ready"
    let pending = Task { await model.start(shopCode: "preview", publicId: "old") }
    await Task.yield()
    await model.handleInvocation(URL(string: "https://example.com/invalid")!)
    await pending.value
    assert(model.state == .failed("无效的机台地址"))
    assert(model.shopCode == nil && model.ticket == nil)
  }
}
