-- Korean catalog growth also moves off AI spend. Re-enable with active := true.
select cron.alter_job(jobid, active := false)
from cron.job
where jobname = 'fill-sori-catalog';
