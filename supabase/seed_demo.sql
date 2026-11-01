-- Run after the three demo accounts have been created in Supabase Authentication.
-- No passwords or privileged keys are stored in this file.
begin;
update public.profiles p set role=x.role,full_name=x.name
from auth.users u join (values
 ('admin@pohod.example','admin','Администратор'),
 ('employee@pohod.example','employee','Алексей Сотрудников'),
 ('client@pohod.example','client','Анна Туристова')
) as x(email,role,name) on lower(u.email)=x.email where p.id=u.id;
update public.customers c set full_name=p.full_name,phone=case p.role when 'admin' then '+79000000001' when 'employee' then '+79000000002' else '+79000000003' end
from public.profiles p join auth.users u on u.id=p.id where c.user_id=p.id and lower(u.email) in ('admin@pohod.example','employee@pohod.example','client@pohod.example');
update public.loyalty_cards set discount_percent=5 where customer_id=(select c.id from public.customers c join auth.users u on u.id=c.user_id where lower(u.email)='client@pohod.example');

do $$ declare client_id bigint; rental bigint;
begin
 select c.id into client_id from public.customers c join auth.users u on u.id=c.user_id where lower(u.email)='client@pohod.example';
 if client_id is null then raise exception 'Create client@pohod.example in Authentication first'; end if;
 if not exists(select 1 from public.rentals where notes='Демо: поход выходного дня') then
  insert into public.rentals(customer_id,location_id,start_on,end_on,status,notes,base_cost,discount_percent,services_cost,total_cost,deposit,issued_at,returned_at)
  values(client_id,1,current_date-10,current_date-8,'returned','Демо: поход выходного дня',1400,5,300,1630,6000,now()-interval '10 days',now()-interval '8 days') returning id into rental;
  insert into public.rental_items(rental_id,unit_id,equipment_name,inventory_code,daily_rate,deposit,booked_period,active)
  select rental,u.id,e.name,u.inventory_code,e.daily_rate,e.deposit,daterange(current_date-10,current_date-8,'[)'),false from public.units u join public.equipment e on e.id=u.equipment_id where u.id=1;
  insert into public.rental_services(rental_id,service_id,service_name,price) select rental,id,name,price from public.services where id=1;
 end if;
 if not exists(select 1 from public.rentals where notes='Демо: ожидает возврата') then
  insert into public.rentals(customer_id,location_id,start_on,end_on,status,notes,base_cost,discount_percent,total_cost,deposit,issued_at)
  values(client_id,1,current_date-3,current_date-1,'issued','Демо: ожидает возврата',700,5,665,3500,now()-interval '3 days') returning id into rental;
  insert into public.rental_items(rental_id,unit_id,equipment_name,inventory_code,daily_rate,deposit,booked_period)
  select rental,u.id,e.name,u.inventory_code,e.daily_rate,e.deposit,daterange(current_date-3,current_date-1,'[)') from public.units u join public.equipment e on e.id=u.equipment_id where u.id=5;
 end if;
 if not exists(select 1 from public.rentals where notes='Демо: готово к выдаче') then
  insert into public.rentals(customer_id,location_id,start_on,end_on,notes,base_cost,discount_percent,total_cost,deposit)
  values(client_id,1,current_date,current_date+3,'Демо: готово к выдаче',1950,5,1852.5,9000) returning id into rental;
  insert into public.rental_items(rental_id,unit_id,equipment_name,inventory_code,daily_rate,deposit,booked_period)
  select rental,u.id,e.name,u.inventory_code,e.daily_rate,e.deposit,daterange(current_date,current_date+3,'[)') from public.units u join public.equipment e on e.id=u.equipment_id where u.id=7;
 end if;
end $$;
commit;
select p.full_name,p.role,u.email from public.profiles p join auth.users u on u.id=p.id order by p.role;
