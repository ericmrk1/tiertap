-- Seed `TierTapAppDefaults` with values that match iOS `TierTapRemoteDefaultFallbacks` / `TierTapProductId`.
-- Idempotent: safe to re-run after edits.

INSERT INTO public."TierTapAppDefaults" (key, value_int) VALUES
  ('pro_plan_included_tokens_per_calendar_month', 1000000),
  ('credits_pack_token_amount', 250000),
  ('max_ai_calls_per_day', 5),
  ('max_ai_calls_per_day_testflight', 20),
  ('tiertap_ai_images_per_day', 2)
ON CONFLICT (key) DO UPDATE SET
  value_int = excluded.value_int,
  updated_at = timezone('utc', now());
