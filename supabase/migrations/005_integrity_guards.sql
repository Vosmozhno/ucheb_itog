begin;

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
  v:=nullif(btrim(d->>rule.key, E' \t\n\r' || chr(160)),'');
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

create or replace function private.archive_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare blocked boolean:=false;
begin
 if tg_table_name='customers' and to_jsonb(new)->'user_id' is distinct from to_jsonb(old)->'user_id' and private.actor_role()<>'' then perform private.fail(403,'Связь с учётной записью задаётся при регистрации'); end if;
 if tg_table_name='units' then
  if (to_jsonb(new)->'equipment_id' is distinct from to_jsonb(old)->'equipment_id'
      or to_jsonb(new)->'location_id' is distinct from to_jsonb(old)->'location_id'
      or upper(btrim(to_jsonb(new)->>'inventory_code')) is distinct from to_jsonb(old)->>'inventory_code')
      and exists(select 1 from public.rental_items where unit_id=new.id and active) then
   perform private.fail(409,'Нельзя перемещать или переименовывать экземпляр, пока есть незавершённая аренда');
  end if;
 end if;
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

create or replace function public.change_role(p_user_id uuid,p_role text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if private.actor_role()<>'admin' then perform private.fail(403,'Роли может изменять только администратор'); end if;
 if p_role not in ('client','employee','admin') then perform private.fail(422,'Неизвестная роль','{"role":"Выберите роль из списка"}'); end if;
 perform pg_catalog.pg_advisory_xact_lock(9340,1);
 -- Recheck after acquiring the lock: another administrator may have revoked access while we waited.
 if private.actor_role()<>'admin' then perform private.fail(403,'Роль администратора была изменена. Войдите снова'); end if;
 if p_role<>'admin' and exists(select 1 from public.profiles where id=p_user_id and role='admin')
     and (select count(*) from public.profiles where role='admin')<=1 then
  perform private.fail(409,'Нельзя убрать последнего администратора');
 end if;
 if p_user_id=auth.uid() then perform private.fail(409,'Нельзя менять собственную роль'); end if;
 if not exists(select 1 from public.profiles where id=p_user_id) then perform private.fail(404,'Пользователь не найден'); end if;
 update public.profiles set role=p_role where id=p_user_id;
end $$;

alter table public.categories alter column id set generated always;
alter table public.brands alter column id set generated always;
alter table public.locations alter column id set generated always;
alter table public.equipment alter column id set generated always;
alter table public.units alter column id set generated always;
alter table public.customers alter column id set generated always;
alter table public.loyalty_cards alter column id set generated always;
alter table public.services alter column id set generated always;
alter table public.rentals alter column id set generated always;
notify pgrst,'reload schema';
commit;
