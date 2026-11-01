-- Only for the isolated local/CI database with tool/test_auth_schema.sql.
-- Every fixture and assertion is rolled back; application data is preserved.
begin;
create schema test;
create function test.expect_error(p_sql text,p_code text) returns void language plpgsql as $$
declare actual text; error_detail text;
begin
 begin execute p_sql; exception when others then
  if sqlstate='PGRST' then
   actual:=sqlerrm::jsonb->>'code';
   get stacked diagnostics error_detail=pg_exception_detail;
   if not(error_detail::jsonb ?& array['status','headers']) then raise exception 'Invalid PostgREST error contract: %',error_detail; end if;
  else actual:=sqlstate; end if;
  if actual<>p_code then raise exception 'Expected %, got %: %',p_code,actual,sqlerrm; end if;
  return;
 end;
 raise exception 'Expected %, but statement succeeded: %',p_code,p_sql;
end $$;
grant usage on schema test to authenticated,anon;
grant execute on function test.expect_error(text,text) to authenticated,anon;
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','admin@pohod.example','{"full_name":"Администратор"}'),
 ('00000000-0000-0000-0000-000000000002','employee@pohod.example','{"full_name":"Сотрудник"}'),
 ('00000000-0000-0000-0000-000000000003','client@pohod.example','{"full_name":"Анна Туристова","role":"admin"}'),
 ('00000000-0000-0000-0000-000000000004','other@pohod.example','{"full_name":"Другой клиент"}');
do $$ begin
 assert (select role='client' from public.profiles where id='00000000-0000-0000-0000-000000000003'),'Signup must ignore user-supplied role';
end $$;
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000001';
update public.profiles set role='employee' where id='00000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
do $$ begin
 assert (select count(*)=1 from public.customers),'Client must see only own contacts';
 assert (select count(*)=1 from public.loyalty_cards),'Client must see only own card';
end $$;
select test.expect_error('select public.list_users()','TR403');
select test.expect_error('update public.profiles set role=''admin''','42501');
select test.expect_error('insert into public.categories(name) values(''Запрещено'')','42501');
-- This is the exact tariff for one 700 ₽ unit, 14 days, 15% duration discount, 300 ₽ service.
do $$ declare q jsonb; begin
 q:=public.quote_rental(jsonb_build_object('location_id',1,'start_on',private.today(),'end_on',private.today()+14,'unit_ids','[1]'::jsonb,'service_ids','[1]'::jsonb));
 assert (q->>'total_cost')::numeric=8630,'Quote must calculate discount before services';
 assert (q->>'deposit')::numeric=6000,'Deposit must remain separate';
end $$;
select test.expect_error('select public.quote_rental(jsonb_build_object(''location_id'',1,''start_on'',private.today(),''end_on'',private.today(),''unit_ids'',''[1]''::jsonb))','TR422');
select test.expect_error('select public.quote_rental(jsonb_build_object(''location_id'',1,''start_on'',private.today(),''end_on'',private.today()+1,''unit_ids'',''[1,1]''::jsonb))','TR422');
select public.save_rental(jsonb_build_object('location_id',1,'start_on',private.today(),'end_on',private.today()+2,'unit_ids','[1]'::jsonb,'service_ids','[1]'::jsonb));
select test.expect_error('select public.save_rental(jsonb_build_object(''location_id'',1,''start_on'',private.today()+1,''end_on'',private.today()+3,''unit_ids'',''[1]''::jsonb))','TR409');
select test.expect_error('select public.rental_action((select max(id) from public.rentals),''issue'')','TR403');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
do $$ begin assert (select count(*)=0 from public.rentals),'Other client cannot see a foreign rental'; end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select test.expect_error('insert into public.categories(name) values(''x'')','TR422');
select test.expect_error('insert into public.categories(name) values(chr(9)||chr(10))','TR422');
select test.expect_error('update public.units set location_id=2 where id=1','TR409');
select test.expect_error('insert into public.services(name,price) values(''Неверная цена'',-1)','TR422');
select test.expect_error('select public.list_users()','TR403');
select public.rental_action((select max(id) from public.rentals),'issue');
select test.expect_error('select public.mutate_records(''rentals'',array[(select max(id) from public.rentals)],''soft'')','TR409');
select public.rental_action((select max(id) from public.rentals),'return');
select public.mutate_records('rentals',array[(select max(id) from public.rentals)],'soft');
select public.mutate_records('rentals',array[(select max(id) from public.rentals)],'restore');
select test.expect_error('select public.mutate_records(''categories'',array[1::bigint],''hard'')','TR403');
select test.expect_error('select public.mutate_records(''categories'',array[1::bigint],''soft'')','TR409');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$ begin assert (select count(*)=4 from public.list_users()),'Admin must see account list'; end $$;
select test.expect_error('select public.change_role(''00000000-0000-0000-0000-000000000001'',''client'')','TR409');
select test.expect_error('select public.rental_action((select max(id) from public.rentals),''issue'')','TR403');
rollback;
select 'PASS: auth roles, ownership, tariff, 422, 409, issue/return, deletion and restore' as result;
