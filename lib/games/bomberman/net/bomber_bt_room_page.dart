// 泡泡堂 · 双人蓝牙联机入口(复用通用 BtRoomPage + 坦克同款 BtSppLink)。
//
// 流程与坦克一致:两台手机先在系统蓝牙设置里配对 → 一台「创建房间」当主机,
// 另一台「加入房间」连接。连上后进入 BomberPage(host 权威模拟 + 客机收快照渲染)。

import '../../../games/tank/net/bt_room_page.dart';
import '../bomberman_page.dart';

/// 泡泡堂 · 双人蓝牙(1v1 对战,复用通用 BtRoomPage)。
class BomberBtRoomPage extends BtRoomPage {
  BomberBtRoomPage({super.key})
      : super(
          title: '泡泡堂 · 双人蓝牙',
          gameId: 'bomber_online',
          guestAutoStart: true,
          onStart: (link, role, autoStart) =>
              BomberPage(link: link, role: role, autoStart: autoStart),
        );
}
