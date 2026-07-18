// 坦克大战联机 · 阶段1 回环验证页(临时入口)。
//
// 在单机上并排创建 host + guest 两个 BattleCityGame,用本地回环链路互连,
// 肉眼验证同步管线:host 广播快照 ↔ guest 上行输入 ↔ 双向画面同步。
// 完全不涉及真蓝牙;阶段2 接入蓝牙后,此页升级为正式「创建/加入房间」流程。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/net/p2p_link.dart';
import '../battle_city_game.dart';
import 'wire.dart';

class TankLoopbackDemoPage extends StatefulWidget {
  const TankLoopbackDemoPage({super.key});

  @override
  State<TankLoopbackDemoPage> createState() => _TankLoopbackDemoPageState();
}

class _TankLoopbackDemoPageState extends State<TankLoopbackDemoPage> {
  late final List<P2pLink> _links;

  @override
  void initState() {
    super.initState();
    // 回环页锁定横屏:两个正方形战场并排更清晰。
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 成对回环:[0]=host 端,[1]=guest 端。host.send→guest,guest.send→host。
    _links = LoopbackP2pLink.pair();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        foregroundColor: const Color(0xFFFFD54A),
        title: const Text('坦克联机 · 回环测试', style: TextStyle(fontSize: 15)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFF222018),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: const Text(
                '左=主机(P1,自动开局) · 右=客机(P2,接收快照)\n'
                '操作任一侧的摇杆与开火,观察对侧画面是否同步。本页为单机回环,非真蓝牙。',
                style: TextStyle(
                    color: Color(0xFFCCCCCC), fontSize: 11, height: 1.45),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: BattleCityGame(
                      link: _links[0],
                      role: NetRole.host,
                      autoStart: true,
                    ),
                  ),
                  Container(width: 1, color: const Color(0xFF333333)),
                  Expanded(
                    child: BattleCityGame(
                      link: _links[1],
                      role: NetRole.guest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
