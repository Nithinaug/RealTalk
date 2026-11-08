-- RealTalk database setup.
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to run again; it skips anything that already exists.
--
-- Also required: Authentication -> Sign In / Providers -> Email -> turn OFF "Confirm email".
-- Both clients sign users up as <username>@example.com, which can't receive a confirmation mail.

-- ---------- tables ----------

-- One row per user, filled automatically at signup (see trigger below).
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text not null unique,
  created_at timestamptz not null default now()
);

-- Room id is chosen by the user and doubles as the join code.
create table if not exists public.rooms (
  id         text primary key,
  name       text not null,
  creator_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Who is in which room. user_id points at profiles so clients can embed profiles(username).
create table if not exists public.user_rooms (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  room_id   text not null references public.rooms (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create table if not exists public.messages (
  id         uuid primary key default gen_random_uuid(),
  room_id    text not null references public.rooms (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  username   text not null,
  text       text not null check (char_length(text) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists messages_room_created_idx on public.messages (room_id, created_at);

-- "Delete for Me": hides one message for one user.
create table if not exists public.user_deleted_messages (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  message_id uuid not null references public.messages (id) on delete cascade,
  deleted_at timestamptz not null default now(),
  primary key (user_id, message_id)
);

-- "Clear History": hides everything in a room older than cleared_at, for one user.
create table if not exists public.user_room_clears (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  room_id    text not null references public.rooms (id) on delete cascade,
  cleared_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

-- ---------- signup -> profile ----------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- row level security ----------

-- security definer so policies on user_rooms can check membership without recursing into themselves.
create or replace function public.is_room_member(r text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_rooms where room_id = r and user_id = auth.uid());
$$;

alter table public.profiles              enable row level security;
alter table public.rooms                 enable row level security;
alter table public.user_rooms            enable row level security;
alter table public.messages              enable row level security;
alter table public.user_deleted_messages enable row level security;
alter table public.user_room_clears      enable row level security;

drop policy if exists "profiles: read" on public.profiles;
create policy "profiles: read" on public.profiles for select to authenticated using (true);

-- Note: any signed-in user can look up rooms. Join-by-ID needs it, but it also means
-- room IDs are not secret. Move the lookup into an RPC if room IDs must stay private.
drop policy if exists "rooms: read" on public.rooms;
create policy "rooms: read" on public.rooms for select to authenticated using (true);
drop policy if exists "rooms: create" on public.rooms;
create policy "rooms: create" on public.rooms for insert to authenticated with check (creator_id = auth.uid());
drop policy if exists "rooms: creator deletes" on public.rooms;
create policy "rooms: creator deletes" on public.rooms for delete to authenticated using (creator_id = auth.uid());

drop policy if exists "user_rooms: members read" on public.user_rooms;
-- Own rows must be readable too: clients join with upsert, which also checks this policy.
create policy "user_rooms: members read" on public.user_rooms for select to authenticated
  using (user_id = auth.uid() or public.is_room_member(room_id));
drop policy if exists "user_rooms: join" on public.user_rooms;
create policy "user_rooms: join" on public.user_rooms for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "user_rooms: rejoin" on public.user_rooms;
create policy "user_rooms: rejoin" on public.user_rooms for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "user_rooms: leave" on public.user_rooms;
create policy "user_rooms: leave" on public.user_rooms for delete to authenticated using (user_id = auth.uid());

-- Note: username is sent by the client and not checked against profiles.
drop policy if exists "messages: members read" on public.messages;
create policy "messages: members read" on public.messages for select to authenticated using (public.is_room_member(room_id));
drop policy if exists "messages: members send" on public.messages;
create policy "messages: members send" on public.messages for insert to authenticated
  with check (user_id = auth.uid() and public.is_room_member(room_id));
drop policy if exists "messages: author deletes" on public.messages;
create policy "messages: author deletes" on public.messages for delete to authenticated using (user_id = auth.uid());

drop policy if exists "user_deleted_messages: own" on public.user_deleted_messages;
create policy "user_deleted_messages: own" on public.user_deleted_messages for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "user_room_clears: own" on public.user_room_clears;
create policy "user_room_clears: own" on public.user_room_clears for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- realtime ----------

do $$
declare t text;
begin
  foreach t in array array['messages', 'rooms', 'user_rooms', 'user_deleted_messages', 'user_room_clears'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
