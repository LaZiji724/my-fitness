// 我的健身 · 图标（2.8.0）
//
// 全 App 只用 Phosphor 一套图标，页面里不直接写 Icons.xxx。
// 线宽规则：22px 及以上用 Regular（线宽约 1.5px）；18px 及以下用 Bold，缩小后线宽看起来还是 1.5px。
// 选中态（底部分栏、已收藏）用 Fill。

import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

abstract final class AppIcons {
  // 底部分栏：未选中 / 选中
  static const IconData navTrain = PhosphorIconsRegular.barbell;
  static const IconData navTrainOn = PhosphorIconsFill.barbell;
  static const IconData navPlan = PhosphorIconsRegular.listChecks;
  static const IconData navPlanOn = PhosphorIconsFill.listChecks;
  static const IconData navCalendar = PhosphorIconsRegular.calendarBlank;
  static const IconData navCalendarOn = PhosphorIconsFill.calendarBlank;
  static const IconData navExercises = PhosphorIconsRegular.personSimpleTaiChi;
  static const IconData navExercisesOn = PhosphorIconsFill.personSimpleTaiChi;
  static const IconData navStats = PhosphorIconsRegular.chartBar;
  static const IconData navStatsOn = PhosphorIconsFill.chartBar;

  // 导航
  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData more = PhosphorIconsRegular.dotsThree;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;

  // 小号（≤18px）：加粗
  static const IconData chevronRight = PhosphorIconsBold.caretRight;
  static const IconData chevronLeft = PhosphorIconsBold.caretLeft;
  static const IconData chevronDown = PhosphorIconsBold.caretDown;
  static const IconData plus = PhosphorIconsBold.plus;
  static const IconData minus = PhosphorIconsBold.minus;
  static const IconData check = PhosphorIconsBold.check;
  static const IconData closeSmall = PhosphorIconsBold.x;
  static const IconData arrowUp = PhosphorIconsBold.arrowUp;
  static const IconData arrowDown = PhosphorIconsBold.arrowDown;
  static const IconData arrowRight = PhosphorIconsBold.arrowRight;
  static const IconData fire = PhosphorIconsFill.fire;
  static const IconData trophy = PhosphorIconsFill.trophy;
  static const IconData play = PhosphorIconsFill.play;
  static const IconData grip = PhosphorIconsBold.dotsSixVertical;
  static const IconData searchSmall = PhosphorIconsBold.magnifyingGlass;
  static const IconData timerSmall = PhosphorIconsBold.timer;
  static const IconData editSmall = PhosphorIconsBold.pencilSimple;

  // 操作
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData edit = PhosphorIconsRegular.pencilSimple;
  static const IconData delete = PhosphorIconsRegular.trash;
  static const IconData copy = PhosphorIconsRegular.copy;
  static const IconData share = PhosphorIconsRegular.export;
  static const IconData backspace = PhosphorIconsRegular.backspace;
  static const IconData eye = PhosphorIconsRegular.eye;
  static const IconData eyeOff = PhosphorIconsRegular.eyeSlash;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData starOn = PhosphorIconsFill.star;
  static const IconData listAdd = PhosphorIconsRegular.listPlus;
  static const IconData saveTemplate = PhosphorIconsRegular.bookmarkSimple;
  static const IconData fileOpen = PhosphorIconsRegular.fileArrowUp;

  // 内容
  static const IconData barbell = PhosphorIconsRegular.barbell;
  static const IconData calendar = PhosphorIconsRegular.calendarBlank;
  static const IconData calendarOk = PhosphorIconsRegular.calendarCheck;
  static const IconData calendarOff = PhosphorIconsRegular.calendarX;
  static const IconData timer = PhosphorIconsRegular.timer;
  static const IconData user = PhosphorIconsRegular.user;
  static const IconData userOn = PhosphorIconsFill.user;
  static const IconData tip = PhosphorIconsRegular.lightbulb;
  static const IconData place = PhosphorIconsRegular.mapPin;
  static const IconData library = PhosphorIconsRegular.books;
  static const IconData bell = PhosphorIconsRegular.bellRinging;
  static const IconData bellOff = PhosphorIconsRegular.bellSlash;
  static const IconData update = PhosphorIconsRegular.arrowCircleUp;
  static const IconData rest = PhosphorIconsRegular.coffee;

  // 同步
  static const IconData cloudDone = PhosphorIconsBold.cloudCheck;
  static const IconData cloudUp = PhosphorIconsBold.cloudArrowUp;
  static const IconData cloudOff = PhosphorIconsBold.cloudSlash;
  static const IconData syncing = PhosphorIconsBold.arrowsClockwise;
  static const IconData sync = PhosphorIconsRegular.arrowsClockwise;
  static const IconData cloudUpLarge = PhosphorIconsRegular.cloudArrowUp;

  // 计划库分类
  static const IconData catMuscle = PhosphorIconsRegular.barbell;
  static const IconData catFatLoss = PhosphorIconsRegular.fire;
  static const IconData catShape = PhosphorIconsRegular.personArmsSpread;
  static const IconData catStretch = PhosphorIconsRegular.flowerLotus;
  static const IconData catRehab = PhosphorIconsRegular.firstAid;
  static const IconData catCardio = PhosphorIconsRegular.personSimpleRun;
  static const IconData catPower = PhosphorIconsRegular.lightning;
  static const IconData catGroup = PhosphorIconsRegular.usersThree;
}
