-- ---------------------------------------------------------------------------
-- 收回 handle_new_user() 的直接调用权限。
-- 这个函数只给 auth.users 上的 on_auth_user_created 触发器用（注册后自动建档），
-- App 从不通过 /rest/v1/rpc 调它。默认 PUBLIC / anon / authenticated 都能直接调用，
-- 而它是 SECURITY DEFINER，Supabase 安全顾问会报警。
-- 触发器执行时不检查 EXECUTE 权限，所以收回后注册建档照常工作。
-- 语句可重复执行，已经手动执行过也没关系。
revoke execute on function public.handle_new_user() from public, anon, authenticated;
