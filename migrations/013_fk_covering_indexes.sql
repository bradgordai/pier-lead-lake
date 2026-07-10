-- Migration 013: FK covering indexes
-- Fills a gap in the spec: section 11 states "Every FK gets a btree" but its
-- index list omits 13 foreign-key columns, causing post-migration audit check 3
-- to fail. This migration adds a plain btree on each uncovered FK column so that
-- every foreign key is index-backed (faster joins, and avoids full-table scans
-- on cascade deletes of the referenced parent row).

CREATE INDEX idx_insurers_team_id              ON public.insurers(team_id);
CREATE INDEX idx_insurance_products_company_id ON public.insurance_products(company_id);
CREATE INDEX idx_insurance_products_team_id    ON public.insurance_products(team_id);
CREATE INDEX idx_insurance_products_insurer_id ON public.insurance_products(insurer_id);
CREATE INDEX idx_agent_handover_team_id        ON public.agent_handover(team_id);
CREATE INDEX idx_agent_errors_team_id          ON public.agent_errors(team_id);
CREATE INDEX idx_drafts_feedback_team_id       ON public.drafts_feedback(team_id);
CREATE INDEX idx_drafts_feedback_user_id       ON public.drafts_feedback(feedback_from_user_id);
CREATE INDEX idx_duplicate_candidates_team_id  ON public.duplicate_candidates(team_id);
CREATE INDEX idx_duplicate_candidates_reviewer ON public.duplicate_candidates(reviewed_by_user_id);
CREATE INDEX idx_saved_views_team_id           ON public.saved_views(team_id);
CREATE INDEX idx_insights_snapshots_company_id ON public.insights_snapshots(company_id);
CREATE INDEX idx_insights_snapshots_team_id    ON public.insights_snapshots(team_id);
