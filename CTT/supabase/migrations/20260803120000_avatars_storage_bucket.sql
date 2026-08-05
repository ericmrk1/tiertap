-- Community / Account profile photos in Supabase Storage.
-- App path: avatars/{userId}/avatar.jpg (see AuthStore.communityAvatarStoragePath).
-- Bucket is public so Community feed can load avatars via getPublicURL; writes are own-folder only.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  5242880, -- 5 MiB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Idempotent policy recreate (safe if an earlier draft already applied policies).
DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
DROP POLICY IF EXISTS "avatars_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_select_public" ON storage.objects;
DROP POLICY IF EXISTS "avatars_insert_own_prefix" ON storage.objects;
DROP POLICY IF EXISTS "avatars_update_own_prefix" ON storage.objects;
DROP POLICY IF EXISTS "avatars_delete_own_prefix" ON storage.objects;

-- Anyone can read objects in this bucket (feed + Account use public URLs).
CREATE POLICY "avatars_public_read"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'avatars');

-- Authenticated users may only write under their own uid folder: "{auth.uid()}/…"
-- Compare lowercased so clients that stringify UUIDs in uppercase still pass RLS.
CREATE POLICY "avatars_insert_own"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND lower(split_part(name, '/', 1)) = auth.uid()::text
  );

CREATE POLICY "avatars_update_own"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND lower(split_part(name, '/', 1)) = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND lower(split_part(name, '/', 1)) = auth.uid()::text
  );

CREATE POLICY "avatars_delete_own"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND lower(split_part(name, '/', 1)) = auth.uid()::text
  );
