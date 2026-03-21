CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.rooms (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    creator_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.messages (
    id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    text TEXT NOT NULL,
    room_id TEXT REFERENCES public.rooms(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.user_rooms (
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    room_id TEXT REFERENCES public.rooms(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, room_id)
);

-- Ensure the relationship exists even if the table was created previously with auth.users
DO $$ 
BEGIN 
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE table_name = 'user_rooms' AND constraint_name = 'user_rooms_user_id_fkey'
    ) THEN
        ALTER TABLE public.user_rooms DROP CONSTRAINT user_rooms_user_id_fkey;
    END IF;
    
    ALTER TABLE public.user_rooms 
    ADD CONSTRAINT user_rooms_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.user_deleted_messages (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    message_id BIGINT REFERENCES public.messages(id) ON DELETE CASCADE,
    deleted_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, message_id)
);

CREATE TABLE IF NOT EXISTS public.user_room_clears (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    room_id TEXT REFERENCES public.rooms(id) ON DELETE CASCADE,
    cleared_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, room_id)
);

ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_deleted_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_room_clears ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view rooms" ON public.rooms;
CREATE POLICY "Anyone can view rooms" ON public.rooms FOR SELECT USING (true);

DROP POLICY IF EXISTS "Creators can manage rooms" ON public.rooms;
CREATE POLICY "Creators can manage rooms" ON public.rooms FOR ALL USING (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Anyone can view messages" ON public.messages;
CREATE POLICY "Anyone can view messages" ON public.messages FOR SELECT USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert messages" ON public.messages;
CREATE POLICY "Authenticated users can insert messages" ON public.messages FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can delete their own messages for everyone" ON public.messages;
CREATE POLICY "Users can delete their own messages for everyone" ON public.messages FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their joined rooms" ON public.user_rooms;
CREATE POLICY "Anyone can view room memberships" ON public.user_rooms FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can join rooms" ON public.user_rooms;
CREATE POLICY "Users can join rooms" ON public.user_rooms FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can leave rooms" ON public.user_rooms;
CREATE POLICY "Users can leave rooms" ON public.user_rooms FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their deleted message markers" ON public.user_deleted_messages;
CREATE POLICY "Users can manage their deleted message markers" ON public.user_deleted_messages FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their room clear markers" ON public.user_room_clears;
CREATE POLICY "Users can manage their room clear markers" ON public.user_room_clears FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, username)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', SPLIT_PART(NEW.email, '@', 1)));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

INSERT INTO public.profiles (id, username)
SELECT id, COALESCE(raw_user_meta_data->>'username', SPLIT_PART(email, '@', 1))
FROM auth.users
ON CONFLICT (id) DO NOTHING;
