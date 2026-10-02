-- 0018_storage.sql — buckets + object policies
insert into storage.buckets (id, name, public)
values ('avatars','avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
values ('verification-documents','verification-documents', false) on conflict (id) do nothing;

-- avatars: public read, owner writes under <uid>/...
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select
  using (bucket_id = 'avatars');
drop policy if exists avatars_write on storage.objects;
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- verification documents: strictly private, owner upload, owner+admin read (signed URLs)
drop policy if exists verifdocs_read on storage.objects;
create policy verifdocs_read on storage.objects for select to authenticated
  using (bucket_id='verification-documents'
         and ((storage.foldername(name))[1] = auth.uid()::text or app.is_admin()));
drop policy if exists verifdocs_write on storage.objects;
create policy verifdocs_write on storage.objects for insert to authenticated
  with check (bucket_id='verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists verifdocs_delete on storage.objects;
create policy verifdocs_delete on storage.objects for delete to authenticated
  using (bucket_id='verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);
