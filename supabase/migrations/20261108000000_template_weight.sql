-- 我的健身 · 模板动作增加「目标负重」
-- 添加动作时可以设置每组负重（公斤），保存在模板动作里并随账号同步。
-- 纯新增一个可为空的列，不改动、不删除任何已有数据，可重复执行。
-- 注意：必须先执行本迁移再安装新版 App，否则新版 App 同步模板动作时会因缺列而失败。

alter table public.template_exercises
  add column if not exists target_weight_kg numeric(7, 2)
    check (target_weight_kg is null or target_weight_kg >= 0);
