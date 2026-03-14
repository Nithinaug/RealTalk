-- RealTalk Unified Supabase Setup
-- This script is idempotent (can be run multiple times safely)

-- 1. EXTENSIONS & SCHEMA
SET search_path TO public;

-- 2. TABLES
CREATE TABLE IF NOT EXISTS rooms (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    creator_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_rooms (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    room_id TEXT REFERENCES rooms(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, room_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT NOT NULL,
    text TEXT NOT NULL,
    room_id TEXT DEFAULT 'public',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='room_id') THEN
        ALTER TABLE messages ADD COLUMN room_id TEXT DEFAULT 'public';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS user_room_clears (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    room_id TEXT REFERENCES rooms(id) ON DELETE CASCADE,
    cleared_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, room_id)
);

DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_deleted_messages') THEN
        IF (SELECT data_type FROM information_schema.columns WHERE table_name = 'user_deleted_messages' AND column_name = 'message_id') != 'uuid' THEN
            DROP TABLE user_deleted_messages;
        END IF;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS user_deleted_messages (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, message_id)
);

-- 3. ROW LEVEL SECURITY (RLS)
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_room_clears ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_deleted_messages ENABLE ROW LEVEL SECURITY;

-- 4. POLICIES (Drop all possible variations to ensure clean state)
DO $$ 
BEGIN
    -- Drops for "rooms"
    DROP POLICY IF EXISTS "Anyone can see rooms" ON rooms;
    DROP POLICY IF EXISTS "Allow authenticated to select rooms" ON rooms;
    DROP POLICY IF EXISTS "Authenticated users can create rooms" ON rooms;
    DROP POLICY IF EXISTS "Allow authenticated to insert rooms" ON rooms;
    DROP POLICY IF EXISTS "Creators can delete their rooms" ON rooms;
    DROP POLICY IF EXISTS "Allow creator to delete rooms" ON rooms;
    
    -- Drops for "messages"
    DROP POLICY IF EXISTS "Anyone can read messages" ON messages;
    DROP POLICY IF EXISTS "Authenticated users can insert messages" ON messages;
    DROP POLICY IF EXISTS "Allow sender to delete for everyone" ON messages;
    
    -- Drops for "user_rooms"
    DROP POLICY IF EXISTS "Users can see their own memberships" ON user_rooms;
    DROP POLICY IF EXISTS "Allow users to see their own room memberships" ON user_rooms;
    DROP POLICY IF EXISTS "Users can manage their own memberships" ON user_rooms;
    DROP POLICY IF EXISTS "Allow users to join rooms" ON user_rooms;
    DROP POLICY IF EXISTS "Allow users to leave rooms" ON user_rooms;
    
    -- Drops for Clears & Deletions
    DROP POLICY IF EXISTS "Users can manage their own room clears" ON user_room_clears;
    DROP POLICY IF EXISTS "Users can manage their own deleted messages" ON user_deleted_messages;
END $$;

-- 5. CREATE NEW POLICIES
-- Rooms
CREATE POLICY "Allow authenticated to select rooms" ON rooms FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Allow authenticated to insert rooms" ON rooms FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Allow creator to delete rooms" ON rooms FOR DELETE USING (auth.uid() = creator_id);

-- Messages
CREATE POLICY "Anyone can read messages" ON messages FOR SELECT USING (true);
CREATE POLICY "Authenticated users can insert messages" ON messages FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Allow sender to delete for everyone" ON messages FOR DELETE USING (
    (auth.uid() IS NOT NULL) AND (
        username = (auth.jwt() -> 'user_metadata' ->> 'username') OR 
        username = split_part(auth.jwt() ->> 'email', '@', 1)
    )
);

-- User Room Memberships
CREATE POLICY "Allow users to see their own room memberships" ON user_rooms FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Allow users to join rooms" ON user_rooms FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Allow users to leave rooms" ON user_rooms FOR DELETE USING (auth.uid() = user_id);

-- User Room Clears
CREATE POLICY "Users can manage their own room clears" ON user_room_clears FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- User Deleted Messages
CREATE POLICY "Users can manage their own deleted messages" ON user_deleted_messages FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 6. REALTIME CONFIGURATION
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'messages') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE messages;
    END IF;
    -- Ensure REPLICA IDENTITY is FULL for DELETE events to work reliably
    ALTER TABLE messages REPLICA IDENTITY FULL;
    
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'user_room_clears') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE user_room_clears;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'user_deleted_messages') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE user_deleted_messages;
    END IF;
END $$;
