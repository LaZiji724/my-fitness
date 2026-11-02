// 我的健身 · 设计令牌与主题（风格「铁与火」）
//
// 设计稿：https://claude.ai/artifact/SCQkbAdLFep7nzpUJpMhrP
// 本文件是 UI 视觉的唯一来源：组件只引用这里的 token，不写死颜色和尺寸。
//
// 字体（打包进 App，均为 SIL OFL 授权）：
//   - Noto Sans SC（思源黑体）400 / 500 / 700 —— 所有中文与普通文字
//   - Barlow Condensed 500 / 600 / 700 —— 重量、次数、计时等数字
// pubspec.yaml：
//   flutter:
//     fonts:
//       - family: NotoSansSC
//         fonts:
//           - asset: assets/fonts/NotoSansSC-Regular.ttf
//           - asset: assets/fonts/NotoSansSC-Medium.ttf
//             weight: 500
//           - asset: assets/fonts/NotoSansSC-Bold.ttf
//             weight: 700
//       - family: BarlowCondensed
//         fonts:
//           - asset: assets/fonts/BarlowCondensed-Medium.ttf
//             weight: 500
//           - asset: assets/fonts/BarlowCondensed-SemiBold.ttf
//             weight: 600
//           - asset: assets/fonts/BarlowCondensed-Bold.ttf
//             weight: 700
//
// 用法：
//   MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: ...)
//   final c = context.colors;  // AppColors
//   Text('82.5', style: AppText.numLarge.copyWith(color: c.text));

import 'package:flutter/material.dart';

/// 颜色令牌。浅色与深色同名，组件只读这里。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.line,
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

  /// 页面背景
  final Color bg;

  /// 卡片、底栏、弹层
  final Color surface;

  /// 输入框、数字格、次要按钮、凹槽
  final Color sunken;

  /// 分隔线、未选中描边
  final Color line;

  /// 主文字 / 次文字 / 辅助文字（均满足 4.5:1）
  final Color text;
  final Color text2;
  final Color text3;

  /// 炭火橙：只用于「下一步」主操作、当前进度、PR、本周数据
  final Color accent;

  /// 橙色底上的文字（深色字，保证对比度）
  final Color onAccent;

  /// 作为文字使用的橙色（比 accent 深/亮一档以满足对比度）
  final Color accentText;

  /// 橙色浅底：选中的底栏指示器、上涨标签、已应用筛选
  final Color accentSoft;

  /// 主卡片 / 休息计时坞的深色底（浅色主题里也是深色）
  final Color hero;
  final Color hero2;
  final Color onHero;
  final Color onHero2;

  /// 对比蓝：上周 / 对比数据
  final Color info;
  final Color success;
  final Color danger;

  /// 热身组 W 徽章
  final Color warmupBg;
  final Color warmupFg;

  /// 趋势图里历史柱子的颜色
  final Color chartBar;

  /// 肌肉图上头、手、脚等非肌肉区域
  final Color bodyNeutral;

  /// 肌肉热度 5 档：0 组 / 1–3 / 4–7 / 8–12 / 13+（每周）
  final List<Color> heat;

  /// 部位色：日历圆点、分布图
  final Color partChest;
  final Color partBack;
  final Color partLegs;
  final Color partShoulders;
  final Color partArms;
  final Color partCore;

  /// 底部弹层遮罩
  final Color scrim;

  static const light = AppColors(
    bg: Color(0xFFF3F2EF),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFECEAE6),
    line: Color(0xFFE2E0DB),
    text: Color(0xFF141416),
    text2: Color(0xFF55545A),
    text3: Color(0xFF6B6A70),
    accent: Color(0xFFFF5B1F),
    onAccent: Color(0xFF141416),
    accentText: Color(0xFFC2410C),
    accentSoft: Color(0xFFFFE6DA),
    hero: Color(0xFF141416),
    hero2: Color(0xFF2A2A2F),
    onHero: Color(0xFFF3F2EF),
    onHero2: Color(0xFFA6A5AB),
    info: Color(0xFF2F6BFF),
    success: Color(0xFF14975F),
    danger: Color(0xFFD92D20),
    warmupBg: Color(0xFFFBE8B8),
    warmupFg: Color(0xFF7A5200),
    chartBar: Color(0xFFD8D5CF),
    bodyNeutral: Color(0xFFDCD9D3),
    heat: [
      Color(0xFFE7E4DF),
      Color(0xFFFFD3BF),
      Color(0xFFFFA27A),
      Color(0xFFFF6E33),
      Color(0xFFD9420B),
    ],
    partChest: Color(0xFFFF5B1F),
    partBack: Color(0xFF2F6BFF),
    partLegs: Color(0xFF14975F),
    partShoulders: Color(0xFFE0A100),
    partArms: Color(0xFF8B5CF6),
    partCore: Color(0xFF6B6A70),
    scrim: Color(0x61141416),
  );

  static const dark = AppColors(
    bg: Color(0xFF0D0D0F),
    surface: Color(0xFF17171A),
    sunken: Color(0xFF222226),
    line: Color(0xFF2A2A2F),
    text: Color(0xFFF3F2EF),
    text2: Color(0xFFA6A5AB),
    text3: Color(0xFF85848A),
    accent: Color(0xFFFF6A2E),
    onAccent: Color(0xFF141416),
    accentText: Color(0xFFFF8A57),
    accentSoft: Color(0xFF3A1F14),
    hero: Color(0xFF221A16),
    hero2: Color(0xFF3A2A22),
    onHero: Color(0xFFF3F2EF),
    onHero2: Color(0xFFB9AFA8),
    info: Color(0xFF6E96FF),
    success: Color(0xFF3CC98A),
    danger: Color(0xFFFF6B5E),
    warmupBg: Color(0xFF3D3113),
    warmupFg: Color(0xFFF2C14E),
    chartBar: Color(0xFF34343A),
    bodyNeutral: Color(0xFF26262B),
    heat: [
      Color(0xFF2E2E34),
      Color(0xFF5A2A17),
      Color(0xFF9A3A14),
      Color(0xFFE2541C),
      Color(0xFFFF8A57),
    ],
    partChest: Color(0xFFFF6A2E),
    partBack: Color(0xFF6E96FF),
    partLegs: Color(0xFF3CC98A),
    partShoulders: Color(0xFFF2C14E),
    partArms: Color(0xFFA78BFA),
    partCore: Color(0xFF85848A),
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
  static const double sectionGap = 14;
}

/// 圆角
abstract final class AppRadius {
  static const double xs = 6; // 标签、PR 徽章
  static const double sm = 10; // 组记录里的数字格
  static const double md = 14; // 按钮、输入框、动作图
  static const double lg = 20; // 卡片
  static const double xl = 28; // 底部弹层顶角
  static const double full = 999; // 胶囊

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get button => BorderRadius.circular(md);
}

/// 尺寸：单手操作，触控区不小于 48
abstract final class AppSize {
  static const double touchMin = 48;
  static const double buttonLarge = 56; // 「开始训练」「完成本组」
  static const double button = 48;
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
}

/// 动效
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
  // 触感：完成一组 HapticFeedback.mediumImpact；破纪录 heavyImpact；
  // 休息倒计时结束 震动 + 本地通知（锁屏也要提醒）。
}

/// 文字样式。中文用 NotoSansSC，数字用 BarlowCondensed + 等宽数字。
abstract final class AppText {
  static const String sans = 'NotoSansSC';
  static const String numeric = 'BarlowCondensed';
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  // 数字
  static const numDisplay = TextStyle(fontFamily: numeric, fontSize: 56, height: 1.0, fontWeight: FontWeight.w600, fontFeatures: _tnum);
  static const numLarge = TextStyle(fontFamily: numeric, fontSize: 34, height: 1.1, fontWeight: FontWeight.w600, fontFeatures: _tnum);
  static const numMedium = TextStyle(fontFamily: numeric, fontSize: 22, height: 1.2, fontWeight: FontWeight.w600, fontFeatures: _tnum);
  static const numSmall = TextStyle(fontFamily: numeric, fontSize: 17, height: 1.2, fontWeight: FontWeight.w600, fontFeatures: _tnum);

  // 文字
  static const titleLarge = TextStyle(fontFamily: sans, fontSize: 28, height: 1.25, fontWeight: FontWeight.w700);
  static const titleMedium = TextStyle(fontFamily: sans, fontSize: 20, height: 1.3, fontWeight: FontWeight.w700);
  static const titleSmall = TextStyle(fontFamily: sans, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontFamily: sans, fontSize: 15, height: 1.45, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontFamily: sans, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500);
  static const caption = TextStyle(fontFamily: sans, fontSize: 11, height: 1.45, fontWeight: FontWeight.w500);
  static const button = TextStyle(fontFamily: sans, fontSize: 16, height: 1.2, fontWeight: FontWeight.w700);
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness b, AppColors c) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accentText,
      secondary: c.info,
      onSecondary: const Color(0xFFFFFFFF),
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

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: AppText.sans,
      scaffoldBackgroundColor: c.bg,
      extensions: <ThemeExtension<dynamic>>[c],
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
        titleTextStyle: t(AppText.titleLarge, c.text),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: const Size.fromHeight(AppSize.button),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppText.button,
        ),
      ),
      // 次要按钮：凹槽底、主文字色
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.sunken,
          foregroundColor: c.text,
          elevation: 0,
          minimumSize: const Size.fromHeight(AppSize.button),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppText.button.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.line, width: 1.5),
          minimumSize: const Size(0, AppSize.chip),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
          textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentText,
          textStyle: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.hero,
        foregroundColor: c.accent,
        extendedTextStyle: AppText.body.copyWith(fontWeight: FontWeight.w700, color: c.onHero),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: t(AppText.body, c.text3),
        labelStyle: t(AppText.label, c.text2),
        border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: c.accent, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: c.danger, width: 2)),
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, AppSize.segmented)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.surface : c.sunken),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.text : c.text2),
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
        ),
        selectedIcon: const SizedBox.shrink(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.chartBar),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppSize.navBar,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? c.accentText : c.text2),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => AppText.caption.copyWith(
            fontSize: 12,
            color: s.contains(WidgetState.selected) ? c.text : c.text2,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.hero,
        contentTextStyle: t(AppText.body, c.onHero),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
    );
  }
}

extension AppThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
