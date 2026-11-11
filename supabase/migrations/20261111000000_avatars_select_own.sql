-- 头像桶补一条「只能查看自己目录」的权限。
-- 没有它时：换头像后删不掉旧头像文件（Storage 删除要先能查到文件），旧文件会一直留着。
-- 不影响别人看头像：avatars 桶是公开的，读图不走这条权限。
create policy "avatars_select_own_folder" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
