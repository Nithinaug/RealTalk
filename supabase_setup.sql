-- 1. Add room_id to the messages table (if missing)
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='room_id') THEN
        ALTER TABLE messages ADD COLUMN room_id TEXT DEFAULT 'public';
    END IF;
END $$;

-- 2. Create the table for synced room clearing
CREATE TABLE IF NOT EXISTS user_room_clears (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    room_id TEXT,
    cleared_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, room_id)
);
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='room_id') THEN
        ALTER TABLE messages ADD COLUMN room_id TEXT DEFAULT 'public';
    END IF;
END $$;
-- 2. Enable RLS on all tables
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_room_clears ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_deleted_messages ENABLE ROW LEVEL SECURITY;
-- 3. DROP old policies to avoid duplicates
DROP POLICY IF EXISTS "Anyone can see rooms" ON rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON rooms;
DROP POLICY IF EXISTS "Creators can delete their rooms" ON rooms;
DROP POLICY IF EXISTS "Anyone can read messages" ON messages;
DROP POLICY IF EXISTS "Authenticated users can insert messages" ON messages;
DROP POLICY IF EXISTS "Users can manage their own room clears" ON user_room_clears;
DROP POLICY IF EXISTS "Users can see their own memberships" ON user_rooms;
DROP POLICY IF EXISTS "Users can manage their own memberships" ON user_rooms;
DROP POLICY IF EXISTS "Users can manage their own deleted messages" ON user_deleted_messages;
-- 4. Create proper policies
CREATE POLICY "Anyone can see rooms" ON rooms FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create rooms" ON rooms FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Creators can delete their rooms" ON rooms FOR DELETE USING (auth.uid() = creator_id);
CREATE POLICY "Anyone can read messages" ON messages FOR SELECT USING (true);
CREATE POLICY "Authenticated users can insert messages" ON messages FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Users can manage their own room clears" ON user_room_clears FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can see their own memberships" ON user_rooms FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can manage their own memberships" ON user_rooms FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can manage their own deleted messages" ON user_deleted_messages FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 3. Recreate user_deleted_messages with the correct UUID type
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_deleted_messages') THEN
        DROP TABLE user_deleted_messages;
    END IF;
END $$;

CREATE TABLE user_deleted_messages (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, message_id)
);

-- 4. Enable Realtime ONLY for tables that aren't already added
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'user_room_clears') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE user_room_clears;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'user_deleted_messages') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE user_deleted_messages;
    END IF;
END $$;

-- 5. Create Rooms and Membership tables
CREATE TABLE IF NOT EXISTS rooms (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    creator_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_rooms (
    user_id UUID REFERENCES auth.users(id),
    room_id TEXT REFERENCES rooms(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, room_id)
);

-- 6. Enable RLS and Policies (checks if policy exists first)
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_rooms ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow authenticated to select rooms') THEN
        CREATE POLICY "Allow authenticated to select rooms" ON rooms FOR SELECT USING (auth.role() = 'authenticated');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow authenticated to insert rooms') THEN
        CREATE POLICY "Allow authenticated to insert rooms" ON rooms FOR INSERT WITH CHECK (auth.role() = 'authenticated');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow creator to delete rooms') THEN
        CREATE POLICY "Allow creator to delete rooms" ON rooms FOR DELETE USING (auth.uid() = creator_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow users to see their own room memberships') THEN
        CREATE POLICY "Allow users to see their own room memberships" ON user_rooms FOR SELECT USING (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow users to join rooms') THEN
        CREATE POLICY "Allow users to join rooms" ON user_rooms FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Allow users to leave rooms') THEN
        CREATE POLICY "Allow users to leave rooms" ON user_rooms FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;
