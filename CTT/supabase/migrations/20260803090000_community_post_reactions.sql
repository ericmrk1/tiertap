-- Community post reactions (like / dislike / heart).
-- Everyone signed in can read counts; writing is own-row only (Pro gated in the app).
-- Mirrors simulator/TestFlight table split used by TableGamePosts / TableGamePosts_Test.
--
-- Superseded by 20260803091000_community_post_reaction_counts.sql (running totals).

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

CREATE POLICY "CommunityPostReactions_select_authenticated"
  ON public."CommunityPostReactions"
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "CommunityPostReactions_insert_own"
  ON public."CommunityPostReactions"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "CommunityPostReactions_delete_own"
  ON public."CommunityPostReactions"
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public."CommunityPostReactions" TO authenticated;

-- Test / simulator table

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

CREATE POLICY "CommunityPostReactions_Test_select_authenticated"
  ON public."CommunityPostReactions_Test"
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "CommunityPostReactions_Test_insert_own"
  ON public."CommunityPostReactions_Test"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "CommunityPostReactions_Test_delete_own"
  ON public."CommunityPostReactions_Test"
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public."CommunityPostReactions_Test" TO authenticated;
