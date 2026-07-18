// 坦克联机 · 经典蓝牙 SPP 的 P2pLink 实现。
//
// SPP 是字节流(无消息边界),而 [P2pLink] 契约要求「一次 send = 对端收一条完整消息」,
// 故在此做长度前缀帧化:每帧 = u32 小端长度(4B)+ payload。
//
// 复用阶段1 的 LoopbackP2pLink 同一接口,业务层(BattleCityGame)零改动。

import 'dart:async';
import 'dart:typed_data';

import 'p2p_link.dart';
import 'tank_bluetooth.dart';

class BtSppLink implements P2pLink {
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  final _RxFramer _framer = _RxFramer();
  bool _connected = true;

  BtSppLink() {
    _sub = TankBluetooth.rx.listen(
      _onData,
      onDone: () => _markClosed(),
      onError: (_) => _markClosed(),
    );
  }

  void _onData(Uint8List chunk) {
    for (final frame in _framer.push(chunk)) {
      _incoming.add(frame);
    }
  }

  void _markClosed() {
    if (!_connected) return;
    _connected = false;
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  bool get isConnected => _connected && !_incoming.isClosed;

  @override
  void send(Uint8List bytes) {
    if (!_connected) return;
    final len = bytes.length;
    final frame = BytesBuilder()
      ..addByte(len & 0xFF)
      ..addByte((len >>> 8) & 0xFF)
      ..addByte((len >>> 16) & 0xFF)
      ..addByte((len >>> 24) & 0xFF)
      ..add(bytes);
    TankBluetooth.write(frame.takeBytes());
  }

  @override
  Future<void> close() async {
    _markClosed();
    await _sub?.cancel();
    _sub = null;
    await TankBluetooth.disconnect();
  }
}

/// SPP 字节流 → 长度前缀消息帧的重组器。
class _RxFramer {
  final List<int> _buf = <int>[];

  /// 喂入一段原始字节,返回其中已完整的若干帧(payload)。
  Iterable<Uint8List> push(Uint8List chunk) sync* {
    if (chunk.isNotEmpty) _buf.addAll(chunk);
    while (_buf.length >= 4) {
      final len = _buf[0] |
          (_buf[1] << 8) |
          (_buf[2] << 16) |
          (_buf[3] << 24);
      if (len < 0 || len > 1 << 20) {
        // 协议异常(>1MB):丢弃缓冲,避免无限增长。
        _buf.clear();
        return;
      }
      if (_buf.length < 4 + len) return; // 等待更多字节
      final payload = Uint8List.fromList(_buf.sublist(4, 4 + len));
      _buf.removeRange(0, 4 + len);
      yield payload;
    }
  }
}
