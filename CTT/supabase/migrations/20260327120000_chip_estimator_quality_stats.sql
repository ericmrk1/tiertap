-- Aggregate chip estimator outcomes (accepted vs ignored) per casino/game.
-- Many clients update safely: increments run in one atomic statement; Postgres
-- serializes concurrent updates to the same row via row-level locks.

CREATE TABLE public.chip_estimator_quality_stats (
  environment text NOT NULL CHECK (environment IN ('production', 'test')),
  casino_key text NOT NULL,
  game_key text NOT NULL,
  accepted_count bigint NOT NULL DEFAULT 0 CHECK (accepted_count >= 0),
  ignored_count bigint NOT NULL DEFAULT 0 CHECK (ignored_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (environment, casino_key, game_key)
);

CREATE INDEX chip_estimator_quality_stats_env_updated_idx
  ON public.chip_estimator_quality_stats (environment, updated_at DESC);

ALTER TABLE public.chip_estimator_quality_stats ENABLE ROW LEVEL SECURITY;

-- No SELECT/INSERT/UPDATE policies: clients use the RPC only.

CREATE OR REPLACE FUNCTION public.record_chip_estimator_outcome(
  p_environment text,
  p_casino_key text,
  p_game_key text,
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
  v_accept_delta bigint;
  v_ignore_delta bigint;
BEGIN
  IF p_environment IS NULL OR p_environment NOT IN ('production', 'test') THEN
    RAISE EXCEPTION 'invalid environment';
  END IF;
  v_env := p_environment;

  v_casino := btrim(p_casino_key);
  v_game := btrim(p_game_key);
  IF v_casino = '' OR v_game = '' THEN
    RAISE EXCEPTION 'casino_key and game_key must be non-empty';
  END IF;

  IF p_accepted THEN
    v_accept_delta := 1;
    v_ignore_delta := 0;
  ELSE
    v_accept_delta := 0;
    v_ignore_delta := 1;
  END IF;

  INSERT INTO public.chip_estimator_quality_stats AS s (
    environment, casino_key, game_key, accepted_count, ignored_count
  )
  VALUES (
    v_env, v_casino, v_game, v_accept_delta, v_ignore_delta
  )
  ON CONFLICT (environment, casino_key, game_key) DO UPDATE SET
    accepted_count = s.accepted_count + EXCLUDED.accepted_count,
    ignored_count = s.ignored_count + EXCLUDED.ignored_count,
    updated_at = now();
END;
$$;

REVOKE ALL ON public.chip_estimator_quality_stats FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_chip_estimator_outcome(text, text, text, boolean) TO anon, authenticated;
