// 坦克联机 · 经典蓝牙「创建/加入房间」入口(阶段2)。
//
// 流程:
// 1. 两台手机先在「系统蓝牙设置」里相互配对(一次性)。
// 2. host 点「创建房间」→ startServer 监听,等待客机。
// 3. guest 点「加入房间」→ 选已配对的 host 设备 → connect。
// 4. 连上后用 BtSppLink 启动 BattleCityGame(host 权威 + autoStart;guest 收快照渲染)。
//
// 离线/单机入口完全不受影响。

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/net/bt_spp_link.dart';
import '../../../shared/net/tank_bluetooth.dart';
import '../battle_city_game.dart';
import 'wire.dart';

class TankBtRoomPage extends StatefulWidget {
  const TankBtRoomPage({super.key});

  @override
  State<TankBtRoomPage> createState() => _TankBtRoomPageState();
}

enum _Mode { menu, hosting, picking, connecting }

class _TankBtRoomPageState extends State<TankBtRoomPage> {
  _Mode _mode = _Mode.menu;
  bool _busy = false;
  String? _hint;
  List<BtDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _ensurePermissionAndAdapter();
  }

  Future<void> _ensurePermissionAndAdapter() async {
    // API31+ 需运行时申请 BLUETOOTH_CONNECT;旧版本自动授予。
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    await _refreshAdapter();
  }

  Future<void> _refreshAdapter() async {
    final supported = await TankBluetooth.isSupported();
    final enabled = await TankBluetooth.isEnabled();
    if (!mounted) return;
    setState(() {
      _hint = !supported
          ? '本机不支持蓝牙,无法联机。'
          : !enabled
              ? '请先在系统设置/快捷面板打开蓝牙。'
              : null;
    });
  }

  Future<void> _loadDevices() async {
    final list = await TankBluetooth.getBondedDevices();
    if (!mounted) return;
    setState(() => _devices = list);
  }

  Future<void> _createRoom() async {
    if (_busy) return;
    final enabled = await TankBluetooth.isEnabled();
    if (!enabled) {
      _snack('蓝牙未开启,请先打开蓝牙。');
      await _refreshAdapter();
      return;
    }
    setState(() {
      _mode = _Mode.hosting;
      _busy = true;
    });
    final r = await TankBluetooth.startServer(); // 阻塞至客机连入
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _enterGame(NetRole.host, autoStart: true);
    } else {
      _snack('未能建立房间:${r.error ?? "监听失败或已取消"}');
      setState(() => _mode = _Mode.menu);
    }
  }

  Future<void> _joinRoom(BtDevice device) async {
    if (_busy) return;
    setState(() {
      _mode = _Mode.connecting;
      _busy = true;
    });
    final r = await TankBluetooth.connect(device.address);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _enterGame(NetRole.guest, autoStart: false);
    } else {
      _snack('连接失败:${r.error ?? "未知原因"}\n请确认对方已「创建房间」且两机已配对。');
      setState(() => _mode = _Mode.picking);
    }
  }

  void _enterGame(NetRole role, {required bool autoStart}) {
    final link = BtSppLink();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BattleCityGame(
          link: link,
          role: role,
          autoStart: autoStart,
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        foregroundColor: const Color(0xFFFFD54A),
        title: const Text('坦克联机 · 蓝牙', style: TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: _hint == null ? _body() : _hintBody(_hint!),
      ),
    );
  }

  Widget _body() {
    switch (_mode) {
      case _Mode.menu:
        return _menu();
      case _Mode.hosting:
        return _hosting();
      case _Mode.picking:
        return _picking();
      case _Mode.connecting:
        return _connecting();
    }
  }

  Widget _menu() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth, size: 64, color: Color(0xFF4CAF50)),
            const SizedBox(height: 16),
            const Text(
              '两台手机蓝牙联机闯关',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '① 先在「系统蓝牙设置」里把两台手机配对\n'
              '② 一台点「创建房间」当主机\n'
              '③ 另一台点「加入房间」选主机连接',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _roleButton(
              '创建房间(当主机)',
              Icons.wifi_tethering,
              const Color(0xFFFFD54A),
              _createRoom,
            ),
            const SizedBox(height: 14),
            _roleButton(
              '加入房间(当客机)',
              Icons.cable,
              const Color(0xFF4FC3F7),
              () async {
                await _loadDevices();
                if (!mounted) return;
                if (_devices.isEmpty) {
                  _snack('没有已配对设备,请先在系统蓝牙设置里配对两台手机。');
                  return;
                }
                setState(() => _mode = _Mode.picking);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, color: const Color(0xFF0E0E0E)),
        label: Text(label,
            style: const TextStyle(
                color: Color(0xFF0E0E0E), fontWeight: FontWeight.bold, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _hosting() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFD54A)),
            const SizedBox(height: 20),
            const Text('房间已创建,等待客机加入…',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('请在另一台手机点「加入房间」并选择本机。',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
            const SizedBox(height: 28),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await TankBluetooth.disconnect();
                      if (!mounted) return;
                      setState(() => _mode = _Mode.menu);
                    },
              child: const Text('取消', style: TextStyle(color: Color(0xFFFF8A80))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _picking() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('选择已配对的主机设备',
                    style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh, color: Color(0xFFFFD54A)),
                onPressed: () async {
                  await _loadDevices();
                  if (_devices.isEmpty) _snack('没有已配对设备。');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _devices.length,
            separatorBuilder: (_, _) =>
                const Divider(color: Color(0xFF2A2A2A), height: 1),
            itemBuilder: (_, i) {
              final d = _devices[i];
              return ListTile(
                leading: const Icon(Icons.phone_android, color: Color(0xFF4FC3F7)),
                title: Text(d.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(d.address,
                    style: const TextStyle(color: Color(0xFF777777), fontSize: 11)),
                onTap: () => _joinRoom(d),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextButton(
            onPressed: () => setState(() => _mode = _Mode.menu),
            child: const Text('返回', style: TextStyle(color: Color(0xFFAAAAAA))),
          ),
        ),
      ],
    );
  }

  Widget _connecting() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF4FC3F7)),
          SizedBox(height: 20),
          Text('正在连接主机…', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _hintBody(String hint) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled,
                size: 56, color: Color(0xFF888888)),
            const SizedBox(height: 16),
            Text(hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14, height: 1.5)),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _refreshAdapter,
              child: const Text('重新检测', style: TextStyle(color: Color(0xFFFFD54A))),
            ),
          ],
        ),
      ),
    );
  }
}
