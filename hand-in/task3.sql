--
-- PostgreSQL database dump
--

-- Dumped from database version 9.2.14
-- Dumped by pg_dump version 9.5.0

SET statement_timeout = 0;
--SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
--SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner:
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: deletehotels(); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE FUNCTION deletehotels() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

begin
update persons
set budget = budget + getval('hotelrefund')*getval('hotelprice')
where personnummer = old.ownerpersonnummer and country = old.ownercountry;
return new;
end

$$;


--
-- Name: deleteroad(); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE FUNCTION deleteroad() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

begin
if exists (select * from roads where
ownerpersonnummer = old.ownerpersonnummer and
ownercountry = old.ownercountry and
toarea = old.fromarea and
tocountry = old.fromcountry and
fromarea = old.toarea and
fromcountry = old.tocountry )then
delete from roads where ownerpersonnummer = old.ownerpersonnummer and
ownercountry = old.ownercountry and
toarea = old.fromarea and
tocountry = old.fromcountry and
fromarea = old.toarea and
fromcountry = old.tocountry;
end if;
return new;
end

$$;


--
-- Name: getcityhotelowners(text, text); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE FUNCTION getcityhotelowners(countryname text, cityname text) RETURNS TABLE(country text, personnummer text)
    LANGUAGE plpgsql
    AS $$
BEGIN
RETURN QUERY (
          SELECT ownercountry AS country, ownerpersonnummer AS personnummer
          FROM hotels
          WHERE cityName = locationname AND countryName = locationcountry
        );
END
$$;

--
-- Name: insertroad(); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE or replace FUNCTION insertroad() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
if
new.ownerpersonnummer = '' and new.ownercountry = '' then 
return new; 
elsif
-- check if person already has this road
    exists
    (select *
    from roads
    where
(ownerpersonnummer = new.ownerpersonnummer and
ownercountry = new.ownercountry and
toarea = new.toarea and
tocountry = new.tocountry and
fromarea = new.fromarea and
fromcountry = new.fromcountry)
or
(ownerpersonnummer = new.ownerpersonnummer and
ownercountry = new.ownercountry and
toarea = new.fromarea and
tocountry = new.fromcountry and
fromarea = new.toarea and
fromcountry = new.tocountry))
then
    raise exception 'This person already owns a road here!';

elsif
-- check that the person is at the start or end of this road
    not exists
    (select *
    from persons
    where

personnummer = new.ownerpersonnummer and country = new.ownercountry 
and ((locationcountry = new.fromcountry and locationarea = new.fromarea) or
(locationarea = new.toarea and locationcountry = new.tocountry)) )
then
    raise exception 'This person is not at the right place to make this road!';

elsif
    (select budget
    from persons
    where personnummer = new.ownerpersonnummer and country = new.ownercountry )
    < getval('roadprice')::numeric
then raise exception 'Not enought money to build road';
else
    update persons set budget = budget - getval('roadprice')
    where personnummer = new.ownerpersonnummer and country = new.ownercountry;
    return new;
end if;

end
$$;

--
-- Name: makehotel(); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE FUNCTION makehotel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  personBudget NUMERIC;
BEGIN
  personBudget :=
    (SELECT budget FROM persons WHERE personnummer = new.ownerpersonnummer AND country = new.ownercountry)
     - getVal('hotelprice')::NUMERIC;
  if (personBudget < 0) THEN
      RAISE EXCEPTION 'Unable to afford hotel';
  ELSE
    UPDATE persons
    SET budget = personBudget
    WHERE personnummer = new.ownerpersonnummer AND country = new.ownercountry;

    RETURN new;
  END if;

END
$$;

--
-- Name: splithotelvisit(text, text); Type: FUNCTION; Schema: public; Owner: tda357_034
--
CREATE or replace FUNCTION splithotelvisit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  split NUMERIC;
BEGIN
if(old.locationarea = new.locationarea AND old.locationcountry = new.locationcountry) THEN
        RETURN new;
elsif ( (SELECT count(*) FROM getCityHotelOwners(new.locationcountry, new.locationarea))  =0 ) then
return new;
else
        split = getVal('cityvisit') / (SELECT count(*) FROM getCityHotelOwners(new.locationcountry, new.locationarea));
        UPDATE persons p
        SET budget = p.budget + split
        WHERE ( EXISTS
              (SELECT country, personnummer from getCityHotelOwners(new.locationcountry, new.locationarea) X
               WHERE p.personnummer = X.personnummer AND p.country = X.country));
    return new;
end if; 
END
$$;



--
-- Name: updatehotel(); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE FUNCTION updatehotel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  if(new.name <> old.name OR new.locationcountry <> old.locationcountry OR new.locationname <> old.locationname) THEN
    RAISE EXCEPTION 'Hotels cannot be moved';
  ELSE
    if (EXISTS (SELECT * FROM hotels WHERE ownerpersonnummer = new.ownerpersonnummer AND ownercountry = new.ownercountry
                 AND locationcountry = old.locationcountry AND locationname = old.locationname)) THEN
        RAISE EXCEPTION 'You can only own one hotel per city';
    ELSE
        RETURN new;
    END if;
  END if;
END
$$;

--
-- Name: updatepersons(); Type: FUNCTION; Schema: public; Owner: tda357_034

create or replace function updatepersons() returns trigger as $$
declare 
    travelCost numeric; 
    minTravelCost numeric;
    hotelGain numeric;
    ownerNbr TEXT;
    ownerCntry TEXT;

begin

    if(old.locationarea = new.locationarea AND old.locationcountry = new.locationcountry) THEN
        RETURN new;
    elsif(old.personnummer = '' and old.country = '') then
        return new; 
    else
        if(NOT EXISTS(
            SELECT *
            FROM nextmoves
            WHERE (personcountry = old.country AND personnummer = old.personnummer
                    AND destcountry = new.locationcountry AND destarea =  new.locationarea)
            )
        ) THEN
            RAISE EXCEPTION 'There is no such road';
        else  
            travelCost := (select min(cost) from nextmoves where (personcountry = old.country AND personnummer = old.personnummer AND destcountry = new.locationcountry AND destarea =  new.locationarea));
            minTravelCost := travelCost;
            if (old.budget<minTravelCost) then 
                raise exception 'Unable to afford move';     
            end if;
            --collect visitbonus if its a city
            if (exists(select * from cities where country = new.locationcountry and name = new.locationarea)) then 
                travelCost := travelCost - (SELECT visitBonus FROM cities WHERE country = new.locationcountry AND name = new.locationarea);
            end if; 
            --pay to stay if there are hotels in the city    
            if(EXISTS (SELECT * FROM getCityHotelOwners(new.locationcountry ,new.locationarea))) THEN
                travelcost := travelCost + getVal('cityvisit');       
            end if; 
            --maybe some extra cash flow from owning a hotel in the city
            if (EXISTS (SELECT * FROM hotels where ownercountry = old.country and ownerpersonnummer = old.personnummer and locationcountry = new.locationcountry and locationname = new.locationarea)) then 
                hotelGain := getVal('cityvisit') / (SELECT count(*) FROM getCityHotelOwners(new.locationcountry, new.locationarea));
            else 
                hotelGain := 0;
            end if;         
            if(travelcost > old.budget+hotelGain) then     
                raise exception 'Unable to afford to stay in this city';
            end if; 


        end if; 
                -- Set visitBonus to 0 in the visited city
        UPDATE cities
        SET visitBonus = 0
        WHERE country = new.locationcountry AND name = new.locationarea;

       
                -- Split the 'money' among all the people owning hotels in the cityVisit

       

        ownerNbr := (SELECT ownerpersonnummer FROM
	    (select * from roads
	    union 
	    select tocountry as fromcountry, toarea as fromarea, fromcountry as tocountry, fromarea as toarea, ownercountry,    ownerpersonnummer, roadtax 
	    from roads) as road
        WHERE fromcountry = old.locationcountry AND fromarea = old.locationarea AND tocountry = new.locationcountry AND toarea = new.locationarea AND minTravelCost = roadtax
        LIMIT 1 );

        ownerCntry :=(SELECT ownercountry FROM
	    (select * from roads
	    union 
	    select tocountry as fromcountry, toarea as fromarea, fromcountry as tocountry, fromarea as toarea, ownercountry,    ownerpersonnummer, roadtax 
	    from roads) as road
        WHERE fromcountry = old.locationcountry AND fromarea = old.locationarea AND tocountry = new.locationcountry AND toarea = new.locationarea AND minTravelCost = roadtax
        LIMIT 1 );

        UPDATE persons p
        SET budget = p.budget + minTravelCost::numeric
        WHERE (p.personnummer, p.country) = (ownerNbr, ownerCntry);

        new.budget := old.budget - travelCost; 
       -- RAISE EXCEPTION 'old.budget = (%)', new;
        return new;    

    end if;
end
$$ LANGUAGE plpgsql;
                                



--
-- Name: updateroad(); Type: FUNCTION; Schema: public; Owner: tda357_034
--

CREATE FUNCTION updateroad() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  if (old.fromcountry <> new.fromcountry OR old.fromarea <> new.fromarea OR old.tocountry <> new.tocountry
        OR old.toarea <> new.toarea OR old.ownercountry <> new.ownercountry OR old.ownerpersonnummer <> new.ownerpersonnummer) THEN
        RAISE EXCEPTION 'Only roadtax can be changed for a road';
  ELSE
        return new;
  END if;
END
$$;

--SET default_tablespace = tda357;

SET default_with_oids = false;

--
-- Name: areas; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE areas (
    country text NOT NULL,
    name text NOT NULL,
    population integer NOT NULL,
    CONSTRAINT areas_population_check CHECK ((population >= 0))
);


--
-- Name: hotels; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE hotels (
    name text NOT NULL,
    locationcountry text NOT NULL,
    locationname text NOT NULL,
    ownercountry text NOT NULL,
    ownerpersonnummer text NOT NULL
);


--
-- Name: persons; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE persons (
    country text NOT NULL,
    personnummer text NOT NULL,
    name text NOT NULL,
    locationcountry text NOT NULL,
    locationarea text NOT NULL,
    budget numeric NOT NULL,
    CONSTRAINT persons_budget_check1 CHECK ((budget >= (0)::numeric)),
    CONSTRAINT persons_government CHECK ((country <> ''::text) OR ((country = ''::text) AND ((name ~* 'The world government'::text) OR (name ~* 'The government'::text)))),
    CONSTRAINT persons_personnummer_check CHECK (((personnummer ~ '^\d{8}-\d{4}$'::text) OR (((personnummer ~ ''::text) AND (country ~ ''::text)) AND ((name ~* 'The world government'::text) OR (name ~* 'The government'::text)))))
);


--
-- Name: roads; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE roads (
    fromcountry text NOT NULL,
    fromarea text NOT NULL,
    tocountry text NOT NULL,
    toarea text NOT NULL,
    ownercountry text NOT NULL,
    ownerpersonnummer character(13) NOT NULL,
    roadtax numeric NOT NULL,
    CONSTRAINT roads_roadtax_check CHECK ((roadtax >= (0)::numeric)),
    CONSTRAINT roads_toisnotfrom_check CHECK (((toarea <> fromarea) OR (tocountry <> fromcountry)))
);


--
-- Name: assetsummary; Type: VIEW; Schema: public; Owner: tda357_034
--

CREATE VIEW assetsummary AS
SELECT a.country, a.personnummer, a.budget, (((COALESCE(hoteltable.nbrhotels, (0)::numeric))::numeric * getval('hotelprice'::text)::numeric) + ((COALESCE(roadtable.nbrroads, (0)::numeric))::numeric * getval('roadprice'::text)::numeric)) AS assets, ((COALESCE(hoteltable.nbrhotels, (0)::numeric))::numeric * getval('hotelrefund'::text)::numeric * getVal('hotelprice'::text)::numeric) AS reclaimable FROM ((persons a LEFT JOIN (SELECT hotels.ownerpersonnummer, count(*) AS nbrhotels, 0 AS nbrroads FROM hotels GROUP BY hotels.ownerpersonnummer) hoteltable ON ((hoteltable.ownerpersonnummer = a.personnummer))) JOIN (persons b LEFT JOIN (SELECT roads.ownerpersonnummer, 0 AS nbrhotels, count(*) AS nbrroads FROM roads GROUP BY roads.ownerpersonnummer) roadtable ON (((roadtable.ownerpersonnummer)::text = b.personnummer))) ON ((a.personnummer = b.personnummer))) WHERE a.personnummer <> '' AND a.country <> '';


--
-- Name: cities; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE cities (
    country text NOT NULL,
    name text NOT NULL,
    visitbonus numeric NOT NULL,
    CONSTRAINT cities_visitbonus_check CHECK ((visitbonus >= 0))
);


--
-- Name: countries; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE countries (
    name text NOT NULL
);


--
-- Name: nextmoves; Type: VIEW; Schema: public; Owner: tda357_034
--

CREATE or replace VIEW nextmoves AS
SELECT persons.country AS personcountry, persons.personnummer, persons.locationcountry AS country, persons.locationarea AS area, road.tocountry AS destcountry, road.toarea AS destarea, 
CASE WHEN (((road.ownerpersonnummer)::text = persons.personnummer) 
AND 
(road.ownercountry = persons.country)) 
THEN (0)::numeric 
ELSE road.roadtax 
END 
AS cost 
FROM (persons 
JOIN 
(SELECT roads.fromcountry, roads.fromarea, roads.tocountry, roads.toarea, roads.ownercountry, roads.ownerpersonnummer, roads.roadtax FROM roads 
UNION 
SELECT roads.tocountry AS fromcountry, roads.toarea AS fromarea, roads.fromcountry AS tocountry, roads.fromarea AS toarea, roads.ownercountry, roads.ownerpersonnummer, roads.roadtax 
FROM roads) road 
ON (((road.fromcountry = persons.locationcountry) AND (road.fromarea = persons.locationarea)))) 
WHERE personnummer <> '' AND country <> '' 
ORDER BY persons.personnummer;



--
-- Name: towns; Type: TABLE; Schema: public; Owner: tda357_034; Tablespace: tda357
--

CREATE TABLE towns (
    country text NOT NULL,
    name text NOT NULL
);


--
-- Data for Name: areas; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY areas (country, name, population) FROM stdin;
--\.


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY cities (country, name, visitbonus) FROM stdin;
--\.


--
-- Data for Name: constants; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY constants (name, value) FROM stdin;
--roadprice	456.9
--hotelprice	789.2
--roadtax	13.5
--hotelrefund	0.50
--cityvisit	102030.3
--\.S


--
-- Data for Name: countries; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY countries (name) FROM stdin;
--\.


--
-- Data for Name: hotels; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY hotels (name, locationcountry, locationname, ownercountry, ownerpersonnummer) FROM stdin;
--\.


--
-- Data for Name: persons; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY persons (country, personnummer, name, locationcountry, locationarea, budget) FROM stdin;
--\.


--
-- Data for Name: roads; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY roads (fromcountry, fromarea, tocountry, toarea, ownercountry, ownerpersonnummer, roadtax) FROM stdin;
--\.


--
-- Data for Name: towns; Type: TABLE DATA; Schema: public; Owner: tda357_034
--

--COPY towns (country, name) FROM stdin;
--\.


--
-- Name: areas_pkey; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY areas
    ADD CONSTRAINT areas_pkey PRIMARY KEY (country, name);


--
-- Name: cities_pkey; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (country, name);


--
-- Name: countries_pkey; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (name);


--
-- Name: hotels_pkey; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY hotels
    ADD CONSTRAINT hotels_pkey PRIMARY KEY (locationcountry, locationname, ownercountry, ownerpersonnummer);


--
-- Name: persons_pkey1; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY persons
    ADD CONSTRAINT persons_pkey1 PRIMARY KEY (country, personnummer);


--
-- Name: roads_pkey; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY roads
    ADD CONSTRAINT roads_pkey PRIMARY KEY (fromcountry, fromarea, tocountry, toarea, ownercountry, ownerpersonnummer);


--
-- Name: towns_pkey; Type: CONSTRAINT; Schema: public; Owner: tda357_034; Tablespace: tda357
--

ALTER TABLE ONLY towns
    ADD CONSTRAINT towns_pkey PRIMARY KEY (country, name);


--
-- Name: deletehotel; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER deletehotel AFTER DELETE ON hotels FOR EACH ROW EXECUTE PROCEDURE deletehotels();


--
-- Name: deleteroad; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER deleteroad AFTER DELETE ON roads FOR EACH ROW EXECUTE PROCEDURE deleteroad();


--
-- Name: inserroad; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER inserroad BEFORE INSERT ON roads FOR EACH ROW EXECUTE PROCEDURE insertroad();


--
-- Name: inserthotel; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER inserthotel BEFORE INSERT ON hotels FOR EACH ROW EXECUTE PROCEDURE makehotel();


--
-- Name: updatehotel; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER updatehotel BEFORE UPDATE ON hotels FOR EACH ROW EXECUTE PROCEDURE updatehotel();


--
-- Name: updatepersons; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER updatepersons BEFORE UPDATE ON persons FOR EACH ROW EXECUTE PROCEDURE updatepersons();

-- trigger after update person to split the hotel money between owners

create trigger splithotelvisit after update on persons for each row execute procedure splithotelvisit();


--
-- Name: updateroad; Type: TRIGGER; Schema: public; Owner: tda357_034
--

CREATE TRIGGER updateroad BEFORE UPDATE ON roads FOR EACH ROW EXECUTE PROCEDURE updateroad();


--
-- Name: areas_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY areas
    ADD CONSTRAINT areas_country_fkey FOREIGN KEY (country) REFERENCES countries(name);


--
-- Name: cities_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY cities
    ADD CONSTRAINT cities_country_fkey FOREIGN KEY (country, name) REFERENCES areas(country, name);


--
-- Name: hotels_locationcountry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY hotels
    ADD CONSTRAINT hotels_locationcountry_fkey FOREIGN KEY (locationcountry, locationname) REFERENCES cities(country, name);


--
-- Name: hotels_ownercountry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY hotels
    ADD CONSTRAINT hotels_ownercountry_fkey FOREIGN KEY (ownercountry, ownerpersonnummer) REFERENCES persons(country, personnummer);


--
-- Name: persons_country_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY persons
    ADD CONSTRAINT persons_country_fkey1 FOREIGN KEY (country) REFERENCES countries(name);


--
-- Name: persons_locationcountry_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY persons
    ADD CONSTRAINT persons_locationcountry_fkey1 FOREIGN KEY (locationcountry, locationarea) REFERENCES areas(country, name);


--
-- Name: roads_fromcountry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY roads
    ADD CONSTRAINT roads_fromcountry_fkey FOREIGN KEY (fromcountry, fromarea) REFERENCES areas(country, name);


--
-- Name: roads_ownercountry_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY roads
    ADD CONSTRAINT roads_ownercountry_fkey1 FOREIGN KEY (ownercountry, ownerpersonnummer) REFERENCES persons(country, personnummer);


--
-- Name: roads_tocountry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY roads
    ADD CONSTRAINT roads_tocountry_fkey FOREIGN KEY (tocountry, toarea) REFERENCES areas(country, name);


--
-- Name: towns_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: tda357_034
--

ALTER TABLE ONLY towns
    ADD CONSTRAINT towns_country_fkey FOREIGN KEY (country, name) REFERENCES areas(country, name);

--INSERT  INTO  Countries  VALUES('');
--INSERT  INTO  Countries  VALUES('Sweden ');
--INSERT  INTO  Areas  VALUES('Sweden ', 'Gothenburg ', 491630);
--INSERT  INTO  Persons  VALUES('', '', 'The government ', 'Sweden ', '
--Gothenburg ', 100000000000);
--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--
