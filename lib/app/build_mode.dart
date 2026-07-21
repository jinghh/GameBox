/// 编译期构建模式开关。
///
/// dev flavor 打包时通过 `--dart-define=MODE=dev` 注入;线上包不传 → 默认 prod。
/// `kIsDev` 是编译期常量,所有 dev-only 分支在 prod 包中被 tree-shake,
/// 线上包零运行时开销、零调试代码泄露。
enum BuildMode { dev, prod }

const BuildMode kBuildMode =
    String.fromEnvironment('MODE', defaultValue: 'prod') == 'dev'
        ? BuildMode.dev
        : BuildMode.prod;

bool get kIsDev => kBuildMode == BuildMode.dev;
