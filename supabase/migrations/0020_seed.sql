-- 0019_seed.sql — development seed (no real personal data). Safe to re-run.
insert into public.settings(key,value) values ('allow_mock_payments','true'::jsonb), ('payment_provider','"mock"'::jsonb)
on conflict (key) do nothing;

insert into public.places (name, type, wilaya, commune, location) values
 ('Alger Centre','wilaya','Alger','Alger Centre', st_setsrid(st_makepoint(3.0588,36.7538),4326)),
 ('Blida','wilaya','Blida','Blida', st_setsrid(st_makepoint(2.8277,36.4703),4326)),
 ('Médéa','wilaya','Médéa','Médéa', st_setsrid(st_makepoint(2.7539,36.2675),4326)),
 ('Laghouat','wilaya','Laghouat','Laghouat', st_setsrid(st_makepoint(2.8650,33.8000),4326)),
 ('Oran','wilaya','Oran','Oran', st_setsrid(st_makepoint(-0.6331,35.6971),4326)),
 ('Constantine','wilaya','Constantine','Constantine', st_setsrid(st_makepoint(6.6147,36.3650),4326)),
 ('Annaba','wilaya','Annaba','Annaba', st_setsrid(st_makepoint(7.7667,36.9000),4326)),
 ('Sétif','wilaya','Sétif','Sétif', st_setsrid(st_makepoint(5.4108,36.1898),4326)),
 ('Tizi Ouzou','wilaya','Tizi Ouzou','Tizi Ouzou', st_setsrid(st_makepoint(4.0500,36.7169),4326)),
 ('Béjaïa','wilaya','Béjaïa','Béjaïa', st_setsrid(st_makepoint(5.0833,36.7500),4326)),
 ('Ghardaïa','wilaya','Ghardaïa','Ghardaïa', st_setsrid(st_makepoint(3.6667,32.4833),4326)),
 ('Ouargla','wilaya','Ouargla','Ouargla', st_setsrid(st_makepoint(5.3333,31.9500),4326)),
 ('Batna','wilaya','Batna','Batna', st_setsrid(st_makepoint(6.1739,35.5559),4326)),
 ('Tlemcen','wilaya','Tlemcen','Tlemcen', st_setsrid(st_makepoint(-1.3150,34.8828),4326)),
 ('Biskra','wilaya','Biskra','Biskra', st_setsrid(st_makepoint(5.7281,34.8500),4326)),
 ('Gare Routière Kharrouba','station','Alger','Kharrouba', st_setsrid(st_makepoint(3.0960,36.7100),4326)),
 ('Aéroport Houari Boumediene','station','Alger','Dar El Beïda', st_setsrid(st_makepoint(3.2154,36.6910),4326))
on conflict do nothing;
