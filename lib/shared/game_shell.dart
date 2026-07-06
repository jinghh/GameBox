import 'package:flutter/material.dart';

/// 新游戏统一外壳：AppBar + 返回键 + 可选 actions。
/// 坦克大战保留自有全屏 Scaffold（带 HUD/虚拟摇杆），不使用此外壳。
///
/// 返回手势策略：
/// - **系统返回手势 / 物理返回键** → 弹「退出游戏？」确认框（防误触退出）；
/// - **AppBar 返回按钮** → 视为明确意图，直接退出，不弹框。
class GameShell extends StatefulWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const GameShell({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  // 临时放行退出：确认退出 / 点击返回按钮后置 true，下一帧真正 pop。
  bool _allowExit = false;

  /// 直接退出（明确意图，绕过确认框）。
  void _exitNow() {
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<bool> _confirmExit() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        title: const Text('退出当前游戏？',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: const Text('当前进度不会保存',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出',
                style: TextStyle(color: Color(0xFFFFD54A), fontSize: 15)),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return; // _allowExit=true 后的正常退出，放行
        // 系统手势触发：弹确认框
        if (await _confirmExit()) _exitNow();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回游戏列表',
            onPressed: _exitNow, // 明确意图：直接退
          ),
          actions: widget.actions,
        ),
        body: widget.body,
      ),
    );
  }
}
