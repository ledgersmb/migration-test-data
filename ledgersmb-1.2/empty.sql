--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.3
-- Dumped by pg_dump version 9.5.3

-- Started on 2017-06-28 18:06:36 EDT

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 1 (class 3079 OID 13310)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 3680 (class 0 OID 0)
-- Dependencies: 1
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- TOC entry 265 (class 1255 OID 43118)
-- Name: add_custom_field(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION add_custom_field(character varying, character varying, character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
table_name ALIAS FOR $1;
new_field_name ALIAS FOR $2;
field_datatype ALIAS FOR $3;

BEGIN
	perform TABLE_ID FROM custom_table_catalog 
		WHERE extends = table_name;
	IF NOT FOUND THEN
		BEGIN
			INSERT INTO custom_table_catalog (extends) 
				VALUES (table_name);
			EXECUTE 'CREATE TABLE ' || 
                               quote_ident('custom_' ||table_name) ||
				' (row_id INT PRIMARY KEY)';
		EXCEPTION WHEN duplicate_table THEN
			-- do nothing
		END;
	END IF;
	INSERT INTO custom_field_catalog (field_name, table_id)
	values (new_field_name, (SELECT table_id 
                                        FROM custom_table_catalog
		WHERE extends = table_name));
	EXECUTE 'ALTER TABLE '|| quote_ident('custom_'||table_name) || 
                ' ADD COLUMN ' || quote_ident(new_field_name) || ' ' || 
                  quote_ident(field_datatype);
	RETURN TRUE;
END;
$_$;


ALTER FUNCTION public.add_custom_field(character varying, character varying, character varying) OWNER TO dbadmin;

--
-- TOC entry 262 (class 1255 OID 43114)
-- Name: avgcost(integer); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION avgcost(integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$

DECLARE

v_cost numeric;
v_qty numeric;
v_parts_id alias for $1;

BEGIN

  SELECT INTO v_cost, v_qty SUM(i.sellprice * i.qty), SUM(i.qty)
  FROM invoice i
  JOIN ap a ON (a.id = i.trans_id)
  WHERE i.parts_id = v_parts_id;
  
  IF v_cost IS NULL THEN
    v_cost := 0;
  END IF;

  IF NOT v_qty IS NULL THEN
    IF v_qty = 0 THEN
      v_cost := 0;
    ELSE
      v_cost := v_cost/v_qty;
    END IF;
  END IF;

RETURN v_cost;
END;
$_$;


ALTER FUNCTION public.avgcost(integer) OWNER TO dbadmin;

--
-- TOC entry 260 (class 1255 OID 43105)
-- Name: check_department(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION check_department() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

declare
  dpt_id int;

begin
 
  if new.department_id = 0 then
    delete from dpt_trans where trans_id = new.id;
    return NULL;
  end if;

  select into dpt_id trans_id from dpt_trans where trans_id = new.id;
  
  if dpt_id > 0 then
    update dpt_trans set department_id = new.department_id where trans_id = dpt_id;
  else
    insert into dpt_trans (trans_id, department_id) values (new.id, new.department_id);
  end if;
return NULL;

end;
$$;


ALTER FUNCTION public.check_department() OWNER TO dbadmin;

--
-- TOC entry 259 (class 1255 OID 43103)
-- Name: check_inventory(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION check_inventory() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

declare
  itemid int;
  row_data inventory%rowtype;

begin

  if not old.quotation then
    for row_data in select * from inventory where trans_id = old.id loop
      select into itemid id from orderitems where trans_id = old.id and id = row_data.orderitems_id;

      if itemid is null then
	delete from inventory where trans_id = old.id and orderitems_id = row_data.orderitems_id;
      end if;
    end loop;
  end if;
return old;
end;
$$;


ALTER FUNCTION public.check_inventory() OWNER TO dbadmin;

--
-- TOC entry 244 (class 1255 OID 43095)
-- Name: del_customer(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION del_customer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  delete from shipto where trans_id = old.id;
  delete from customertax where customer_id = old.id;
  delete from partscustomer where customer_id = old.id;
  return NULL;
end;
$$;


ALTER FUNCTION public.del_customer() OWNER TO dbadmin;

--
-- TOC entry 243 (class 1255 OID 43090)
-- Name: del_department(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION del_department() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  delete from dpt_trans where trans_id = old.id;
  return NULL;
end;
$$;


ALTER FUNCTION public.del_department() OWNER TO dbadmin;

--
-- TOC entry 258 (class 1255 OID 43099)
-- Name: del_exchangerate(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION del_exchangerate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

declare
  t_transdate date;
  t_curr char(3);
  t_id int;
  d_curr text;

begin

  select into d_curr substr(value,1,3) from defaults where setting_key = 'curr';
  
  if TG_RELNAME = 'ar' then
    select into t_curr, t_transdate curr, transdate from ar where id = old.id;
  end if;
  if TG_RELNAME = 'ap' then
    select into t_curr, t_transdate curr, transdate from ap where id = old.id;
  end if;
  if TG_RELNAME = 'oe' then
    select into t_curr, t_transdate curr, transdate from oe where id = old.id;
  end if;

  if d_curr != t_curr then

    select into t_id a.id from acc_trans ac
    join ar a on (a.id = ac.trans_id)
    where a.curr = t_curr
    and ac.transdate = t_transdate

    except select a.id from ar a where a.id = old.id
    
    union
    
    select a.id from acc_trans ac
    join ap a on (a.id = ac.trans_id)
    where a.curr = t_curr
    and ac.transdate = t_transdate
    
    except select a.id from ap a where a.id = old.id
    
    union
    
    select o.id from oe o
    where o.curr = t_curr
    and o.transdate = t_transdate
    
    except select o.id from oe o where o.id = old.id;

    if not found then
      delete from exchangerate where curr = t_curr and transdate = t_transdate;
    end if;
  end if;
return old;

end;
$$;


ALTER FUNCTION public.del_exchangerate() OWNER TO dbadmin;

--
-- TOC entry 261 (class 1255 OID 43110)
-- Name: del_recurring(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION del_recurring() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM recurring WHERE id = old.id;
  DELETE FROM recurringemail WHERE id = old.id;
  DELETE FROM recurringprint WHERE id = old.id;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.del_recurring() OWNER TO dbadmin;

--
-- TOC entry 245 (class 1255 OID 43097)
-- Name: del_vendor(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION del_vendor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  delete from shipto where trans_id = old.id;
  delete from vendortax where vendor_id = old.id;
  delete from partsvendor where vendor_id = old.id;
  return NULL;
end;
$$;


ALTER FUNCTION public.del_vendor() OWNER TO dbadmin;

--
-- TOC entry 242 (class 1255 OID 43088)
-- Name: del_yearend(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION del_yearend() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  delete from yearend where trans_id = old.id;
  return NULL;
end;
$$;


ALTER FUNCTION public.del_yearend() OWNER TO dbadmin;

--
-- TOC entry 266 (class 1255 OID 43119)
-- Name: drop_custom_field(character varying, character varying); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION drop_custom_field(character varying, character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
table_name ALIAS FOR $1;
custom_field_name ALIAS FOR $2;
BEGIN
	DELETE FROM custom_field_catalog 
	WHERE field_name = custom_field_name AND 
		table_id = (SELECT table_id FROM custom_table_catalog 
			WHERE extends = table_name);
	EXECUTE 'ALTER TABLE ' || quote_ident('custom_' || table_name) || 
		' DROP COLUMN ' || quote_ident(custom_field_name);
	RETURN TRUE;	
END;
$_$;


ALTER FUNCTION public.drop_custom_field(character varying, character varying) OWNER TO dbadmin;

--
-- TOC entry 263 (class 1255 OID 43115)
-- Name: lastcost(integer); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION lastcost(integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$

DECLARE

v_cost numeric;
v_parts_id alias for $1;

BEGIN

  SELECT INTO v_cost sellprice FROM invoice i
  JOIN ap a ON (a.id = i.trans_id)
  WHERE i.parts_id = v_parts_id
  ORDER BY a.transdate desc, a.id desc
  LIMIT 1;

  IF v_cost IS NULL THEN
    v_cost := 0;
  END IF;

RETURN v_cost;
END;
$_$;


ALTER FUNCTION public.lastcost(integer) OWNER TO dbadmin;

--
-- TOC entry 264 (class 1255 OID 43116)
-- Name: trigger_parts_short(); Type: FUNCTION; Schema: public; Owner: dbadmin
--

CREATE FUNCTION trigger_parts_short() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.onhand >= NEW.rop THEN
    NOTIFY parts_short;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.trigger_parts_short() OWNER TO dbadmin;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 192 (class 1259 OID 42545)
-- Name: acc_trans; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE acc_trans (
    trans_id integer,
    chart_id integer NOT NULL,
    amount numeric,
    transdate date DEFAULT ('now'::text)::date,
    source text,
    cleared boolean DEFAULT false,
    fx_transaction boolean DEFAULT false,
    project_id integer,
    memo text,
    invoice_id integer,
    entry_id integer NOT NULL
);


ALTER TABLE acc_trans OWNER TO dbadmin;

--
-- TOC entry 191 (class 1259 OID 42543)
-- Name: acc_trans_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE acc_trans_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE acc_trans_entry_id_seq OWNER TO dbadmin;

--
-- TOC entry 3681 (class 0 OID 0)
-- Dependencies: 191
-- Name: acc_trans_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE acc_trans_entry_id_seq OWNED BY acc_trans.entry_id;


--
-- TOC entry 181 (class 1259 OID 42481)
-- Name: id; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE id
    START WITH 10000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE id OWNER TO dbadmin;

--
-- TOC entry 198 (class 1259 OID 42621)
-- Name: ap; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE ap (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    invnumber text,
    transdate date DEFAULT ('now'::text)::date,
    vendor_id integer,
    taxincluded boolean DEFAULT false,
    amount numeric,
    netamount numeric,
    paid numeric,
    datepaid date,
    duedate date,
    invoice boolean DEFAULT false,
    ordnumber text,
    curr character(3),
    notes text,
    employee_id integer,
    till character varying(20),
    quonumber text,
    intnotes text,
    department_id integer DEFAULT 0,
    shipvia text,
    language_code character varying(6),
    ponumber text,
    shippingpoint text,
    terms smallint DEFAULT 0
);


ALTER TABLE ap OWNER TO dbadmin;

--
-- TOC entry 197 (class 1259 OID 42608)
-- Name: ar; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE ar (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    invnumber text,
    transdate date DEFAULT ('now'::text)::date,
    customer_id integer,
    taxincluded boolean,
    amount numeric,
    netamount numeric,
    paid numeric,
    datepaid date,
    duedate date,
    invoice boolean DEFAULT false,
    shippingpoint text,
    terms smallint DEFAULT 0,
    notes text,
    curr character(3),
    ordnumber text,
    employee_id integer,
    till character varying(20),
    quonumber text,
    intnotes text,
    department_id integer DEFAULT 0,
    shipvia text,
    language_code character varying(6),
    ponumber text
);


ALTER TABLE ar OWNER TO dbadmin;

--
-- TOC entry 196 (class 1259 OID 42600)
-- Name: assembly; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE assembly (
    id integer NOT NULL,
    parts_id integer NOT NULL,
    qty numeric,
    bom boolean,
    adj boolean
);


ALTER TABLE assembly OWNER TO dbadmin;

--
-- TOC entry 232 (class 1259 OID 42905)
-- Name: audittrail; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE audittrail (
    trans_id integer,
    tablename text,
    reference text,
    formname text,
    action text,
    transdate timestamp without time zone DEFAULT now(),
    employee_id integer,
    entry_id bigint NOT NULL
);


ALTER TABLE audittrail OWNER TO dbadmin;

--
-- TOC entry 231 (class 1259 OID 42903)
-- Name: audittrail_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE audittrail_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE audittrail_entry_id_seq OWNER TO dbadmin;

--
-- TOC entry 3682 (class 0 OID 0)
-- Dependencies: 231
-- Name: audittrail_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE audittrail_entry_id_seq OWNED BY audittrail.entry_id;


--
-- TOC entry 219 (class 1259 OID 42822)
-- Name: business; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE business (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    description text,
    discount numeric
);


ALTER TABLE business OWNER TO dbadmin;

--
-- TOC entry 188 (class 1259 OID 42516)
-- Name: chart; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE chart (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    accno text NOT NULL,
    description text,
    charttype character(1) DEFAULT 'A'::bpchar,
    category character(1),
    link text,
    gifi_accno text,
    contra boolean DEFAULT false
);


ALTER TABLE chart OWNER TO dbadmin;

--
-- TOC entry 241 (class 1259 OID 43000)
-- Name: custom_field_catalog; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE custom_field_catalog (
    field_id integer NOT NULL,
    table_id integer,
    field_name text
);


ALTER TABLE custom_field_catalog OWNER TO dbadmin;

--
-- TOC entry 240 (class 1259 OID 42998)
-- Name: custom_field_catalog_field_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE custom_field_catalog_field_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE custom_field_catalog_field_id_seq OWNER TO dbadmin;

--
-- TOC entry 3683 (class 0 OID 0)
-- Dependencies: 240
-- Name: custom_field_catalog_field_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE custom_field_catalog_field_id_seq OWNED BY custom_field_catalog.field_id;


--
-- TOC entry 239 (class 1259 OID 42989)
-- Name: custom_table_catalog; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE custom_table_catalog (
    table_id integer NOT NULL,
    extends text,
    table_name text
);


ALTER TABLE custom_table_catalog OWNER TO dbadmin;

--
-- TOC entry 238 (class 1259 OID 42987)
-- Name: custom_table_catalog_table_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE custom_table_catalog_table_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE custom_table_catalog_table_id_seq OWNER TO dbadmin;

--
-- TOC entry 3684 (class 0 OID 0)
-- Dependencies: 238
-- Name: custom_table_catalog_table_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE custom_table_catalog_table_id_seq OWNED BY custom_table_catalog.table_id;


--
-- TOC entry 194 (class 1259 OID 42572)
-- Name: customer; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE customer (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    name character varying(64),
    address1 character varying(32),
    address2 character varying(32),
    city character varying(32),
    state character varying(32),
    zipcode character varying(10),
    country character varying(32),
    contact character varying(64),
    phone character varying(20),
    fax character varying(20),
    email text,
    notes text,
    discount numeric,
    taxincluded boolean DEFAULT false,
    creditlimit numeric DEFAULT 0,
    terms smallint DEFAULT 0,
    customernumber character varying(32),
    cc text,
    bcc text,
    business_id integer,
    taxnumber character varying(32),
    sic_code character varying(6),
    iban character varying(34),
    bic character varying(11),
    employee_id integer,
    language_code character varying(6),
    pricegroup_id integer,
    curr character(3),
    startdate date,
    enddate date
);


ALTER TABLE customer OWNER TO dbadmin;

--
-- TOC entry 205 (class 1259 OID 42702)
-- Name: customertax; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE customertax (
    customer_id integer NOT NULL,
    chart_id integer NOT NULL
);


ALTER TABLE customertax OWNER TO dbadmin;

--
-- TOC entry 190 (class 1259 OID 42535)
-- Name: defaults; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE defaults (
    setting_key text NOT NULL,
    value text
);


ALTER TABLE defaults OWNER TO dbadmin;

--
-- TOC entry 217 (class 1259 OID 42807)
-- Name: department; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE department (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    description text,
    role character(1) DEFAULT 'P'::bpchar
);


ALTER TABLE department OWNER TO dbadmin;

--
-- TOC entry 218 (class 1259 OID 42817)
-- Name: dpt_trans; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE dpt_trans (
    trans_id integer NOT NULL,
    department_id integer
);


ALTER TABLE dpt_trans OWNER TO dbadmin;

--
-- TOC entry 210 (class 1259 OID 42743)
-- Name: employee; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE employee (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    login text,
    name character varying(64),
    address1 character varying(32),
    address2 character varying(32),
    city character varying(32),
    state character varying(32),
    zipcode character varying(10),
    country character varying(32),
    workphone character varying(20),
    homephone character varying(20),
    startdate date DEFAULT ('now'::text)::date,
    enddate date,
    notes text,
    role character varying(20),
    sales boolean DEFAULT false,
    email text,
    ssn character varying(20),
    iban character varying(34),
    bic character varying(11),
    managerid integer,
    employeenumber character varying(32),
    dob date
);


ALTER TABLE employee OWNER TO dbadmin;

--
-- TOC entry 209 (class 1259 OID 42735)
-- Name: exchangerate; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE exchangerate (
    curr character(3) NOT NULL,
    transdate date NOT NULL,
    buy numeric,
    sell numeric
);


ALTER TABLE exchangerate OWNER TO dbadmin;

--
-- TOC entry 189 (class 1259 OID 42527)
-- Name: gifi; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE gifi (
    accno text NOT NULL,
    description text
);


ALTER TABLE gifi OWNER TO dbadmin;

--
-- TOC entry 187 (class 1259 OID 42505)
-- Name: gl; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE gl (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    reference text,
    description text,
    transdate date DEFAULT ('now'::text)::date,
    employee_id integer,
    notes text,
    department_id integer DEFAULT 0
);


ALTER TABLE gl OWNER TO dbadmin;

--
-- TOC entry 223 (class 1259 OID 42850)
-- Name: inventory; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE inventory (
    warehouse_id integer,
    parts_id integer,
    trans_id integer,
    orderitems_id integer,
    qty numeric,
    shippingdate date,
    employee_id integer,
    entry_id integer NOT NULL
);


ALTER TABLE inventory OWNER TO dbadmin;

--
-- TOC entry 222 (class 1259 OID 42848)
-- Name: inventory_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE inventory_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE inventory_entry_id_seq OWNER TO dbadmin;

--
-- TOC entry 3685 (class 0 OID 0)
-- Dependencies: 222
-- Name: inventory_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE inventory_entry_id_seq OWNED BY inventory.entry_id;


--
-- TOC entry 182 (class 1259 OID 42483)
-- Name: invoiceid; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE invoiceid
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE invoiceid OWNER TO dbadmin;

--
-- TOC entry 193 (class 1259 OID 42562)
-- Name: invoice; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE invoice (
    id integer DEFAULT nextval('invoiceid'::regclass) NOT NULL,
    trans_id integer,
    parts_id integer,
    description text,
    qty numeric,
    allocated numeric,
    sellprice numeric,
    fxsellprice numeric,
    discount real,
    assemblyitem boolean DEFAULT false,
    unit character varying(5),
    project_id integer,
    deliverydate date,
    serialnumber text,
    notes text
);


ALTER TABLE invoice OWNER TO dbadmin;

--
-- TOC entry 184 (class 1259 OID 42487)
-- Name: jcitemsid; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE jcitemsid
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE jcitemsid OWNER TO dbadmin;

--
-- TOC entry 237 (class 1259 OID 42948)
-- Name: jcitems; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE jcitems (
    id integer DEFAULT nextval('jcitemsid'::regclass) NOT NULL,
    project_id integer,
    parts_id integer,
    description text,
    qty numeric,
    allocated numeric,
    sellprice numeric,
    fxsellprice numeric,
    serialnumber text,
    checkedin timestamp with time zone,
    checkedout timestamp with time zone,
    employee_id integer,
    notes text
);


ALTER TABLE jcitems OWNER TO dbadmin;

--
-- TOC entry 230 (class 1259 OID 42895)
-- Name: language; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE language (
    code character varying(6) NOT NULL,
    description text
);


ALTER TABLE language OWNER TO dbadmin;

--
-- TOC entry 186 (class 1259 OID 42497)
-- Name: makemodel; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE makemodel (
    parts_id integer NOT NULL,
    make text,
    model text
);


ALTER TABLE makemodel OWNER TO dbadmin;

--
-- TOC entry 207 (class 1259 OID 42712)
-- Name: oe; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE oe (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    ordnumber text,
    transdate date DEFAULT ('now'::text)::date,
    vendor_id integer,
    customer_id integer,
    amount numeric,
    netamount numeric,
    reqdate date,
    taxincluded boolean,
    shippingpoint text,
    notes text,
    curr character(3),
    employee_id integer,
    closed boolean DEFAULT false,
    quotation boolean DEFAULT false,
    quonumber text,
    intnotes text,
    department_id integer DEFAULT 0,
    shipvia text,
    language_code character varying(6),
    ponumber text,
    terms smallint DEFAULT 0
);


ALTER TABLE oe OWNER TO dbadmin;

--
-- TOC entry 183 (class 1259 OID 42485)
-- Name: orderitemsid; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE orderitemsid
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE orderitemsid OWNER TO dbadmin;

--
-- TOC entry 208 (class 1259 OID 42726)
-- Name: orderitems; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE orderitems (
    id integer DEFAULT nextval('orderitemsid'::regclass) NOT NULL,
    trans_id integer,
    parts_id integer,
    description text,
    qty numeric,
    sellprice numeric,
    discount numeric,
    unit character varying(5),
    project_id integer,
    reqdate date,
    ship numeric,
    serialnumber text,
    notes text
);


ALTER TABLE orderitems OWNER TO dbadmin;

--
-- TOC entry 195 (class 1259 OID 42584)
-- Name: parts; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE parts (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    partnumber text,
    description text,
    unit character varying(5),
    listprice numeric,
    sellprice numeric,
    lastcost numeric,
    priceupdate date DEFAULT ('now'::text)::date,
    weight numeric,
    onhand numeric DEFAULT 0,
    notes text,
    makemodel boolean DEFAULT false,
    assembly boolean DEFAULT false,
    alternate boolean DEFAULT false,
    rop real,
    inventory_accno_id integer,
    income_accno_id integer,
    expense_accno_id integer,
    bin text,
    obsolete boolean DEFAULT false,
    bom boolean DEFAULT false,
    image text,
    drawing text,
    microfiche text,
    partsgroup_id integer,
    project_id integer,
    avgcost numeric
);


ALTER TABLE parts OWNER TO dbadmin;

--
-- TOC entry 229 (class 1259 OID 42886)
-- Name: partscustomer; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE partscustomer (
    parts_id integer,
    customer_id integer,
    pricegroup_id integer,
    pricebreak numeric,
    sellprice numeric,
    validfrom date,
    validto date,
    curr character(3),
    entry_id integer NOT NULL
);


ALTER TABLE partscustomer OWNER TO dbadmin;

--
-- TOC entry 228 (class 1259 OID 42884)
-- Name: partscustomer_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE partscustomer_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE partscustomer_entry_id_seq OWNER TO dbadmin;

--
-- TOC entry 3686 (class 0 OID 0)
-- Dependencies: 228
-- Name: partscustomer_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE partscustomer_entry_id_seq OWNED BY partscustomer.entry_id;


--
-- TOC entry 215 (class 1259 OID 42788)
-- Name: partsgroup; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE partsgroup (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    partsgroup text
);


ALTER TABLE partsgroup OWNER TO dbadmin;

--
-- TOC entry 203 (class 1259 OID 42662)
-- Name: partstax; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE partstax (
    parts_id integer NOT NULL,
    chart_id integer NOT NULL,
    taxcategory_id integer
);


ALTER TABLE partstax OWNER TO dbadmin;

--
-- TOC entry 226 (class 1259 OID 42866)
-- Name: partsvendor; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE partsvendor (
    vendor_id integer,
    parts_id integer,
    partnumber text,
    leadtime smallint,
    lastcost numeric,
    curr character(3),
    entry_id integer NOT NULL
);


ALTER TABLE partsvendor OWNER TO dbadmin;

--
-- TOC entry 225 (class 1259 OID 42864)
-- Name: partsvendor_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE partsvendor_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE partsvendor_entry_id_seq OWNER TO dbadmin;

--
-- TOC entry 3687 (class 0 OID 0)
-- Dependencies: 225
-- Name: partsvendor_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE partsvendor_entry_id_seq OWNED BY partsvendor.entry_id;


--
-- TOC entry 227 (class 1259 OID 42875)
-- Name: pricegroup; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE pricegroup (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    pricegroup text
);


ALTER TABLE pricegroup OWNER TO dbadmin;

--
-- TOC entry 214 (class 1259 OID 42777)
-- Name: project; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE project (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    projectnumber text,
    description text,
    startdate date,
    enddate date,
    parts_id integer,
    production numeric DEFAULT 0,
    completed numeric DEFAULT 0,
    customer_id integer
);


ALTER TABLE project OWNER TO dbadmin;

--
-- TOC entry 234 (class 1259 OID 42923)
-- Name: recurring; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE recurring (
    id integer NOT NULL,
    reference text,
    startdate date,
    nextdate date,
    enddate date,
    repeat smallint,
    unit character varying(6),
    howmany integer,
    payment boolean DEFAULT false
);


ALTER TABLE recurring OWNER TO dbadmin;

--
-- TOC entry 235 (class 1259 OID 42932)
-- Name: recurringemail; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE recurringemail (
    id integer NOT NULL,
    formname text,
    format text,
    message text
);


ALTER TABLE recurringemail OWNER TO dbadmin;

--
-- TOC entry 236 (class 1259 OID 42940)
-- Name: recurringprint; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE recurringprint (
    id integer NOT NULL,
    formname text,
    format text,
    printer text
);


ALTER TABLE recurringprint OWNER TO dbadmin;

--
-- TOC entry 212 (class 1259 OID 42756)
-- Name: shipto; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE shipto (
    trans_id integer,
    shiptoname character varying(64),
    shiptoaddress1 character varying(32),
    shiptoaddress2 character varying(32),
    shiptocity character varying(32),
    shiptostate character varying(32),
    shiptozipcode character varying(10),
    shiptocountry character varying(32),
    shiptocontact character varying(64),
    shiptophone character varying(20),
    shiptofax character varying(20),
    shiptoemail text,
    entry_id integer NOT NULL
);


ALTER TABLE shipto OWNER TO dbadmin;

--
-- TOC entry 211 (class 1259 OID 42754)
-- Name: shipto_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE shipto_entry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shipto_entry_id_seq OWNER TO dbadmin;

--
-- TOC entry 3688 (class 0 OID 0)
-- Dependencies: 211
-- Name: shipto_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE shipto_entry_id_seq OWNED BY shipto.entry_id;


--
-- TOC entry 220 (class 1259 OID 42831)
-- Name: sic; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE sic (
    code character varying(6) NOT NULL,
    sictype character(1),
    description text
);


ALTER TABLE sic OWNER TO dbadmin;

--
-- TOC entry 216 (class 1259 OID 42797)
-- Name: status; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE status (
    trans_id integer NOT NULL,
    formname text,
    printed boolean DEFAULT false,
    emailed boolean DEFAULT false,
    spoolfile text
);


ALTER TABLE status OWNER TO dbadmin;

--
-- TOC entry 204 (class 1259 OID 42682)
-- Name: tax; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE tax (
    chart_id integer NOT NULL,
    rate numeric,
    taxnumber text,
    validto date,
    pass integer DEFAULT 0 NOT NULL,
    taxmodule_id integer DEFAULT 1 NOT NULL
);


ALTER TABLE tax OWNER TO dbadmin;

--
-- TOC entry 202 (class 1259 OID 42648)
-- Name: taxcategory; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE taxcategory (
    taxcategory_id integer NOT NULL,
    taxcategoryname text NOT NULL,
    taxmodule_id integer NOT NULL
);


ALTER TABLE taxcategory OWNER TO dbadmin;

--
-- TOC entry 201 (class 1259 OID 42646)
-- Name: taxcategory_taxcategory_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE taxcategory_taxcategory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE taxcategory_taxcategory_id_seq OWNER TO dbadmin;

--
-- TOC entry 3689 (class 0 OID 0)
-- Dependencies: 201
-- Name: taxcategory_taxcategory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE taxcategory_taxcategory_id_seq OWNED BY taxcategory.taxcategory_id;


--
-- TOC entry 200 (class 1259 OID 42637)
-- Name: taxmodule; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE taxmodule (
    taxmodule_id integer NOT NULL,
    taxmodulename text NOT NULL
);


ALTER TABLE taxmodule OWNER TO dbadmin;

--
-- TOC entry 199 (class 1259 OID 42635)
-- Name: taxmodule_taxmodule_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

CREATE SEQUENCE taxmodule_taxmodule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE taxmodule_taxmodule_id_seq OWNER TO dbadmin;

--
-- TOC entry 3690 (class 0 OID 0)
-- Dependencies: 199
-- Name: taxmodule_taxmodule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dbadmin
--

ALTER SEQUENCE taxmodule_taxmodule_id_seq OWNED BY taxmodule.taxmodule_id;


--
-- TOC entry 185 (class 1259 OID 42489)
-- Name: transactions; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE transactions (
    id integer NOT NULL,
    table_name text
);


ALTER TABLE transactions OWNER TO dbadmin;

--
-- TOC entry 233 (class 1259 OID 42915)
-- Name: translation; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE translation (
    trans_id integer NOT NULL,
    language_code character varying(6) NOT NULL,
    description text
);


ALTER TABLE translation OWNER TO dbadmin;

--
-- TOC entry 213 (class 1259 OID 42765)
-- Name: vendor; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE vendor (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    name character varying(64),
    address1 character varying(32),
    address2 character varying(32),
    city character varying(32),
    state character varying(32),
    zipcode character varying(10),
    country character varying(32),
    contact character varying(64),
    phone character varying(20),
    fax character varying(20),
    email text,
    notes text,
    terms smallint DEFAULT 0,
    taxincluded boolean DEFAULT false,
    vendornumber character varying(32),
    cc text,
    bcc text,
    gifi_accno character varying(30),
    business_id integer,
    taxnumber character varying(32),
    sic_code character varying(6),
    discount numeric,
    creditlimit numeric DEFAULT 0,
    iban character varying(34),
    bic character varying(11),
    employee_id integer,
    language_code character varying(6),
    pricegroup_id integer,
    curr character(3),
    startdate date,
    enddate date
);


ALTER TABLE vendor OWNER TO dbadmin;

--
-- TOC entry 206 (class 1259 OID 42707)
-- Name: vendortax; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE vendortax (
    vendor_id integer NOT NULL,
    chart_id integer NOT NULL
);


ALTER TABLE vendortax OWNER TO dbadmin;

--
-- TOC entry 221 (class 1259 OID 42839)
-- Name: warehouse; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE warehouse (
    id integer DEFAULT nextval('id'::regclass) NOT NULL,
    description text
);


ALTER TABLE warehouse OWNER TO dbadmin;

--
-- TOC entry 224 (class 1259 OID 42859)
-- Name: yearend; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE yearend (
    trans_id integer NOT NULL,
    transdate date
);


ALTER TABLE yearend OWNER TO dbadmin;

--
-- TOC entry 3208 (class 2604 OID 42551)
-- Name: entry_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY acc_trans ALTER COLUMN entry_id SET DEFAULT nextval('acc_trans_entry_id_seq'::regclass);


--
-- TOC entry 3268 (class 2604 OID 42909)
-- Name: entry_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY audittrail ALTER COLUMN entry_id SET DEFAULT nextval('audittrail_entry_id_seq'::regclass);


--
-- TOC entry 3272 (class 2604 OID 43003)
-- Name: field_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY custom_field_catalog ALTER COLUMN field_id SET DEFAULT nextval('custom_field_catalog_field_id_seq'::regclass);


--
-- TOC entry 3271 (class 2604 OID 42992)
-- Name: table_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY custom_table_catalog ALTER COLUMN table_id SET DEFAULT nextval('custom_table_catalog_table_id_seq'::regclass);


--
-- TOC entry 3263 (class 2604 OID 42853)
-- Name: entry_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY inventory ALTER COLUMN entry_id SET DEFAULT nextval('inventory_entry_id_seq'::regclass);


--
-- TOC entry 3266 (class 2604 OID 42889)
-- Name: entry_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partscustomer ALTER COLUMN entry_id SET DEFAULT nextval('partscustomer_entry_id_seq'::regclass);


--
-- TOC entry 3264 (class 2604 OID 42869)
-- Name: entry_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partsvendor ALTER COLUMN entry_id SET DEFAULT nextval('partsvendor_entry_id_seq'::regclass);


--
-- TOC entry 3248 (class 2604 OID 42759)
-- Name: entry_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY shipto ALTER COLUMN entry_id SET DEFAULT nextval('shipto_entry_id_seq'::regclass);


--
-- TOC entry 3235 (class 2604 OID 42651)
-- Name: taxcategory_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY taxcategory ALTER COLUMN taxcategory_id SET DEFAULT nextval('taxcategory_taxcategory_id_seq'::regclass);


--
-- TOC entry 3234 (class 2604 OID 42640)
-- Name: taxmodule_id; Type: DEFAULT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY taxmodule ALTER COLUMN taxmodule_id SET DEFAULT nextval('taxmodule_taxmodule_id_seq'::regclass);


--
-- TOC entry 3623 (class 0 OID 42545)
-- Dependencies: 192
-- Data for Name: acc_trans; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY acc_trans (trans_id, chart_id, amount, transdate, source, cleared, fx_transaction, project_id, memo, invoice_id, entry_id) FROM stdin;
\.


--
-- TOC entry 3691 (class 0 OID 0)
-- Dependencies: 191
-- Name: acc_trans_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('acc_trans_entry_id_seq', 1, false);


--
-- TOC entry 3629 (class 0 OID 42621)
-- Dependencies: 198
-- Data for Name: ap; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY ap (id, invnumber, transdate, vendor_id, taxincluded, amount, netamount, paid, datepaid, duedate, invoice, ordnumber, curr, notes, employee_id, till, quonumber, intnotes, department_id, shipvia, language_code, ponumber, shippingpoint, terms) FROM stdin;
\.


--
-- TOC entry 3628 (class 0 OID 42608)
-- Dependencies: 197
-- Data for Name: ar; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY ar (id, invnumber, transdate, customer_id, taxincluded, amount, netamount, paid, datepaid, duedate, invoice, shippingpoint, terms, notes, curr, ordnumber, employee_id, till, quonumber, intnotes, department_id, shipvia, language_code, ponumber) FROM stdin;
\.


--
-- TOC entry 3627 (class 0 OID 42600)
-- Dependencies: 196
-- Data for Name: assembly; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY assembly (id, parts_id, qty, bom, adj) FROM stdin;
\.


--
-- TOC entry 3663 (class 0 OID 42905)
-- Dependencies: 232
-- Data for Name: audittrail; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY audittrail (trans_id, tablename, reference, formname, action, transdate, employee_id, entry_id) FROM stdin;
\.


--
-- TOC entry 3692 (class 0 OID 0)
-- Dependencies: 231
-- Name: audittrail_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('audittrail_entry_id_seq', 1, false);


--
-- TOC entry 3650 (class 0 OID 42822)
-- Dependencies: 219
-- Data for Name: business; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY business (id, description, discount) FROM stdin;
\.


--
-- TOC entry 3619 (class 0 OID 42516)
-- Dependencies: 188
-- Data for Name: chart; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY chart (id, accno, description, charttype, category, link, gifi_accno, contra) FROM stdin;
10001	1000	CURRENT ASSETS	H	A			f
10003	1060	Checking Account	A	A	AR_paid:AP_paid		f
10005	1065	Petty Cash	A	A	AR_paid:AP_paid		f
10007	1200	Accounts Receivables	A	A	AR		f
10009	1205	Allowance for doubtful accounts	A	A			f
10011	1500	INVENTORY ASSETS	H	A			f
10013	1520	Inventory / General	A	A	IC		f
10015	1530	Inventory / Aftermarket Parts	A	A	IC		f
10017	1800	CAPITAL ASSETS	H	A			f
10019	1820	Office Furniture & Equipment	A	A			f
10021	1825	Accum. Amort. -Furn. & Equip.	A	A			t
10023	1840	Vehicle	A	A			f
10025	1845	Accum. Amort. -Vehicle	A	A			t
10027	2000	CURRENT LIABILITIES	H	L			f
10029	2100	Accounts Payable	A	L	AP		f
10031	2160	Corporate Taxes Payable	A	L			f
10033	2190	Federal Income Tax Payable	A	L			f
10035	2210	Workers Comp Payable	A	L			f
10037	2220	Vacation Pay Payable	A	L			f
10039	2250	Pension Plan Payable	A	L			f
10041	2260	Employment Insurance Payable	A	L			f
10043	2280	Payroll Taxes Payable	A	L			f
10045	2310	VAT (10%)	A	L	AR_tax:AP_tax:IC_taxpart:IC_taxservice		f
10047	2320	VAT (14%)	A	L	AR_tax:AP_tax:IC_taxpart:IC_taxservice		f
10049	2330	VAT (30%)	A	L	AR_tax:AP_tax:IC_taxpart:IC_taxservice		f
10051	2600	LONG TERM LIABILITIES	H	L			f
10053	2620	Bank Loans	A	L			f
10055	2680	Loans from Shareholders	A	L	AP_paid		f
10057	3300	SHARE CAPITAL	H	Q			f
10059	3350	Common Shares	A	Q			f
10061	4000	SALES REVENUE	H	I			f
10063	4020	Sales / General	A	I	AR_amount:IC_sale		f
10065	4030	Sales / Aftermarket Parts	A	I	AR_amount:IC_sale		f
10067	4300	CONSULTING REVENUE	H	I			f
10069	4320	Consulting	A	I	AR_amount:IC_income		f
10071	4400	OTHER REVENUE	H	I			f
10073	4430	Shipping & Handling	A	I	IC_income		f
10075	4440	Interest	A	I			f
10077	4450	Foreign Exchange Gain	A	I			f
10079	5000	COST OF GOODS SOLD	H	E			f
10081	5010	Purchases	A	E	AP_amount:IC_expense		f
10083	5020	COGS / General	A	E	AP_amount:IC_cogs		f
10085	5030	COGS / Aftermarket Parts	A	E	AP_amount:IC_cogs		f
10087	5100	Freight	A	E	AP_amount:IC_expense		f
10089	5400	PAYROLL EXPENSES	H	E			f
10091	5410	Wages & Salaries	A	E			f
10093	5420	Employment Insurance Expense	A	E			f
10095	5430	Pension Plan Expense	A	E			f
10097	5440	Workers Comp Expense	A	E			f
10099	5470	Employee Benefits	A	E			f
10101	5600	GENERAL & ADMINISTRATIVE EXPENSES	H	E			f
10103	5610	Accounting & Legal	A	E	AP_amount		f
10105	5615	Advertising & Promotions	A	E	AP_amount		f
10107	5620	Bad Debts	A	E			f
10109	5650	Capital Cost Allowance Expense	A	E			f
10111	5660	Amortization Expense	A	E			f
10113	5680	Income Taxes	A	E			f
10115	5685	Insurance	A	E	AP_amount		f
10117	5690	Interest & Bank Charges	A	E			f
10119	5700	Office Supplies	A	E	AP_amount		f
10121	5760	Rent	A	E	AP_amount		f
10123	5765	Repair & Maintenance	A	E	AP_amount		f
10125	5780	Telephone	A	E	AP_amount		f
10127	5785	Travel & Entertainment	A	E			f
10129	5790	Utilities	A	E	AP_amount		f
10131	5795	Registrations	A	E	AP_amount		f
10133	5800	Licenses	A	E	AP_amount		f
10135	5810	Foreign Exchange Loss	A	E			f
\.


--
-- TOC entry 3672 (class 0 OID 43000)
-- Dependencies: 241
-- Data for Name: custom_field_catalog; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY custom_field_catalog (field_id, table_id, field_name) FROM stdin;
\.


--
-- TOC entry 3693 (class 0 OID 0)
-- Dependencies: 240
-- Name: custom_field_catalog_field_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('custom_field_catalog_field_id_seq', 1, false);


--
-- TOC entry 3670 (class 0 OID 42989)
-- Dependencies: 239
-- Data for Name: custom_table_catalog; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY custom_table_catalog (table_id, extends, table_name) FROM stdin;
\.


--
-- TOC entry 3694 (class 0 OID 0)
-- Dependencies: 238
-- Name: custom_table_catalog_table_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('custom_table_catalog_table_id_seq', 1, false);


--
-- TOC entry 3625 (class 0 OID 42572)
-- Dependencies: 194
-- Data for Name: customer; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY customer (id, name, address1, address2, city, state, zipcode, country, contact, phone, fax, email, notes, discount, taxincluded, creditlimit, terms, customernumber, cc, bcc, business_id, taxnumber, sic_code, iban, bic, employee_id, language_code, pricegroup_id, curr, startdate, enddate) FROM stdin;
\.


--
-- TOC entry 3636 (class 0 OID 42702)
-- Dependencies: 205
-- Data for Name: customertax; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY customertax (customer_id, chart_id) FROM stdin;
\.


--
-- TOC entry 3621 (class 0 OID 42535)
-- Dependencies: 190
-- Data for Name: defaults; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY defaults (setting_key, value) FROM stdin;
sinumber	1
sonumber	1
yearend	1
businessnumber	1
version	1.2.0
closedto	\N
revtrans	1
ponumber	1
sqnumber	1
rfqnumber	1
audittrail	0
vinumber	1
employeenumber	1
partnumber	1
customernumber	1
vendornumber	1
glnumber	1
projectnumber	1
inventory_accno_id	10013
income_accno_id	10063
expense_accno_id	10081
fxgain_accno_id	10077
fxloss_accno_id	10135
curr	USD:CAD:EUR
weightunit	kg
\.


--
-- TOC entry 3648 (class 0 OID 42807)
-- Dependencies: 217
-- Data for Name: department; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY department (id, description, role) FROM stdin;
\.


--
-- TOC entry 3649 (class 0 OID 42817)
-- Dependencies: 218
-- Data for Name: dpt_trans; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY dpt_trans (trans_id, department_id) FROM stdin;
\.


--
-- TOC entry 3641 (class 0 OID 42743)
-- Dependencies: 210
-- Data for Name: employee; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY employee (id, login, name, address1, address2, city, state, zipcode, country, workphone, homephone, startdate, enddate, notes, role, sales, email, ssn, iban, bic, managerid, employeenumber, dob) FROM stdin;
\.


--
-- TOC entry 3640 (class 0 OID 42735)
-- Dependencies: 209
-- Data for Name: exchangerate; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY exchangerate (curr, transdate, buy, sell) FROM stdin;
\.


--
-- TOC entry 3620 (class 0 OID 42527)
-- Dependencies: 189
-- Data for Name: gifi; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY gifi (accno, description) FROM stdin;
\.


--
-- TOC entry 3618 (class 0 OID 42505)
-- Dependencies: 187
-- Data for Name: gl; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY gl (id, reference, description, transdate, employee_id, notes, department_id) FROM stdin;
\.


--
-- TOC entry 3695 (class 0 OID 0)
-- Dependencies: 181
-- Name: id; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('id', 10136, true);


--
-- TOC entry 3654 (class 0 OID 42850)
-- Dependencies: 223
-- Data for Name: inventory; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY inventory (warehouse_id, parts_id, trans_id, orderitems_id, qty, shippingdate, employee_id, entry_id) FROM stdin;
\.


--
-- TOC entry 3696 (class 0 OID 0)
-- Dependencies: 222
-- Name: inventory_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('inventory_entry_id_seq', 1, false);


--
-- TOC entry 3624 (class 0 OID 42562)
-- Dependencies: 193
-- Data for Name: invoice; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY invoice (id, trans_id, parts_id, description, qty, allocated, sellprice, fxsellprice, discount, assemblyitem, unit, project_id, deliverydate, serialnumber, notes) FROM stdin;
\.


--
-- TOC entry 3697 (class 0 OID 0)
-- Dependencies: 182
-- Name: invoiceid; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('invoiceid', 1, true);


--
-- TOC entry 3668 (class 0 OID 42948)
-- Dependencies: 237
-- Data for Name: jcitems; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY jcitems (id, project_id, parts_id, description, qty, allocated, sellprice, fxsellprice, serialnumber, checkedin, checkedout, employee_id, notes) FROM stdin;
\.


--
-- TOC entry 3698 (class 0 OID 0)
-- Dependencies: 184
-- Name: jcitemsid; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('jcitemsid', 1, true);


--
-- TOC entry 3661 (class 0 OID 42895)
-- Dependencies: 230
-- Data for Name: language; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY language (code, description) FROM stdin;
\.


--
-- TOC entry 3617 (class 0 OID 42497)
-- Dependencies: 186
-- Data for Name: makemodel; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY makemodel (parts_id, make, model) FROM stdin;
\.


--
-- TOC entry 3638 (class 0 OID 42712)
-- Dependencies: 207
-- Data for Name: oe; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY oe (id, ordnumber, transdate, vendor_id, customer_id, amount, netamount, reqdate, taxincluded, shippingpoint, notes, curr, employee_id, closed, quotation, quonumber, intnotes, department_id, shipvia, language_code, ponumber, terms) FROM stdin;
\.


--
-- TOC entry 3639 (class 0 OID 42726)
-- Dependencies: 208
-- Data for Name: orderitems; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY orderitems (id, trans_id, parts_id, description, qty, sellprice, discount, unit, project_id, reqdate, ship, serialnumber, notes) FROM stdin;
\.


--
-- TOC entry 3699 (class 0 OID 0)
-- Dependencies: 183
-- Name: orderitemsid; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('orderitemsid', 1, true);


--
-- TOC entry 3626 (class 0 OID 42584)
-- Dependencies: 195
-- Data for Name: parts; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY parts (id, partnumber, description, unit, listprice, sellprice, lastcost, priceupdate, weight, onhand, notes, makemodel, assembly, alternate, rop, inventory_accno_id, income_accno_id, expense_accno_id, bin, obsolete, bom, image, drawing, microfiche, partsgroup_id, project_id, avgcost) FROM stdin;
\.


--
-- TOC entry 3660 (class 0 OID 42886)
-- Dependencies: 229
-- Data for Name: partscustomer; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY partscustomer (parts_id, customer_id, pricegroup_id, pricebreak, sellprice, validfrom, validto, curr, entry_id) FROM stdin;
\.


--
-- TOC entry 3700 (class 0 OID 0)
-- Dependencies: 228
-- Name: partscustomer_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('partscustomer_entry_id_seq', 1, false);


--
-- TOC entry 3646 (class 0 OID 42788)
-- Dependencies: 215
-- Data for Name: partsgroup; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY partsgroup (id, partsgroup) FROM stdin;
\.


--
-- TOC entry 3634 (class 0 OID 42662)
-- Dependencies: 203
-- Data for Name: partstax; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY partstax (parts_id, chart_id, taxcategory_id) FROM stdin;
\.


--
-- TOC entry 3657 (class 0 OID 42866)
-- Dependencies: 226
-- Data for Name: partsvendor; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY partsvendor (vendor_id, parts_id, partnumber, leadtime, lastcost, curr, entry_id) FROM stdin;
\.


--
-- TOC entry 3701 (class 0 OID 0)
-- Dependencies: 225
-- Name: partsvendor_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('partsvendor_entry_id_seq', 1, false);


--
-- TOC entry 3658 (class 0 OID 42875)
-- Dependencies: 227
-- Data for Name: pricegroup; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY pricegroup (id, pricegroup) FROM stdin;
\.


--
-- TOC entry 3645 (class 0 OID 42777)
-- Dependencies: 214
-- Data for Name: project; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY project (id, projectnumber, description, startdate, enddate, parts_id, production, completed, customer_id) FROM stdin;
\.


--
-- TOC entry 3665 (class 0 OID 42923)
-- Dependencies: 234
-- Data for Name: recurring; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY recurring (id, reference, startdate, nextdate, enddate, repeat, unit, howmany, payment) FROM stdin;
\.


--
-- TOC entry 3666 (class 0 OID 42932)
-- Dependencies: 235
-- Data for Name: recurringemail; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY recurringemail (id, formname, format, message) FROM stdin;
\.


--
-- TOC entry 3667 (class 0 OID 42940)
-- Dependencies: 236
-- Data for Name: recurringprint; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY recurringprint (id, formname, format, printer) FROM stdin;
\.


--
-- TOC entry 3643 (class 0 OID 42756)
-- Dependencies: 212
-- Data for Name: shipto; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY shipto (trans_id, shiptoname, shiptoaddress1, shiptoaddress2, shiptocity, shiptostate, shiptozipcode, shiptocountry, shiptocontact, shiptophone, shiptofax, shiptoemail, entry_id) FROM stdin;
\.


--
-- TOC entry 3702 (class 0 OID 0)
-- Dependencies: 211
-- Name: shipto_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('shipto_entry_id_seq', 1, false);


--
-- TOC entry 3651 (class 0 OID 42831)
-- Dependencies: 220
-- Data for Name: sic; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY sic (code, sictype, description) FROM stdin;
\.


--
-- TOC entry 3647 (class 0 OID 42797)
-- Dependencies: 216
-- Data for Name: status; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY status (trans_id, formname, printed, emailed, spoolfile) FROM stdin;
\.


--
-- TOC entry 3635 (class 0 OID 42682)
-- Dependencies: 204
-- Data for Name: tax; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY tax (chart_id, rate, taxnumber, validto, pass, taxmodule_id) FROM stdin;
10045	0.1	\N	\N	0	1
10047	0.14	\N	\N	0	1
10049	0.3	\N	\N	0	1
\.


--
-- TOC entry 3633 (class 0 OID 42648)
-- Dependencies: 202
-- Data for Name: taxcategory; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY taxcategory (taxcategory_id, taxcategoryname, taxmodule_id) FROM stdin;
\.


--
-- TOC entry 3703 (class 0 OID 0)
-- Dependencies: 201
-- Name: taxcategory_taxcategory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('taxcategory_taxcategory_id_seq', 1, false);


--
-- TOC entry 3631 (class 0 OID 42637)
-- Dependencies: 200
-- Data for Name: taxmodule; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY taxmodule (taxmodule_id, taxmodulename) FROM stdin;
1	Simple
\.


--
-- TOC entry 3704 (class 0 OID 0)
-- Dependencies: 199
-- Name: taxmodule_taxmodule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dbadmin
--

SELECT pg_catalog.setval('taxmodule_taxmodule_id_seq', 1, false);


--
-- TOC entry 3616 (class 0 OID 42489)
-- Dependencies: 185
-- Data for Name: transactions; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY transactions (id, table_name) FROM stdin;
10002	chart
10004	chart
10006	chart
10008	chart
10010	chart
10012	chart
10014	chart
10016	chart
10018	chart
10020	chart
10022	chart
10024	chart
10026	chart
10028	chart
10030	chart
10032	chart
10034	chart
10036	chart
10038	chart
10040	chart
10042	chart
10044	chart
10046	chart
10048	chart
10050	chart
10052	chart
10054	chart
10056	chart
10058	chart
10060	chart
10062	chart
10064	chart
10066	chart
10068	chart
10070	chart
10072	chart
10074	chart
10076	chart
10078	chart
10080	chart
10082	chart
10084	chart
10086	chart
10088	chart
10090	chart
10092	chart
10094	chart
10096	chart
10098	chart
10100	chart
10102	chart
10104	chart
10106	chart
10108	chart
10110	chart
10112	chart
10114	chart
10116	chart
10118	chart
10120	chart
10122	chart
10124	chart
10126	chart
10128	chart
10130	chart
10132	chart
10134	chart
10136	chart
\.


--
-- TOC entry 3664 (class 0 OID 42915)
-- Dependencies: 233
-- Data for Name: translation; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY translation (trans_id, language_code, description) FROM stdin;
\.


--
-- TOC entry 3644 (class 0 OID 42765)
-- Dependencies: 213
-- Data for Name: vendor; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY vendor (id, name, address1, address2, city, state, zipcode, country, contact, phone, fax, email, notes, terms, taxincluded, vendornumber, cc, bcc, gifi_accno, business_id, taxnumber, sic_code, discount, creditlimit, iban, bic, employee_id, language_code, pricegroup_id, curr, startdate, enddate) FROM stdin;
\.


--
-- TOC entry 3637 (class 0 OID 42707)
-- Dependencies: 206
-- Data for Name: vendortax; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY vendortax (vendor_id, chart_id) FROM stdin;
\.


--
-- TOC entry 3652 (class 0 OID 42839)
-- Dependencies: 221
-- Data for Name: warehouse; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY warehouse (id, description) FROM stdin;
\.


--
-- TOC entry 3655 (class 0 OID 42859)
-- Dependencies: 224
-- Data for Name: yearend; Type: TABLE DATA; Schema: public; Owner: dbadmin
--

COPY yearend (trans_id, transdate) FROM stdin;
\.


--
-- TOC entry 3301 (class 2606 OID 42556)
-- Name: acc_trans_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY acc_trans
    ADD CONSTRAINT acc_trans_pkey PRIMARY KEY (entry_id);


--
-- TOC entry 3337 (class 2606 OID 42634)
-- Name: ap_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY ap
    ADD CONSTRAINT ap_pkey PRIMARY KEY (id);


--
-- TOC entry 3329 (class 2606 OID 42620)
-- Name: ar_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY ar
    ADD CONSTRAINT ar_pkey PRIMARY KEY (id);


--
-- TOC entry 3322 (class 2606 OID 42607)
-- Name: assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY assembly
    ADD CONSTRAINT assembly_pkey PRIMARY KEY (id, parts_id);


--
-- TOC entry 3423 (class 2606 OID 42914)
-- Name: audittrail_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY audittrail
    ADD CONSTRAINT audittrail_pkey PRIMARY KEY (entry_id);


--
-- TOC entry 3400 (class 2606 OID 42830)
-- Name: business_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY business
    ADD CONSTRAINT business_pkey PRIMARY KEY (id);


--
-- TOC entry 3293 (class 2606 OID 42526)
-- Name: chart_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY chart
    ADD CONSTRAINT chart_pkey PRIMARY KEY (id);


--
-- TOC entry 3440 (class 2606 OID 43008)
-- Name: custom_field_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY custom_field_catalog
    ADD CONSTRAINT custom_field_catalog_pkey PRIMARY KEY (field_id);


--
-- TOC entry 3438 (class 2606 OID 42997)
-- Name: custom_table_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY custom_table_catalog
    ADD CONSTRAINT custom_table_catalog_pkey PRIMARY KEY (table_id);


--
-- TOC entry 3314 (class 2606 OID 42583)
-- Name: customer_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (id);


--
-- TOC entry 3352 (class 2606 OID 42706)
-- Name: customertax_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY customertax
    ADD CONSTRAINT customertax_pkey PRIMARY KEY (customer_id, chart_id);


--
-- TOC entry 3298 (class 2606 OID 42542)
-- Name: defaults_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY defaults
    ADD CONSTRAINT defaults_pkey PRIMARY KEY (setting_key);


--
-- TOC entry 3396 (class 2606 OID 42816)
-- Name: department_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY department
    ADD CONSTRAINT department_pkey PRIMARY KEY (id);


--
-- TOC entry 3398 (class 2606 OID 42821)
-- Name: dpt_trans_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY dpt_trans
    ADD CONSTRAINT dpt_trans_pkey PRIMARY KEY (trans_id);


--
-- TOC entry 3373 (class 2606 OID 42753)
-- Name: employee_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY employee
    ADD CONSTRAINT employee_pkey PRIMARY KEY (id);


--
-- TOC entry 3368 (class 2606 OID 42742)
-- Name: exchangerate_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY exchangerate
    ADD CONSTRAINT exchangerate_pkey PRIMARY KEY (curr, transdate);


--
-- TOC entry 3296 (class 2606 OID 42534)
-- Name: gifi_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY gifi
    ADD CONSTRAINT gifi_pkey PRIMARY KEY (accno);


--
-- TOC entry 3284 (class 2606 OID 42515)
-- Name: gl_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY gl
    ADD CONSTRAINT gl_pkey PRIMARY KEY (id);


--
-- TOC entry 3406 (class 2606 OID 42858)
-- Name: inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (entry_id);


--
-- TOC entry 3307 (class 2606 OID 42571)
-- Name: invoice_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (id);


--
-- TOC entry 3436 (class 2606 OID 42956)
-- Name: jcitems_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY jcitems
    ADD CONSTRAINT jcitems_pkey PRIMARY KEY (id);


--
-- TOC entry 3421 (class 2606 OID 42902)
-- Name: language_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_pkey PRIMARY KEY (code);


--
-- TOC entry 3279 (class 2606 OID 42504)
-- Name: makemodel_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY makemodel
    ADD CONSTRAINT makemodel_pkey PRIMARY KEY (parts_id);


--
-- TOC entry 3360 (class 2606 OID 42725)
-- Name: oe_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY oe
    ADD CONSTRAINT oe_pkey PRIMARY KEY (id);


--
-- TOC entry 3364 (class 2606 OID 42734)
-- Name: orderitems_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY orderitems
    ADD CONSTRAINT orderitems_pkey PRIMARY KEY (id);


--
-- TOC entry 3319 (class 2606 OID 42599)
-- Name: parts_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY parts
    ADD CONSTRAINT parts_pkey PRIMARY KEY (id);


--
-- TOC entry 3418 (class 2606 OID 42894)
-- Name: partscustomer_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partscustomer
    ADD CONSTRAINT partscustomer_pkey PRIMARY KEY (entry_id);


--
-- TOC entry 3390 (class 2606 OID 42796)
-- Name: partsgroup_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partsgroup
    ADD CONSTRAINT partsgroup_pkey PRIMARY KEY (id);


--
-- TOC entry 3347 (class 2606 OID 42666)
-- Name: partstax_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partstax
    ADD CONSTRAINT partstax_pkey PRIMARY KEY (parts_id, chart_id);


--
-- TOC entry 3411 (class 2606 OID 42874)
-- Name: partsvendor_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partsvendor
    ADD CONSTRAINT partsvendor_pkey PRIMARY KEY (entry_id);


--
-- TOC entry 3415 (class 2606 OID 42883)
-- Name: pricegroup_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY pricegroup
    ADD CONSTRAINT pricegroup_pkey PRIMARY KEY (id);


--
-- TOC entry 3385 (class 2606 OID 42787)
-- Name: project_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- TOC entry 3429 (class 2606 OID 42931)
-- Name: recurring_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY recurring
    ADD CONSTRAINT recurring_pkey PRIMARY KEY (id);


--
-- TOC entry 3431 (class 2606 OID 42939)
-- Name: recurringemail_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY recurringemail
    ADD CONSTRAINT recurringemail_pkey PRIMARY KEY (id);


--
-- TOC entry 3433 (class 2606 OID 42947)
-- Name: recurringprint_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY recurringprint
    ADD CONSTRAINT recurringprint_pkey PRIMARY KEY (id);


--
-- TOC entry 3375 (class 2606 OID 42764)
-- Name: shipto_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY shipto
    ADD CONSTRAINT shipto_pkey PRIMARY KEY (entry_id);


--
-- TOC entry 3402 (class 2606 OID 42838)
-- Name: sic_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY sic
    ADD CONSTRAINT sic_pkey PRIMARY KEY (code);


--
-- TOC entry 3392 (class 2606 OID 42806)
-- Name: status_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY status
    ADD CONSTRAINT status_pkey PRIMARY KEY (trans_id);


--
-- TOC entry 3349 (class 2606 OID 42691)
-- Name: tax_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY tax
    ADD CONSTRAINT tax_pkey PRIMARY KEY (chart_id);


--
-- TOC entry 3344 (class 2606 OID 42656)
-- Name: taxcategory_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY taxcategory
    ADD CONSTRAINT taxcategory_pkey PRIMARY KEY (taxcategory_id);


--
-- TOC entry 3342 (class 2606 OID 42645)
-- Name: taxmodule_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY taxmodule
    ADD CONSTRAINT taxmodule_pkey PRIMARY KEY (taxmodule_id);


--
-- TOC entry 3274 (class 2606 OID 42496)
-- Name: transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);


--
-- TOC entry 3426 (class 2606 OID 42922)
-- Name: translation_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_pkey PRIMARY KEY (trans_id, language_code);


--
-- TOC entry 3381 (class 2606 OID 42776)
-- Name: vendor_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY vendor
    ADD CONSTRAINT vendor_pkey PRIMARY KEY (id);


--
-- TOC entry 3354 (class 2606 OID 42711)
-- Name: vendortax_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY vendortax
    ADD CONSTRAINT vendortax_pkey PRIMARY KEY (vendor_id, chart_id);


--
-- TOC entry 3404 (class 2606 OID 42847)
-- Name: warehouse_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY warehouse
    ADD CONSTRAINT warehouse_pkey PRIMARY KEY (id);


--
-- TOC entry 3408 (class 2606 OID 42863)
-- Name: yearend_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY yearend
    ADD CONSTRAINT yearend_pkey PRIMARY KEY (trans_id);


--
-- TOC entry 3299 (class 1259 OID 43015)
-- Name: acc_trans_chart_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX acc_trans_chart_id_key ON acc_trans USING btree (chart_id);


--
-- TOC entry 3302 (class 1259 OID 43017)
-- Name: acc_trans_source_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX acc_trans_source_key ON acc_trans USING btree (lower(source));


--
-- TOC entry 3303 (class 1259 OID 43014)
-- Name: acc_trans_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX acc_trans_trans_id_key ON acc_trans USING btree (trans_id);


--
-- TOC entry 3304 (class 1259 OID 43016)
-- Name: acc_trans_transdate_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX acc_trans_transdate_key ON acc_trans USING btree (transdate);


--
-- TOC entry 3332 (class 1259 OID 43023)
-- Name: ap_employee_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_employee_id_key ON ap USING btree (employee_id);


--
-- TOC entry 3333 (class 1259 OID 43018)
-- Name: ap_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_id_key ON ap USING btree (id);


--
-- TOC entry 3334 (class 1259 OID 43020)
-- Name: ap_invnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_invnumber_key ON ap USING btree (invnumber);


--
-- TOC entry 3335 (class 1259 OID 43021)
-- Name: ap_ordnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_ordnumber_key ON ap USING btree (ordnumber);


--
-- TOC entry 3338 (class 1259 OID 43024)
-- Name: ap_quonumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_quonumber_key ON ap USING btree (quonumber);


--
-- TOC entry 3339 (class 1259 OID 43019)
-- Name: ap_transdate_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_transdate_key ON ap USING btree (transdate);


--
-- TOC entry 3340 (class 1259 OID 43022)
-- Name: ap_vendor_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ap_vendor_id_key ON ap USING btree (vendor_id);


--
-- TOC entry 3323 (class 1259 OID 43029)
-- Name: ar_customer_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_customer_id_key ON ar USING btree (customer_id);


--
-- TOC entry 3324 (class 1259 OID 43030)
-- Name: ar_employee_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_employee_id_key ON ar USING btree (employee_id);


--
-- TOC entry 3325 (class 1259 OID 43025)
-- Name: ar_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_id_key ON ar USING btree (id);


--
-- TOC entry 3326 (class 1259 OID 43027)
-- Name: ar_invnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_invnumber_key ON ar USING btree (invnumber);


--
-- TOC entry 3327 (class 1259 OID 43028)
-- Name: ar_ordnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_ordnumber_key ON ar USING btree (ordnumber);


--
-- TOC entry 3330 (class 1259 OID 43031)
-- Name: ar_quonumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_quonumber_key ON ar USING btree (quonumber);


--
-- TOC entry 3331 (class 1259 OID 43026)
-- Name: ar_transdate_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX ar_transdate_key ON ar USING btree (transdate);


--
-- TOC entry 3320 (class 1259 OID 43032)
-- Name: assembly_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX assembly_id_key ON assembly USING btree (id);


--
-- TOC entry 3424 (class 1259 OID 43084)
-- Name: audittrail_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX audittrail_trans_id_key ON audittrail USING btree (trans_id);


--
-- TOC entry 3287 (class 1259 OID 43034)
-- Name: chart_accno_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE UNIQUE INDEX chart_accno_key ON chart USING btree (accno);


--
-- TOC entry 3288 (class 1259 OID 43035)
-- Name: chart_category_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX chart_category_key ON chart USING btree (category);


--
-- TOC entry 3289 (class 1259 OID 43037)
-- Name: chart_gifi_accno_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX chart_gifi_accno_key ON chart USING btree (gifi_accno);


--
-- TOC entry 3290 (class 1259 OID 43033)
-- Name: chart_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX chart_id_key ON chart USING btree (id);


--
-- TOC entry 3291 (class 1259 OID 43036)
-- Name: chart_link_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX chart_link_key ON chart USING btree (link);


--
-- TOC entry 3309 (class 1259 OID 43041)
-- Name: customer_contact_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX customer_contact_key ON customer USING btree (lower((contact)::text));


--
-- TOC entry 3350 (class 1259 OID 43042)
-- Name: customer_customer_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX customer_customer_id_key ON customertax USING btree (customer_id);


--
-- TOC entry 3310 (class 1259 OID 43039)
-- Name: customer_customernumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX customer_customernumber_key ON customer USING btree (customernumber);


--
-- TOC entry 3311 (class 1259 OID 43038)
-- Name: customer_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX customer_id_key ON customer USING btree (id);


--
-- TOC entry 3312 (class 1259 OID 43040)
-- Name: customer_name_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX customer_name_key ON customer USING btree (lower((name)::text));


--
-- TOC entry 3394 (class 1259 OID 43079)
-- Name: department_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX department_id_key ON department USING btree (id);


--
-- TOC entry 3369 (class 1259 OID 43043)
-- Name: employee_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX employee_id_key ON employee USING btree (id);


--
-- TOC entry 3370 (class 1259 OID 43044)
-- Name: employee_login_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE UNIQUE INDEX employee_login_key ON employee USING btree (login);


--
-- TOC entry 3371 (class 1259 OID 43045)
-- Name: employee_name_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX employee_name_key ON employee USING btree (lower((name)::text));


--
-- TOC entry 3366 (class 1259 OID 43046)
-- Name: exchangerate_ct_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX exchangerate_ct_key ON exchangerate USING btree (curr, transdate);


--
-- TOC entry 3294 (class 1259 OID 43047)
-- Name: gifi_accno_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE UNIQUE INDEX gifi_accno_key ON gifi USING btree (accno);


--
-- TOC entry 3280 (class 1259 OID 43051)
-- Name: gl_description_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX gl_description_key ON gl USING btree (lower(description));


--
-- TOC entry 3281 (class 1259 OID 43052)
-- Name: gl_employee_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX gl_employee_id_key ON gl USING btree (employee_id);


--
-- TOC entry 3282 (class 1259 OID 43048)
-- Name: gl_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX gl_id_key ON gl USING btree (id);


--
-- TOC entry 3285 (class 1259 OID 43050)
-- Name: gl_reference_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX gl_reference_key ON gl USING btree (reference);


--
-- TOC entry 3286 (class 1259 OID 43049)
-- Name: gl_transdate_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX gl_transdate_key ON gl USING btree (transdate);


--
-- TOC entry 3305 (class 1259 OID 43053)
-- Name: invoice_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX invoice_id_key ON invoice USING btree (id);


--
-- TOC entry 3308 (class 1259 OID 43054)
-- Name: invoice_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX invoice_trans_id_key ON invoice USING btree (trans_id);


--
-- TOC entry 3434 (class 1259 OID 43087)
-- Name: jcitems_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX jcitems_id_key ON jcitems USING btree (id);


--
-- TOC entry 3419 (class 1259 OID 43086)
-- Name: language_code_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE UNIQUE INDEX language_code_key ON language USING btree (code);


--
-- TOC entry 3275 (class 1259 OID 43056)
-- Name: makemodel_make_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX makemodel_make_key ON makemodel USING btree (lower(make));


--
-- TOC entry 3276 (class 1259 OID 43057)
-- Name: makemodel_model_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX makemodel_model_key ON makemodel USING btree (lower(model));


--
-- TOC entry 3277 (class 1259 OID 43055)
-- Name: makemodel_parts_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX makemodel_parts_id_key ON makemodel USING btree (parts_id);


--
-- TOC entry 3356 (class 1259 OID 43061)
-- Name: oe_employee_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX oe_employee_id_key ON oe USING btree (employee_id);


--
-- TOC entry 3357 (class 1259 OID 43058)
-- Name: oe_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX oe_id_key ON oe USING btree (id);


--
-- TOC entry 3358 (class 1259 OID 43060)
-- Name: oe_ordnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX oe_ordnumber_key ON oe USING btree (ordnumber);


--
-- TOC entry 3361 (class 1259 OID 43059)
-- Name: oe_transdate_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX oe_transdate_key ON oe USING btree (transdate);


--
-- TOC entry 3362 (class 1259 OID 43063)
-- Name: orderitems_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX orderitems_id_key ON orderitems USING btree (id);


--
-- TOC entry 3365 (class 1259 OID 43062)
-- Name: orderitems_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX orderitems_trans_id_key ON orderitems USING btree (trans_id);


--
-- TOC entry 3315 (class 1259 OID 43066)
-- Name: parts_description_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX parts_description_key ON parts USING btree (lower(description));


--
-- TOC entry 3316 (class 1259 OID 43064)
-- Name: parts_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX parts_id_key ON parts USING btree (id);


--
-- TOC entry 3317 (class 1259 OID 43065)
-- Name: parts_partnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX parts_partnumber_key ON parts USING btree (lower(partnumber));


--
-- TOC entry 3387 (class 1259 OID 43076)
-- Name: partsgroup_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX partsgroup_id_key ON partsgroup USING btree (id);


--
-- TOC entry 3388 (class 1259 OID 43077)
-- Name: partsgroup_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE UNIQUE INDEX partsgroup_key ON partsgroup USING btree (partsgroup);


--
-- TOC entry 3345 (class 1259 OID 43067)
-- Name: partstax_parts_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX partstax_parts_id_key ON partstax USING btree (parts_id);


--
-- TOC entry 3409 (class 1259 OID 43081)
-- Name: partsvendor_parts_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX partsvendor_parts_id_key ON partsvendor USING btree (parts_id);


--
-- TOC entry 3412 (class 1259 OID 43080)
-- Name: partsvendor_vendor_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX partsvendor_vendor_id_key ON partsvendor USING btree (vendor_id);


--
-- TOC entry 3413 (class 1259 OID 43083)
-- Name: pricegroup_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX pricegroup_id_key ON pricegroup USING btree (id);


--
-- TOC entry 3416 (class 1259 OID 43082)
-- Name: pricegroup_pricegroup_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX pricegroup_pricegroup_key ON pricegroup USING btree (pricegroup);


--
-- TOC entry 3383 (class 1259 OID 43074)
-- Name: project_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX project_id_key ON project USING btree (id);


--
-- TOC entry 3386 (class 1259 OID 43075)
-- Name: projectnumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE UNIQUE INDEX projectnumber_key ON project USING btree (projectnumber);


--
-- TOC entry 3376 (class 1259 OID 43073)
-- Name: shipto_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX shipto_trans_id_key ON shipto USING btree (trans_id);


--
-- TOC entry 3393 (class 1259 OID 43078)
-- Name: status_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX status_trans_id_key ON status USING btree (trans_id);


--
-- TOC entry 3427 (class 1259 OID 43085)
-- Name: translation_trans_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX translation_trans_id_key ON translation USING btree (trans_id);


--
-- TOC entry 3377 (class 1259 OID 43071)
-- Name: vendor_contact_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX vendor_contact_key ON vendor USING btree (lower((contact)::text));


--
-- TOC entry 3378 (class 1259 OID 43068)
-- Name: vendor_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX vendor_id_key ON vendor USING btree (id);


--
-- TOC entry 3379 (class 1259 OID 43069)
-- Name: vendor_name_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX vendor_name_key ON vendor USING btree (lower((name)::text));


--
-- TOC entry 3382 (class 1259 OID 43070)
-- Name: vendor_vendornumber_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX vendor_vendornumber_key ON vendor USING btree (vendornumber);


--
-- TOC entry 3355 (class 1259 OID 43072)
-- Name: vendortax_vendor_id_key; Type: INDEX; Schema: public; Owner: dbadmin
--

CREATE INDEX vendortax_vendor_id_key ON vendortax USING btree (vendor_id);


--
-- TOC entry 3582 (class 2618 OID 42957)
-- Name: ap_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE ap_id_track_i AS
    ON INSERT TO ap DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'ap'::text);


--
-- TOC entry 3583 (class 2618 OID 42958)
-- Name: ap_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE ap_id_track_u AS
    ON UPDATE TO ap DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3584 (class 2618 OID 42959)
-- Name: ar_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE ar_id_track_i AS
    ON INSERT TO ar DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'ar'::text);


--
-- TOC entry 3585 (class 2618 OID 42960)
-- Name: ar_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE ar_id_track_u AS
    ON UPDATE TO ar DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3586 (class 2618 OID 42961)
-- Name: business_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE business_id_track_i AS
    ON INSERT TO business DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'business'::text);


--
-- TOC entry 3587 (class 2618 OID 42962)
-- Name: business_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE business_id_track_u AS
    ON UPDATE TO business DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3588 (class 2618 OID 42963)
-- Name: chart_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE chart_id_track_i AS
    ON INSERT TO chart DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'chart'::text);


--
-- TOC entry 3589 (class 2618 OID 42964)
-- Name: chart_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE chart_id_track_u AS
    ON UPDATE TO chart DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3590 (class 2618 OID 42965)
-- Name: customer_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE customer_id_track_i AS
    ON INSERT TO customer DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'customer'::text);


--
-- TOC entry 3591 (class 2618 OID 42966)
-- Name: customer_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE customer_id_track_u AS
    ON UPDATE TO customer DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3592 (class 2618 OID 42967)
-- Name: department_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE department_id_track_i AS
    ON INSERT TO department DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'department'::text);


--
-- TOC entry 3593 (class 2618 OID 42968)
-- Name: department_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE department_id_track_u AS
    ON UPDATE TO department DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3594 (class 2618 OID 42969)
-- Name: employee_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE employee_id_track_i AS
    ON INSERT TO employee DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'employee'::text);


--
-- TOC entry 3595 (class 2618 OID 42970)
-- Name: employee_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE employee_id_track_u AS
    ON UPDATE TO employee DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3609 (class 2618 OID 42984)
-- Name: employee_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE employee_id_track_u AS
    ON UPDATE TO vendor DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3596 (class 2618 OID 42971)
-- Name: gl_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE gl_id_track_i AS
    ON INSERT TO gl DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'gl'::text);


--
-- TOC entry 3597 (class 2618 OID 42972)
-- Name: gl_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE gl_id_track_u AS
    ON UPDATE TO gl DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3598 (class 2618 OID 42973)
-- Name: oe_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE oe_id_track_i AS
    ON INSERT TO oe DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'oe'::text);


--
-- TOC entry 3599 (class 2618 OID 42974)
-- Name: oe_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE oe_id_track_u AS
    ON UPDATE TO oe DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3600 (class 2618 OID 42975)
-- Name: parts_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE parts_id_track_i AS
    ON INSERT TO parts DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'parts'::text);


--
-- TOC entry 3601 (class 2618 OID 42976)
-- Name: parts_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE parts_id_track_u AS
    ON UPDATE TO parts DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3602 (class 2618 OID 42977)
-- Name: partsgroup_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE partsgroup_id_track_i AS
    ON INSERT TO partsgroup DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'partsgroup'::text);


--
-- TOC entry 3603 (class 2618 OID 42978)
-- Name: partsgroup_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE partsgroup_id_track_u AS
    ON UPDATE TO partsgroup DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3604 (class 2618 OID 42979)
-- Name: pricegroup_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE pricegroup_id_track_i AS
    ON INSERT TO pricegroup DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'pricegroup'::text);


--
-- TOC entry 3605 (class 2618 OID 42980)
-- Name: pricegroup_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE pricegroup_id_track_u AS
    ON UPDATE TO pricegroup DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3606 (class 2618 OID 42981)
-- Name: project_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE project_id_track_i AS
    ON INSERT TO project DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'project'::text);


--
-- TOC entry 3607 (class 2618 OID 42982)
-- Name: project_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE project_id_track_u AS
    ON UPDATE TO project DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3608 (class 2618 OID 42983)
-- Name: vendor_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE vendor_id_track_i AS
    ON INSERT TO vendor DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'vendor'::text);


--
-- TOC entry 3610 (class 2618 OID 42985)
-- Name: warehouse_id_track_i; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE warehouse_id_track_i AS
    ON INSERT TO warehouse DO  INSERT INTO transactions (id, table_name)
  VALUES (new.id, 'employee'::text);


--
-- TOC entry 3611 (class 2618 OID 42986)
-- Name: warehouse_id_track_u; Type: RULE; Schema: public; Owner: dbadmin
--

CREATE RULE warehouse_id_track_u AS
    ON UPDATE TO warehouse DO  UPDATE transactions SET id = new.id
  WHERE (transactions.id = old.id);


--
-- TOC entry 3457 (class 2620 OID 43106)
-- Name: check_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER check_department AFTER INSERT OR UPDATE ON ar FOR EACH ROW EXECUTE PROCEDURE check_department();


--
-- TOC entry 3461 (class 2620 OID 43107)
-- Name: check_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER check_department AFTER INSERT OR UPDATE ON ap FOR EACH ROW EXECUTE PROCEDURE check_department();


--
-- TOC entry 3451 (class 2620 OID 43108)
-- Name: check_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER check_department AFTER INSERT OR UPDATE ON gl FOR EACH ROW EXECUTE PROCEDURE check_department();


--
-- TOC entry 3466 (class 2620 OID 43109)
-- Name: check_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER check_department AFTER INSERT OR UPDATE ON oe FOR EACH ROW EXECUTE PROCEDURE check_department();


--
-- TOC entry 3465 (class 2620 OID 43104)
-- Name: check_inventory; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER check_inventory AFTER UPDATE ON oe FOR EACH ROW EXECUTE PROCEDURE check_inventory();


--
-- TOC entry 3453 (class 2620 OID 43096)
-- Name: del_customer; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_customer AFTER DELETE ON customer FOR EACH ROW EXECUTE PROCEDURE del_customer();


--
-- TOC entry 3455 (class 2620 OID 43091)
-- Name: del_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_department AFTER DELETE ON ar FOR EACH ROW EXECUTE PROCEDURE del_department();


--
-- TOC entry 3459 (class 2620 OID 43092)
-- Name: del_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_department AFTER DELETE ON ap FOR EACH ROW EXECUTE PROCEDURE del_department();


--
-- TOC entry 3450 (class 2620 OID 43093)
-- Name: del_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_department AFTER DELETE ON gl FOR EACH ROW EXECUTE PROCEDURE del_department();


--
-- TOC entry 3463 (class 2620 OID 43094)
-- Name: del_department; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_department AFTER DELETE ON oe FOR EACH ROW EXECUTE PROCEDURE del_department();


--
-- TOC entry 3456 (class 2620 OID 43100)
-- Name: del_exchangerate; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_exchangerate BEFORE DELETE ON ar FOR EACH ROW EXECUTE PROCEDURE del_exchangerate();


--
-- TOC entry 3460 (class 2620 OID 43101)
-- Name: del_exchangerate; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_exchangerate BEFORE DELETE ON ap FOR EACH ROW EXECUTE PROCEDURE del_exchangerate();


--
-- TOC entry 3464 (class 2620 OID 43102)
-- Name: del_exchangerate; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_exchangerate BEFORE DELETE ON oe FOR EACH ROW EXECUTE PROCEDURE del_exchangerate();


--
-- TOC entry 3458 (class 2620 OID 43111)
-- Name: del_recurring; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_recurring AFTER DELETE ON ar FOR EACH ROW EXECUTE PROCEDURE del_recurring();


--
-- TOC entry 3462 (class 2620 OID 43112)
-- Name: del_recurring; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_recurring AFTER DELETE ON ap FOR EACH ROW EXECUTE PROCEDURE del_recurring();


--
-- TOC entry 3452 (class 2620 OID 43113)
-- Name: del_recurring; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_recurring AFTER DELETE ON gl FOR EACH ROW EXECUTE PROCEDURE del_recurring();


--
-- TOC entry 3467 (class 2620 OID 43098)
-- Name: del_vendor; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_vendor AFTER DELETE ON vendor FOR EACH ROW EXECUTE PROCEDURE del_vendor();


--
-- TOC entry 3449 (class 2620 OID 43089)
-- Name: del_yearend; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER del_yearend AFTER DELETE ON gl FOR EACH ROW EXECUTE PROCEDURE del_yearend();


--
-- TOC entry 3454 (class 2620 OID 43117)
-- Name: parts_short; Type: TRIGGER; Schema: public; Owner: dbadmin
--

CREATE TRIGGER parts_short AFTER UPDATE ON parts FOR EACH ROW EXECUTE PROCEDURE trigger_parts_short();


--
-- TOC entry 3441 (class 2606 OID 42557)
-- Name: acc_trans_chart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY acc_trans
    ADD CONSTRAINT acc_trans_chart_id_fkey FOREIGN KEY (chart_id) REFERENCES chart(id);


--
-- TOC entry 3448 (class 2606 OID 43009)
-- Name: custom_field_catalog_table_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY custom_field_catalog
    ADD CONSTRAINT custom_field_catalog_table_id_fkey FOREIGN KEY (table_id) REFERENCES custom_table_catalog(table_id);


--
-- TOC entry 3444 (class 2606 OID 42672)
-- Name: partstax_chart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partstax
    ADD CONSTRAINT partstax_chart_id_fkey FOREIGN KEY (chart_id) REFERENCES chart(id);


--
-- TOC entry 3443 (class 2606 OID 42667)
-- Name: partstax_parts_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partstax
    ADD CONSTRAINT partstax_parts_id_fkey FOREIGN KEY (parts_id) REFERENCES parts(id);


--
-- TOC entry 3445 (class 2606 OID 42677)
-- Name: partstax_taxcategory_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY partstax
    ADD CONSTRAINT partstax_taxcategory_id_fkey FOREIGN KEY (taxcategory_id) REFERENCES taxcategory(taxcategory_id);


--
-- TOC entry 3446 (class 2606 OID 42692)
-- Name: tax_chart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY tax
    ADD CONSTRAINT tax_chart_id_fkey FOREIGN KEY (chart_id) REFERENCES chart(id);


--
-- TOC entry 3447 (class 2606 OID 42697)
-- Name: tax_taxmodule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY tax
    ADD CONSTRAINT tax_taxmodule_id_fkey FOREIGN KEY (taxmodule_id) REFERENCES taxmodule(taxmodule_id);


--
-- TOC entry 3442 (class 2606 OID 42657)
-- Name: taxcategory_taxmodule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY taxcategory
    ADD CONSTRAINT taxcategory_taxmodule_id_fkey FOREIGN KEY (taxmodule_id) REFERENCES taxmodule(taxmodule_id);


--
-- TOC entry 3679 (class 0 OID 0)
-- Dependencies: 7
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2017-06-28 18:06:38 EDT

--
-- PostgreSQL database dump complete
--

