begin;

create or replace function private.read_ids(p_data jsonb,p_key text,p_required boolean default false)
returns bigint[] language plpgsql immutable set search_path='' as $$
declare ids bigint[];
begin
 if p_data->p_key is null or p_data->p_key='null'::jsonb then
  if p_required then perform private.fail(422,'Выберите снаряжение',jsonb_build_object(p_key,'Выберите хотя бы один экземпляр')); end if;
  return '{}';
 end if;
 if jsonb_typeof(p_data->p_key)<>'array' then perform private.fail(422,'Некорректный список',jsonb_build_object(p_key,'Ожидается массив идентификаторов')); end if;
 begin
  select coalesce(array_agg(value::bigint),'{}') into ids from jsonb_array_elements_text(p_data->p_key);
 exception when invalid_text_representation or numeric_value_out_of_range then
  perform private.fail(422,'Некорректный список',jsonb_build_object(p_key,'Идентификаторы должны быть целыми числами'));
 end;
 if cardinality(ids)>20 or (p_required and cardinality(ids)=0) or exists(select 1 from unnest(ids) n where n is null or n<=0) then
  perform private.fail(422,'Некорректный список',jsonb_build_object(p_key,'Выберите от '||(case when p_required then '1' else '0' end)||' до 20 записей'));
 end if;
 if cardinality(ids)<>(select count(distinct n) from unnest(ids) n) then perform private.fail(422,'Повторяющиеся записи',jsonb_build_object(p_key,'Уберите повторяющиеся идентификаторы')); end if;
 return ids;
end $$;

create or replace function private.make_quote(p_data jsonb,p_exclude_id bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_unit_ids bigint[]:=private.read_ids(p_data,'unit_ids',true);
 v_service_ids bigint[]:=private.read_ids(p_data,'service_ids');
 customer bigint; location bigint; first_day date; last_day date; days integer;
 daily numeric; base numeric; deposit numeric; extras numeric; loyalty integer; duration_discount integer; discount integer;
 role text:=private.actor_role(); errors jsonb:='{}';
begin
 if role not in ('client','employee','admin') then perform private.fail(403,'Требуется учётная запись'); end if;
 begin customer:=(p_data->>'customer_id')::bigint; exception when invalid_text_representation or numeric_value_out_of_range then errors:=errors||'{"customer_id":"Выберите клиента"}'; end;
 begin location:=(p_data->>'location_id')::bigint; exception when invalid_text_representation or numeric_value_out_of_range then errors:=errors||'{"location_id":"Выберите пункт проката"}'; end;
 begin first_day:=(p_data->>'start_on')::date; exception when invalid_datetime_format or datetime_field_overflow then errors:=errors||'{"start_on":"Дата в формате ГГГГ-ММ-ДД"}'; end;
 begin last_day:=(p_data->>'end_on')::date; exception when invalid_datetime_format or datetime_field_overflow then errors:=errors||'{"end_on":"Дата в формате ГГГГ-ММ-ДД"}'; end;
 if role='client' then
  if customer is not null and customer is distinct from private.customer_id() then perform private.fail(403,'Нельзя оформить аренду на другого клиента'); end if;
  customer:=private.customer_id();
 end if;
 if customer is null or not exists(select 1 from public.customers where id=customer and deleted_at is null) then errors:=errors||'{"customer_id":"Клиент не найден или удалён"}'; end if;
 if location is null or not exists(select 1 from public.locations where id=location and deleted_at is null) then errors:=errors||'{"location_id":"Выберите действующий пункт проката"}'; end if;
 if first_day is null then errors:=errors||'{"start_on":"Обязательное поле"}'; elsif first_day<current_date then errors:=errors||'{"start_on":"Начало аренды не может быть в прошлом"}'; end if;
 if last_day is null then errors:=errors||'{"end_on":"Обязательное поле"}'; elsif last_day<=first_day or last_day-first_day>90 then errors:=errors||'{"end_on":"Продолжительность: от 1 до 90 суток"}'; end if;
 if errors<>'{}'::jsonb then perform private.fail(422,'Проверьте поля аренды',errors); end if;
 days:=last_day-first_day;
 if (select count(*) from public.units u join public.equipment e on e.id=u.equipment_id where u.id=any(v_unit_ids) and u.deleted_at is null and e.deleted_at is null and u.state='ready' and u.location_id=location)<>cardinality(v_unit_ids) then
  perform private.fail(422,'Снаряжение недоступно',jsonb_build_object('unit_ids','Выберите готовые экземпляры из указанного пункта проката'));
 end if;
 if (select count(*) from public.services where id=any(v_service_ids) and deleted_at is null)<>cardinality(v_service_ids) then perform private.fail(422,'Услуга недоступна','{"service_ids":"Одна из услуг удалена. Обновите список"}'); end if;
 if exists(
  select 1 from public.rental_items i join public.rentals r on r.id=i.rental_id
  where i.unit_id=any(v_unit_ids) and i.active and (p_exclude_id is null or r.id<>p_exclude_id)
  and (i.booked_period && daterange(first_day,last_day,'[)') or (r.status='issued' and r.end_on<=current_date))
 ) then perform private.fail(409,'Один из экземпляров уже занят на выбранные даты или ещё не возвращён','{"unit_ids":"Обновите доступность и выберите другие экземпляры"}'); end if;
 select sum(e.daily_rate),sum(e.deposit) into daily,deposit from public.units u join public.equipment e on e.id=u.equipment_id where u.id=any(v_unit_ids);
 select coalesce(sum(price),0) into extras from public.services where id=any(v_service_ids);
 select coalesce(max(discount_percent),0) into loyalty from public.loyalty_cards where customer_id=customer and deleted_at is null and issued_on<=current_date and expires_on>=current_date;
 duration_discount:=case when days>=14 then 15 when days>=7 then 10 else 0 end;
 discount:=least(20,loyalty+duration_discount); base:=daily*days;
 return jsonb_build_object('customer_id',customer,'location_id',location,'start_on',first_day,'end_on',last_day,'days',days,
  'daily_rate',daily,'base_cost',base,'loyalty_discount',loyalty,'duration_discount',duration_discount,'discount_percent',discount,
  'discount_amount',round(base*discount/100,2),'services_cost',extras,'total_cost',round(base*(100-discount)/100+extras,2),'deposit',deposit,
  'due_now',round(base*(100-discount)/100+extras+deposit,2));
end $$;

create or replace function public.quote_rental(p_data jsonb,p_id bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_id is not null and not exists(select 1 from public.rentals where id=p_id and deleted_at is null and (private.actor_role() in ('employee','admin') or customer_id=private.customer_id())) then perform private.fail(403,'Эта аренда недоступна'); end if;
 return private.make_quote(p_data,p_id);
end $$;

create or replace function public.available_units(p_start date,p_end date,p_location bigint,p_rental_id bigint default null)
returns table(id bigint,inventory_code text,equipment_id bigint,equipment_name text,daily_rate integer,deposit integer,location_id bigint)
language plpgsql security definer set search_path='' as $$
begin
 if private.actor_role() not in ('client','employee','admin') then perform private.fail(403,'Требуется учётная запись'); end if;
 if p_start is null or p_start<current_date then perform private.fail(422,'Некорректные даты','{"start_on":"Выберите сегодня или более позднюю дату"}'); end if;
 if p_end is null or p_end<=p_start or p_end-p_start>90 then perform private.fail(422,'Некорректные даты','{"end_on":"Продолжительность: от 1 до 90 суток"}'); end if;
 if p_location is null then perform private.fail(422,'Выберите пункт проката','{"location_id":"Обязательное поле"}'); end if;
 if p_rental_id is not null and not exists(select 1 from public.rentals where rentals.id=p_rental_id and (private.actor_role() in ('employee','admin') or customer_id=private.customer_id())) then perform private.fail(403,'Эта аренда недоступна'); end if;
 return query select u.id,u.inventory_code,e.id,e.name,e.daily_rate,e.deposit,u.location_id
 from public.units u join public.equipment e on e.id=u.equipment_id join public.locations l on l.id=u.location_id
 where u.location_id=p_location and u.state='ready' and u.deleted_at is null and e.deleted_at is null and l.deleted_at is null
 and not exists(select 1 from public.rental_items i join public.rentals r on r.id=i.rental_id where i.unit_id=u.id and i.active and (p_rental_id is null or r.id<>p_rental_id) and (i.booked_period && daterange(p_start,p_end,'[)') or (r.status='issued' and r.end_on<=current_date)))
 order by e.name,u.inventory_code;
end $$;

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
 q:=private.make_quote(p_data,p_id);
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

create or replace function public.rental_action(p_id bigint,p_action text) returns public.rentals
language plpgsql security definer set search_path='' as $$
declare r public.rentals; role text:=private.actor_role(); daily numeric;
begin
 select * into r from public.rentals where id=p_id and deleted_at is null for update;
 if not found then perform private.fail(404,'Аренда не найдена'); end if;
 if role not in ('client','employee','admin') then perform private.fail(403,'Требуется учётная запись'); end if;
 if role='client' and r.customer_id is distinct from private.customer_id() then perform private.fail(403,'Это аренда другого клиента'); end if;
 if p_action='cancel' then
  if r.status<>'reserved' then perform private.fail(409,'Отменить можно только бронирование до выдачи'); end if;
  update public.rentals set status='cancelled' where id=p_id returning * into r;
 elsif p_action in ('issue','return') then
  if role<>'employee' then perform private.fail(403,'Выдача и возврат доступны только сотруднику'); end if;
  perform u.id from public.units u join public.rental_items i on i.unit_id=u.id where i.rental_id=p_id order by u.id for update of u;
  if p_action='issue' then
   if r.status<>'reserved' then perform private.fail(409,'Аренда уже обработана'); end if;
   if current_date<r.start_on or current_date>=r.end_on then perform private.fail(409,'Выдать снаряжение можно в период бронирования'); end if;
   if exists(select 1 from public.rental_items i join public.units u on u.id=i.unit_id join public.equipment e on e.id=u.equipment_id where i.rental_id=p_id and (u.state<>'ready' or u.deleted_at is not null or e.deleted_at is not null)) then perform private.fail(409,'Снаряжение удалено или находится на проверке'); end if;
   if exists(select 1 from public.rental_items mine join public.rental_items other on other.unit_id=mine.unit_id join public.rentals occupied on occupied.id=other.rental_id where mine.rental_id=p_id and occupied.id<>p_id and occupied.status='issued' and occupied.deleted_at is null) then perform private.fail(409,'Снаряжение ещё не вернул другой клиент'); end if;
   update public.rentals set status='issued',issued_at=now() where id=p_id returning * into r;
  else
   if r.status<>'issued' then perform private.fail(409,'Вернуть можно только выданное снаряжение'); end if;
   select sum(daily_rate) into daily from public.rental_items where rental_id=p_id;
   update public.rentals set status='returned',returned_at=now(),late_fee=round(greatest(current_date-end_on,0)*daily*0.5,2) where id=p_id returning * into r;
  end if;
 else perform private.fail(422,'Неизвестное действие'); end if;
 if r.status in ('returned','cancelled') then update public.rental_items set active=false where rental_id=p_id; end if;
 return r;
end $$;

create or replace function private.archive_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare blocked boolean:=false;
begin
 if tg_table_name='customers' and to_jsonb(new)->'user_id' is distinct from to_jsonb(old)->'user_id' and private.actor_role()<>'' then perform private.fail(403,'Связь с учётной записью задаётся при регистрации'); end if;
 if old.deleted_at is not null or new.deleted_at is null then return new; end if;
 case tg_table_name
 when 'categories' then select exists(select 1 from public.equipment where category_id=new.id and deleted_at is null) into blocked;
 when 'brands' then select exists(select 1 from public.equipment where brand_id=new.id and deleted_at is null) into blocked;
 when 'locations' then select exists(select 1 from public.units where location_id=new.id and deleted_at is null) or exists(select 1 from public.rentals where location_id=new.id and status in ('reserved','issued') and deleted_at is null) into blocked;
 when 'equipment' then select exists(select 1 from public.units where equipment_id=new.id and deleted_at is null) into blocked;
 when 'units' then select exists(select 1 from public.rental_items where unit_id=new.id and active) into blocked;
 when 'customers' then select exists(select 1 from public.rentals where customer_id=new.id and status in ('reserved','issued') and deleted_at is null) into blocked;
 when 'rentals' then blocked:=new.status='issued';
 else null;
 end case;
 if blocked then perform private.fail(409,'Запись используется: сначала завершите аренды или удалите зависимые записи'); end if;
 return new;
end $$;
do $$ declare t text; begin
 foreach t in array array['categories','brands','locations','equipment','units','customers','loyalty_cards','services','rentals'] loop
  execute format('create trigger archive_guard before update on public.%I for each row execute function private.archive_guard()',t);
 end loop;
end $$;

create or replace function public.mutate_records(p_entity text,p_ids bigint[],p_action text)
returns integer language plpgsql security definer set search_path='' as $$
declare v_id bigint; changed integer:=0; row_count integer; r public.rentals; role text:=private.actor_role();
begin
 if role not in ('employee','admin') then perform private.fail(403,'Управление записями доступно сотруднику и администратору'); end if;
 if not exists(select 1 from private.validation_rules where entity=p_entity) then perform private.fail(422,'Неизвестная сущность'); end if;
 if p_action not in ('soft','restore','hard') then perform private.fail(422,'Неизвестное действие'); end if;
 if p_action='hard' and role<>'admin' then perform private.fail(403,'Удаление навсегда доступно только администратору'); end if;
 if coalesce(cardinality(p_ids),0) not between 1 and 100 then perform private.fail(422,'Выберите от 1 до 100 записей'); end if;
 foreach v_id in array p_ids loop
  if p_entity='rentals' then
   select * into r from public.rentals where rentals.id=v_id for update;
   if not found then continue; end if;
   if r.status='issued' then perform private.fail(409,'Сначала оформите возврат снаряжения'); end if;
   if p_action='restore' and r.status='reserved' then
    if exists(select 1 from public.rental_items i join public.units u on u.id=i.unit_id join public.equipment e on e.id=u.equipment_id where i.rental_id=r.id and (u.deleted_at is not null or e.deleted_at is not null or u.state<>'ready')) then perform private.fail(409,'Сначала восстановите и подготовьте снаряжение'); end if;
   end if;
  end if;
  if p_action='soft' then execute format('update public.%I set deleted_at=now() where id=$1 and deleted_at is null',p_entity) using v_id;
  elsif p_action='restore' then execute format('update public.%I set deleted_at=null where id=$1 and deleted_at is not null',p_entity) using v_id;
  else execute format('delete from public.%I where id=$1 and deleted_at is not null',p_entity) using v_id; end if;
  get diagnostics row_count=row_count; changed:=changed+row_count;
  if p_entity='rentals' and p_action<>'hard' and row_count>0 then update public.rental_items set active=(p_action='restore' and r.status='reserved') where rental_id=v_id; end if;
 end loop;
 return changed;
exception
 when foreign_key_violation then perform private.fail(409,'Запись связана с другими данными. Удалите зависимые записи первыми');
 when exclusion_violation then perform private.fail(409,'Восстановление невозможно: снаряжение уже занято');
end $$;

create or replace function public.list_users() returns table(id uuid,full_name text,email text,role text,created_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 if private.actor_role()<>'admin' then perform private.fail(403,'Список пользователей доступен только администратору'); end if;
 return query select p.id,p.full_name,u.email::text,p.role,p.created_at from public.profiles p join auth.users u on u.id=p.id order by p.created_at,p.id;
end $$;
create or replace function public.change_role(p_user_id uuid,p_role text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if private.actor_role()<>'admin' then perform private.fail(403,'Роли может изменять только администратор'); end if;
 if p_role not in ('client','employee','admin') then perform private.fail(422,'Неизвестная роль','{"role":"Выберите роль из списка"}'); end if;
 perform pg_catalog.pg_advisory_xact_lock(9340,1);
 if p_user_id=auth.uid() then perform private.fail(409,'Нельзя менять собственную роль'); end if;
 if not exists(select 1 from public.profiles where id=p_user_id) then perform private.fail(404,'Пользователь не найден'); end if;
 update public.profiles set role=p_role where id=p_user_id;
end $$;

revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.actor_role(),private.customer_id() to authenticated;
revoke all on function public.quote_rental(jsonb,bigint),public.available_units(date,date,bigint,bigint),public.save_rental(jsonb,bigint),public.rental_action(bigint,text),public.mutate_records(text,bigint[],text),public.list_users(),public.change_role(uuid,text) from public,anon;
grant execute on function public.quote_rental(jsonb,bigint),public.available_units(date,date,bigint,bigint),public.save_rental(jsonb,bigint),public.rental_action(bigint,text),public.mutate_records(text,bigint[],text),public.list_users(),public.change_role(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
