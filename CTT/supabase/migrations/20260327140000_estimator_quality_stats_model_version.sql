-- Track estimator model version on each aggregate row so stats stay comparable across model changes.

-- Chip estimator -----------------------------------------------------------------

ALTER TABLE public.chip_estimator_quality_stats
  ADD COLUMN model_version text NOT NULL DEFAULT '1';

ALTER TABLE public.chip_estimator_quality_stats
  DROP CONSTRAINT chip_estimator_quality_stats_pkey,
  ADD PRIMARY KEY (environment, casino_key, game_key, model_version);

ALTER TABLE public.chip_estimator_quality_stats
  ALTER COLUMN model_version DROP DEFAULT;

DROP FUNCTION IF EXISTS public.record_chip_estimator_outcome(text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.record_chip_estimator_outcome(
  p_environment text,
  p_casino_key text,
  p_game_key text,
  p_model_version text,
  p_accepted boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_env text;
  v_casino text;
  v_game text;
  v_model text;
  v_accept_delta bigint;
  v_ignore_delta bigint;
BEGIN
  IF p_environment IS NULL OR p_environment NOT IN ('production', 'test') THEN
    RAISE EXCEPTION 'invalid environment';
  END IF;
  v_env := p_environment;

  v_casino := btrim(p_casino_key);
  v_game := btrim(p_game_key);
  v_model := btrim(p_model_version);
  IF v_casino = '' OR v_game = '' OR v_model = '' THEN
    RAISE EXCEPTION 'casino_key, game_key, and model_version must be non-empty';
  END IF;

  IF p_accepted THEN
    v_accept_delta := 1;
    v_ignore_delta := 0;
  ELSE
    v_accept_delta := 0;
    v_ignore_delta := 1;
  END IF;

  INSERT INTO public.chip_estimator_quality_stats AS s (
    environment, casino_key, game_key, model_version, accepted_count, ignored_count
  )
  VALUES (
    v_env, v_casino, v_game, v_model, v_accept_delta, v_ignore_delta
  )
  ON CONFLICT (environment, casino_key, game_key, model_version) DO UPDATE SET
    accepted_count = s.accepted_count + EXCLUDED.accepted_count,
    ignored_count = s.ignored_count + EXCLUDED.ignored_count,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_chip_estimator_outcome(text, text, text, text, boolean) TO anon, authenticated;

-- Comp estimator -----------------------------------------------------------------

ALTER TABLE public.comp_estimator_quality_stats
  ADD COLUMN model_version text NOT NULL DEFAULT '1';

ALTER TABLE public.comp_estimator_quality_stats
  DROP CONSTRAINT comp_estimator_quality_stats_pkey,
  ADD PRIMARY KEY (environment, casino_key, game_key, model_version);

ALTER TABLE public.comp_estimator_quality_stats
  ALTER COLUMN model_version DROP DEFAULT;

DROP FUNCTION IF EXISTS public.record_comp_estimator_outcome(text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.record_comp_estimator_outcome(
  p_environment text,
  p_casino_key text,
  p_game_key text,
  p_model_version text,
  p_accepted boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_env text;
  v_casino text;
  v_game text;
  v_model text;
  v_accept_delta bigint;
  v_decline_delta bigint;
BEGIN
  IF p_environment IS NULL OR p_environment NOT IN ('production', 'test') THEN
    RAISE EXCEPTION 'invalid environment';
  END IF;
  v_env := p_environment;

  v_casino := btrim(p_casino_key);
  v_game := btrim(p_game_key);
  v_model := btrim(p_model_version);
  IF v_casino = '' OR v_game = '' OR v_model = '' THEN
    RAISE EXCEPTION 'casino_key, game_key, and model_version must be non-empty';
  END IF;

  IF p_accepted THEN
    v_accept_delta := 1;
    v_decline_delta := 0;
  ELSE
    v_accept_delta := 0;
    v_decline_delta := 1;
  END IF;

  INSERT INTO public.comp_estimator_quality_stats AS s (
    environment, casino_key, game_key, model_version, accepted_count, declined_count
  )
  VALUES (
    v_env, v_casino, v_game, v_model, v_accept_delta, v_decline_delta
  )
  ON CONFLICT (environment, casino_key, game_key, model_version) DO UPDATE SET
    accepted_count = s.accepted_count + EXCLUDED.accepted_count,
    declined_count = s.declined_count + EXCLUDED.declined_count,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_comp_estimator_outcome(text, text, text, text, boolean) TO anon, authenticated;
