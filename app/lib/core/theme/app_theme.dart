// 我的健身 · 设计令牌与主题（2.8.0「墨、纸、一点火」）
//
// 本文件是 UI 视觉的唯一来源：组件只引用这里的 token，不写死颜色和尺寸。
//
// 设计规则（改界面时照着做）：
//   - 界面只用黑白灰；炭火橙是唯一的强调色，只给「下一步」主操作、今天、进行中、破纪录。
//   - 文字只有 5 个字号：12 / 14 / 16 / 20 / 28；数字另有一套（Barlow Condensed）：18 / 24 / 36 / 56。
//   - 圆角只有 3 档：8（标签、数字格、小图）/ 12（按钮、输入框）/ 20（卡片），外加弹层 28 和胶囊。
//   - 卡片不用阴影，用 0.5px 的发丝边；阴影只给浮起来的东西（底部操作坞、弹出菜单、拖动中的卡片）。
//   - 间距都是 4 的倍数，页面左右边距 16，卡片内边距 16。
//
// 字体（打包进 App，均为 SIL OFL 授权）：
//   - Noto Sans SC（思源黑体）400 / 500 / 700 —— 所有中文与普通文字
//   - Barlow Condensed 500 / 600 / 700 —— 重量、次数、计时等数字
//
// 用法：
//   MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: ...)
//   final c = context.colors;  // AppColors
//   Text('82.5', style: AppText.numLarge.copyWith(color: c.text));

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'package:my_fitness/core/theme/app_icons.dart';

/// 颜色令牌。浅色与深色同名，组件只读这里。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.raised,
    required this.line,
    required this.border,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.accentSoft,
    required this.hero,
    required this.hero2,
    required this.onHero,
    required this.onHero2,
    required this.info,
    required this.success,
    required this.danger,
    required this.warmupBg,
    required this.warmupFg,
    required this.chartBar,
    required this.bodyNeutral,
    required this.heat,
    required this.partChest,
    required this.partBack,
    required this.partLegs,
    required this.partShoulders,
    required this.partArms,
    required this.partCore,
    required this.scrim,
  });

  /// 页面背景（纸）
  final Color bg;

  /// 卡片、底栏、弹层
  final Color surface;

  /// 输入框、数字格、次要按钮、凹槽
  final Color sunken;

  /// 凹槽里被选中的那一块（分段切换的选中项）：浅色是白，深色比凹槽亮一档
  final Color raised;

  /// 卡片内部的分隔线
  final Color line;

  /// 卡片、按钮外圈的发丝边（半透明，叠在任何底色上都合适）
  final Color border;

  /// 主文字 / 次文字 / 辅助文字（均满足 4.5:1）
  final Color text;
  final Color text2;
  final Color text3;

  /// 深色模式（背景比较暗）
  bool get isDark => bg.computeLuminance() < 0.4;

  /// 选中项的底色和字色：浅色模式是炭火橙实心 + 墨色字，未选中回到白底；深色模式是亮色实心
  Color get selectedFill => isDark ? text : accent;
  Color get onSelected => isDark ? bg : onAccent;

  /// 炭火橙：只用于「下一步」主操作、今天、进行中、破纪录
  final Color accent;

  /// 橙色底上的文字（深色字，保证对比度）
  final Color onAccent;

  /// 作为文字使用的橙色（比 accent 深/亮一档以满足对比度）
  final Color accentText;

  /// 橙色浅底：练过的天、已完成的组、上涨标签
  final Color accentSoft;

  /// 墨色主卡片 / 休息计时坞（浅色主题里也是深色）
  final Color hero;
  final Color hero2;
  final Color onHero;
  final Color onHero2;

  /// 对比用的中性色：上周 / 上期的数据
  final Color info;
  final Color success;
  final Color danger;

  /// 热身组 W 徽章（中性灰，靠字母 W 区分，不另起一个颜色）
  final Color warmupBg;
  final Color warmupFg;

  /// 趋势图里历史柱子的颜色
  final Color chartBar;

  /// 肌肉图上头、手、脚等非肌肉区域
  final Color bodyNeutral;

  /// 肌肉热度 5 档：0 组 / 1–3 / 4–7 / 8–12 / 13+（每周）
  final List<Color> heat;

  /// 标签色：日历上区分不同训练日的小圆点。六个颜色按固定顺序分配，
  /// 浅色、深色两套都用 dataviz 的校验脚本验过（色弱也分得开），要改先重新跑校验。
  final Color partChest;
  final Color partBack;
  final Color partLegs;
  final Color partShoulders;
  final Color partArms;
  final Color partCore;

  /// 底部弹层遮罩
  final Color scrim;

  static const light = AppColors(
    bg: Color(0xFFF4F3F0),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEDEBE7),
    raised: Color(0xFFFFFFFF),
    line: Color(0xFFE9E7E2),
    border: Color(0x14121214),
    text: Color(0xFF121214),
    text2: Color(0xFF55545A),
    text3: Color(0xFF75747A),
    accent: Color(0xFFFF5A1F),
    onAccent: Color(0xFF180C06),
    accentText: Color(0xFFC2410C),
    accentSoft: Color(0xFFFFE9DE),
    hero: Color(0xFF131315),
    hero2: Color(0xFF29292D),
    onHero: Color(0xFFF4F3F0),
    onHero2: Color(0xFFA5A4AA),
    info: Color(0xFFB4B2AC),
    success: Color(0xFF14915C),
    danger: Color(0xFFD92D20),
    warmupBg: Color(0xFFE4E2DD),
    warmupFg: Color(0xFF55545A),
    chartBar: Color(0xFFDDDAD4),
    bodyNeutral: Color(0xFFDFDCD6),
    heat: [
      Color(0xFFE8E5E0),
      Color(0xFFFFD6C2),
      Color(0xFFFFA57D),
      Color(0xFFFF6E33),
      Color(0xFFD9420B),
    ],
    partChest: Color(0xFFFF5A1F),
    partBack: Color(0xFF3A6BE0),
    partLegs: Color(0xFF16966A),
    partShoulders: Color(0xFFC98A00),
    partArms: Color(0xFF8266D9),
    partCore: Color(0xFFD4488E),
    scrim: Color(0x66121214),
  );

  static const dark = AppColors(
    bg: Color(0xFF0B0B0C),
    surface: Color(0xFF151516),
    sunken: Color(0xFF202022),
    raised: Color(0xFF323235),
    line: Color(0xFF242426),
    border: Color(0x14FFFFFF),
    text: Color(0xFFF3F2EF),
    text2: Color(0xFFA5A4AA),
    text3: Color(0xFF85848A),
    accent: Color(0xFFFF6A2E),
    onAccent: Color(0xFF180C06),
    accentText: Color(0xFFFF8A57),
    accentSoft: Color(0xFF34190E),
    hero: Color(0xFF1C1C1E),
    hero2: Color(0xFF2E2E31),
    onHero: Color(0xFFF3F2EF),
    onHero2: Color(0xFFA5A4AA),
    info: Color(0xFF5A595E),
    success: Color(0xFF3CC98A),
    danger: Color(0xFFFF6B5E),
    warmupBg: Color(0xFF2E2E31),
    warmupFg: Color(0xFFC9C8CC),
    chartBar: Color(0xFF323235),
    bodyNeutral: Color(0xFF262628),
    heat: [
      Color(0xFF2C2C2F),
      Color(0xFF5A2A17),
      Color(0xFF9A3A14),
      Color(0xFFE2541C),
      Color(0xFFFF8A57),
    ],
    partChest: Color(0xFFE8602C),
    partBack: Color(0xFF5580E8),
    partLegs: Color(0xFF1A8A60),
    partShoulders: Color(0xFFB88A1C),
    partArms: Color(0xFF9380E0),
    partCore: Color(0xFFD45A95),
    scrim: Color(0x99000000),
  );

  /// 每周组数 → 热度色
  Color heatFor(double weeklySets) {
    if (weeklySets >= 13) return heat[4];
    if (weeklySets >= 8) return heat[3];
    if (weeklySets >= 4) return heat[2];
    if (weeklySets >= 1) return heat[1];
    return heat[0];
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// 间距：4 的倍数。页面左右边距 16，卡片内边距 16。
abstract final class AppSpace {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;

  static const double pageGutter = 16;
  static const double cardPadding = 16;

  /// 同一页里卡片与卡片之间
  static const double sectionGap = 12;
}

/// 圆角：只有 3 档 + 弹层 + 胶囊。嵌套时内圆角 = 外圆角 − 内边距（卡片 20、内边距 12 → 里面的图 8）。
abstract final class AppRadius {
  static const double sm = 8; // 标签、数字格、列表里的小图
  static const double md = 12; // 按钮、输入框、分段切换
  static const double lg = 20; // 卡片
  static const double xl = 28; // 底部弹层顶角、对话框
  static const double full = 999; // 胶囊

  /// 旧名字，等同于 [sm]
  static const double xs = sm;

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get small => BorderRadius.circular(sm);
}

/// 线宽：全 App 统一用发丝线。
abstract final class AppStroke {
  static const double hairline = 0.5;
}

/// 尺寸：单手操作，触控区不小于 48
abstract final class AppSize {
  static const double touchMin = 48;
  static const double buttonLarge = 56; // 「开始训练」「完成本组」
  static const double button = 48;
  static const double buttonSmall = 36;
  static const double input = 52;
  static const double chip = 36;
  static const double segmented = 44;
  static const double setRow = 52;
  static const double setCellW = 72;
  static const double setCellH = 44;
  static const double setCheck = 44;
  static const double navBar = 64;
  static const double keypadKey = 52;
  static const double exerciseThumb = 52;
  static const double pageHeader = 56;
}

/// 动效：默认少放；要放就用 ease-out、250ms 上下。
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasized = Duration(milliseconds: 320);
  static const Curve curve = Cubic(0.22, 1, 0.36, 1);
  // 触感：完成一组 HapticFeedback.mediumImpact；破纪录 heavyImpact；
  // 休息倒计时结束 震动 + 本地通知（锁屏也要提醒）。
}

/// 文字样式。中文用 NotoSansSC，数字用 BarlowCondensed + 等宽数字。
abstract final class AppText {
  static const String sans = 'NotoSansSC';
  static const String numeric = 'BarlowCondensed';
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  /// 数字样式里偶尔夹带的中文（「休」「入门」「天」）回退到思源黑体，不出现方块或系统字体。
  static const List<String> _numFallback = [sans];

  // 数字：18 / 24 / 36 / 56
  static const numDisplay = TextStyle(fontFamily: numeric, fontSize: 56, height: 1.0, fontWeight: FontWeight.w600, fontFeatures: _tnum, fontFamilyFallback: _numFallback);
  static const numLarge = TextStyle(fontFamily: numeric, fontSize: 36, height: 1.1, fontWeight: FontWeight.w600, fontFeatures: _tnum, fontFamilyFallback: _numFallback);
  static const numMedium = TextStyle(fontFamily: numeric, fontSize: 24, height: 1.2, fontWeight: FontWeight.w600, fontFeatures: _tnum, fontFamilyFallback: _numFallback);
  static const numSmall = TextStyle(fontFamily: numeric, fontSize: 18, height: 1.2, fontWeight: FontWeight.w600, fontFeatures: _tnum, fontFamilyFallback: _numFallback);

  // 文字：28 / 20 / 16 / 14 / 12。层级不够时用字重和颜色拉开，不再加字号。
  static const titleLarge = TextStyle(fontFamily: sans, fontSize: 28, height: 1.25, fontWeight: FontWeight.w700);
  static const titleMedium = TextStyle(fontFamily: sans, fontSize: 20, height: 1.3, fontWeight: FontWeight.w700);
  static const titleSmall = TextStyle(fontFamily: sans, fontSize: 16, height: 1.4, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontFamily: sans, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontFamily: sans, fontSize: 14, height: 1.45, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontFamily: sans, fontSize: 12, height: 1.4, fontWeight: FontWeight.w400);
  static const button = TextStyle(fontFamily: sans, fontSize: 16, height: 1.2, fontWeight: FontWeight.w700);
}

/// 有触感的按钮面：上亮下暗的细微渐变 + 一圈比面深一档的描边 + 顶部高光 + 两层很轻的投影。
/// 按下时渐变上下翻转、投影收起，配合 PressScale 的缩放，像真的按下去了。
class _ButtonFace extends StatelessWidget {
  const _ButtonFace({
    required this.states,
    required this.child,
    required this.top,
    required this.bottom,
    required this.edge,
    required this.highlight,
    required this.disabled,
    this.radius = AppRadius.md,
    this.lifted = true,
  });

  final Set<WidgetState> states;
  final Widget? child;
  final Color top;
  final Color bottom;
  final Color edge;
  final Color highlight;
  final Color disabled;
  final double radius;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final off = states.contains(WidgetState.disabled);
    final pressed = states.contains(WidgetState.pressed);
    final r = BorderRadius.circular(radius);
    if (off) {
      return DecoratedBox(decoration: BoxDecoration(color: disabled, borderRadius: r), child: child);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pressed ? [bottom, top] : [top, bottom],
        ),
        boxShadow: lifted && !pressed
            ? const [
                BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x1F000000), blurRadius: 10, spreadRadius: -3, offset: Offset(0, 4)),
              ]
            : null,
      ),
      child: CustomPaint(
        foregroundPainter: _EdgePainter(radius: radius, edge: edge, highlight: pressed ? const Color(0x00000000) : highlight),
        child: child,
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  const _EdgePainter({required this.radius, required this.edge, required this.highlight});
  final double radius;
  final Color edge;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius - 0.5));
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
    if (highlight.a == 0) return;
    // 顶部一道 1px 高光：只画上沿，往下很快淡出
    final inner = RRect.fromRectAndRadius((Offset.zero & size).deflate(1.5), Radius.circular(radius - 1.5));
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [highlight, highlight.withValues(alpha: 0)],
          stops: const [0, 0.35],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.edge != edge || old.highlight != highlight || old.radius != radius;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  /// 主按钮（炭火橙）的面。给不走 FilledButton 的自绘按钮复用。
  static Widget primaryFace(AppColors c, Set<WidgetState> states, Widget? child, {double radius = AppRadius.md}) => _ButtonFace(
        states: states,
        top: Color.lerp(c.accent, const Color(0xFFFFFFFF), 0.10)!,
        bottom: Color.lerp(c.accent, const Color(0xFF000000), 0.04)!,
        edge: Color.lerp(c.accent, const Color(0xFF000000), 0.16)!,
        highlight: const Color(0x59FFFFFF),
        disabled: c.sunken,
        radius: radius,
        child: child,
      );

  /// 次要按钮（中性灰）的面。
  static Widget neutralFace(AppColors c, Brightness b, Set<WidgetState> states, Widget? child, {double radius = AppRadius.md}) {
    final light = b == Brightness.light;
    return _ButtonFace(
      states: states,
      top: light ? const Color(0xFFFFFFFF) : const Color(0xFF2D2D30),
      bottom: light ? const Color(0xFFF3F2EE) : const Color(0xFF242426),
      edge: light ? const Color(0x24121214) : const Color(0x1FFFFFFF),
      highlight: light ? const Color(0xCCFFFFFF) : const Color(0x14FFFFFF),
      disabled: c.sunken,
      radius: radius,
      lifted: light,
      child: child,
    );
  }

  static ThemeData _build(Brightness b, AppColors c) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accentText,
      secondary: c.text,
      onSecondary: c.bg,
      secondaryContainer: c.sunken,
      onSecondaryContainer: c.text,
      error: c.danger,
      onError: const Color(0xFFFFFFFF),
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.text2,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.bg,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.sunken,
      surfaceContainerHighest: c.sunken,
      outline: c.line,
      outlineVariant: c.line,
      inverseSurface: c.hero,
      onInverseSurface: c.onHero,
      scrim: c.scrim,
      shadow: const Color(0xFF000000),
      surfaceTint: Colors.transparent,
    );

    TextStyle t(TextStyle s, Color color) => s.copyWith(color: color);

    WidgetStateProperty<Color?> fg(Color normal) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.text3 : normal);
    const noOverlay = WidgetStatePropertyAll<Color>(Colors.transparent);
    final buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.button);
    final hairline = BorderSide(color: c.border, width: AppStroke.hairline);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: AppText.sans,
      scaffoldBackgroundColor: c.bg,
      splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
      splashColor: c.text.withValues(alpha: 0.06),
      highlightColor: c.text.withValues(alpha: 0.04),
      extensions: <ThemeExtension<dynamic>>[c],
      // 所有平台都用横向滑入的翻页，比安卓默认的缩放更安静
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(AppIcons.back),
        closeButtonIconBuilder: (_) => const Icon(AppIcons.close),
      ),
      iconTheme: IconThemeData(color: c.text, size: 24),
      textTheme: TextTheme(
        displayLarge: t(AppText.numDisplay, c.text),
        displayMedium: t(AppText.numLarge, c.text),
        displaySmall: t(AppText.numMedium, c.text),
        headlineMedium: t(AppText.titleLarge, c.text),
        titleLarge: t(AppText.titleMedium, c.text),
        titleMedium: t(AppText.titleSmall, c.text),
        bodyLarge: t(AppText.body, c.text),
        bodyMedium: t(AppText.body, c.text2),
        labelLarge: t(AppText.button, c.text),
        labelMedium: t(AppText.label, c.text2),
        labelSmall: t(AppText.caption, c.text3),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 4,
        toolbarHeight: AppSize.pageHeader,
        titleTextStyle: t(AppText.titleMedium, c.text),
        systemOverlayStyle: b == Brightness.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card, side: hairline),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: AppStroke.hairline * 2, space: 1),
      // 主按钮：炭火橙 + 墨色字
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: fg(c.onAccent),
          overlayColor: noOverlay,
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(AppSize.button)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: const WidgetStatePropertyAll(AppText.button),
          backgroundBuilder: (context, states, child) => primaryFace(c, states, child),
        ),
      ),
      // 次要按钮：中性灰面、墨色字
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: fg(c.text),
          overlayColor: noOverlay,
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(AppSize.button)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(AppText.button.copyWith(fontWeight: FontWeight.w600)),
          backgroundBuilder: (context, states, child) => neutralFace(c, b, states, child),
        ),
      ),
      // 第三级按钮：发丝边、透明底（「添加动作」「新建计划」这类）
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          disabledForegroundColor: c.text3,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: c.text.withValues(alpha: 0.16), width: 1),
          minimumSize: const Size(0, AppSize.buttonSmall),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: buttonShape,
          textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentText,
          disabledForegroundColor: c.text3,
          minimumSize: const Size(0, AppSize.buttonSmall),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: buttonShape,
          textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.text, disabledForegroundColor: c.text3.withValues(alpha: 0.5)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.hero,
        foregroundColor: c.accent,
        extendedTextStyle: AppText.body.copyWith(fontWeight: FontWeight.w700, color: c.onHero),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: t(AppText.body, c.text3),
        labelStyle: t(AppText.body, c.text2),
        floatingLabelStyle: t(AppText.label, c.text2),
        helperStyle: t(AppText.caption, c.text3),
        errorStyle: t(AppText.caption, c.danger),
        counterStyle: t(AppText.caption, c.text3),
        prefixIconColor: c.text3,
        suffixIconColor: c.text2,
        border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide.none),
        disabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: c.isDark ? c.text : c.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: c.danger, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: c.danger, width: 1.5)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.24),
        selectionHandleColor: c.accent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.sunken,
        selectedColor: c.text,
        labelStyle: t(AppText.label, c.text),
        secondaryLabelStyle: t(AppText.label, c.bg),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.chartBar),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.text.withValues(alpha: 0.16),
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      // 对话框与弹出菜单：和卡片同一套语言
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: c.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: t(AppText.titleMedium, c.text),
        contentTextStyle: t(AppText.body, c.text2),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x40000000),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.button, side: hairline),
        textStyle: t(AppText.body, c.text),
        labelTextStyle: WidgetStatePropertyAll(t(AppText.body, c.text)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        headerBackgroundColor: c.hero,
        headerForegroundColor: c.onHero,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.sunken,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(AppRadius.full),
        // 进度条就是一根线：不要末端的小圆点，也不要中间的缺口
        stopIndicatorRadius: 0,
        trackGap: 0,
        // ignore: deprecated_member_use
        year2023: false,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.text2,
        textColor: c.text,
        titleTextStyle: t(AppText.body, c.text).copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: t(AppText.label, c.text2),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.hero,
        contentTextStyle: t(AppText.label, c.onHero),
        actionTextColor: c.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.hero, borderRadius: AppRadius.small),
        textStyle: t(AppText.caption, c.onHero),
      ),
    );
  }
}

extension AppThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
