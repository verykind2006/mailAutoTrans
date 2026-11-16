import 'dart:io';

import 'package:flutter/services.dart';

import 'translator.dart';

/// 本机 MLX 模型（只有 Mac）：通过平台通道调 macOS 原生代码（macos/Runner/LocalModelChannel.swift），
/// 那边用 MLX 在本机跑 qwen 之类的模型——做法照搬 autoTransWhatsapp 的 LocalTranslator.swift。
/// 不联网、不花钱，但比联网模型慢、质量差一些。
class LocalModel {
  static const _channel = MethodChannel('mailautotrans/local_model');

  static bool get supported => Platform.isMacOS;

  /// 检查模型文件夹（只看文件，不加载模型，很快）。返回每一项的检查结果（ok + 说明）。
  static Future<List<({bool ok, String text})>> check(String path) async {
    if (!supported) return [(ok: false, text: '本机模型只支持 Mac')];
    final r = await _channel.invokeListMethod<Map>('check', {'path': path}) ?? [];
    return r.map((m) => (ok: m['ok'] == true, text: '${m['text']}')).toList();
  }

  /// 弹出系统的「选择文件夹」窗口，返回选中的路径（取消返回 null）
  static Future<String?> pickFolder(String start) async {
    if (!supported) return null;
    return _channel.invokeMethod<String>('pickFolder', {'start': start});
  }

  /// 生成一段回复（翻译用）。第一次调用会把模型载入内存，要十几秒。
  static Future<String> generate({
    required String modelPath,
    required String system,
    required String user,
    int maxTokens = 4096,
  }) async {
    if (!supported) throw TranslateException('本机模型只支持 Mac。');
    try {
      final r = await _channel.invokeMethod<String>('generate', {
        'path': modelPath,
        'system': system,
        'user': user,
        'maxTokens': maxTokens,
      });
      return r ?? '';
    } on PlatformException catch (e) {
      throw TranslateException('本机模型出错：${e.message ?? e.code}');
    } on MissingPluginException {
      throw TranslateException('这个版本没有带本机模型功能。');
    }
  }
}
