-- Jojo catalog growth moves to the free caption pipeline (.github/workflows/daily-caption-clips.yml).
-- AI credits are reserved for in-app word explanations. Re-enable with active := true.
select cron.alter_job(jobid, active := false)
from cron.job
where jobname = 'fill-jojo-catalog';
