-- 125 F20.0(a): the pg_cron jobs stop carrying the Edge Function bearer as a literal. Proposed 18 Sep (F17.1),
-- never applied. This unblocks the secret rotation: after this, rotating means ONE vault.update_secret call.
-- The value is copied into Vault INSIDE this statement, from the existing chase-engine job. It is never
-- printed, never in this file, never in a log. All three literals were verified identical by md5 first.
do $$
declare v_secret text; v_id uuid; j record; v_new text;
begin
  select substring(command from 'Bearer ([A-Za-z0-9._-]{20,})') into v_secret from cron.job where jobname = 'daily-chase-engine';
  if v_secret is null then raise exception 'no literal found in daily-chase-engine; nothing changed'; end if;
  select id into v_id from vault.secrets where name = 'internal_app_secret';
  if v_id is null then
    perform vault.create_secret(v_secret, 'internal_app_secret', 'Bearer the pg_cron jobs present to Pier Edge Functions. Rotate with vault.update_secret.');
  else
    perform vault.update_secret(v_id, v_secret);
  end if;
  if (select decrypted_secret from vault.decrypted_secrets where name = 'internal_app_secret') is distinct from v_secret then
    raise exception 'vault round-trip failed; nothing changed';
  end if;
  -- the three jobs that carry the literal
  for j in select jobid, jobname, command from cron.job where command ~ 'Bearer [A-Za-z0-9._-]{20,}' loop
    v_new := regexp_replace(j.command, '''Bearer [A-Za-z0-9._-]{20,}''',
      '''Bearer '' || (select decrypted_secret from vault.decrypted_secrets where name = ''internal_app_secret'')', 'g');
    if v_new = j.command or v_new ~ 'Bearer [A-Za-z0-9._-]{20,}' then
      raise exception 'job % could not be rewritten cleanly; nothing changed', j.jobname;
    end if;
    perform cron.alter_job(job_id := j.jobid, command := v_new);
  end loop;
  -- the drain job read the bearer out of the chase-engine command at runtime; that literal is gone now
  for j in select jobid, command from cron.job where jobname = 'send-queue-drain' loop
    v_new := replace(j.command,
      '(select substring(command from ''Bearer ([A-Za-z0-9._-]+)'') from cron.job where jobname = ''daily-chase-engine'')',
      '(select decrypted_secret from vault.decrypted_secrets where name = ''internal_app_secret'')');
    if v_new = j.command then raise exception 'send-queue-drain could not be rewritten; nothing changed'; end if;
    perform cron.alter_job(job_id := j.jobid, command := v_new);
  end loop;
end $$;
