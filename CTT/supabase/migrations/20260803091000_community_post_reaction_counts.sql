-- Follow-up: drop the original per-reaction CommunityPostReactions tables and
-- replace with running totals (CommunityPostReactionCounts) + a slim per-user ledger.
-- Safe if the original 20260803090000 migration was already applied; also drops any
-- partial counts objects from an earlier draft of that file.

DROP TRIGGER IF EXISTS "CommunityPostReactions_maintain_counts"
  ON public."CommunityPostReactions";
DROP TRIGGER IF EXISTS "CommunityPostReactions_Test_maintain_counts"
  ON public."CommunityPostReactions_Test";

DROP FUNCTION IF EXISTS public.tier_tap_maintain_community_reaction_counts();
DROP FUNCTION IF EXISTS public.tier_tap_maintain_community_reaction_counts_test();

DROP TABLE IF EXISTS public."CommunityPostReactionCounts" CASCADE;
DROP TABLE IF EXISTS public."CommunityPostReactionCounts_Test" CASCADE;
DROP TABLE IF EXISTS public."CommunityPostReactions" CASCADE;
DROP TABLE IF EXISTS public."CommunityPostReactions_Test" CASCADE;

-- ---------------------------------------------------------------------------
-- Production: running totals + ledger
-- ---------------------------------------------------------------------------

CREATE TABLE public."CommunityPostReactionCounts" (
  post_id bigint PRIMARY KEY,
  like_count integer NOT NULL DEFAULT 0 CHECK (like_count >= 0),
  dislike_count integer NOT NULL DEFAULT 0 CHECK (dislike_count >= 0),
  heart_count integer NOT NULL DEFAULT 0 CHECK (heart_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public."CommunityPostReactionCounts" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "CommunityPostReactionCounts_select_authenticated"
  ON public."CommunityPostReactionCounts"
  FOR SELECT TO authenticated
  USING (true);

GRANT SELECT ON public."CommunityPostReactionCounts" TO authenticated;

CREATE TABLE public."CommunityPostReactions" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id bigint NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  reaction_type text NOT NULL CHECK (reaction_type IN ('like', 'dislike', 'heart')),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT "CommunityPostReactions_post_user_type_key"
    UNIQUE (post_id, user_id, reaction_type)
);

CREATE INDEX "CommunityPostReactions_post_id_idx"
  ON public."CommunityPostReactions" (post_id);

CREATE INDEX "CommunityPostReactions_user_id_idx"
  ON public."CommunityPostReactions" (user_id);

ALTER TABLE public."CommunityPostReactions" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "CommunityPostReactions_select_own"
  ON public."CommunityPostReactions"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "CommunityPostReactions_insert_own"
  ON public."CommunityPostReactions"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "CommunityPostReactions_delete_own"
  ON public."CommunityPostReactions"
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public."CommunityPostReactions" TO authenticated;

CREATE OR REPLACE FUNCTION public.tier_tap_maintain_community_reaction_counts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  delta integer;
  target_post_id bigint;
  target_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    delta := 1;
    target_post_id := NEW.post_id;
    target_type := NEW.reaction_type;
  ELSIF TG_OP = 'DELETE' THEN
    delta := -1;
    target_post_id := OLD.post_id;
    target_type := OLD.reaction_type;
  ELSE
    RETURN NULL;
  END IF;

  INSERT INTO public."CommunityPostReactionCounts" AS c (post_id, like_count, dislike_count, heart_count, updated_at)
  VALUES (
    target_post_id,
    CASE WHEN target_type = 'like' THEN greatest(delta, 0) ELSE 0 END,
    CASE WHEN target_type = 'dislike' THEN greatest(delta, 0) ELSE 0 END,
    CASE WHEN target_type = 'heart' THEN greatest(delta, 0) ELSE 0 END,
    timezone('utc', now())
  )
  ON CONFLICT (post_id) DO UPDATE SET
    like_count = CASE
      WHEN target_type = 'like' THEN greatest(c.like_count + delta, 0)
      ELSE c.like_count
    END,
    dislike_count = CASE
      WHEN target_type = 'dislike' THEN greatest(c.dislike_count + delta, 0)
      ELSE c.dislike_count
    END,
    heart_count = CASE
      WHEN target_type = 'heart' THEN greatest(c.heart_count + delta, 0)
      ELSE c.heart_count
    END,
    updated_at = timezone('utc', now());

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER "CommunityPostReactions_maintain_counts"
  AFTER INSERT OR DELETE ON public."CommunityPostReactions"
  FOR EACH ROW
  EXECUTE PROCEDURE public.tier_tap_maintain_community_reaction_counts();

-- ---------------------------------------------------------------------------
-- Test / simulator
-- ---------------------------------------------------------------------------

CREATE TABLE public."CommunityPostReactionCounts_Test" (
  post_id bigint PRIMARY KEY,
  like_count integer NOT NULL DEFAULT 0 CHECK (like_count >= 0),
  dislike_count integer NOT NULL DEFAULT 0 CHECK (dislike_count >= 0),
  heart_count integer NOT NULL DEFAULT 0 CHECK (heart_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public."CommunityPostReactionCounts_Test" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "CommunityPostReactionCounts_Test_select_authenticated"
  ON public."CommunityPostReactionCounts_Test"
  FOR SELECT TO authenticated
  USING (true);

GRANT SELECT ON public."CommunityPostReactionCounts_Test" TO authenticated;

CREATE TABLE public."CommunityPostReactions_Test" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id bigint NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  reaction_type text NOT NULL CHECK (reaction_type IN ('like', 'dislike', 'heart')),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT "CommunityPostReactions_Test_post_user_type_key"
    UNIQUE (post_id, user_id, reaction_type)
);

CREATE INDEX "CommunityPostReactions_Test_post_id_idx"
  ON public."CommunityPostReactions_Test" (post_id);

CREATE INDEX "CommunityPostReactions_Test_user_id_idx"
  ON public."CommunityPostReactions_Test" (user_id);

ALTER TABLE public."CommunityPostReactions_Test" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "CommunityPostReactions_Test_select_own"
  ON public."CommunityPostReactions_Test"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "CommunityPostReactions_Test_insert_own"
  ON public."CommunityPostReactions_Test"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "CommunityPostReactions_Test_delete_own"
  ON public."CommunityPostReactions_Test"
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public."CommunityPostReactions_Test" TO authenticated;

CREATE OR REPLACE FUNCTION public.tier_tap_maintain_community_reaction_counts_test()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  delta integer;
  target_post_id bigint;
  target_type text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    delta := 1;
    target_post_id := NEW.post_id;
    target_type := NEW.reaction_type;
  ELSIF TG_OP = 'DELETE' THEN
    delta := -1;
    target_post_id := OLD.post_id;
    target_type := OLD.reaction_type;
  ELSE
    RETURN NULL;
  END IF;

  INSERT INTO public."CommunityPostReactionCounts_Test" AS c (post_id, like_count, dislike_count, heart_count, updated_at)
  VALUES (
    target_post_id,
    CASE WHEN target_type = 'like' THEN greatest(delta, 0) ELSE 0 END,
    CASE WHEN target_type = 'dislike' THEN greatest(delta, 0) ELSE 0 END,
    CASE WHEN target_type = 'heart' THEN greatest(delta, 0) ELSE 0 END,
    timezone('utc', now())
  )
  ON CONFLICT (post_id) DO UPDATE SET
    like_count = CASE
      WHEN target_type = 'like' THEN greatest(c.like_count + delta, 0)
      ELSE c.like_count
    END,
    dislike_count = CASE
      WHEN target_type = 'dislike' THEN greatest(c.dislike_count + delta, 0)
      ELSE c.dislike_count
    END,
    heart_count = CASE
      WHEN target_type = 'heart' THEN greatest(c.heart_count + delta, 0)
      ELSE c.heart_count
    END,
    updated_at = timezone('utc', now());

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER "CommunityPostReactions_Test_maintain_counts"
  AFTER INSERT OR DELETE ON public."CommunityPostReactions_Test"
  FOR EACH ROW
  EXECUTE PROCEDURE public.tier_tap_maintain_community_reaction_counts_test();
