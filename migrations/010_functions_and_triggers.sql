-- Migration 010: Functions and triggers
-- Section 10 of pier-supabase-migration-spec.md

-- 10.1 Auto updated_at
-- Standard pattern. Every table with updated_at gets this trigger.
CREATE OR REPLACE FUNCTION public.tg_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to every table with updated_at
CREATE TRIGGER tg_companies_updated_at BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_contacts_updated_at BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_outreach_log_updated_at BEFORE UPDATE ON public.outreach_log FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_insurers_updated_at BEFORE UPDATE ON public.insurers FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_insurance_products_updated_at BEFORE UPDATE ON public.insurance_products FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_teams_updated_at BEFORE UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_pier_pipeline_updated_at BEFORE UPDATE ON public.pier_pipeline FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_eurefas_members_updated_at BEFORE UPDATE ON public.eurefas_members FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();
CREATE TRIGGER tg_saved_views_updated_at BEFORE UPDATE ON public.saved_views FOR EACH ROW EXECUTE FUNCTION public.tg_update_updated_at();

-- 10.2 Auto contacts_count on companies
-- Recompute contacts_count on affected companies on insert/delete/move.
CREATE OR REPLACE FUNCTION public.tg_recompute_contacts_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.companies SET contacts_count = contacts_count + 1 WHERE id = NEW.company_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.companies SET contacts_count = GREATEST(contacts_count - 1, 0) WHERE id = OLD.company_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.company_id IS DISTINCT FROM NEW.company_id THEN
    IF OLD.company_id IS NOT NULL THEN
      UPDATE public.companies SET contacts_count = GREATEST(contacts_count - 1, 0) WHERE id = OLD.company_id;
    END IF;
    IF NEW.company_id IS NOT NULL THEN
      UPDATE public.companies SET contacts_count = contacts_count + 1 WHERE id = NEW.company_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_contacts_after_change AFTER INSERT OR UPDATE OR DELETE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_recompute_contacts_count();

-- 10.3 Normalise email + domain
-- Populate email_normalised and root_domain on write.
CREATE OR REPLACE FUNCTION public.fn_normalise_email(input TEXT)
RETURNS TEXT AS $$
BEGIN
  IF input IS NULL THEN RETURN NULL; END IF;
  RETURN lower(trim(input));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.fn_extract_root_domain(url TEXT)
RETURNS TEXT AS $$
DECLARE
  cleaned TEXT;
BEGIN
  IF url IS NULL THEN RETURN NULL; END IF;
  cleaned := lower(url);
  cleaned := regexp_replace(cleaned, '^https?://', '');
  cleaned := regexp_replace(cleaned, '^www\.', '');
  cleaned := split_part(cleaned, '/', 1);
  RETURN cleaned;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.tg_normalise_contact_fields()
RETURNS TRIGGER AS $$
BEGIN
  NEW.email_normalised := public.fn_normalise_email(NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.tg_normalise_company_fields()
RETURNS TRIGGER AS $$
BEGIN
  NEW.root_domain := public.fn_extract_root_domain(NEW.website_url);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_contacts_normalise BEFORE INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_normalise_contact_fields();
CREATE TRIGGER tg_companies_normalise BEFORE INSERT OR UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.tg_normalise_company_fields();

-- 10.4 Cooldown status derivation
-- Mirror Excel col AC formula.
CREATE OR REPLACE FUNCTION public.tg_update_cooldown_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.outreach_status = 'Cooldown' THEN
    IF NEW.cooldown_until IS NOT NULL AND NEW.cooldown_until <= CURRENT_DATE THEN
      NEW.cooldown_status_derived := 'Ready for re-engagement';
    ELSE
      NEW.cooldown_status_derived := 'In cooldown';
    END IF;
  ELSE
    NEW.cooldown_status_derived := 'Not in cooldown';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_contacts_cooldown BEFORE INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.tg_update_cooldown_status();

-- 10.5 Auto-resolve tracking flag on companies
-- Mirror Excel col C VLOOKUP cascade: Pier Pipeline > EUREFAS > default.
CREATE OR REPLACE FUNCTION public.tg_resolve_tracking()
RETURNS TRIGGER AS $$
DECLARE
  pipeline_stage TEXT;
  eurefas_membership TEXT;
BEGIN
  -- Check Pier Pipeline first
  SELECT stage INTO pipeline_stage FROM public.pier_pipeline WHERE lower(company_name) = lower(NEW.company_name) AND deleted = FALSE LIMIT 1;
  IF pipeline_stage IS NOT NULL THEN
    NEW.tracking := CASE
      WHEN pipeline_stage = 'Live Partner' THEN 'Live Partner'::tracking_flag
      WHEN pipeline_stage = 'Live Prospect' THEN 'Live Prospect'::tracking_flag
      WHEN pipeline_stage = 'No longer active' THEN 'No longer active'::tracking_flag
      ELSE ''::tracking_flag
    END;
    RETURN NEW;
  END IF;

  -- Check EUREFAS
  SELECT membership INTO eurefas_membership FROM public.eurefas_members WHERE lower(company_name) = lower(NEW.company_name) LIMIT 1;
  IF eurefas_membership = 'Founding member' THEN
    NEW.tracking := 'EUREFAS Founding Member'::tracking_flag;
  ELSIF eurefas_membership IS NOT NULL THEN
    NEW.tracking := 'EUREFAS Member'::tracking_flag;
  ELSE
    NEW.tracking := ''::tracking_flag;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_companies_tracking BEFORE INSERT OR UPDATE OF company_name ON public.companies FOR EACH ROW EXECUTE FUNCTION public.tg_resolve_tracking();
