-- Remote numeric defaults for the TierTap app. When a row exists for a `key`,
-- `value_int` overrides the on-device bundled fallback (see iOS `TierTapRemoteDefaultFallbacks`
-- and `tier_tap_app_default_int`). No seed rows: empty table means all bundled defaults apply.
-- Only `pro_plan_included_tokens_per_calendar_month` is read server-side today (Gemini spend RPC).

CREATE TABLE public."TierTapAppDefaults" (
  key text PRIMARY KEY,
  value_int bigint NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public."TierTapAppDefaults" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "TierTapAppDefaults_select_anon_authenticated"
  ON public."TierTapAppDefaults"
  FOR SELECT
  TO anon, authenticated
  USING (true);

GRANT SELECT ON public."TierTapAppDefaults" TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.tier_tap_app_default_int(p_key text, p_fallback bigint)
RETURNS bigint
LANGUAGE sql
STABLE
PARALLEL SAFE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT d.value_int FROM public."TierTapAppDefaults" AS d WHERE d.key = p_key LIMIT 1),
    p_fallback
  );
$$;

GRANT EXECUTE ON FUNCTION public.tier_tap_app_default_int(text, bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.tier_tap_apply_gemini_token_usage(p_invocation_tokens integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  cur_month text := to_char(timezone('utc', now()), 'YYYY-MM');
  allowance bigint := public.tier_tap_app_default_int('pro_plan_included_tokens_per_calendar_month', 1000000);
  tokens bigint;
  r public."UserAITokenBalances"%ROWTYPE;
  allowance_remaining bigint;
  from_plan bigint;
  from_purchased_need bigint;
  take bigint;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  tokens := greatest(coalesce(p_invocation_tokens, 0), 0);
  IF tokens = 0 THEN
    RETURN public.tier_tap_get_ai_token_balances();
  END IF;

  INSERT INTO public."UserAITokenBalances" (user_id, pro_plan_month_key)
  VALUES (uid, cur_month)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO r FROM public."UserAITokenBalances" WHERE user_id = uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'balance row missing';
  END IF;

  IF r.pro_plan_month_key IS DISTINCT FROM cur_month OR r.pro_plan_month_key IS NULL OR r.pro_plan_month_key = '' THEN
    r.pro_plan_tokens_consumed_month := 0;
    r.pro_plan_month_key := cur_month;
  END IF;

  allowance_remaining := greatest(allowance - r.pro_plan_tokens_consumed_month, 0);
  from_plan := least(tokens, allowance_remaining);
  r.pro_plan_tokens_consumed_month := r.pro_plan_tokens_consumed_month + from_plan;

  from_purchased_need := tokens - from_plan;
  IF from_purchased_need > 0 THEN
    take := least(from_purchased_need, r.purchased_balance_remaining);
    r.purchased_balance_remaining := r.purchased_balance_remaining - take;
    r.consumed_from_packs := r.consumed_from_packs + take;
  END IF;

  UPDATE public."UserAITokenBalances"
  SET
    purchased_balance_remaining = r.purchased_balance_remaining,
    consumed_from_packs = r.consumed_from_packs,
    pro_plan_tokens_consumed_month = r.pro_plan_tokens_consumed_month,
    pro_plan_month_key = r.pro_plan_month_key,
    updated_at = timezone('utc', now())
  WHERE user_id = uid;

  RETURN public.tier_tap_get_ai_token_balances();
END;
$$;

CREATE OR REPLACE FUNCTION public.tier_tap_apply_gemini_token_usage_test(p_invocation_tokens integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  cur_month text := to_char(timezone('utc', now()), 'YYYY-MM');
  allowance bigint := public.tier_tap_app_default_int('pro_plan_included_tokens_per_calendar_month', 1000000);
  tokens bigint;
  r public."UserAITokenBalances_Test"%ROWTYPE;
  allowance_remaining bigint;
  from_plan bigint;
  from_purchased_need bigint;
  take bigint;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  tokens := greatest(coalesce(p_invocation_tokens, 0), 0);
  IF tokens = 0 THEN
    RETURN public.tier_tap_get_ai_token_balances_test();
  END IF;

  INSERT INTO public."UserAITokenBalances_Test" (user_id, pro_plan_month_key)
  VALUES (uid, cur_month)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO r FROM public."UserAITokenBalances_Test" WHERE user_id = uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'balance row missing';
  END IF;

  IF r.pro_plan_month_key IS DISTINCT FROM cur_month OR r.pro_plan_month_key IS NULL OR r.pro_plan_month_key = '' THEN
    r.pro_plan_tokens_consumed_month := 0;
    r.pro_plan_month_key := cur_month;
  END IF;

  allowance_remaining := greatest(allowance - r.pro_plan_tokens_consumed_month, 0);
  from_plan := least(tokens, allowance_remaining);
  r.pro_plan_tokens_consumed_month := r.pro_plan_tokens_consumed_month + from_plan;

  from_purchased_need := tokens - from_plan;
  IF from_purchased_need > 0 THEN
    take := least(from_purchased_need, r.purchased_balance_remaining);
    r.purchased_balance_remaining := r.purchased_balance_remaining - take;
    r.consumed_from_packs := r.consumed_from_packs + take;
  END IF;

  UPDATE public."UserAITokenBalances_Test"
  SET
    purchased_balance_remaining = r.purchased_balance_remaining,
    consumed_from_packs = r.consumed_from_packs,
    pro_plan_tokens_consumed_month = r.pro_plan_tokens_consumed_month,
    pro_plan_month_key = r.pro_plan_month_key,
    updated_at = timezone('utc', now())
  WHERE user_id = uid;

  RETURN public.tier_tap_get_ai_token_balances_test();
END;
$$;
