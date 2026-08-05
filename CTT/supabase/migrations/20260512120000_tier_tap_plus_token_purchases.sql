-- TierTap Plus (Credits) consumable token purchases: one row per StoreKit transaction, keyed by user + transaction id.

CREATE TABLE public."TierTapPlusTokenPurchases" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  tokens_granted integer NOT NULL CHECK (tokens_granted > 0),
  product_id text NOT NULL,
  store_transaction_id text NOT NULL,
  purchased_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT "TierTapPlusTokenPurchases_user_txn_key" UNIQUE (user_id, store_transaction_id)
);

CREATE INDEX "TierTapPlusTokenPurchases_user_id_purchased_at_idx"
  ON public."TierTapPlusTokenPurchases" (user_id, purchased_at DESC);

ALTER TABLE public."TierTapPlusTokenPurchases" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "TierTapPlusTokenPurchases_select_own"
  ON public."TierTapPlusTokenPurchases"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "TierTapPlusTokenPurchases_insert_own"
  ON public."TierTapPlusTokenPurchases"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT ON public."TierTapPlusTokenPurchases" TO authenticated;

-- Simulator / TestFlight mirror

CREATE TABLE public."TierTapPlusTokenPurchases_Test" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  tokens_granted integer NOT NULL CHECK (tokens_granted > 0),
  product_id text NOT NULL,
  store_transaction_id text NOT NULL,
  purchased_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT "TierTapPlusTokenPurchases_Test_user_txn_key" UNIQUE (user_id, store_transaction_id)
);

CREATE INDEX "TierTapPlusTokenPurchases_Test_user_id_purchased_at_idx"
  ON public."TierTapPlusTokenPurchases_Test" (user_id, purchased_at DESC);

ALTER TABLE public."TierTapPlusTokenPurchases_Test" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "TierTapPlusTokenPurchases_Test_select_own"
  ON public."TierTapPlusTokenPurchases_Test"
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "TierTapPlusTokenPurchases_Test_insert_own"
  ON public."TierTapPlusTokenPurchases_Test"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT ON public."TierTapPlusTokenPurchases_Test" TO authenticated;
