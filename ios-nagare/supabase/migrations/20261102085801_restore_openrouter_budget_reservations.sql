-- Restore the owner-controlled cap and atomically reserve concurrent provider calls.
alter table public.openrouter_budget add column if not exists reserved_usd numeric not null default 0;

create table public.openrouter_budget_reservations (
  id uuid primary key default gen_random_uuid(),
  reserved_usd numeric not null check (reserved_usd > 0),
  actual_usd numeric check (actual_usd >= 0),
  created_at timestamptz not null default now(),
  settled_at timestamptz
);
alter table public.openrouter_budget_reservations enable row level security;
revoke all on public.openrouter_budget_reservations from public,anon,authenticated;
grant select,insert,update on public.openrouter_budget_reservations to service_role;
revoke all on public.openrouter_budget from public,anon,authenticated;
grant select,update on public.openrouter_budget to service_role;

create or replace function public.openrouter_budget_ok(reserve numeric default 0.05)
returns boolean language sql security invoker set search_path = '' as $$
  select coalesce((select spent_usd + reserved_usd + greatest(reserve,0) <= cap_usd
    from public.openrouter_budget where id=1),false)
$$;

create function public.openrouter_reserve_budget(p_amount numeric)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare reservation_id uuid;
begin
  if p_amount is null or p_amount <= 0 or p_amount > 10 then return null; end if;
  update public.openrouter_budget set reserved_usd=reserved_usd+p_amount,updated_at=now()
    where id=1 and spent_usd+reserved_usd+p_amount<=cap_usd;
  if not found then return null; end if;
  insert into public.openrouter_budget_reservations(reserved_usd) values(p_amount)
    returning id into reservation_id;
  return reservation_id;
end
$$;

create function public.openrouter_settle_budget(p_reservation uuid,p_cost numeric)
returns numeric language plpgsql security invoker set search_path = '' as $$
declare held public.openrouter_budget_reservations%rowtype; total numeric;
begin
  select * into held from public.openrouter_budget_reservations where id=p_reservation for update;
  if not found then return null; end if;
  if held.settled_at is not null then
    select spent_usd into total from public.openrouter_budget where id=1;
    return total;
  end if;
  update public.openrouter_budget set
    spent_usd=spent_usd+greatest(coalesce(p_cost,held.reserved_usd),0),
    reserved_usd=greatest(0,reserved_usd-held.reserved_usd),updated_at=now()
    where id=1 returning spent_usd into total;
  update public.openrouter_budget_reservations set
    actual_usd=greatest(coalesce(p_cost,held.reserved_usd),0),settled_at=now()
    where id=p_reservation;
  return total;
end
$$;

revoke all on function public.openrouter_budget_ok(numeric) from public,anon,authenticated;
revoke all on function public.openrouter_reserve_budget(numeric) from public,anon,authenticated;
revoke all on function public.openrouter_settle_budget(uuid,numeric) from public,anon,authenticated;
grant execute on function public.openrouter_budget_ok(numeric) to service_role;
grant execute on function public.openrouter_reserve_budget(numeric) to service_role;
grant execute on function public.openrouter_settle_budget(uuid,numeric) to service_role;
comment on function public.openrouter_budget_ok(numeric) is
  'Owner cap is enforced including unsettled reservations. Unknown-cost calls retain their full allowance.';
