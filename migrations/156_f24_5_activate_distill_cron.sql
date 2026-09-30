-- 156 F24 Task 5: activate the weekly distill-learned-corrections cron (Brad, F24 brief). Layer 5 is NOT wired.
-- Job 'distill-learned-corrections' (schedule 30 5 * * 1 = Monday 05:30 UTC) was created INACTIVE in F22B.6; it has never run
-- from cron (0 job_run_details). Its command is not read or changed here (never SELECT cron.job.command unredacted); only
-- the active flag flips. Measured before: the command calls distill-learned-corrections with the Vault bearer, carries
-- triggered_by and a timeout, and passes neither dry_run nor include_legacy, so each run is a REAL run.
-- Effect of a run: reads draft_feedback (use_for_training, signal_type 'draft_quality', since the last done run;
-- 35 waiting), one Sonnet call, rewrites learned_correction_rules and UPDATES voice_assets row 'learned_corrections'
-- (body + version). generate-draft-from-context does not read that row, so no draft changes. First run: Mon 5 Oct 2026.
-- FLAG: that voice_assets write conflicts with the standing "do not touch voice_assets" rule; reported to Brad.
-- Reverse with: select cron.alter_job((select jobid from cron.job where jobname = 'distill-learned-corrections'), active := false);

select cron.alter_job((select jobid from cron.job where jobname = 'distill-learned-corrections'), active := true);
