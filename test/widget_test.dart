// 冒烟测试：验证游戏注册表正确（不 pump 整个 App，避免平台插件依赖）。

import 'package:flutter_test/flutter_test.dart';

import 'package:tank_app/app/games.dart';

void main() {
  test('合集注册表包含至少 4 款游戏且 id 唯一', () {
    expect(kGames.length, greaterThanOrEqualTo(4));
    final ids = kGames.map((g) => g.id).toSet();
    expect(ids.length, kGames.length, reason: '游戏 id 必须唯一');
  });

  test('坦克大战仍在合集中', () {
    expect(kGames.any((g) => g.id == 'tank'), isTrue);
  });
}
