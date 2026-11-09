-- The local aligners and Edge validator treat Japanese full-width tilde as punctuation.
create or replace function public.catalog_local_alignment_ok(p_video_id text,p_start numeric,p_duration numeric,p_lines jsonb)
returns boolean language plpgsql immutable security invoker set search_path='' as $body$
declare expected_hash text;
begin
 if p_start is null or p_start<0 or p_duration is null or p_duration<=0 or p_duration>300 then return false; end if;
 if jsonb_typeof(p_lines) is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>100 then return false; end if;
 expected_hash := public.catalog_review_hash(p_video_id,p_start,p_duration,p_lines);
 if exists(select 1 from jsonb_array_elements(p_lines) l where
  l->>'timing' is distinct from 'word'
  or l->'translationReview'->'localAlignment'->>'version' is distinct from '1'
  or not coalesce((l->'translationReview'->'localAlignment'->>'method'='local-forced-alignment'
    and l->'translationReview'->'localAlignment'->>'model'='Qwen/Qwen3-ForcedAligner-0.6B'
    and l->'translationReview'->'localAlignment'->>'revision'='c7cbfc2048c462b0d63a45797104fc9db3ad62b7')
   or (l->'translationReview'->'localAlignment'->>'method'='local-attention-dtw'
    and l->'translationReview'->'localAlignment'->>'model'='dropbox-dash/faster-whisper-large-v3-turbo'
    and l->'translationReview'->'localAlignment'->>'revision'='0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf'),false)
  or coalesce(l->'translationReview'->'localAlignment'->>'audioSha256','') !~ '^[a-f0-9]{64}$'
  or coalesce(l->'translationReview'->'localAlignment'->>'sourceLinesHash','') !~ '^[a-f0-9]{64}$'
  or l->'translationReview'->'localAlignment'->>'databaseHash' is distinct from expected_hash
  or l->'translationReview'->'localAlignment'->>'videoId' is distinct from p_video_id
  or l->'translationReview'->'localAlignment'->'sourceStartSec' is distinct from to_jsonb(p_start)
  or l->'translationReview'->'localAlignment'->'durationSec' is distinct from to_jsonb(p_duration)
  or jsonb_typeof(l->'start') is distinct from 'number'
  or jsonb_typeof(l->'end') is distinct from 'number'
  or jsonb_typeof(l->'tokens') is distinct from 'array'
 ) then return false; end if;
 if exists(select 1 from (
   select l,(l->>'start')::numeric s,(l->>'end')::numeric e,
    lag((l->>'end')::numeric) over(order by i) previous_end
   from jsonb_array_elements(p_lines) with ordinality ll(l,i)
  ) q where s<0 or e<=s or e>p_duration+.001 or s<previous_end
   or jsonb_array_length(l->'tokens')=0
 ) then return false; end if;
 if exists(select 1 from jsonb_array_elements(p_lines) l
  cross join lateral jsonb_array_elements(l->'tokens') t
  where jsonb_typeof(t->'start') is distinct from 'number'
   or jsonb_typeof(t->'end') is distinct from 'number'
 ) then return false; end if;
 return not exists(select 1 from jsonb_array_elements(p_lines) l
  cross join lateral (
   select t,(t->>'start')::numeric s,(t->>'end')::numeric e,
    lag((t->>'end')::numeric) over(order by j) previous_end
   from jsonb_array_elements(l->'tokens') with ordinality tt(t,j)
  ) q where s<(l->>'start')::numeric-.001 or e>(l->>'end')::numeric+.001
    or e<s or s<previous_end-.001
    or (coalesce(t->>'surface','') !~ '^[[:space:][:punct:]ー〜～]+$' and e<=s)
 );
exception when invalid_text_representation or numeric_value_out_of_range then return false;
end;
$body$;
