------------public.shipping_country_rates-------------------------------------------------

insert into public.shipping_country_rates (shipping_country, shipping_country_base_rate)
select distinct 
	shipping_country,
	shipping_country_base_rate	
from public.shipping ps;

------------------------------------------------------------------------------------------
---хххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххх-
------------public.shipping_agreement ----------------------------------------------------

insert into public.shipping_agreement 
(agreementid, agreement_number, agreement_rate, agreement_commission)
	select 	x.agreements[1]::INT8,
		x.agreements[2]::TEXT,
		x.agreements[3]::NUMERIC(14,2),
		x.agreements[4]::NUMERIC(14,2)
	from (select distinct regexp_split_to_array(vendor_agreement_description, E'\\:+')
as agreements from public.shipping ps) x;

------------------------------------------------------------------------------------------
---хххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххx-
------------public.shipping_transfer  ----------------------------------------------------


insert into public.shipping_transfer
(transfer_type, transfer_model, shipping_transfer_rate)
	select distinct 
		(regexp_split_to_array(shipping_transfer_description, E'\\:+'))[1] as transfer_type,
		(regexp_split_to_array(shipping_transfer_description, E'\\:+'))[2] as transfer_model,
		shipping_transfer_rate
	from public.shipping ps;


------------------------------------------------------------------------------------------
---хххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххx-
------------public.shipping_info ---------------------------------------------------------

insert into public.shipping_info
(shippingid, vendorid, payment_amount, shipping_plan_datetime, transfer_type_id, shipping_country_id, agreementid)
	select distinct  
		ps.shippingid as shippingid, 
		ps.vendorid as vendorid, 
		ps.payment_amount as payment_amount, 
		ps.shipping_plan_datetime as shipping_plan_datetime,
		pst.id as transfer_type_id,
		pscr.id as shipping_country_id,
		(regexp_split_to_array(ps.vendor_agreement_description, E'\\:+'))[1]::INT8 as agreementid	
	from public.shipping ps 
	left join public.shipping_transfer pst on pst.transfer_type ||':'||pst.transfer_model = ps.shipping_transfer_description 
	left join public.shipping_country_rates pscr on pscr.shipping_country = ps.shipping_country;

------------------------------------------------------------------------------------------
---хххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххx-
------------public.shipping_status   -------------------------------------------------------

insert into public.shipping_status
(shippingid, status, state, shipping_start_fact_datetime, shipping_end_fact_datetime)
with 
main as(
	select 
		shippingid, 
		status, 
		state, 
		state_datetime,
		row_number () over(partition by shippingid order by state_datetime desc) as max_d
	from public.shipping ps),	
start_s as (
	select 
			shippingid as shippingid,
			state_datetime as shipping_start_fact_datetime
	from public.shipping ps 
	where state = 'booked'),	
end_s as (
	select 
			shippingid as shippingid,
			state_datetime as shipping_end_fact_datetime 
	from public.shipping ps 
	where state = 'recieved')
select 
	main.shippingid as shippingid, 
	main.status as status, 
	main.state as state,
	start_s.shipping_start_fact_datetime as shipping_start_fact_datetime,
	end_s.shipping_end_fact_datetime as shipping_end_fact_datetime	
	from main 
        left join start_s 
        on main.shippingid = start_s.shippingid
	left join end_s 
        on main.shippingid = end_s.shippingid
	where main.max_d=1 
	order by shippingid;

------------------------------------------------------------------------------------------
---хххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххххx-
-------------view shipping_datamart  -----------------------------------------------------


create or replace view public.shipping_datamart as (
select 
	pss.shippingid as shippingid,
	psi.vendorid as vendorid,
	pst.transfer_type as transfer_type,
	EXTRACT(DAY FROM (shipping_end_fact_datetime - shipping_start_fact_datetime)) AS full_day_at_shipping,
	(case 
         when pss.shipping_end_fact_datetime > psi.shipping_plan_datetime
         then 1 
         else 0 
    end) as is_delay,
	(case 
         when pss.status = 'finished' 
             then 1 
             else 0 
        end) as is_shipping_finish,
	(case 
         when pss.shipping_end_fact_datetime > psi.shipping_plan_datetime 
                  then 
	              EXTRACT(DAY FROM (pss.shipping_end_fact_datetime - psi.shipping_plan_datetime))
	          else 0 
             end) as delay_day_at_shipping,
	psi.payment_amount as payment_amount,
	psi.payment_amount * (scr.shipping_country_base_rate + psa.agreement_rate + pst.shipping_transfer_rate) as vat,
	psi.payment_amount * psa.agreement_commission as profit
from public.shipping_status pss 
	left join public.shipping_info psi 
                  on pss.shippingid = psi.shippingid
	left join public.shipping_transfer pst
                  on psi.transfer_type_id = pst.id
	left join public.shipping_country_rates scr
                  on psi.shipping_country_id = scr.id
	left join public.shipping_agreement psa 
                  on psi.agreementid = psa.agreementid
	                                              );
iu