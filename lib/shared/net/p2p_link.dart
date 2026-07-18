// 点对点字节通道抽象:联机对战用。
// 阶段1 仅提供本地回环实现(同进程把两端直连),用于在单机上验证 host↔guest 同步管线;
// 阶段2 由经典蓝牙 SPP(BluetoothSppLink)实现同一接口,业务层零改动。

import 'dart:async';
import 'dart:typed_data';

/// 一条有消息边界的字节通道:send 一次 = 对端 incoming 收到完整一条 Uint8List。
///
/// 实现需保证「整体到达 + 按一条解析」:
/// - 回环实现天然满足(内存对象直接传递);
/// - 真蓝牙/Socket 实现需自行加长度前缀做帧化(接口不变)。
abstract class P2pLink {
  /// 已按消息切分的接收流(每条 Uint8List = 对端一次 send)。
  Stream<Uint8List> get incoming;

  /// 发送一条消息。
  void send(Uint8List bytes);

  /// 当前是否已连通。
  bool get isConnected;

  /// 关闭通道,释放资源。
  Future<void> close();
}

/// 本地回环链路:成对创建 [host, guest]。
///
/// host.send 直接送进 guest.incoming,guest.send 送进 host.incoming,
/// 同步执行(无真实网络延迟),专供阶段1在单机上验证同步正确性。
class LoopbackP2pLink implements P2pLink {
  final StreamController<Uint8List> _rx =
      StreamController<Uint8List>.broadcast();
  LoopbackP2pLink? _peer;
  bool _closed = false;

  LoopbackP2pLink();

  /// 创建一对互连的回环链路:[a, b],a.send→b,b.send→a。
  static List<P2pLink> pair() {
    final a = LoopbackP2pLink();
    final b = LoopbackP2pLink();
    a._peer = b;
    b._peer = a;
    return [a, b];
  }

  @override
  Stream<Uint8List> get incoming => _rx.stream;

  @override
  void send(Uint8List bytes) {
    if (_closed) return;
    final peer = _peer;
    if (peer == null || peer._closed) return;
    // 同步派发:对端 listener 立即收到。bytes 由发送方新建(toBytes 每次产生新缓冲),
    // 接收方只读不修改,故无需拷贝。
    peer._rx.add(bytes);
  }

  @override
  bool get isConnected => !_closed && _peer != null && !_peer!._closed;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _rx.close();
  }
}
