begin;

create or replace function private.today() returns date language sql stable set search_path='' as $$ select (now() at time zone 'Europe/Moscow')::date; $$;

revoke all on function private.today() from public,anon;

grant execute on function private.today() to authenticated;

create or replace function private.fail(p_status integer,p_message text,p_fields jsonb default '{}'::jsonb)
returns void language plpgsql set search_path='' as $$
begin
 raise sqlstate 'PGRST' using message=jsonb_build_object('code','TR'||p_status,'message',p_message,'details',p_fields::text,'hint',null)::text,
 detail=jsonb_build_object('status',p_status,'headers','{}'::jsonb)::text;
end $$;

create or replace function private.validate_record() returns trigger language plpgsql security definer set search_path='' as $$
declare
 d jsonb:=to_jsonb(new); old_d jsonb:='{}'; rules jsonb; rule record;
 v text; errors jsonb:='{}'; duplicate boolean; valid_ref boolean;
begin
 if tg_op='UPDATE' then
  old_d:=to_jsonb(old);
  if new.id<>old.id then perform private.fail(422,'Идентификатор нельзя изменять',jsonb_build_object('id','Поле доступно только для чтения')); end if;
  new.created_at:=old.created_at;
 else new.created_at:=now(); end if;
 new.updated_at:=now();
 select r.rules into rules from private.validation_rules r where r.entity=tg_table_name;
 for rule in select key,value from jsonb_each(rules) loop
  v:=nullif(btrim(d->>rule.key),'');
  if rule.value->>'type' in ('text','email','phone') and v is not null then
   if rule.value->>'type'='email' then v:=lower(v); end if;
   if rule.key in ('sku','inventory_code','number') then v:=upper(v); end if;
   d:=jsonb_set(d,array[rule.key],to_jsonb(v));
  end if;
  if coalesce((rule.value->>'required')::boolean,false) and v is null then
   errors:=errors||jsonb_build_object(rule.key,'Обязательное поле'); continue;
  end if;
  if v is null then continue; end if;
  if rule.value->>'type' in ('text','email','phone') then
   if length(v)<(rule.value->>'min')::int then errors:=errors||jsonb_build_object(rule.key,'Минимум '||(rule.value->>'min')||' символа'); end if;
   if length(v)>(rule.value->>'max')::int then errors:=errors||jsonb_build_object(rule.key,'Максимум '||(rule.value->>'max')||' символов'); end if;
  elsif rule.value->>'type'='integer' then
   if v::numeric<(rule.value->>'min')::numeric or v::numeric>(rule.value->>'max')::numeric then
    errors:=errors||jsonb_build_object(rule.key,'Допустимо от '||(rule.value->>'min')||' до '||(rule.value->>'max'));
   end if;
  elsif rule.value->>'type'='reference' then
   execute format('select exists(select 1 from public.%I where id=$1 and deleted_at is null)',rule.value->>'reference') into valid_ref using v::bigint;
   if not valid_ref and (tg_op='INSERT' or d->rule.key is distinct from old_d->rule.key or (old_d->>'deleted_at' is not null and d->>'deleted_at' is null)) then
    errors:=errors||jsonb_build_object(rule.key,'Связанная запись удалена или не существует');
   end if;
  elsif rule.value->>'type'='choice' then
   if not (rule.value->'choices' ? v) then errors:=errors||jsonb_build_object(rule.key,'Выберите значение из списка'); end if;
  end if;
  if rule.value->>'type'='email' and v!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then errors:=errors||jsonb_build_object(rule.key,'Некорректная почта'); end if;
  if rule.value->>'type'='phone' and (v!~'^\+?[0-9 ()-]+$' or length(regexp_replace(v,'\D','','g')) not between 10 and 15) then errors:=errors||jsonb_build_object(rule.key,'Введите телефон: от 10 до 15 цифр'); end if;
  if rule.key in ('sku','inventory_code') and v!~'^[A-Z0-9][A-Z0-9-]{2,29}$' then errors:=errors||jsonb_build_object(rule.key,'От 3 до 30 латинских букв, цифр или дефисов'); end if;
  if rule.key='number' and v!~'^TR-[0-9]{6}$' then errors:=errors||jsonb_build_object(rule.key,'Формат номера: TR-000001'); end if;
  if coalesce((rule.value->>'unique')::boolean,false) then
   execute format('select exists(select 1 from public.%I where lower(%I)=$1 and id<>$2)',tg_table_name,rule.key) into duplicate using lower(v),new.id;
   if duplicate then errors:=errors||jsonb_build_object(rule.key,'Такое значение уже используется, в том числе в корзине'); end if;
  end if;
 end loop;
 if tg_table_name='loyalty_cards' then
  if (d->>'expires_on')::date<=(d->>'issued_on')::date then errors:=errors||jsonb_build_object('expires_on','Дата окончания должна быть позже даты выдачи'); end if;
  if exists(select 1 from public.loyalty_cards where customer_id=(d->>'customer_id')::bigint and id<>new.id) then errors:=errors||jsonb_build_object('customer_id','У клиента уже есть карта, проверьте корзину'); end if;
 end if;
 if tg_table_name='units' and (d->>'acquired_on')::date>private.today() then errors:=errors||jsonb_build_object('acquired_on','Дата приобретения не может быть в будущем'); end if;
 if tg_table_name='rentals' and ((d->>'end_on')::date<=(d->>'start_on')::date or (d->>'end_on')::date-(d->>'start_on')::date>90) then
  errors:=errors||jsonb_build_object('end_on','Продолжительность аренды: от 1 до 90 суток');
 end if;
 if errors<>'{}'::jsonb then perform private.fail(422,'Проверьте поля формы',errors); end if;
 -- jsonb_populate_record applies normalized text while timestamps remain server-owned.
 d:=d||jsonb_build_object('created_at',new.created_at,'updated_at',new.updated_at);
 new:=jsonb_populate_record(new,d);
 return new;
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
 if first_day is null then errors:=errors||'{"start_on":"Обязательное поле"}'; elsif first_day<private.today() then errors:=errors||'{"start_on":"Начало аренды не может быть в прошлом"}'; end if;
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
  and (i.booked_period && daterange(first_day,last_day,'[)') or (r.status='issued' and r.end_on<=private.today()))
 ) then perform private.fail(409,'Один из экземпляров уже занят на выбранные даты или ещё не возвращён','{"unit_ids":"Обновите доступность и выберите другие экземпляры"}'); end if;
 select sum(e.daily_rate),sum(e.deposit) into daily,deposit from public.units u join public.equipment e on e.id=u.equipment_id where u.id=any(v_unit_ids);
 select coalesce(sum(price),0) into extras from public.services where id=any(v_service_ids);
 select coalesce(max(discount_percent),0) into loyalty from public.loyalty_cards where customer_id=customer and deleted_at is null and issued_on<=private.today() and expires_on>=private.today();
 duration_discount:=case when days>=14 then 15 when days>=7 then 10 else 0 end;
 discount:=least(20,loyalty+duration_discount); base:=daily*days;
 return jsonb_build_object('customer_id',customer,'location_id',location,'start_on',first_day,'end_on',last_day,'days',days,
  'daily_rate',daily,'base_cost',base,'loyalty_discount',loyalty,'duration_discount',duration_discount,'discount_percent',discount,
  'discount_amount',round(base*discount/100,2),'services_cost',extras,'total_cost',round(base*(100-discount)/100+extras,2),'deposit',deposit,
  'due_now',round(base*(100-discount)/100+extras+deposit,2));
end $$;

create or replace function public.available_units(p_start date,p_end date,p_location bigint,p_rental_id bigint default null)
returns table(id bigint,inventory_code text,equipment_id bigint,equipment_name text,daily_rate integer,deposit integer,location_id bigint)
language plpgsql security definer set search_path='' as $$
begin
 if private.actor_role() not in ('client','employee','admin') then perform private.fail(403,'Требуется учётная запись'); end if;
 if p_start is null or p_start<private.today() then perform private.fail(422,'Некорректные даты','{"start_on":"Выберите сегодня или более позднюю дату"}'); end if;
 if p_end is null or p_end<=p_start or p_end-p_start>90 then perform private.fail(422,'Некорректные даты','{"end_on":"Продолжительность: от 1 до 90 суток"}'); end if;
 if p_location is null then perform private.fail(422,'Выберите пункт проката','{"location_id":"Обязательное поле"}'); end if;
 if p_rental_id is not null and not exists(select 1 from public.rentals where rentals.id=p_rental_id and (private.actor_role() in ('employee','admin') or customer_id=private.customer_id())) then perform private.fail(403,'Эта аренда недоступна'); end if;
 return query select u.id,u.inventory_code,e.id,e.name,e.daily_rate,e.deposit,u.location_id
 from public.units u join public.equipment e on e.id=u.equipment_id join public.locations l on l.id=u.location_id
 where u.location_id=p_location and u.state='ready' and u.deleted_at is null and e.deleted_at is null and l.deleted_at is null
 and not exists(select 1 from public.rental_items i join public.rentals r on r.id=i.rental_id where i.unit_id=u.id and i.active and (p_rental_id is null or r.id<>p_rental_id) and (i.booked_period && daterange(p_start,p_end,'[)') or (r.status='issued' and r.end_on<=private.today())))
 order by e.name,u.inventory_code;
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
   if private.today()<r.start_on or private.today()>=r.end_on then perform private.fail(409,'Выдать снаряжение можно в период бронирования'); end if;
   if exists(select 1 from public.rental_items i join public.units u on u.id=i.unit_id join public.equipment e on e.id=u.equipment_id where i.rental_id=p_id and (u.state<>'ready' or u.deleted_at is not null or e.deleted_at is not null)) then perform private.fail(409,'Снаряжение удалено или находится на проверке'); end if;
   if exists(select 1 from public.rental_items mine join public.rental_items other on other.unit_id=mine.unit_id join public.rentals occupied on occupied.id=other.rental_id where mine.rental_id=p_id and occupied.id<>p_id and occupied.status='issued' and occupied.deleted_at is null) then perform private.fail(409,'Снаряжение ещё не вернул другой клиент'); end if;
   update public.rentals set status='issued',issued_at=now() where id=p_id returning * into r;
  else
   if r.status<>'issued' then perform private.fail(409,'Вернуть можно только выданное снаряжение'); end if;
   select sum(daily_rate) into daily from public.rental_items where rental_id=p_id;
   update public.rentals set status='returned',returned_at=now(),late_fee=round(greatest(private.today()-end_on,0)*daily*0.5,2) where id=p_id returning * into r;
  end if;
 else perform private.fail(422,'Неизвестное действие'); end if;
 if r.status in ('returned','cancelled') then update public.rental_items set active=false where rental_id=p_id; end if;
 return r;
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
  'overdue',(select count(*) from public.rentals where deleted_at is null and status='issued' and end_on<private.today()),
  'completed_cost',(select coalesce(sum(total_cost+late_fee),0) from public.rentals where deleted_at is null and status='returned'),
  'statuses',(select coalesce(jsonb_object_agg(status,count),'{}') from (select status,count(*) from public.rentals where deleted_at is null group by status) s),
  'locations',(select coalesce(jsonb_agg(jsonb_build_object('name',l.name,'units',(select count(*) from public.units where location_id=l.id and deleted_at is null)) order by l.id),'[]') from public.locations l where l.deleted_at is null)
 );
end $$;

alter table public.units alter column acquired_on set default private.today();

alter table public.loyalty_cards alter column issued_on set default private.today();

alter table public.loyalty_cards alter column expires_on set default (private.today()+365);

notify pgrst,'reload schema';

commit;
