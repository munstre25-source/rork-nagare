begin;set local role service_role;
update public.openrouter_budget set spent_usd=cap_usd,reserved_usd=0,lookup_allowance_usd=1.79,lookup_spent_usd=0,lookup_reserved_usd=0 where id=1;
do $test$ declare held_id uuid; total numeric; begin
 if public.openrouter_reserve_budget(0.5) is not null then raise exception 'Video used lookup reserve';end if;
 held_id:=public.openrouter_reserve_lookup_budget(0.1);
 if held_id is null then raise exception 'Lookup could not use its allowance';end if;
 total:=public.openrouter_settle_budget(held_id,0.02);
 total:=public.openrouter_settle_budget(held_id,0.02);
 if (select b.lookup_spent_usd<>0.02 or b.lookup_reserved_usd<>0 from public.openrouter_budget b where b.id=1)
 then raise exception 'Lookup settlement was not exact and idempotent';end if;
 update public.openrouter_budget set lookup_spent_usd=1.79 where id=1;
 if public.openrouter_reserve_lookup_budget(0.01) is not null then raise exception 'Lookup allowance exceeded';end if;
end;$test$;
select 'lookup reserve safety passed' result;
rollback;
