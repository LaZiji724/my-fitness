// 我的健身 · 图标（2.8.0）
//
// 全 App 只用 Phosphor 一套图标（MIT 许可，字体文件在 assets/fonts/Phosphor-*.ttf），页面里不直接写 Icons.xxx。
// 这里直接按码位引用字体，不依赖 phosphor_flutter 包。要加新图标：到 phosphoricons.com 查名字，
// 码位见 https://github.com/phosphor-icons/core 里的 icons 列表，行尾注释写上图标名。
// 线宽规则：22px 及以上用 Regular（线宽约 1.5px）；18px 及以下用 Bold，缩小后线宽看起来还是 1.5px。
// 选中态（底部分栏、已收藏）用 Fill。

import 'package:flutter/widgets.dart';

abstract final class AppIcons {
  static const String _regular = 'PhosphorRegular';
  static const String _bold = 'PhosphorBold';
  static const String _fill = 'PhosphorFill';

  // 底部分栏：未选中 / 选中
  static const IconData navTrain = IconData(0xe0b6, fontFamily: _regular); // barbell
  static const IconData navTrainOn = IconData(0xe0b6, fontFamily: _fill); // barbell
  static const IconData navPlan = IconData(0xeadc, fontFamily: _regular); // listChecks
  static const IconData navPlanOn = IconData(0xeadc, fontFamily: _fill); // listChecks
  static const IconData navCalendar = IconData(0xe10a, fontFamily: _regular); // calendarBlank
  static const IconData navCalendarOn = IconData(0xe10a, fontFamily: _fill); // calendarBlank
  static const IconData navExercises = IconData(0xed5c, fontFamily: _regular); // personSimpleTaiChi
  static const IconData navExercisesOn = IconData(0xed5c, fontFamily: _fill); // personSimpleTaiChi
  static const IconData navStats = IconData(0xe150, fontFamily: _regular); // chartBar
  static const IconData navStatsOn = IconData(0xe150, fontFamily: _fill); // chartBar
  static const IconData navFriends = IconData(0xe4d6, fontFamily: _regular); // users
  static const IconData navFriendsOn = IconData(0xe4d6, fontFamily: _fill); // users

  // 导航
  static const IconData back = IconData(0xe058, fontFamily: _regular); // arrowLeft
  static const IconData close = IconData(0xe4f6, fontFamily: _regular); // x
  static const IconData more = IconData(0xe1fe, fontFamily: _regular); // dotsThree
  static const IconData search = IconData(0xe30c, fontFamily: _regular); // magnifyingGlass

  // 小号（≤18px）：加粗
  static const IconData chevronRight = IconData(0xe13a, fontFamily: _bold); // caretRight
  static const IconData chevronLeft = IconData(0xe138, fontFamily: _bold); // caretLeft
  static const IconData chevronDown = IconData(0xe136, fontFamily: _bold); // caretDown
  static const IconData plus = IconData(0xe3d4, fontFamily: _bold); // plus
  static const IconData minus = IconData(0xe32a, fontFamily: _bold); // minus
  static const IconData check = IconData(0xe182, fontFamily: _bold); // check
  static const IconData closeSmall = IconData(0xe4f6, fontFamily: _bold); // x
  static const IconData arrowUp = IconData(0xe08e, fontFamily: _bold); // arrowUp
  static const IconData arrowDown = IconData(0xe03e, fontFamily: _bold); // arrowDown
  static const IconData arrowRight = IconData(0xe06c, fontFamily: _bold); // arrowRight
  static const IconData fire = IconData(0xe242, fontFamily: _fill); // fire
  static const IconData trophy = IconData(0xe67e, fontFamily: _fill); // trophy
  static const IconData play = IconData(0xe3d0, fontFamily: _fill); // play
  static const IconData grip = IconData(0xeae2, fontFamily: _bold); // dotsSixVertical
  static const IconData searchSmall = IconData(0xe30c, fontFamily: _bold); // magnifyingGlass
  static const IconData timerSmall = IconData(0xe492, fontFamily: _bold); // timer
  static const IconData editSmall = IconData(0xe3b4, fontFamily: _bold); // pencilSimple

  // 操作
  static const IconData add = IconData(0xe3d4, fontFamily: _regular); // plus
  static const IconData edit = IconData(0xe3b4, fontFamily: _regular); // pencilSimple
  static const IconData delete = IconData(0xe4a6, fontFamily: _regular); // trash
  static const IconData copy = IconData(0xe1ca, fontFamily: _regular); // copy
  static const IconData share = IconData(0xeaf0, fontFamily: _regular); // export
  static const IconData backspace = IconData(0xe0ae, fontFamily: _regular); // backspace
  static const IconData eye = IconData(0xe220, fontFamily: _regular); // eye
  static const IconData eyeOff = IconData(0xe224, fontFamily: _regular); // eyeSlash
  static const IconData star = IconData(0xe46a, fontFamily: _regular); // star
  static const IconData starOn = IconData(0xe46a, fontFamily: _fill); // star
  static const IconData listAdd = IconData(0xe2f8, fontFamily: _regular); // listPlus
  static const IconData saveTemplate = IconData(0xe0ea, fontFamily: _regular); // bookmarkSimple
  static const IconData fileOpen = IconData(0xe61e, fontFamily: _regular); // fileArrowUp

  // 内容
  static const IconData barbell = IconData(0xe0b6, fontFamily: _regular); // barbell
  static const IconData calendar = IconData(0xe10a, fontFamily: _regular); // calendarBlank
  static const IconData calendarOk = IconData(0xe712, fontFamily: _regular); // calendarCheck
  static const IconData calendarOff = IconData(0xe10c, fontFamily: _regular); // calendarX
  static const IconData timer = IconData(0xe492, fontFamily: _regular); // timer
  static const IconData user = IconData(0xe4c2, fontFamily: _regular); // user
  static const IconData userOn = IconData(0xe4c2, fontFamily: _fill); // user
  static const IconData tip = IconData(0xe2dc, fontFamily: _regular); // lightbulb
  static const IconData place = IconData(0xe316, fontFamily: _regular); // mapPin
  static const IconData library = IconData(0xe758, fontFamily: _regular); // books
  static const IconData bell = IconData(0xe5e8, fontFamily: _regular); // bellRinging
  static const IconData bellOff = IconData(0xe0d4, fontFamily: _regular); // bellSlash
  static const IconData update = IconData(0xe030, fontFamily: _regular); // arrowCircleUp
  static const IconData rest = IconData(0xe1c2, fontFamily: _regular); // coffee

  // 同步
  static const IconData cloudDone = IconData(0xe1b0, fontFamily: _bold); // cloudCheck
  static const IconData cloudUp = IconData(0xe1ae, fontFamily: _bold); // cloudArrowUp
  static const IconData cloudOff = IconData(0xe1b6, fontFamily: _bold); // cloudSlash
  static const IconData syncing = IconData(0xe094, fontFamily: _bold); // arrowsClockwise
  static const IconData sync = IconData(0xe094, fontFamily: _regular); // arrowsClockwise
  static const IconData cloudUpLarge = IconData(0xe1ae, fontFamily: _regular); // cloudArrowUp

  // 计划库分类
  static const IconData catMuscle = IconData(0xe0b6, fontFamily: _regular); // barbell
  static const IconData catFatLoss = IconData(0xe242, fontFamily: _regular); // fire
  static const IconData catShape = IconData(0xecfe, fontFamily: _regular); // personArmsSpread
  static const IconData catStretch = IconData(0xe6cc, fontFamily: _regular); // flowerLotus
  static const IconData catRehab = IconData(0xe56e, fontFamily: _regular); // firstAid
  static const IconData catCardio = IconData(0xe730, fontFamily: _regular); // personSimpleRun
  static const IconData catPower = IconData(0xe2de, fontFamily: _regular); // lightning
  static const IconData catGroup = IconData(0xe68e, fontFamily: _regular); // usersThree

  // 好友与聊天
  static const IconData friends = IconData(0xe4d6, fontFamily: _regular); // users
  static const IconData userAdd = IconData(0xe4d0, fontFamily: _regular); // userPlus
  static const IconData userRemove = IconData(0xe4ce, fontFamily: _regular); // userMinus
  static const IconData qrCode = IconData(0xe3e6, fontFamily: _regular); // qrCode
  static const IconData scan = IconData(0xebb6, fontFamily: _regular); // scan
  static const IconData chat = IconData(0xe168, fontFamily: _regular); // chatCircle
  static const IconData emoji = IconData(0xe436, fontFamily: _regular); // smiley
  static const IconData keyboard = IconData(0xe2d8, fontFamily: _regular); // keyboard
  static const IconData send = IconData(0xe396, fontFamily: _fill); // paperPlaneRight
  static const IconData privacy = IconData(0xe40c, fontFamily: _regular); // shieldCheck
  static const IconData privacySmall = IconData(0xe40c, fontFamily: _bold); // shieldCheck
  static const IconData lockSmall = IconData(0xe308, fontFamily: _bold); // lockSimple
  static const IconData eyeSmall = IconData(0xe220, fontFamily: _bold); // eye
  static const IconData eyeOffSmall = IconData(0xe224, fontFamily: _bold); // eyeSlash
  static const IconData clock = IconData(0xe19a, fontFamily: _regular); // clock
  static const IconData scale = IconData(0xe750, fontFamily: _regular); // scales
  static const IconData listDetail = IconData(0xeadc, fontFamily: _regular); // listChecks
  static const IconData refreshSmall = IconData(0xe036, fontFamily: _bold); // arrowClockwise
  static const IconData warnSmall = IconData(0xe4e2, fontFamily: _fill); // warningCircle
  static const IconData camera = IconData(0xe10e, fontFamily: _fill); // camera
  static const IconData cameraSmall = IconData(0xe10e, fontFamily: _bold); // camera
  static const IconData photo = IconData(0xe2ca, fontFamily: _regular); // image
  static const IconData cameraOff = IconData(0xe110, fontFamily: _regular); // cameraSlash
  static const IconData flashlight = IconData(0xe246, fontFamily: _regular); // flashlight
  static const IconData flashlightOn = IconData(0xe246, fontFamily: _fill); // flashlight
}
