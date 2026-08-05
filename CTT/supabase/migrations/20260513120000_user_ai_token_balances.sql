-- Authoritative TierTap Plus / Pro token balances per Supabase user (mirrors simulator/TestFlight `_Test` table).
-- Plan monthly allowance fallback is 1_000_000 tokens; override with `TierTapAppDefaults` key `pro_plan_included_tokens_per_calendar_month` (see migration `20260514120000_tier_tap_app_defaults.sql`).

CREATE TABLE public."UserAITokenBalances" (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  purchased_balance_remaining bigint NOT NULL DEFAULT 0 CHECK (purchased_balance_remaining >= 0),
  lifetime_plus_tokens_purchased bigint NOT NULL DEFAULT 0 CHECK (lifetime_plus_tokens_purchased >= 0),
  consumed_from_packs bigint NOT NULL DEFAULT 0 CHECK (consumed_from_packs >= 0),
  pro_plan_tokens_consumed_month bigint NOT NULL DEFAULT 0 CHECK (pro_plan_tokens_consumed_month >= 0),
  pro_plan_month_key text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE TRIGGER "UserAITokenBalances_set_updated_at"
  BEFORE UPDATE ON public."UserAITokenBalances"
  FOR EACH ROW
  EXECUTE PROCEDURE public.tier_tap_touch_updated_at();

ALTER TABLE public."UserAITokenBalances" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "UserAITokenBalances_select_own"
  ON public."UserAITokenBalances"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "UserAITokenBalances_insert_own"
  ON public."UserAITokenBalances"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "UserAITokenBalances_update_own"
  ON public."UserAITokenBalances"
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE ON public."UserAITokenBalances" TO authenticated;

-- Test / simulator mirror

CREATE TABLE public."UserAITokenBalances_Test" (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  purchased_balance_remaining bigint NOT NULL DEFAULT 0 CHECK (purchased_balance_remaining >= 0),
  lifetime_plus_tokens_purchased bigint NOT NULL DEFAULT 0 CHECK (lifetime_plus_tokens_purchased >= 0),
  consumed_from_packs bigint NOT NULL DEFAULT 0 CHECK (consumed_from_packs >= 0),
  pro_plan_tokens_consumed_month bigint NOT NULL DEFAULT 0 CHECK (pro_plan_tokens_consumed_month >= 0),
  pro_plan_month_key text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE TRIGGER "UserAITokenBalances_Test_set_updated_at"
  BEFORE UPDATE ON public."UserAITokenBalances_Test"
  FOR EACH ROW
  EXECUTE PROCEDURE public.tier_tap_touch_updated_at();

ALTER TABLE public."UserAITokenBalances_Test" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "UserAITokenBalances_Test_select_own"
  ON public."UserAITokenBalances_Test"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "UserAITokenBalances_Test_insert_own"
  ON public."UserAITokenBalances_Test"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "UserAITokenBalances_Test_update_own"
  ON public."UserAITokenBalances_Test"
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE ON public."UserAITokenBalances_Test" TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC helpers (SECURITY INVOKER: RLS applies; uses auth.uid())
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.tier_tap_get_ai_token_balances()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  r public."UserAITokenBalances"%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO r FROM public."UserAITokenBalances" WHERE user_id = uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'purchased_balance_remaining', 0,
      'lifetime_plus_tokens_purchased', 0,
      'consumed_from_packs', 0,
      'pro_plan_tokens_consumed_month', 0,
      'pro_plan_month_key', to_char(timezone('utc', now()), 'YYYY-MM')
    );
  END IF;

  RETURN jsonb_build_object(
    'purchased_balance_remaining', r.purchased_balance_remaining,
    'lifetime_plus_tokens_purchased', r.lifetime_plus_tokens_purchased,
    'consumed_from_packs', r.consumed_from_packs,
    'pro_plan_tokens_consumed_month', r.pro_plan_tokens_consumed_month,
    'pro_plan_month_key', r.pro_plan_month_key
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.tier_tap_get_ai_token_balances_test()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  r public."UserAITokenBalances_Test"%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO r FROM public."UserAITokenBalances_Test" WHERE user_id = uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'purchased_balance_remaining', 0,
      'lifetime_plus_tokens_purchased', 0,
      'consumed_from_packs', 0,
      'pro_plan_tokens_consumed_month', 0,
      'pro_plan_month_key', to_char(timezone('utc', now()), 'YYYY-MM')
    );
  END IF;

  RETURN jsonb_build_object(
    'purchased_balance_remaining', r.purchased_balance_remaining,
    'lifetime_plus_tokens_purchased', r.lifetime_plus_tokens_purchased,
    'consumed_from_packs', r.consumed_from_packs,
    'pro_plan_tokens_consumed_month', r.pro_plan_tokens_consumed_month,
    'pro_plan_month_key', r.pro_plan_month_key
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.tier_tap_grant_plus_tokens(p_tokens integer, p_product_id text, p_store_transaction_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  ins_count integer;
  cur_month text := to_char(timezone('utc', now()), 'YYYY-MM');
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_tokens IS NULL OR p_tokens <= 0 THEN
    RAISE EXCEPTION 'invalid p_tokens';
  END IF;

  INSERT INTO public."TierTapPlusTokenPurchases" (user_id, tokens_granted, product_id, store_transaction_id)
  VALUES (uid, p_tokens, p_product_id, p_store_transaction_id)
  ON CONFLICT (user_id, store_transaction_id) DO NOTHING;
  GET DIAGNOSTICS ins_count = ROW_COUNT;

  IF ins_count = 0 THEN
    RETURN public.tier_tap_get_ai_token_balances();
  END IF;

  INSERT INTO public."UserAITokenBalances" (
    user_id,
    purchased_balance_remaining,
    lifetime_plus_tokens_purchased,
    consumed_from_packs,
    pro_plan_tokens_consumed_month,
    pro_plan_month_key
  )
  VALUES (uid, p_tokens, p_tokens, 0, 0, cur_month)
  ON CONFLICT (user_id) DO UPDATE SET
    purchased_balance_remaining = public."UserAITokenBalances".purchased_balance_remaining + p_tokens,
    lifetime_plus_tokens_purchased = public."UserAITokenBalances".lifetime_plus_tokens_purchased + p_tokens,
    updated_at = timezone('utc', now());

  RETURN public.tier_tap_get_ai_token_balances();
END;
$$;

CREATE OR REPLACE FUNCTION public.tier_tap_grant_plus_tokens_test(p_tokens integer, p_product_id text, p_store_transaction_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  ins_count integer;
  cur_month text := to_char(timezone('utc', now()), 'YYYY-MM');
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_tokens IS NULL OR p_tokens <= 0 THEN
    RAISE EXCEPTION 'invalid p_tokens';
  END IF;

  INSERT INTO public."TierTapPlusTokenPurchases_Test" (user_id, tokens_granted, product_id, store_transaction_id)
  VALUES (uid, p_tokens, p_product_id, p_store_transaction_id)
  ON CONFLICT (user_id, store_transaction_id) DO NOTHING;
  GET DIAGNOSTICS ins_count = ROW_COUNT;

  IF ins_count = 0 THEN
    RETURN public.tier_tap_get_ai_token_balances_test();
  END IF;

  INSERT INTO public."UserAITokenBalances_Test" (
    user_id,
    purchased_balance_remaining,
    lifetime_plus_tokens_purchased,
    consumed_from_packs,
    pro_plan_tokens_consumed_month,
    pro_plan_month_key
  )
  VALUES (uid, p_tokens, p_tokens, 0, 0, cur_month)
  ON CONFLICT (user_id) DO UPDATE SET
    purchased_balance_remaining = public."UserAITokenBalances_Test".purchased_balance_remaining + p_tokens,
    lifetime_plus_tokens_purchased = public."UserAITokenBalances_Test".lifetime_plus_tokens_purchased + p_tokens,
    updated_at = timezone('utc', now());

  RETURN public.tier_tap_get_ai_token_balances_test();
END;
$$;

CREATE OR REPLACE FUNCTION public.tier_tap_apply_gemini_token_usage(p_invocation_tokens integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  cur_month text := to_char(timezone('utc', now()), 'YYYY-MM');
  allowance constant bigint := 1000000;
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
  allowance constant bigint := 1000000;
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

GRANT EXECUTE ON FUNCTION public.tier_tap_get_ai_token_balances() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tier_tap_get_ai_token_balances_test() TO authenticated;
GRANT EXECUTE ON FUNCTION public.tier_tap_grant_plus_tokens(integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tier_tap_grant_plus_tokens_test(integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tier_tap_apply_gemini_token_usage(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tier_tap_apply_gemini_token_usage_test(integer) TO authenticated;
