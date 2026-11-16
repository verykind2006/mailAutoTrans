import Cocoa
import Darwin
import FlutterMacOS
import MLXLLM
import MLXLMCommon

/// 本机翻译模型：Dart 通过平台通道 mailautotrans/local_model 调这里。
/// 加载 / 生成的写法照搬 autoTransWhatsapp 的 LocalTranslator.swift（那边又照搬 vInput 的 MLXTranslator）。
public class LocalModelMlxPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mailautotrans/local_model", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(LocalModelMlxPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "check":
      let path = args["path"] as? String ?? ""
      result(LocalLLM.checkDirectory(path).map { ["ok": $0.ok, "text": $0.text] })

    case "pickFolder":
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.prompt = "选这个文件夹"
      panel.message = "选择 MLX 格式的模型文件夹"
      if let start = args["start"] as? String, !start.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: start)
      }
      result(panel.runModal() == .OK ? panel.url?.path : nil)

    case "generate":
      let path = args["path"] as? String ?? ""
      let system = args["system"] as? String ?? ""
      let user = args["user"] as? String ?? ""
      let maxTokens = args["maxTokens"] as? Int ?? 4096
      Task {
        do {
          let text = try await LocalLLM.shared.generate(system: system, user: user, maxTokens: maxTokens, modelPath: path)
          DispatchQueue.main.async { result(text) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "generate", message: "\(error.localizedDescription)", details: nil))
          }
        }
      }

    case "unload":
      Task {
        await LocalLLM.shared.unload()
        DispatchQueue.main.async { result(nil) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// 用 MLX 在本机跑 qwen 之类的模型
actor LocalLLM {
  static let shared = LocalLLM()

  private var container: ModelContainer?
  private var loadedPath: String?

  /// 只看文件，不加载模型（快）。返回每一项的检查结果。
  static func checkDirectory(_ path: String) -> [(ok: Bool, text: String)] {
    var out: [(ok: Bool, text: String)] = []
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if path.isEmpty { return [(false, "还没有选择模型文件夹")] }
    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
      return [(false, "文件夹不存在")]
    }
    out.append((true, "文件夹存在"))

    let cfgURL = URL(fileURLWithPath: path).appendingPathComponent("config.json")
    if let data = try? Data(contentsOf: cfgURL),
       let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let type = cfg["model_type"] as? String ?? "未知"
      out.append((true, "config.json 正常（模型类型：\(type)）"))
      if let q = cfg["quantization"] as? [String: Any], let bits = q["bits"] {
        out.append((true, "已量化：\(bits) 位（MLX 格式）"))
      }
    } else {
      out.append((false, "缺少 config.json 或内容看不懂"))
    }

    for f in ["tokenizer.json", "tokenizer_config.json"] {
      let ok = fm.fileExists(atPath: path + "/" + f)
      out.append((ok, ok ? "\(f) 存在" : "缺少 \(f)"))
    }

    let files = (try? fm.contentsOfDirectory(atPath: path)) ?? []
    let weights = files.filter { $0.hasSuffix(".safetensors") }
    if weights.isEmpty {
      out.append((false, "没有找到模型权重文件（.safetensors）"))
    } else {
      var total: Int64 = 0
      var cloudOnly: [String] = []
      for w in weights {
        var st = stat()
        if stat(path + "/" + w, &st) == 0 {
          total += Int64(st.st_size)
          // OneDrive「仅在线」的占位文件：看着在，其实内容没下载到本机
          if st.st_flags & 0x4000_0000 != 0 { cloudOnly.append(w) }
        }
      }
      let gb = String(format: "%.1f", Double(total) / 1_073_741_824)
      out.append((true, "权重文件 \(weights.count) 个，共 \(gb) GB"))
      if !cloudOnly.isEmpty {
        out.append((false, "有文件还在云盘里没下载到本机：\(cloudOnly.joined(separator: "、"))。请在访达里右键这个文件夹 →「始终保留在此设备上」"))
      }
    }
    return out
  }

  private func ensureLoaded(_ path: String) async throws -> ModelContainer {
    if let container, loadedPath == path { return container }
    container = nil
    let c = try await loadModelContainer(directory: URL(fileURLWithPath: path))
    container = c
    loadedPath = path
    return c
  }

  /// 换成联网引擎时释放模型，把几 GB 内存还给系统
  func unload() {
    container = nil
    loadedPath = nil
  }

  func generate(system: String, user: String, maxTokens: Int, modelPath: String) async throws -> String {
    let container = try await ensureLoaded(modelPath)
    var p = GenerateParameters()
    p.temperature = 0 // 要确定、稳定，不要创造力
    p.maxTokens = maxTokens
    // 规则写进用户消息：ChatSession 的 streamResponse 会丢掉系统消息（vInput 实测）
    let prompt = system.isEmpty ? user : "\(system)\n\n\(user)"
    let session = ChatSession(container, generateParameters: p)
    var out = ""
    for try await chunk in session.streamResponse(to: prompt) { out += chunk }
    // 带「思考」的模型（如 Qwen3）会先输出 <think>…</think>，去掉
    if let r = out.range(of: "</think>") { out = String(out[r.upperBound...]) }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
