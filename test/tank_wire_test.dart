// 坦克联机线协议回归测试：版本号识别与编解码往返。
// 字节布局一旦变更必须同步升级 kWireVersion，否则新旧 APK 会按不同布局解析。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tank_app/games/tank/constants.dart';
import 'package:tank_app/games/tank/models.dart';
import 'package:tank_app/games/tank/net/wire.dart';

void main() {
  group('协议版本', () {
    test('本版本消息首字节高 4 位等于 kWireVersion', () {
      expect(kMsgSnapshot >>> 4, kWireVersion);
      expect(kMsgInput >>> 4, kWireVersion);
      expect(isWireVersionMismatch(Uint8List.fromList([kMsgSnapshot])), isFalse);
      expect(isWireVersionMismatch(Uint8List.fromList([kMsgInput])), isFalse);
    });

    test('旧版本(首字节 1/2)被识别为版本不匹配', () {
      expect(isWireVersionMismatch(Uint8List.fromList([1, 0, 0])), isTrue);
      expect(isWireVersionMismatch(Uint8List.fromList([2, 255, 1])), isTrue);
      // 旧包不会被误解析成新协议的 Snapshot。
      expect(
          Snapshot.fromBytes(Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0])),
          isNull);
    });

    test('空包与噪声包不误报', () {
      expect(isWireVersionMismatch(Uint8List(0)), isFalse);
      expect(isWireVersionMismatch(Uint8List.fromList([0xFF, 0x00])), isFalse);
      expect(isWireVersionMismatch(Uint8List.fromList([0x23])), isFalse);
    });
  });

  group('编解码往返', () {
    test('InputFrame 的方向与开火状态不丢失', () {
      for (final dir in <Dir?>[Dir.up, Dir.down, Dir.left, Dir.right, null]) {
        final fire = dir == null;
        final back =
            InputFrame.fromBytes(InputFrame(dir: dir, fire: fire).toBytes());
        expect(back, isNotNull, reason: 'dir=$dir 解码失败');
        expect(back!.dir, dir);
        expect(back.fire, fire);
      }
    });

    test('Snapshot(无地形差量)字段往返一致且首字节带版本', () {
      final s = Snapshot(
        phase: Phase.playing,
        score: 12345,
        lives: 3,
        level: 7,
        baseAlive: true,
        freezeActive: false,
        enemyRemaining: 9,
        gridSeq: 4,
        time: 12.5,
        grid: null,
        players: <Tank>[],
        enemies: <Tank>[],
        bullets: <Bullet>[],
        powerups: <PowerUp>[],
        explosions: <Explosion>[],
      );
      final bytes = s.toBytes();
      expect(bytes[0], kMsgSnapshot);
      final back = Snapshot.fromBytes(bytes);
      expect(back, isNotNull);
      expect(back!.phase, Phase.playing);
      expect(back.score, 12345);
      expect(back.lives, 3);
      expect(back.level, 7);
      expect(back.baseAlive, isTrue);
      expect(back.freezeActive, isFalse);
      expect(back.enemyRemaining, 9);
      expect(back.gridSeq, 4);
      expect(back.time, closeTo(12.5, 1e-5));
      expect(back.grid, isNull);
      expect(back.players, isEmpty);
    });
  });
}
