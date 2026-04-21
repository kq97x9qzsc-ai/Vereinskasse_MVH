create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  group_name text not null,
  article text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(10,2) not null check (unit_price >= 0),
  total_price numeric(10,2) not null check (total_price >= 0),
  workday text not null,
  invoice_number integer not null,
  table_name text not null default '',
  sold_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.sales enable row level security;

drop policy if exists "allow anon insert sales" on public.sales;
create policy "allow anon insert sales"
on public.sales
for insert
to anon, authenticated
with check (true);

drop policy if exists "allow authenticated read sales" on public.sales;
create policy "allow authenticated read sales"
on public.sales
for select
to authenticated
using (true);
