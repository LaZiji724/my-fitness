import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';

/// 日历圆点、分布图用的部位色。
Color partColor(AppColors c, BodyPart p) => switch (p) {
      BodyPart.chest => c.partChest,
      BodyPart.back => c.partBack,
      BodyPart.legs || BodyPart.glutes => c.partLegs,
      BodyPart.shoulders => c.partShoulders,
      BodyPart.arms => c.partArms,
      BodyPart.core || BodyPart.cardio || BodyPart.other => c.partCore,
    };

/// 日历图例里的分组名。
String partGroupLabel(BodyPart p) => switch (p) {
      BodyPart.chest => '胸',
      BodyPart.back => '背',
      BodyPart.legs || BodyPart.glutes => '腿臀',
      BodyPart.shoulders => '肩',
      BodyPart.arms => '手臂',
      BodyPart.core || BodyPart.cardio || BodyPart.other => '核心',
    };
