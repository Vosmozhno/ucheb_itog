begin;
create or replace function public.save_rental(p_data jsonb,p_id bigint default null)
returns public.rentals language plpgsql security definer set search_path='' as $$
declare v_unit_ids bigint[]:=private.read_ids(p_data,'unit_ids',true); v_service_ids bigint[]:=private.read_ids(p_data,'service_ids'); q jsonb; r public.rentals;
begin
 if p_id is not null then
  select * into r from public.rentals where id=p_id and deleted_at is null for update;
  if not found then perform private.fail(404,'Аренда не найдена'); end if;
  if private.actor_role()='client' and r.customer_id is distinct from private.customer_id() then perform private.fail(403,'Это аренда другого клиента'); end if;
  if r.status<>'reserved' then perform private.fail(409,'Изменять можно только бронирование до выдачи'); end if;
 end if;
 -- Deterministic row locks serialize concurrent reservations for the same units.
 perform id from public.units where id=any(v_unit_ids) order by id for update;
 perform e.id from public.equipment e where e.id in (select equipment_id from public.units where id=any(v_unit_ids)) order by e.id for update;
 perform id from public.services where id=any(v_service_ids) order by id for update;
 q:=private.make_quote(p_data,p_id);
 if p_data ? 'expected_total' and (p_data->>'expected_total')::numeric<>(q->>'total_cost')::numeric then
  perform private.fail(409,'Стоимость изменилась. Получите новый расчёт перед бронированием','{"quote":"Пересчитайте стоимость"}');
 end if;
 if p_id is null then
  insert into public.rentals(customer_id,location_id,start_on,end_on,notes,base_cost,discount_percent,services_cost,total_cost,deposit)
  values((q->>'customer_id')::bigint,(q->>'location_id')::bigint,(q->>'start_on')::date,(q->>'end_on')::date,coalesce(p_data->>'notes',''),(q->>'base_cost')::numeric,(q->>'discount_percent')::int,(q->>'services_cost')::numeric,(q->>'total_cost')::numeric,(q->>'deposit')::numeric) returning * into r;
 else
  update public.rentals set customer_id=(q->>'customer_id')::bigint,location_id=(q->>'location_id')::bigint,start_on=(q->>'start_on')::date,end_on=(q->>'end_on')::date,notes=coalesce(p_data->>'notes',''),base_cost=(q->>'base_cost')::numeric,discount_percent=(q->>'discount_percent')::int,services_cost=(q->>'services_cost')::numeric,total_cost=(q->>'total_cost')::numeric,deposit=(q->>'deposit')::numeric where id=p_id returning * into r;
  delete from public.rental_items where rental_id=r.id;
  delete from public.rental_services where rental_id=r.id;
 end if;
 insert into public.rental_items(rental_id,unit_id,equipment_name,inventory_code,daily_rate,deposit,booked_period)
 select r.id,u.id,e.name,u.inventory_code,e.daily_rate,e.deposit,daterange(r.start_on,r.end_on,'[)') from public.units u join public.equipment e on e.id=u.equipment_id where u.id=any(v_unit_ids);
 insert into public.rental_services(rental_id,service_id,service_name,price) select r.id,id,name,price from public.services where id=any(v_service_ids);
 return r;
exception when exclusion_violation then perform private.fail(409,'Снаряжение только что забронировал другой клиент','{"unit_ids":"Обновите доступность и повторите выбор"}');
end $$;
create or replace function public.admin_summary() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if private.actor_role()<>'admin' then perform private.fail(403,'Сводка доступна только администратору'); end if;
 return jsonb_build_object(
  'equipment',(select count(*) from public.equipment where deleted_at is null),
  'units',(select count(*) from public.units where deleted_at is null),
  'customers',(select count(*) from public.customers where deleted_at is null),
  'active_rentals',(select count(*) from public.rentals where deleted_at is null and status in ('reserved','issued')),
  'overdue',(select count(*) from public.rentals where deleted_at is null and status='issued' and end_on<current_date),
  'completed_cost',(select coalesce(sum(total_cost+late_fee),0) from public.rentals where deleted_at is null and status='returned'),
  'statuses',(select coalesce(jsonb_object_agg(status,count),'{}') from (select status,count(*) from public.rentals where deleted_at is null group by status) s),
  'locations',(select coalesce(jsonb_agg(jsonb_build_object('name',l.name,'units',(select count(*) from public.units where location_id=l.id and deleted_at is null)) order by l.id),'[]') from public.locations l where l.deleted_at is null)
 );
end $$;
revoke all on function public.admin_summary() from public,anon;
grant execute on function public.admin_summary() to authenticated;
notify pgrst,'reload schema';
commit;
