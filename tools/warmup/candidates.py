"""激活 / 拉伸动作候选清单（方案阶段，尚未入库）。

字段：key, 中文名, kind, 区域, 目标肌群(中文), 要点, 建议量, 图片来源
kind：activation 激活 | dynamic 动态热身 | stretch 静态拉伸 | foam 泡沫轴放松
区域：neck_shoulder 颈肩 | chest_arm 胸臂 | back_core 背腹 | hip_glute 髋臀 | leg 大小腿 | full 全身
图片来源：
  db:<ID>    free-exercise-db 里有现成配图（The Unlicense），入库时按「铁与火」统一调色
  lib:<ID>   已在现有 235 个动作库里，只需补 kind / 区域标签，不用新图
  extra:<slug>  PR #2 里已有的原创动作（无配图），只补标签
  new        新原创动作，无配图（占位图 / 简笔画）
"""

# (key, name_zh, kind, region, muscles, cue, dose, src)
C = [
 # ───────────── 激活（让该发力的肌肉先醒过来，热身用）
 ("glute_bridge", "臀桥", "activation", "hip_glute", "臀大肌", "脚跟蹬地把髋顶起，顶点夹臀停 1 秒，肋骨不外翻", "12–15 次 × 2 组", "lib:Butt_Lift_Bridge"),
 ("single_leg_bridge", "单腿臀桥", "activation", "hip_glute", "臀大肌、腘绳肌", "骨盆保持水平，不要让未发力一侧下沉", "每侧 8–10 次 × 2 组", "lib:Single_Leg_Glute_Bridge"),
 ("band_hip_lift", "弹力带臀桥", "activation", "hip_glute", "臀大肌、臀中肌", "弹力带绕在膝上方，顶髋时膝盖向外撑住带子", "12–15 次 × 2 组", "db:Hip_Lift_with_Band"),
 ("band_hip_extension", "弹力带髋后伸", "activation", "hip_glute", "臀大肌", "站姿脚踝套带向后踢，用臀部发力，腰不要代偿", "每侧 12 次 × 2 组", "db:Hip_Extension_with_Bands"),
 ("band_hip_adduction", "弹力带髋内收", "activation", "hip_glute", "内收肌", "站姿脚踝套带向内夹，慢进慢出", "每侧 12 次 × 2 组", "db:Band_Hip_Adductions"),
 ("monster_walk", "弹力带怪兽步", "activation", "hip_glute", "臀中肌", "半蹲姿势侧向走，膝盖不内扣，带子始终有张力", "每侧 10 步 × 2 组", "lib:Monster_Walk"),
 ("clamshell", "蚌式开合", "activation", "hip_glute", "臀中肌", "侧卧屈膝，骨盆不后倒，只让膝盖打开", "每侧 12–15 次 × 2 组", "extra:fc_clamshell"),
 ("fire_hydrant", "消防栓式抬腿", "activation", "hip_glute", "臀中肌、臀大肌", "四点支撑，腰背平直，膝盖向外侧抬到髋高", "每侧 12 次 × 2 组", "extra:fc_fire_hydrant"),
 ("glute_bridge_march", "臀桥交替抬腿", "activation", "hip_glute", "臀大肌、核心", "髋部保持抬高，骨盆不左右晃", "每侧 8 次 × 2 组", "extra:fc_glute_bridge_march"),
 ("frog_pump", "青蛙式臀桥", "activation", "hip_glute", "臀大肌", "脚掌相对、膝盖外打开，顶髋夹臀", "15–20 次 × 2 组", "extra:fc_frog_pump"),
 ("donkey_kick", "驴踢腿", "activation", "hip_glute", "臀大肌", "膝盖保持弯曲，脚掌朝天花板蹬，不塌腰", "每侧 12 次 × 2 组", "extra:fc_donkey_kick"),
 ("dead_bug", "死虫式", "activation", "back_core", "腹横肌、腹直肌", "下背压住地面，对侧手脚慢慢伸出，呼气发力", "每侧 8 次 × 2 组", "lib:Dead_Bug"),
 ("bird_dog", "鸟狗式", "activation", "back_core", "竖脊肌、臀大肌", "伸手伸腿时骨盆不晃，停 2 秒再收回", "每侧 8 次 × 2 组", "extra:fc_bird_dog"),
 ("side_bridge", "侧平板支撑", "activation", "back_core", "腹斜肌、腰方肌", "肘在肩正下方，身体成一条线", "每侧 20–30 秒 × 2 组", "lib:Side_Bridge"),
 ("pelvic_tilt_bridge", "骨盆后倾卷臀", "activation", "back_core", "腹直肌、臀大肌", "从尾椎开始一节一节卷起，再一节一节放下", "10 次 × 2 组", "db:Pelvic_Tilt_Into_Bridge"),
 ("superman", "超人式背伸展", "activation", "back_core", "竖脊肌、臀大肌", "手臂和双腿抬离地面一点，停 2 秒，不仰头", "10 次 × 2 组", "db:Superman"),
 ("band_pull_apart", "弹力带拉开", "activation", "neck_shoulder", "后三角肌、菱形肌", "手臂平举拉开带子，肩胛后收，肩不耸", "15 次 × 2 组", "lib:Band_Pull_Apart"),
 ("band_external_rotation", "弹力带肩外旋", "activation", "neck_shoulder", "肩袖（冈下肌、小圆肌）", "肘夹紧身体、屈 90 度，向外拉开，宁轻勿重", "每侧 12–15 次 × 2 组", "db:External_Rotation_with_Band"),
 ("band_internal_rotation", "弹力带肩内旋", "activation", "neck_shoulder", "肩袖（肩胛下肌）", "肘夹紧身体，向腹部方向拉，动作慢", "每侧 12–15 次 × 2 组", "db:Internal_Rotation_with_Band"),
 ("band_back_fly", "弹力带反向飞鸟", "activation", "neck_shoulder", "后三角肌、中背部", "手臂微屈向两侧拉开，肩胛后收", "15 次 × 2 组", "db:Back_Flyes_-_With_Bands"),
 ("scapular_pullup", "肩胛下沉引体", "activation", "back_core", "下斜方肌、背阔肌", "悬挂，手臂伸直，只靠肩胛下沉把身体提起一点", "8–10 次 × 2 组", "db:Scapular_Pull-Up"),
 ("wall_angel", "靠墙天使", "activation", "neck_shoulder", "中下斜方肌、前锯肌", "背贴墙，双臂沿墙上下滑，腰不拱", "10 次 × 2 组", "extra:fc_wall_angel"),
 ("scapular_pushup", "肩胛俯卧撑", "activation", "neck_shoulder", "前锯肌", "手臂伸直，只让肩胛前伸、后收", "10–12 次 × 2 组", "extra:fc_scapular_pushup"),
 ("prone_ytw", "俯卧 Y-T-W 上举", "activation", "neck_shoulder", "中下斜方肌、后三角肌", "拇指朝上，用肩胛骨发力，幅度小而慢", "每个字母 6 次", "extra:fc_prone_ytw"),
 ("chin_tuck", "下巴内收", "activation", "neck_shoulder", "颈深屈肌", "下巴水平向后收，停 5 秒，不低头不仰头", "8 次 × 2 组", "extra:fc_chin_tuck"),
 ("hip_hinge_drill", "髋铰链练习", "activation", "hip_glute", "臀大肌、腘绳肌", "手放大腿根，臀部向后推，背保持平直", "10 次 × 2 组", "extra:fc_hip_hinge_drill"),
 ("single_leg_balance", "单腿站立平衡", "activation", "leg", "足踝稳定肌、臀中肌", "站稳后可闭眼或站软垫增加难度", "每侧 30 秒 × 2 组", "extra:fc_single_leg_balance"),
 ("wall_knee_drive", "靠墙顶膝", "activation", "hip_glute", "髂腰肌、腹部", "手扶墙，单膝向上顶到髋高，停 2 秒", "每侧 10 次 × 2 组", "new"),
 ("tibialis_raise", "靠墙勾脚尖", "activation", "leg", "胫骨前肌", "背靠墙、脚后跟前伸，勾起脚尖再放下", "15–20 次 × 2 组", "new"),

 # ───────────── 动态热身（运动前，边动边拉开）
 ("worlds_greatest", "全身动态拉伸（弓步转体）", "dynamic", "full", "髋屈肌、腘绳肌、胸椎", "弓步手撑地，另一臂向天花板打开转胸，眼睛跟手", "每侧 5 次", "db:Worlds_Greatest_Stretch"),
 ("inchworm", "尺蠖爬行", "dynamic", "full", "腘绳肌、核心、肩", "手向前爬到平板，再把脚走回手边，膝尽量伸直", "6–8 次", "db:Inchworm"),
 ("cat_cow", "猫牛式", "dynamic", "back_core", "脊柱、竖脊肌", "吸气塌腰抬头，呼气拱背低头，配合呼吸", "10 次", "db:Cat_Stretch"),
 ("arm_circles", "手臂绕环", "dynamic", "neck_shoulder", "三角肌、肩袖", "先小圈再大圈，再反向，肩不耸", "每向 10 次", "db:Arm_Circles"),
 ("shoulder_circles", "肩部绕环", "dynamic", "neck_shoulder", "斜方肌、三角肌", "肩膀向上、向后、向下画大圈", "每向 10 次", "db:Shoulder_Circles"),
 ("elbow_circles", "肘部绕环", "dynamic", "neck_shoulder", "肩袖、三角肌", "指尖搭肩，用肘画圈", "每向 10 次", "db:Elbow_Circles"),
 ("dynamic_chest", "动态扩胸", "dynamic", "chest_arm", "胸大肌、三角肌前束", "手臂胸前交叉再向后打开，节奏流畅", "12 次", "db:Dynamic_Chest_Stretch"),
 ("dynamic_back", "动态背部拉伸", "dynamic", "back_core", "背阔肌、斜方肌", "手臂摆动带动躯干轻转，不要用力甩", "每侧 10 次", "db:Dynamic_Back_Stretch"),
 ("standing_hip_circles", "站姿髋绕环", "dynamic", "hip_glute", "髋关节周围肌群", "单腿站稳，另一膝抬起向外画大圈", "每向每侧 8 次", "db:Standing_Hip_Circles"),
 ("prone_hip_circles", "四点髋绕环", "dynamic", "hip_glute", "臀中肌、髋外旋肌", "四点支撑，一膝抬起画大圈，腰背平直", "每向每侧 8 次", "db:Hip_Circles_prone"),
 ("front_leg_swing", "前后摆腿", "dynamic", "leg", "腘绳肌、髋屈肌", "扶稳后腿前后摆动，幅度由小渐大", "每侧 10 次", "db:Front_Leg_Raises"),
 ("side_leg_swing", "侧向摆腿", "dynamic", "hip_glute", "内收肌、外展肌", "扶稳后腿左右摆动，上身稳定", "每侧 10 次", "db:Side_Leg_Raises"),
 ("rear_leg_raise", "四点后踢摆腿", "dynamic", "hip_glute", "臀大肌、股四头肌", "四点支撑，一腿向后蹬出再收回", "每侧 10 次", "db:Rear_Leg_Raises"),
 ("groiners", "深蹲撑地开髋", "dynamic", "hip_glute", "内收肌、髋", "从平板位把一脚迈到手外侧，髋下沉再换", "每侧 6 次", "db:Groiners"),
 ("sit_squats", "坐姿深蹲活动", "dynamic", "leg", "股四头肌、臀大肌", "慢慢下蹲到最低点停 2 秒，脚跟不离地", "8–10 次", "db:Sit_Squats"),
 ("split_squats", "分腿蹲活动", "dynamic", "leg", "股四头肌、臀大肌", "前后站开，垂直下沉，不要向前冲膝", "每侧 8 次", "db:Split_Squats"),
 ("ankle_circles", "踝关节绕环", "dynamic", "leg", "踝关节", "单脚离地，脚尖画大圆，小腿不带动", "每向每侧 10 次", "db:Ankle_Circles"),
 ("knee_circles", "膝关节绕环", "dynamic", "leg", "膝关节", "双脚并拢、手扶膝，缓慢画小圈", "每向 8 次", "db:Knee_Circles"),
 ("wrist_circles", "手腕绕环", "dynamic", "chest_arm", "前臂、腕关节", "双手交扣或单独画圈，范围由小渐大", "每向 10 次", "db:Wrist_Circles"),
 ("torso_rotation", "站姿躯干转体", "dynamic", "back_core", "腹斜肌、胸椎", "骨盆朝前，只转胸腔，手持轻球或徒手", "每侧 10 次", "db:Torso_Rotation"),
 ("windmills", "仰卧风车转体", "dynamic", "back_core", "腰背、腹斜肌", "仰卧手臂打开，一腿摆向对侧，肩不离地", "每侧 8 次", "db:Windmills"),
 ("leg_swing_wall", "扶墙摆腿", "dynamic", "leg", "腘绳肌、髋屈肌", "单手扶墙前后摆，上身稳定", "每侧 10 次", "extra:fc_leg_swing"),
 ("ankle_mobilization", "靠墙踝背屈", "dynamic", "leg", "小腿、踝", "膝盖向前顶向墙，脚跟踩实", "每侧 10 次", "extra:fc_ankle_dorsiflexion"),
 ("thoracic_rotation", "跪姿胸椎旋转", "dynamic", "back_core", "胸椎、肩", "手扶脑后，肘向下转向对侧再向上打开", "每侧 8 次", "extra:fc_thoracic_rotation"),
 ("hip_9090", "90/90 髋旋转", "dynamic", "hip_glute", "髋外旋、内旋肌", "前后腿各 90 度，双膝从一侧倒向另一侧", "每侧 8 次", "extra:fc_9090_hip"),

 # ───────────── 静态拉伸（放松，每个拉到有牵拉感、不疼）
 ("neck_side", "颈部侧向拉伸", "stretch", "neck_shoulder", "斜方肌上束、颈侧", "头向一侧缓倾，另一侧肩下沉，力度轻", "每侧 30 秒", "db:Side_Neck_Stretch"),
 ("neck_flex", "颈后侧拉伸", "stretch", "neck_shoulder", "颈后肌群", "坐直，让头自然低向胸口，背不要弓", "30 秒", "db:Chin_To_Chest_Stretch"),
 ("cross_body_shoulder", "肩后侧交叉拉伸", "stretch", "neck_shoulder", "三角肌后束", "一臂横过胸前，另一手托住肘向身体拉", "每侧 30 秒", "db:Shoulder_Stretch"),
 ("overhead_reach", "站姿上举伸展", "stretch", "neck_shoulder", "三角肌、背阔肌", "双手交扣向上推，身体向上延伸", "30 秒", "db:Upward_Stretch"),
 ("stick_shoulder", "木棍绕肩拉伸", "stretch", "neck_shoulder", "三角肌前束、胸大肌", "双手握棍从前向后绕过头顶，握距宽一点", "10 次", "db:Round_The_World_Shoulder_Stretch"),
 ("chest_stick", "木棍胸肩拉伸", "stretch", "chest_arm", "胸大肌、三角肌前束", "握棍向前上方推，胸口打开，肩不耸", "30 秒", "db:Chest_And_Front_Of_Shoulder_Stretch"),
 ("doorway_chest", "靠墙胸部拉伸", "stretch", "chest_arm", "胸大肌", "前臂贴墙，身体缓缓转离，胸口前侧有牵拉", "每侧 30 秒", "db:One_Arm_Against_Wall"),
 ("triceps_overhead", "过头三头肌拉伸", "stretch", "chest_arm", "肱三头肌", "一臂上举屈肘，另一手轻压肘部，背部保持直立", "每侧 30 秒", "db:Triceps_Stretch"),
 ("triceps_side", "三头肌侧拉伸", "stretch", "chest_arm", "肱三头肌、背阔肌", "手放脑后，另一手拉肘并向侧倾", "每侧 30 秒", "db:Tricep_Side_Stretch"),
 ("forearm_kneel", "跪姿前臂拉伸", "stretch", "chest_arm", "前臂屈肌", "手掌朝后撑地，臀部向后坐，慢慢加大牵拉", "30 秒", "db:Kneeling_Forearm_Stretch"),
 ("wrist_pull", "侧向拉腕", "stretch", "chest_arm", "前臂、肩", "一手拉另一手手背，使手腕向内侧屈", "每侧 20 秒", "db:Side_Wrist_Pull"),
 ("child_pose", "婴儿式", "stretch", "back_core", "背阔肌、下背", "臀部坐向脚跟，双臂前伸，深呼吸放松", "40–60 秒", "db:Childs_Pose"),
 ("hug_knees", "仰卧抱膝", "stretch", "back_core", "下背、臀大肌", "双手抱膝向胸口靠，背贴地放松", "30 秒", "db:Hug_Knees_To_Chest"),
 ("spinal_twist_chair", "坐姿脊柱扭转", "stretch", "back_core", "竖脊肌、腹斜肌", "坐直，一手扶对侧膝盖，缓慢转向后方", "每侧 30 秒", "db:Spinal_Stretch"),
 ("seated_side_bend", "坐姿侧屈拉伸", "stretch", "back_core", "腹斜肌、背阔肌", "一臂上举侧倾，盘腿坐稳，骨盆不翘", "每侧 30 秒", "db:Seated_Overhead_Stretch"),
 ("standing_side_bend", "站姿侧弯拉伸", "stretch", "back_core", "腹斜肌、背阔肌", "一手上举向侧弯，髋不外顶", "每侧 30 秒", "db:Standing_Lateral_Stretch"),
 ("lying_floor_side", "侧卧背阔肌拉伸", "stretch", "back_core", "背阔肌", "侧卧一臂过头向远处伸，身体延展", "每侧 30 秒", "db:Side-Lying_Floor_Stretch"),
 ("dancers_twist", "坐姿髋外旋转体", "stretch", "hip_glute", "臀大肌、腰背", "坐姿一腿屈曲，上身向另一侧转，背保持直立", "每侧 30 秒", "db:Dancers_Stretch"),
 ("kneel_hip_flexor", "跪姿髋屈肌拉伸", "stretch", "hip_glute", "髂腰肌、股四头肌", "单膝跪地，骨盆前推下沉，上身直立不塌腰", "每侧 30–40 秒", "db:Kneeling_Hip_Flexor"),
 ("stand_hip_flexor", "站姿髋屈肌拉伸", "stretch", "hip_glute", "髂腰肌", "弓步站姿，后腿伸直，臀夹紧向前推髋", "每侧 30 秒", "db:Standing_Hip_Flexors"),
 ("figure4", "4 字拉伸", "stretch", "hip_glute", "臀大肌、梨状肌", "仰卧，脚踝搭对侧膝，抱住下方大腿向胸口拉", "每侧 30–45 秒", "db:Ankle_On_The_Knee"),
 ("knee_across", "仰卧膝过身体拉伸", "stretch", "hip_glute", "臀大肌、髂胫束", "仰卧，一膝被对侧手带向对侧肩，肩膀贴地", "每侧 30 秒", "db:Knee_Across_The_Body"),
 ("knee_to_chest", "单膝抱胸", "stretch", "hip_glute", "臀大肌、下背", "仰卧，一膝抱向胸口，另一腿放平", "每侧 30 秒", "db:One_Knee_To_Chest"),
 ("butterfly", "蝴蝶式内收肌拉伸", "stretch", "hip_glute", "内收肌", "脚掌相对，膝盖自然下沉，背挺直，不要用手压膝", "30–40 秒", "db:Groin_and_Back_Stretch"),
 ("straddle", "坐姿宽距前屈", "stretch", "hip_glute", "内收肌、腘绳肌", "双腿分开坐，上身从髋部向前折叠", "30–40 秒", "db:The_Straddle"),
 ("band_it_glute", "弹力带髂胫束臀部拉伸", "stretch", "hip_glute", "髂胫束、臀大肌", "仰卧，用带子把腿拉向对侧，肩不离地", "每侧 30 秒", "db:IT_Band_and_Glute_Stretch"),
 ("seated_hamstring", "坐姿腘绳肌拉伸", "stretch", "leg", "腘绳肌", "一腿伸直一腿屈，上身从髋部向脚尖方向折", "每侧 30 秒", "db:Seated_Floor_Hamstring_Stretch"),
 ("lying_hamstring", "仰卧腘绳肌拉伸", "stretch", "leg", "腘绳肌", "仰卧抬腿，双手或毛巾拉住，膝盖尽量伸直", "每侧 30 秒", "db:Leg-Up_Hamstring_Stretch"),
 ("toe_touch", "站姿触脚尖", "stretch", "leg", "腘绳肌、下背", "膝盖微屈，从髋部折叠，让上身自然垂下", "30 秒", "db:Standing_Toe_Touches"),
 ("quad_standing", "站姿股四头肌拉伸", "stretch", "leg", "股四头肌", "手抓脚踝向臀拉，膝盖并拢，骨盆不前倾", "每侧 30 秒", "db:Standing_Elevated_Quad_Stretch"),
 ("quad_all_fours", "四点跪股四头肌拉伸", "stretch", "leg", "股四头肌", "四点支撑，手抓脚踝向臀拉，腰不塌", "每侧 30 秒", "db:All_Fours_Quad_Stretch"),
 ("calf_wall", "靠墙小腿拉伸", "stretch", "leg", "腓肠肌", "手扶墙，一脚后蹬、膝伸直，脚跟不离地", "每侧 30 秒", "db:Calf_Stretch_Hands_Against_Wall"),
 ("soleus_wall", "比目鱼肌与跟腱拉伸", "stretch", "leg", "比目鱼肌、跟腱", "后腿膝盖微屈，脚跟踩实，身体前倾", "每侧 30 秒", "db:Standing_Soleus_And_Achilles_Stretch"),

 # ───────────── 泡沫轴放松（运动后滚动、找酸痛点停留）
 ("foam_quad", "泡沫轴大腿前侧", "foam", "leg", "股四头肌", "俯撑，前臂支撑缓慢滚动，避开膝盖骨", "30–60 秒", "db:Quadriceps-SMR"),
 ("foam_hamstring", "泡沫轴大腿后侧", "foam", "leg", "腘绳肌", "坐姿轴放大腿后侧，手撑地抬臀滚动", "30–60 秒", "db:Hamstring-SMR"),
 ("foam_calf", "泡沫轴小腿", "foam", "leg", "小腿三头肌", "坐姿轴放小腿下方，抬臀缓慢滚动", "30–60 秒", "db:Calves-SMR"),
 ("foam_itband", "泡沫轴大腿外侧", "foam", "hip_glute", "髂胫束", "侧卧轴垫大腿外侧，较敏感，从轻开始", "30–60 秒", "db:Iliotibial_Tract-SMR"),
 ("foam_glute", "泡沫轴臀部", "foam", "hip_glute", "臀大肌、梨状肌", "坐在轴上一腿搭对侧膝，向搭腿侧倾斜滚动", "30–60 秒", "db:Piriformis-SMR"),
 ("foam_adductor", "泡沫轴内收肌", "foam", "hip_glute", "内收肌", "俯卧一腿侧抬放在轴上，缓慢滚动", "30–60 秒", "db:Adductor"),
 ("foam_lat", "泡沫轴背阔肌", "foam", "back_core", "背阔肌", "侧卧轴垫在腋下，手臂上举，小范围滚动", "30–60 秒", "db:Latissimus_Dorsi-SMR"),
 ("foam_upper_back", "泡沫轴上背", "foam", "back_core", "菱形肌、中背部", "双手抱头、抬臀，在肩胛下缘滚动，不要滚腰", "30–60 秒", "db:Rhomboids-SMR"),
 ("foam_shin", "泡沫轴小腿前侧", "foam", "leg", "胫骨前肌", "四点支撑，把小腿前侧压在轴上缓慢滚动", "30 秒", "db:Anterior_Tibialis-SMR"),
 ("foam_foot", "足底按压放松", "foam", "leg", "足底筋膜", "坐在椅上，脚踩小球或轴前后滚动", "30–60 秒", "db:Foot-SMR"),
]

KIND_ZH = {"activation": "激活", "dynamic": "动态热身", "stretch": "静态拉伸", "foam": "泡沫轴放松"}
REGION_ZH = {"neck_shoulder": "颈肩", "chest_arm": "胸臂", "back_core": "背腹", "hip_glute": "髋臀", "leg": "腿", "full": "全身"}

if __name__ == "__main__":
    import collections
    print(len(C), collections.Counter(c[2] for c in C), collections.Counter(c[7].split(":")[0] for c in C))
    keys = [c[0] for c in C]; assert len(set(keys)) == len(keys)
