# 我的健身

自用的 Android（后续 iPhone）健身记录 App。Flutter + Supabase（免费版），本地优先、云端同步。

```
app/                 Flutter 工程
supabase/migrations/ 建表、触发器、RLS、存储桶（可重复部署的 SQL）
tools/               字体生成、动作库种子脚本、启动图标生成（make_icon.py）
```

## 第一次运行（Mac）

1. 安装 Flutter 与 Android Studio，`flutter doctor` 里 Flutter / Android toolchain 为绿色。
2. 在 Supabase 新建项目；Authentication → Sign In / Providers → Email 里**关闭 Confirm email**，
   并把最小密码长度设为 8。
3. 在 Supabase 后台 SQL Editor 里执行 `supabase/migrations/` 下的 SQL 文件（按文件名顺序）。
4. `cp app/env.example.json app/env.json`，填入 Project URL 和 anon/publishable key（**不要**填 service_role）。
5. 手机连电脑并开启 USB 调试：

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=env.json
```

## 构建可安装的 APK

### 1. 生成签名密钥（只做一次，务必备份）

```bash
keytool -genkey -v -keystore ~/my-fitness-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias my-fitness
```

把 `my-fitness-release.jks` 和你设的密码**备份到安全的地方**（网盘 + 密码管理器）：以后只有用同一个密钥签名的 APK 才能覆盖安装升级，
丢了就只能卸载重装（本地没同步的数据会丢）。

在 `app/android/` 下新建 `key.properties`（已在 `.gitignore`，不会被提交）：

```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=my-fitness
storeFile=/Users/你的用户名/my-fitness-release.jks
```

没有这个文件时会退回调试签名，也能安装，但不能和正式版互相覆盖。

### 2. 构建

```bash
cd app
flutter build apk --release --dart-define-from-file=env.json
# 产物：app/build/app/outputs/flutter-apk/app-release.apk
```

把 APK 发到手机（数据线、网盘、微信文件传输都行），点开安装；第一次需要允许「安装未知来源应用」。
升级时直接安装新版本即可，数据保留。版本号在 `app/pubspec.yaml` 的 `version:`（`1.0.0+1` 里 `+` 后面每次发布要加 1）。

## 云同步、备份与保活

- **本地优先**：训练时写的是手机本地数据库，没网也能正常记录；有网时自动同步到 Supabase
  （启动、改动 3 秒后、回到前台、每 5 分钟）。首页右上角的小标签显示状态，点一下立即同步；「我的」里能看上次同步时间。
- **换手机 / 重装**：登录同一个账号，数据会自动拉回来。
- **冲突**：同一条记录两台设备都改过时，以较晚的修改为准。
- **备份**：「我的 → 导出备份」生成一个 JSON 文件，存到网盘即可；「导入备份」可以合并回来。
  Supabase 免费版**没有自动备份**，建议每月导出一次。
- **防暂停**：免费项目 7 天没有请求会被暂停。每天正常使用就不会触发；长时间不用的话，
  在 GitHub 仓库的 Settings → Secrets and variables → Actions 里添加 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY`，
  `.github/workflows/keepalive.yml` 每周会自动请求一次。如果真被暂停了，到 Supabase 后台点 Restore 即可，数据不会丢。
- **忘记密码**：用户名登录没有邮件找回。到 Supabase 后台 Authentication → Users 里重置该用户密码。

## 常见问题

- **登录时提示网络不可用**：先用手机浏览器打开你的 Supabase 地址（`https://xxxx.supabase.co`）确认能访问；
  国内网络有时需要换网络或开代理。
- **同步提示「云端还没有动作库数据」**：还没上传内置动作，见下面「动作库种子」。
- **同步提示「云端数据库还没建表」**：到 SQL Editor 执行 `supabase/migrations/` 下的 SQL。

## 测试

```bash
cd app && flutter analyze && flutter test
```

## 字体

`app/assets/fonts/` 里的字体（Noto Sans SC 裁剪版、Barlow Condensed）均为 SIL OFL 授权，
由 `tools/make_fonts.py` 生成，说明见脚本顶部。

## 设计

视觉令牌与主题来自 `app/lib/core/theme/app_theme.dart`（风格「铁与火」），组件只引用这里的 token。

## 动作库种子（内置动作 + 图片）

内置动作来自 [free-exercise-db](https://github.com/yuhonas/free-exercise-db)（The Unlicense，公有领域），
手工精选 235 个常用动作并汉化（`tools/seed/curated.txt`）。构建产物已提交在 `tools/seed/out/`
（`exercises.json` + 470 张 480px WebP，共约 10 MB；图片保留照片原有色彩、居中方形裁切，规则在 `build_seed.py` 的 `stylize`），**不需要联网重新构建**。

把它们上传到你自己的 Supabase（只在你的电脑上运行，service_role 密钥不要发给任何人、不要提交）：

```bash
cd tools
python3 -m venv .venv && .venv/bin/pip install requests pillow
export SUPABASE_URL=https://你的项目.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=你的 service_role 密钥
.venv/bin/python seed/upload_seed.py
```

想增删动作：改 `tools/seed/curated.txt`，运行 `.venv/bin/python seed/build_seed.py` 重新构建，再上传。

## 内置训练计划库

「计划」页顶部的入口进入计划库：左侧是分类栏（近期上新、新手入门、进阶计划、有氧跟练、团课计划、瘦身减脂、塑形美体、增肌增重、健康改善、拉伸放松、丰满翘臀、我的收藏），
上方可按频率 / 难度 / 场景 / 人群筛选，也能搜索。详情页有「加入计划」（课程生成为模板，并按周一开始的 7 天循环生成计划）、
「添加到日历」（选一个日期，从那周的周一开始排进日历）和「去训练」（按已完成的节数轮到下一节，热身组、时长目标、休息时间、动作要点都会带进训练页）。

- 计划内容全部是原创文字，动作映射到内置动作库；没有任何第三方的图片或文案。封面是渐变色块，「已练几节」来自你自己的训练记录。
- 离线可用：计划随 App 打包在 `app/assets/seed/programs.json`，云端 `programs*` 表只是同一份内容的只读镜像，方便以后更新。
- 数据来源是 `tools/programs/`（`content_*.py` 写计划，`exercises_extra.py` 补充 86 个拉伸与有氧动作）。改完内容运行：

  ```bash
  python3 tools/programs/build_programs.py
  ```

  会先校验（动作存在、记录方式匹配、每周安排与课次对应），再更新 `programs.json`、`exercises.json` 和 `supabase/seed/program_library.sql`。

升级顺序（只需一次）：

1. 在 Supabase 的 SQL Editor 里执行 `supabase/migrations/20261103000000_program_library.sql`（建表和新列）。
2. 执行 `supabase/seed/program_library.sql`（补充动作 + 计划镜像，可重复执行）。
3. 再安装新版 APK。新版本第一次同步前，云端必须已经完成第 1 步，否则同步会提示缺表。
