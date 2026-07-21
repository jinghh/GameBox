// 全局调试覆盖层:仅在开发包挂载。悬浮可拖动的 🐞 按钮 + 点击弹出调试面板。
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'fps_tracker.dart';
import 'game_debug.dart';
import 'game_debug_registry.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const DebugOverlay({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay>
    with SingleTickerProviderStateMixin {
  static const _size = 64.0;
  static const _margin = 4.0;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final _fps = FpsTracker.instance;

  Offset? _anchor; // 按钮左上角(屏幕坐标)
  int _taps = 0; // 点击计数(诊断用:tap 触发即变色;也作面板入口反馈)

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
    debugPrint('[debug-overlay] overlay 已挂载,日志通道 OK');
  }

  void _onTick(Duration e) {
    final dt = e - _last;
    _last = e;
    _fps.onFrame(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 默认位置往上抬高:避开屏幕底部系统手势/导航区,防点击被吞。
    final a = _anchor ??
        Offset(mq.size.width - _size - _margin,
            mq.size.height - _size - _margin - mq.padding.bottom - 48);
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: a.dx,
          top: a.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _taps++);
              _openPanel(context);
            },
            onPanUpdate: (d) => setState(() {
              final np = (_anchor ?? a) + d.delta;
              _anchor = Offset(
                np.dx.clamp(_margin, mq.size.width - _size - _margin),
                np.dy.clamp(_margin, mq.size.height - _size - _margin),
              );
            }),
            child: _bugButton(),
          ),
        ),
      ],
    );
  }

  Widget _bugButton() {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (_taps % 2 == 0)
            ? Colors.black.withValues(alpha: 0.55)
            : const Color(0xFFE53935).withValues(alpha: 0.9),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🐞', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 1),
          ValueListenableBuilder<String>(
            valueListenable: _fps.label,
            builder: (_, v, __) => Text(
              v,
              style: const TextStyle(
                color: Color(0xFFFFD54A),
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPanel(BuildContext context) {
    // 直接用根 Navigator 的 state push 一个 DialogRoute,
    // 完全绕开 showDialog 内部的 Navigator.of(context) 查找
    // (overlay 在 Navigator 上方,其 context 找不到 Navigator)。
    final nav = widget.navigatorKey.currentState;
    final ctx = widget.navigatorKey.currentContext ?? context;
    debugPrint('[debug-overlay] 🐞 tap: nav=$nav');
    if (nav == null) {
      debugPrint('[debug-overlay] 根 Navigator 还没建好,push 跳过');
      return;
    }
    try {
      nav.push<void>(
        DialogRoute<void>(
          context: ctx,
          barrierDismissible: true,
          builder: (_) => const _DebugPanel(),
        ),
      );
    } catch (e, s) {
      debugPrint('[debug-overlay] push DialogRoute 失败: $e\n$s');
    }
  }
}

// ---- 调试面板对话框 ----
class _DebugPanel extends StatefulWidget {
  const _DebugPanel();
  @override
  State<_DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<_DebugPanel> {
  final _ctrl = TextEditingController();
  final _fps = FpsTracker.instance;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _jump() {
    final n = int.tryParse(_ctrl.text);
    final g = kActiveGameDebug.value;
    if (n == null || g == null) return;
    // 越界防护:有关卡上限的游戏,非法关卡号(≤0 或 >max)直接忽略,
    // 避免 jumpToLevel 内部按索引取关卡时(如负索引取模)越界崩溃。
    final max = g.maxLevel;
    if (max != null && (n < 1 || n > max)) return;
    g.jumpToLevel(n);
    setState(() {}); // 跳关后刷新 info 表
  }

  /// 汇总当前游戏的关卡情况:总关数 / 无尽 / 无关卡概念。
  String _levelSummary(GameDebug g) {
    final cur = g.currentLevel;
    if (cur == null) return '该游戏无关卡';
    final max = g.maxLevel;
    if (max == null) return '无尽关卡(当前第 $cur 关)';
    return '共 $max 关(当前第 $cur 关)';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Row(
        children: [
          Text('🛠 调试面板',
              style: TextStyle(color: Color(0xFFFFD54A), fontSize: 18)),
          Spacer(),
          Text('DEV',
              style: TextStyle(
                  color: Color(0xFFFF5252),
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('性能'),
              ValueListenableBuilder<String>(
                valueListenable: _fps.label,
                builder: (_, v, __) => _kv('帧率', v),
              ),
              const Divider(height: 18, color: Color(0xFF444444)),
              ValueListenableBuilder<GameDebug?>(
                valueListenable: kActiveGameDebug,
                builder: (_, g, __) {
                  if (g == null) {
                    return const _Kv('当前游戏', '未进入(在首页)');
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section('游戏信息'),
                      _kv('游戏', g.id),
                      _kv('关卡总数', _levelSummary(g)),
                      ...g.info().entries.map((e) => _kv(e.key, e.value)),
                      if (g.currentLevel != null) ...[
                        const Divider(height: 18, color: Color(0xFF444444)),
                        _section('跳关测试'),
                        Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _ctrl,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: g.maxLevel != null
                                      ? '1-${g.maxLevel}'
                                      : '关卡号',
                                  hintStyle: const TextStyle(
                                      color: Color(0xFF888888), fontSize: 12),
                                  enabledBorder: const UnderlineInputBorder(
                                      borderSide:
                                          BorderSide(color: Color(0xFFFFD54A))),
                                  focusedBorder: const UnderlineInputBorder(
                                      borderSide:
                                          BorderSide(color: Color(0xFFFFD54A))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD54A),
                              ),
                              onPressed: _jump,
                              child: const Text('跳关',
                                  style: TextStyle(
                                      color: Color(0xFF222222),
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              const Text('关闭', style: TextStyle(color: Color(0xFFFFD54A))),
        ),
      ],
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: Color(0xFF9A9A9A),
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      );
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text('$k  ',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
          Flexible(
            child: Text(v,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

class _Kv extends StatelessWidget {
  final String k, v;
  const _Kv(this.k, this.v);
  @override
  Widget build(BuildContext context) => _kv(k, v);
}
