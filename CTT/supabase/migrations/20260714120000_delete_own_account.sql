-- Allow a signed-in user to permanently delete their own auth account.
-- Fallback used by the iOS app when GoTrue DELETE /auth/v1/user is unavailable.
-- Cascades remove related rows that reference auth.users(id) ON DELETE CASCADE
-- (e.g. UserScreenNames, UserAITokenBalances, TierTapPlusTokenPurchases).

CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  DELETE FROM auth.users WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_own_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;

COMMENT ON FUNCTION public.delete_own_account() IS
  'Permanently deletes the calling auth user (auth.uid()). Used for Apple Guideline 5.1.1(v) account deletion.';
