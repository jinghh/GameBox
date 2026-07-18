// 坦克联机 · 蓝牙传输通道的 Dart 侧封装(对接原生 TankBluetooth 插件)。
//
// 原生用经典蓝牙 SPP 实现 host 监听 + guest 连接;本文件只做 method/event channel 映射,
// 不含协议语义(帧化在 [BtSppLink] 中处理)。

import 'dart:async';

import 'package:flutter/services.dart';

class TankBluetooth {
  static const _method = MethodChannel('tank_app/bluetooth');
  static const _rx = EventChannel('tank_app/bluetooth/rx');

  /// 设备是否具备蓝牙模块。
  static Future<bool> isSupported() async =>
      (await _method.invokeMethod<bool>('isSupported')) ?? false;

  /// 蓝牙适配器是否已开启。
  static Future<bool> isEnabled() async =>
      (await _method.invokeMethod<bool>('isEnabled')) ?? false;

  /// 已配对设备列表(需先在系统蓝牙设置里配对)。
  static Future<List<BtDevice>> getBondedDevices() async {
    final list = await _method.invokeMethod<List>('getBondedDevices');
    if (list == null) return const [];
    return list
        .map((e) => BtDevice(
              address: (e['address'] as String?) ?? '',
              name: (e['name'] as String?) ?? '未知',
            ))
        .toList();
  }

  /// host:开始监听。{ok:true} 在客机连入时;否则 {ok:false, error}。
  static Future<({bool ok, String? error})> startServer() async {
    final m = await _method.invokeMethod<Map>('startServer');
    return (
      ok: (m?['ok'] as bool?) ?? false,
      error: m?['error'] as String?,
    );
  }

  /// guest:主动连接指定 MAC。{ok:true} 连上;否则 {ok:false, error}。
  static Future<({bool ok, String? error})> connect(String address) async {
    final m = await _method
        .invokeMethod<Map>('connect', {'address': address});
    return (
      ok: (m?['ok'] as bool?) ?? false,
      error: m?['error'] as String?,
    );
  }

  /// 发送原始字节(帧化由调用方负责)。
  static Future<void> write(Uint8List bytes) =>
      _method.invokeMethod<void>('write', {'bytes': bytes});

  /// 断开并释放。
  static Future<void> disconnect() =>
      _method.invokeMethod<void>('disconnect');

  /// 接收字节流(SPP 原始流,无消息边界)。连接断开时流 done。
  static Stream<Uint8List> get rx =>
      _rx.receiveBroadcastStream().cast<Uint8List>();
}

class BtDevice {
  final String address;
  final String name;
  const BtDevice({required this.address, required this.name});
}
