create or replace function public.create_profile_for_auth_user_v8()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, name, role, status, site_id, all_sites)
  values (
    new.id,
    new.email,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'name'), ''), ''),
    'mechanic',
    'pending',
    null,
    false
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists auth_user_profile_after_insert on auth.users;
create trigger auth_user_profile_after_insert
  after insert on auth.users
  for each row
  execute function public.create_profile_for_auth_user_v8();
