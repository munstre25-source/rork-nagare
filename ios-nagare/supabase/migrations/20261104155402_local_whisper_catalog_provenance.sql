-- Add pinned, free local Whisper ASR provenance. Keep alignment, source approval, seals, and privileges intact.
create or replace function public.catalog_local_publication_ok(p_video_id text,p_start numeric,p_duration numeric,p_lines jsonb,p_category text)
returns boolean language plpgsql immutable security invoker set search_path='' as $body$
declare expected_hash text;
begin
 if not public.catalog_local_alignment_ok(p_video_id,p_start,p_duration,p_lines) then return false; end if;
 expected_hash := public.catalog_review_hash(p_video_id,p_start,p_duration,p_lines);
 return not exists(select 1 from jsonb_array_elements(p_lines) l where
  l->'translationReview'->>'version' is distinct from 'local-1'
  or l->'translationReview'->'localPublication'->>'version' is distinct from '1'
  or l->'translationReview'->'localPublication'->>'method' is distinct from 'local-asr-translation'
  or l->'translationReview'->'localPublication'->>'language' is distinct from 'Japanese'
  or not coalesce((l->'translationReview'->'localPublication'->>'asrModel'='Qwen/Qwen3-ASR-0.6B' and l->'translationReview'->'localPublication'->>'asrRevision'='5eb144179a02acc5e5ba31e748d22b0cf3e303b0')
    or (l->'translationReview'->'localPublication'->>'asrModel'='dropbox-dash/faster-whisper-large-v3-turbo' and l->'translationReview'->'localPublication'->>'asrRevision'='0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf'),false)
  or l->'translationReview'->'localPublication'->>'translationModel' is distinct from 'Helsinki-NLP/opus-mt-ja-en'
  or l->'translationReview'->'localPublication'->>'translationRevision' is distinct from '0770961a39ba6bd66305b149c3f4110bcafca2e6'
  or l->'translationReview'->'localPublication'->>'databaseHash' is distinct from expected_hash
  or coalesce(l->'translationReview'->'localPublication'->>'channelId','') !~ '^UC[A-Za-z0-9_-]{22}$'
  or l->'translationReview'->'localPublication'->>'videoId' is distinct from p_video_id
  or l->'translationReview'->'localPublication'->'sourceStartSec' is distinct from to_jsonb(p_start)
  or l->'translationReview'->'localPublication'->'durationSec' is distinct from to_jsonb(p_duration)
  or l->'translationReview'->'localPublication'->>'category' is distinct from p_category
  or coalesce(btrim(l->>'translation'),'')=''
 );
end;
$body$;
