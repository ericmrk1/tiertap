-- Registered Community screen names: one row per auth user, globally unique
-- (case-insensitive, ignoring leading/trailing whitespace). Mirrors simulator/TestFlight
-- table split used by TableGamePosts / TableGamePosts_Test.

CREATE OR REPLACE FUNCTION public.tier_tap_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := timezone('utc', now());
  RETURN NEW;
END;
$$;

CREATE TABLE public."UserScreenNames" (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  screen_name text NOT NULL CHECK (length(btrim(screen_name)) > 0),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE UNIQUE INDEX "UserScreenNames_normalized_screen_name_key"
  ON public."UserScreenNames" (lower(btrim(screen_name)));

CREATE TRIGGER "UserScreenNames_set_updated_at"
  BEFORE UPDATE ON public."UserScreenNames"
  FOR EACH ROW
  EXECUTE PROCEDURE public.tier_tap_touch_updated_at();

ALTER TABLE public."UserScreenNames" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "UserScreenNames_select_own"
  ON public."UserScreenNames"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "UserScreenNames_insert_own"
  ON public."UserScreenNames"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "UserScreenNames_update_own"
  ON public."UserScreenNames"
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "UserScreenNames_delete_own"
  ON public."UserScreenNames"
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public."UserScreenNames" TO authenticated;

-- Test / simulator table (same policies and uniqueness rules)

CREATE TABLE public."UserScreenNames_Test" (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  screen_name text NOT NULL CHECK (length(btrim(screen_name)) > 0),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE UNIQUE INDEX "UserScreenNames_Test_normalized_screen_name_key"
  ON public."UserScreenNames_Test" (lower(btrim(screen_name)));

CREATE TRIGGER "UserScreenNames_Test_set_updated_at"
  BEFORE UPDATE ON public."UserScreenNames_Test"
  FOR EACH ROW
  EXECUTE PROCEDURE public.tier_tap_touch_updated_at();

ALTER TABLE public."UserScreenNames_Test" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "UserScreenNames_Test_select_own"
  ON public."UserScreenNames_Test"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "UserScreenNames_Test_insert_own"
  ON public."UserScreenNames_Test"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "UserScreenNames_Test_update_own"
  ON public."UserScreenNames_Test"
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "UserScreenNames_Test_delete_own"
  ON public."UserScreenNames_Test"
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public."UserScreenNames_Test" TO authenticated;
