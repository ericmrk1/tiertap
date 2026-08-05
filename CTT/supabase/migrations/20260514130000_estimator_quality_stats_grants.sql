-- Explicit privileges for aggregate estimator stats tables.
-- Clients record outcomes via SECURITY DEFINER RPCs only; do not grant table DML to anon/authenticated.

REVOKE ALL ON TABLE public.chip_estimator_quality_stats FROM PUBLIC;
REVOKE ALL ON TABLE public.chip_estimator_quality_stats FROM anon, authenticated;
GRANT ALL ON TABLE public.chip_estimator_quality_stats TO service_role;

REVOKE ALL ON TABLE public.comp_estimator_quality_stats FROM PUBLIC;
REVOKE ALL ON TABLE public.comp_estimator_quality_stats FROM anon, authenticated;
GRANT ALL ON TABLE public.comp_estimator_quality_stats TO service_role;

GRANT EXECUTE ON FUNCTION public.record_chip_estimator_outcome(text, text, text, text, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_comp_estimator_outcome(text, text, text, text, boolean) TO anon, authenticated;
