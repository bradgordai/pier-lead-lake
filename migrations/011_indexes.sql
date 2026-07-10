-- Migration 011: Indexes
-- Section 11 of pier-supabase-migration-spec.md
-- Every FK gets a btree. Search fields get GIN (trigram). Frequent filter
-- fields get btree.

-- Companies
CREATE INDEX idx_companies_team_id ON public.companies(team_id);
CREATE INDEX idx_companies_priority ON public.companies(priority);
CREATE INDEX idx_companies_research_stage ON public.companies(research_stage);
CREATE INDEX idx_companies_country ON public.companies(country);
CREATE INDEX idx_companies_product_line ON public.companies(product_line);
CREATE INDEX idx_companies_account_owner ON public.companies(account_owner);
CREATE INDEX idx_companies_opportunity_status ON public.companies(opportunity_status);
CREATE INDEX idx_companies_archived_at ON public.companies(archived_at) WHERE archived_at IS NULL;
CREATE INDEX idx_companies_root_domain ON public.companies(root_domain);
CREATE INDEX idx_companies_company_id ON public.companies(company_id);
CREATE INDEX idx_companies_name_trgm ON public.companies USING GIN (lower(company_name) gin_trgm_ops);
CREATE INDEX idx_companies_notes_trgm ON public.companies USING GIN (lower(usp_notes) gin_trgm_ops);

-- Contacts
CREATE INDEX idx_contacts_team_id ON public.contacts(team_id);
CREATE INDEX idx_contacts_company_id ON public.contacts(company_id);
CREATE INDEX idx_contacts_company_ref ON public.contacts(company_ref);
CREATE INDEX idx_contacts_email_normalised ON public.contacts(email_normalised);
CREATE INDEX idx_contacts_outreach_status ON public.contacts(outreach_status);
CREATE INDEX idx_contacts_connection_status ON public.contacts(connection_status);
CREATE INDEX idx_contacts_seniority ON public.contacts(seniority);
CREATE INDEX idx_contacts_country ON public.contacts(country);
CREATE INDEX idx_contacts_do_not_contact ON public.contacts(do_not_contact) WHERE do_not_contact = FALSE;
CREATE INDEX idx_contacts_name_trgm ON public.contacts USING GIN (lower(first_name || ' ' || last_name) gin_trgm_ops);
CREATE INDEX idx_contacts_last_contacted ON public.contacts(last_contacted);
CREATE INDEX idx_contacts_next_action_date ON public.contacts(next_action_date);

-- Outreach Log
CREATE INDEX idx_outreach_team_id ON public.outreach_log(team_id);
CREATE INDEX idx_outreach_contact_id ON public.outreach_log(contact_id);
CREATE INDEX idx_outreach_company_id ON public.outreach_log(company_id);
CREATE INDEX idx_outreach_touch_date ON public.outreach_log(touch_date);
CREATE INDEX idx_outreach_send_status ON public.outreach_log(send_status);
CREATE INDEX idx_outreach_draft_status ON public.outreach_log(draft_status);
CREATE INDEX idx_outreach_channel ON public.outreach_log(channel);
CREATE INDEX idx_outreach_touch_type ON public.outreach_log(touch_type);
CREATE INDEX idx_outreach_thread_id ON public.outreach_log(thread_id);
CREATE INDEX idx_outreach_pre_lint_pass ON public.outreach_log(pre_lint_pass);
CREATE INDEX idx_outreach_reply_classification ON public.outreach_log(reply_classification);
CREATE INDEX idx_outreach_body_trgm ON public.outreach_log USING GIN (lower(message_body) gin_trgm_ops);

-- Reference tables
CREATE INDEX idx_pier_pipeline_name_lower ON public.pier_pipeline(lower(company_name)) WHERE deleted = FALSE;
CREATE INDEX idx_eurefas_name_lower ON public.eurefas_members(lower(company_name));

-- Supporting
CREATE INDEX idx_agent_handover_status ON public.agent_handover(status);
CREATE INDEX idx_agent_handover_to_agent ON public.agent_handover(to_agent) WHERE status = 'open';
CREATE INDEX idx_agent_handover_entity ON public.agent_handover(entity_type, entity_id);
CREATE INDEX idx_nightly_summary_date ON public.nightly_summary(run_date DESC);
CREATE INDEX idx_agent_errors_created ON public.agent_errors(created_at DESC);
CREATE INDEX idx_blocklist_entity ON public.blocklist(entity_type, entity_id);
CREATE INDEX idx_drafts_feedback_outreach ON public.drafts_feedback(outreach_log_id);
CREATE INDEX idx_duplicate_candidates_status ON public.duplicate_candidates(status) WHERE status = 'pending';
CREATE INDEX idx_duplicate_candidates_entity ON public.duplicate_candidates(entity_type, source_a_id, source_b_id);
CREATE INDEX idx_saved_views_user_table ON public.saved_views(user_id, target_table);
