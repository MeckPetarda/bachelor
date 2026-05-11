--
-- PostgreSQL database dump
--

\restrict lWdcdQEggVTn21u2EQqDNrxnPYcm0MP7kYzRHgtQl2aSU7TEBuZwPCCSX9u25uI

-- Dumped from database version 15.17 (Ubuntu 15.17-1.pgdg24.04+1)
-- Dumped by pg_dump version 15.17 (Ubuntu 15.17-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: algorithm_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.algorithm_type AS ENUM (
    'temporal_centroid',
    'rssi_weighted_centroid',
    'manual'
);


ALTER TYPE public.algorithm_type OWNER TO postgres;

--
-- Name: direction_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.direction_type AS ENUM (
    'in',
    'out',
    'unknown'
);


ALTER TYPE public.direction_type OWNER TO postgres;

--
-- Name: lighthouse_placement; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.lighthouse_placement AS ENUM (
    'STANDALONE',
    'INSIDE',
    'OUTSIDE'
);


ALTER TYPE public.lighthouse_placement OWNER TO postgres;

--
-- Name: orphan_reason_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.orphan_reason_type AS ENUM (
    'insufficient_data',
    'misconfigured_group',
    'unsyncable'
);


ALTER TYPE public.orphan_reason_type OWNER TO postgres;

--
-- Name: scan_source; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scan_source AS ENUM (
    'realtime',
    'offline_sync'
);


ALTER TYPE public.scan_source OWNER TO postgres;

--
-- Name: time_basis; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.time_basis AS ENUM (
    'synced',
    'estimated',
    'relative'
);


ALTER TYPE public.time_basis OWNER TO postgres;

--
-- Name: user_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.user_type AS ENUM (
    'STANDALONE',
    'INSIDE',
    'OUTSIDE'
);


ALTER TYPE public.user_type OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    user_id uuid,
    action character varying(100) NOT NULL,
    resource_type character varying(100),
    resource_id uuid,
    changes jsonb,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.audit_logs_id_seq OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: dashboard_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dashboard_users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role public.user_type NOT NULL,
    is_active boolean DEFAULT true,
    last_login timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.dashboard_users OWNER TO postgres;

--
-- Name: lighthouse_connection_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lighthouse_connection_events (
    id bigint NOT NULL,
    lighthouse_id integer NOT NULL,
    event_type character varying(20) NOT NULL,
    is_graceful boolean,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lighthouse_connection_events OWNER TO postgres;

--
-- Name: lighthouse_connection_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lighthouse_connection_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lighthouse_connection_events_id_seq OWNER TO postgres;

--
-- Name: lighthouse_connection_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lighthouse_connection_events_id_seq OWNED BY public.lighthouse_connection_events.id;


--
-- Name: lighthouse_groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lighthouse_groups (
    id integer NOT NULL,
    label character varying(255) NOT NULL,
    description character varying(500),
    activity_timeout_ms integer DEFAULT 4000 NOT NULL,
    orphan_timeout_ms integer DEFAULT 8000 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lighthouse_groups OWNER TO postgres;

--
-- Name: lighthouse_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lighthouse_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lighthouse_groups_id_seq OWNER TO postgres;

--
-- Name: lighthouse_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lighthouse_groups_id_seq OWNED BY public.lighthouse_groups.id;


--
-- Name: lighthouse_health_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lighthouse_health_snapshots (
    id bigint NOT NULL,
    lighthouse_id integer NOT NULL,
    uptime_sec integer,
    free_heap_bytes integer,
    min_free_heap_bytes integer,
    wifi_rssi_dbm integer,
    rfid_state character varying(50),
    rfid_is_responsive boolean,
    rfid_power_rail_present boolean,
    rfid_fw_version character varying(20),
    rfid_last_error integer,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lighthouse_health_snapshots OWNER TO postgres;

--
-- Name: lighthouse_health_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lighthouse_health_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lighthouse_health_snapshots_id_seq OWNER TO postgres;

--
-- Name: lighthouse_health_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lighthouse_health_snapshots_id_seq OWNED BY public.lighthouse_health_snapshots.id;


--
-- Name: lighthouses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lighthouses (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    device_id character varying(255) NOT NULL,
    placement public.lighthouse_placement DEFAULT 'STANDALONE'::public.lighthouse_placement NOT NULL,
    comment character varying(256),
    firmware_version character varying(50),
    last_seen_at timestamp with time zone,
    is_active boolean DEFAULT true,
    config jsonb DEFAULT '{}'::jsonb,
    group_id integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    canged_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lighthouses OWNER TO postgres;

--
-- Name: lighthouses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lighthouses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lighthouses_id_seq OWNER TO postgres;

--
-- Name: lighthouses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lighthouses_id_seq OWNED BY public.lighthouses.id;


--
-- Name: mqtt_clients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mqtt_clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lighthouse_id integer,
    client_id character varying(255) NOT NULL,
    connected_at timestamp with time zone,
    last_activity timestamp with time zone,
    is_connected boolean DEFAULT false,
    ip_address character varying(45),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.mqtt_clients OWNER TO postgres;

--
-- Name: processed_event_scans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.processed_event_scans (
    processed_event_id uuid NOT NULL,
    raw_scan_id bigint NOT NULL
);


ALTER TABLE public.processed_event_scans OWNER TO postgres;

--
-- Name: processed_event_scans_raw_scan_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.processed_event_scans_raw_scan_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.processed_event_scans_raw_scan_id_seq OWNER TO postgres;

--
-- Name: processed_event_scans_raw_scan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.processed_event_scans_raw_scan_id_seq OWNED BY public.processed_event_scans.raw_scan_id;


--
-- Name: processed_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.processed_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    algorithm_id public.algorithm_type NOT NULL,
    direction public.direction_type NOT NULL,
    tag_epc character varying(96) NOT NULL,
    user_id uuid,
    group_id integer NOT NULL,
    confidence real NOT NULL,
    centroid_separation_factor real NOT NULL,
    cluster_size_factor real NOT NULL,
    bilateral_coverage_factor real NOT NULL,
    rssi_trend_consistency_factor real,
    "timestamp" timestamp with time zone NOT NULL,
    cluster_started_at timestamp with time zone NOT NULL,
    cluster_ended_at timestamp with time zone NOT NULL,
    metadata jsonb,
    synced_to_integration boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    navigo3_record_id integer
);


ALTER TABLE public.processed_events OWNER TO postgres;

--
-- Name: raw_scans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.raw_scans (
    id bigint NOT NULL,
    lighthouse_id integer NOT NULL,
    epc character varying(96) NOT NULL,
    epc_length smallint,
    rssi_dbm integer,
    antenna_id smallint,
    frequency integer,
    sequence_number integer,
    detection_confidence real,
    timestamp_ms bigint NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    received_at timestamp with time zone DEFAULT now(),
    processed_at timestamp with time zone,
    orphaned_at timestamp with time zone,
    orphan_reason public.orphan_reason_type,
    source public.scan_source DEFAULT 'realtime'::public.scan_source NOT NULL,
    time_basis public.time_basis DEFAULT 'synced'::public.time_basis NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.raw_scans OWNER TO postgres;

--
-- Name: raw_scans_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.raw_scans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.raw_scans_id_seq OWNER TO postgres;

--
-- Name: raw_scans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.raw_scans_id_seq OWNED BY public.raw_scans.id;


--
-- Name: raw_scans_timestamp_ms_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.raw_scans_timestamp_ms_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.raw_scans_timestamp_ms_seq OWNER TO postgres;

--
-- Name: raw_scans_timestamp_ms_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.raw_scans_timestamp_ms_seq OWNED BY public.raw_scans.timestamp_ms;


--
-- Name: tag_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tag_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    tag_epc character varying(96) NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    deactivated_at timestamp with time zone,
    notes character varying(1000),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tag_assignments OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sync_id character varying(255),
    name character varying(255),
    email character varying(255),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: lighthouse_connection_events id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_connection_events ALTER COLUMN id SET DEFAULT nextval('public.lighthouse_connection_events_id_seq'::regclass);


--
-- Name: lighthouse_groups id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_groups ALTER COLUMN id SET DEFAULT nextval('public.lighthouse_groups_id_seq'::regclass);


--
-- Name: lighthouse_health_snapshots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_health_snapshots ALTER COLUMN id SET DEFAULT nextval('public.lighthouse_health_snapshots_id_seq'::regclass);


--
-- Name: lighthouses id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouses ALTER COLUMN id SET DEFAULT nextval('public.lighthouses_id_seq'::regclass);


--
-- Name: processed_event_scans raw_scan_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_event_scans ALTER COLUMN raw_scan_id SET DEFAULT nextval('public.processed_event_scans_raw_scan_id_seq'::regclass);


--
-- Name: raw_scans id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_scans ALTER COLUMN id SET DEFAULT nextval('public.raw_scans_id_seq'::regclass);


--
-- Name: raw_scans timestamp_ms; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_scans ALTER COLUMN timestamp_ms SET DEFAULT nextval('public.raw_scans_timestamp_ms_seq'::regclass);


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_logs (id, user_id, action, resource_type, resource_id, changes, "timestamp") FROM stdin;
\.


--
-- Data for Name: dashboard_users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.dashboard_users (id, username, password_hash, role, is_active, last_login, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: lighthouse_connection_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouse_connection_events (id, lighthouse_id, event_type, is_graceful, recorded_at) FROM stdin;
303	9	disconnected	t	2026-05-09 12:55:00.695105+02
304	10	disconnected	t	2026-05-09 12:55:03.034041+02
305	9	connected	\N	2026-05-09 12:55:17.106067+02
306	10	connected	\N	2026-05-09 12:55:18.516533+02
\.


--
-- Data for Name: lighthouse_groups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouse_groups (id, label, description, activity_timeout_ms, orphan_timeout_ms, created_at, updated_at) FROM stdin;
5	Test	\N	4000	8000	2026-05-08 22:50:40.19+02	2026-05-08 22:50:40.19+02
\.


--
-- Data for Name: lighthouse_health_snapshots; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouse_health_snapshots (id, lighthouse_id, uptime_sec, free_heap_bytes, min_free_heap_bytes, wifi_rssi_dbm, rfid_state, rfid_is_responsive, rfid_power_rail_present, rfid_fw_version, rfid_last_error, recorded_at) FROM stdin;
7524	9	9	189964	189548	-63	UNINITIALIZED	f	f	0.0	0	2026-05-09 12:55:17.415124+02
7525	10	7	193288	191216	-35	UNINITIALIZED	f	f	0.0	0	2026-05-09 12:55:18.572665+02
7526	9	21	170636	166036	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 12:55:29.289194+02
7527	10	19	170604	166012	-33	POWERED_OFF	t	t	129.3	0	2026-05-09 12:55:30.482461+02
7528	10	26	170372	166012	-35	UNKNOWN	t	t	129.3	0	2026-05-09 12:55:37.791659+02
7529	9	30	170404	166036	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:55:37.813026+02
7530	9	37	170404	166036	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:55:44.853792+02
7531	10	34	170372	165072	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:55:46.290908+02
7532	9	44	170404	166036	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 12:55:51.786845+02
7533	10	41	170372	165072	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:55:53.352813+02
7534	9	51	170404	166036	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 12:55:58.882555+02
7535	10	49	168820	164760	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:00.931934+02
7536	9	60	170404	165860	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:08.201774+02
7537	10	57	170372	164760	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:08.718104+02
7538	10	64	170372	161608	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:16.188337+02
7539	9	71	170404	163340	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:19.316879+02
7540	10	73	170372	161608	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:24.693843+02
7541	9	81	170404	163340	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:29.669532+02
7542	10	81	170372	161608	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:33.186737+02
7543	9	92	170404	163340	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:39.842919+02
7544	10	89	170372	161608	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:40.733697+02
7545	10	97	170236	161576	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:49.16152+02
7546	9	102	170404	158932	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:50.108251+02
7547	10	106	170236	160892	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:56:57.88559+02
7548	9	113	170404	156188	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:01.715082+02
7549	10	114	168672	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:05.95619+02
7550	9	124	170428	156188	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:12.200873+02
7551	10	122	170264	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:13.532735+02
7552	10	130	168700	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:22.243728+02
7553	9	135	170432	156188	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:23.260456+02
7554	10	138	170264	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:30.12775+02
7555	9	146	170432	156188	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:33.910606+02
7556	10	147	170256	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:38.518469+02
7557	9	156	170432	156188	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:44.151216+02
7558	10	156	170264	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:47.343397+02
7559	9	167	170432	156188	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:55.006373+02
7560	10	163	170264	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:57:55.187658+02
7561	10	172	170264	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:03.503796+02
7562	9	177	170432	156188	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:05.309176+02
7563	10	180	170268	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:11.869083+02
7564	9	188	170432	156188	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:16.407338+02
7565	10	188	170268	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:19.657092+02
7566	9	199	170432	156188	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:26.954564+02
7567	10	196	170268	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:28.162144+02
7569	9	210	170432	156188	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:38.115839+02
7570	10	212	170396	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:43.999416+02
7571	9	220	170432	156188	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:48.374649+02
7574	10	228	170396	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:59.620037+02
7577	10	244	170396	160892	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:59:16.197111+02
7568	10	205	170396	160892	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:36.488294+02
7572	10	220	170396	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:52.144762+02
7573	9	230	170432	156188	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:58:58.315812+02
7575	10	236	170396	160892	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:59:08.270005+02
7576	9	241	170432	156188	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:59:09.143437+02
7578	9	251	170300	156188	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 12:59:19.382954+02
7579	10	252	170396	160892	-33	RESPONSIVE	t	t	129.3	0	2026-05-09 12:59:23.991442+02
7580	9	261	170296	156188	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 12:59:29.315721+02
\.


--
-- Data for Name: lighthouses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouses (id, name, device_id, placement, comment, firmware_version, last_seen_at, is_active, config, group_id, created_at, canged_at) FROM stdin;
10	Red	68:FE:71:0D:D0:74	OUTSIDE	\N	\N	2026-05-09 12:59:23.993+02	t	{}	5	2026-05-08 22:52:09.26+02	2026-05-08 22:52:09.261586+02
9	Yellow	00:70:07:25:15:00	INSIDE	\N	\N	2026-05-09 12:59:29.317+02	t	{}	5	2026-05-08 22:51:30.087+02	2026-05-08 22:51:30.088128+02
\.


--
-- Data for Name: mqtt_clients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.mqtt_clients (id, lighthouse_id, client_id, connected_at, last_activity, is_connected, ip_address, created_at) FROM stdin;
\.


--
-- Data for Name: processed_event_scans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.processed_event_scans (processed_event_id, raw_scan_id) FROM stdin;
2bc37173-543c-46a7-871a-642a18790940	19687
de96e099-401f-4191-afa8-728c8e1def69	19687
2bc37173-543c-46a7-871a-642a18790940	19688
de96e099-401f-4191-afa8-728c8e1def69	19688
2bc37173-543c-46a7-871a-642a18790940	19689
de96e099-401f-4191-afa8-728c8e1def69	19689
2bc37173-543c-46a7-871a-642a18790940	19690
de96e099-401f-4191-afa8-728c8e1def69	19690
2bc37173-543c-46a7-871a-642a18790940	19691
de96e099-401f-4191-afa8-728c8e1def69	19691
2bc37173-543c-46a7-871a-642a18790940	19692
de96e099-401f-4191-afa8-728c8e1def69	19692
2bc37173-543c-46a7-871a-642a18790940	19693
de96e099-401f-4191-afa8-728c8e1def69	19693
2bc37173-543c-46a7-871a-642a18790940	19694
de96e099-401f-4191-afa8-728c8e1def69	19694
2bc37173-543c-46a7-871a-642a18790940	19695
de96e099-401f-4191-afa8-728c8e1def69	19695
2bc37173-543c-46a7-871a-642a18790940	19696
de96e099-401f-4191-afa8-728c8e1def69	19696
2bc37173-543c-46a7-871a-642a18790940	19697
de96e099-401f-4191-afa8-728c8e1def69	19697
2bc37173-543c-46a7-871a-642a18790940	19698
de96e099-401f-4191-afa8-728c8e1def69	19698
2bc37173-543c-46a7-871a-642a18790940	19699
de96e099-401f-4191-afa8-728c8e1def69	19699
2bc37173-543c-46a7-871a-642a18790940	19700
de96e099-401f-4191-afa8-728c8e1def69	19700
2bc37173-543c-46a7-871a-642a18790940	19701
de96e099-401f-4191-afa8-728c8e1def69	19701
2bc37173-543c-46a7-871a-642a18790940	19702
de96e099-401f-4191-afa8-728c8e1def69	19702
2bc37173-543c-46a7-871a-642a18790940	19703
de96e099-401f-4191-afa8-728c8e1def69	19703
2bc37173-543c-46a7-871a-642a18790940	19704
de96e099-401f-4191-afa8-728c8e1def69	19704
2bc37173-543c-46a7-871a-642a18790940	19705
de96e099-401f-4191-afa8-728c8e1def69	19705
2bc37173-543c-46a7-871a-642a18790940	19706
de96e099-401f-4191-afa8-728c8e1def69	19706
2bc37173-543c-46a7-871a-642a18790940	19707
de96e099-401f-4191-afa8-728c8e1def69	19707
2bc37173-543c-46a7-871a-642a18790940	19708
de96e099-401f-4191-afa8-728c8e1def69	19708
2bc37173-543c-46a7-871a-642a18790940	19709
de96e099-401f-4191-afa8-728c8e1def69	19709
2bc37173-543c-46a7-871a-642a18790940	19710
de96e099-401f-4191-afa8-728c8e1def69	19710
2bc37173-543c-46a7-871a-642a18790940	19711
de96e099-401f-4191-afa8-728c8e1def69	19711
2bc37173-543c-46a7-871a-642a18790940	19712
de96e099-401f-4191-afa8-728c8e1def69	19712
2bc37173-543c-46a7-871a-642a18790940	19713
de96e099-401f-4191-afa8-728c8e1def69	19713
2bc37173-543c-46a7-871a-642a18790940	19714
de96e099-401f-4191-afa8-728c8e1def69	19714
2bc37173-543c-46a7-871a-642a18790940	19715
de96e099-401f-4191-afa8-728c8e1def69	19715
2bc37173-543c-46a7-871a-642a18790940	19716
de96e099-401f-4191-afa8-728c8e1def69	19716
2bc37173-543c-46a7-871a-642a18790940	19717
de96e099-401f-4191-afa8-728c8e1def69	19717
2bc37173-543c-46a7-871a-642a18790940	19718
de96e099-401f-4191-afa8-728c8e1def69	19718
2bc37173-543c-46a7-871a-642a18790940	19719
de96e099-401f-4191-afa8-728c8e1def69	19719
2bc37173-543c-46a7-871a-642a18790940	19720
de96e099-401f-4191-afa8-728c8e1def69	19720
2bc37173-543c-46a7-871a-642a18790940	19721
de96e099-401f-4191-afa8-728c8e1def69	19721
2bc37173-543c-46a7-871a-642a18790940	19722
de96e099-401f-4191-afa8-728c8e1def69	19722
2bc37173-543c-46a7-871a-642a18790940	19723
de96e099-401f-4191-afa8-728c8e1def69	19723
2bc37173-543c-46a7-871a-642a18790940	19724
de96e099-401f-4191-afa8-728c8e1def69	19724
2bc37173-543c-46a7-871a-642a18790940	19725
de96e099-401f-4191-afa8-728c8e1def69	19725
2bc37173-543c-46a7-871a-642a18790940	19726
de96e099-401f-4191-afa8-728c8e1def69	19726
2bc37173-543c-46a7-871a-642a18790940	19727
de96e099-401f-4191-afa8-728c8e1def69	19727
2bc37173-543c-46a7-871a-642a18790940	19728
de96e099-401f-4191-afa8-728c8e1def69	19728
2bc37173-543c-46a7-871a-642a18790940	19729
de96e099-401f-4191-afa8-728c8e1def69	19729
2bc37173-543c-46a7-871a-642a18790940	19730
de96e099-401f-4191-afa8-728c8e1def69	19730
73502188-5f8c-4dab-a2b1-ef5f779938f6	19749
859d64f3-c923-4a07-8f5e-33fb82604345	19749
73502188-5f8c-4dab-a2b1-ef5f779938f6	19750
859d64f3-c923-4a07-8f5e-33fb82604345	19750
73502188-5f8c-4dab-a2b1-ef5f779938f6	19751
859d64f3-c923-4a07-8f5e-33fb82604345	19751
73502188-5f8c-4dab-a2b1-ef5f779938f6	19753
859d64f3-c923-4a07-8f5e-33fb82604345	19753
73502188-5f8c-4dab-a2b1-ef5f779938f6	19752
859d64f3-c923-4a07-8f5e-33fb82604345	19752
73502188-5f8c-4dab-a2b1-ef5f779938f6	19754
859d64f3-c923-4a07-8f5e-33fb82604345	19754
73502188-5f8c-4dab-a2b1-ef5f779938f6	19755
859d64f3-c923-4a07-8f5e-33fb82604345	19755
73502188-5f8c-4dab-a2b1-ef5f779938f6	19756
859d64f3-c923-4a07-8f5e-33fb82604345	19756
73502188-5f8c-4dab-a2b1-ef5f779938f6	19757
859d64f3-c923-4a07-8f5e-33fb82604345	19757
73502188-5f8c-4dab-a2b1-ef5f779938f6	19758
859d64f3-c923-4a07-8f5e-33fb82604345	19758
73502188-5f8c-4dab-a2b1-ef5f779938f6	19760
859d64f3-c923-4a07-8f5e-33fb82604345	19760
73502188-5f8c-4dab-a2b1-ef5f779938f6	19759
859d64f3-c923-4a07-8f5e-33fb82604345	19759
73502188-5f8c-4dab-a2b1-ef5f779938f6	19761
859d64f3-c923-4a07-8f5e-33fb82604345	19761
73502188-5f8c-4dab-a2b1-ef5f779938f6	19762
859d64f3-c923-4a07-8f5e-33fb82604345	19762
73502188-5f8c-4dab-a2b1-ef5f779938f6	19763
859d64f3-c923-4a07-8f5e-33fb82604345	19763
73502188-5f8c-4dab-a2b1-ef5f779938f6	19764
859d64f3-c923-4a07-8f5e-33fb82604345	19764
73502188-5f8c-4dab-a2b1-ef5f779938f6	19765
859d64f3-c923-4a07-8f5e-33fb82604345	19765
73502188-5f8c-4dab-a2b1-ef5f779938f6	19766
859d64f3-c923-4a07-8f5e-33fb82604345	19766
73502188-5f8c-4dab-a2b1-ef5f779938f6	19767
859d64f3-c923-4a07-8f5e-33fb82604345	19767
73502188-5f8c-4dab-a2b1-ef5f779938f6	19768
859d64f3-c923-4a07-8f5e-33fb82604345	19768
73502188-5f8c-4dab-a2b1-ef5f779938f6	19769
859d64f3-c923-4a07-8f5e-33fb82604345	19769
73502188-5f8c-4dab-a2b1-ef5f779938f6	19770
859d64f3-c923-4a07-8f5e-33fb82604345	19770
73502188-5f8c-4dab-a2b1-ef5f779938f6	19771
859d64f3-c923-4a07-8f5e-33fb82604345	19771
73502188-5f8c-4dab-a2b1-ef5f779938f6	19772
859d64f3-c923-4a07-8f5e-33fb82604345	19772
73502188-5f8c-4dab-a2b1-ef5f779938f6	19773
859d64f3-c923-4a07-8f5e-33fb82604345	19773
73502188-5f8c-4dab-a2b1-ef5f779938f6	19731
859d64f3-c923-4a07-8f5e-33fb82604345	19731
73502188-5f8c-4dab-a2b1-ef5f779938f6	19732
859d64f3-c923-4a07-8f5e-33fb82604345	19732
73502188-5f8c-4dab-a2b1-ef5f779938f6	19733
859d64f3-c923-4a07-8f5e-33fb82604345	19733
73502188-5f8c-4dab-a2b1-ef5f779938f6	19735
859d64f3-c923-4a07-8f5e-33fb82604345	19735
73502188-5f8c-4dab-a2b1-ef5f779938f6	19734
859d64f3-c923-4a07-8f5e-33fb82604345	19734
73502188-5f8c-4dab-a2b1-ef5f779938f6	19736
859d64f3-c923-4a07-8f5e-33fb82604345	19736
73502188-5f8c-4dab-a2b1-ef5f779938f6	19738
859d64f3-c923-4a07-8f5e-33fb82604345	19738
73502188-5f8c-4dab-a2b1-ef5f779938f6	19737
859d64f3-c923-4a07-8f5e-33fb82604345	19737
73502188-5f8c-4dab-a2b1-ef5f779938f6	19739
859d64f3-c923-4a07-8f5e-33fb82604345	19739
73502188-5f8c-4dab-a2b1-ef5f779938f6	19740
859d64f3-c923-4a07-8f5e-33fb82604345	19740
73502188-5f8c-4dab-a2b1-ef5f779938f6	19741
859d64f3-c923-4a07-8f5e-33fb82604345	19741
73502188-5f8c-4dab-a2b1-ef5f779938f6	19742
859d64f3-c923-4a07-8f5e-33fb82604345	19742
73502188-5f8c-4dab-a2b1-ef5f779938f6	19743
859d64f3-c923-4a07-8f5e-33fb82604345	19743
73502188-5f8c-4dab-a2b1-ef5f779938f6	19744
859d64f3-c923-4a07-8f5e-33fb82604345	19744
73502188-5f8c-4dab-a2b1-ef5f779938f6	19745
859d64f3-c923-4a07-8f5e-33fb82604345	19745
73502188-5f8c-4dab-a2b1-ef5f779938f6	19746
859d64f3-c923-4a07-8f5e-33fb82604345	19746
73502188-5f8c-4dab-a2b1-ef5f779938f6	19747
859d64f3-c923-4a07-8f5e-33fb82604345	19747
73502188-5f8c-4dab-a2b1-ef5f779938f6	19748
859d64f3-c923-4a07-8f5e-33fb82604345	19748
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19774
c36310ef-c11f-42a6-887e-e78859098ac2	19774
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19775
c36310ef-c11f-42a6-887e-e78859098ac2	19775
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19777
c36310ef-c11f-42a6-887e-e78859098ac2	19777
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19776
c36310ef-c11f-42a6-887e-e78859098ac2	19776
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19779
c36310ef-c11f-42a6-887e-e78859098ac2	19779
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19778
c36310ef-c11f-42a6-887e-e78859098ac2	19778
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19780
c36310ef-c11f-42a6-887e-e78859098ac2	19780
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19781
c36310ef-c11f-42a6-887e-e78859098ac2	19781
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19782
c36310ef-c11f-42a6-887e-e78859098ac2	19782
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19784
c36310ef-c11f-42a6-887e-e78859098ac2	19784
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19783
c36310ef-c11f-42a6-887e-e78859098ac2	19783
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19785
c36310ef-c11f-42a6-887e-e78859098ac2	19785
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19786
c36310ef-c11f-42a6-887e-e78859098ac2	19786
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19788
c36310ef-c11f-42a6-887e-e78859098ac2	19788
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19789
c36310ef-c11f-42a6-887e-e78859098ac2	19789
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19792
c36310ef-c11f-42a6-887e-e78859098ac2	19792
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19791
c36310ef-c11f-42a6-887e-e78859098ac2	19791
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19790
c36310ef-c11f-42a6-887e-e78859098ac2	19790
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19793
c36310ef-c11f-42a6-887e-e78859098ac2	19793
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19787
c36310ef-c11f-42a6-887e-e78859098ac2	19787
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19794
c36310ef-c11f-42a6-887e-e78859098ac2	19794
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19795
c36310ef-c11f-42a6-887e-e78859098ac2	19795
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19796
c36310ef-c11f-42a6-887e-e78859098ac2	19796
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19797
c36310ef-c11f-42a6-887e-e78859098ac2	19797
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19798
c36310ef-c11f-42a6-887e-e78859098ac2	19798
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19799
c36310ef-c11f-42a6-887e-e78859098ac2	19799
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19800
c36310ef-c11f-42a6-887e-e78859098ac2	19800
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19801
c36310ef-c11f-42a6-887e-e78859098ac2	19801
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19802
c36310ef-c11f-42a6-887e-e78859098ac2	19802
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19803
c36310ef-c11f-42a6-887e-e78859098ac2	19803
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19804
c36310ef-c11f-42a6-887e-e78859098ac2	19804
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19805
c36310ef-c11f-42a6-887e-e78859098ac2	19805
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19807
c36310ef-c11f-42a6-887e-e78859098ac2	19807
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19806
c36310ef-c11f-42a6-887e-e78859098ac2	19806
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19808
c36310ef-c11f-42a6-887e-e78859098ac2	19808
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19809
c36310ef-c11f-42a6-887e-e78859098ac2	19809
9dfaae2b-8acc-4298-a00b-e9e80fe48888	19810
c36310ef-c11f-42a6-887e-e78859098ac2	19810
8b44ee69-290f-4e89-94d2-a134710d6abf	19813
a81bea53-849b-44e5-8000-0643541595a4	19813
8b44ee69-290f-4e89-94d2-a134710d6abf	19814
a81bea53-849b-44e5-8000-0643541595a4	19814
8b44ee69-290f-4e89-94d2-a134710d6abf	19815
a81bea53-849b-44e5-8000-0643541595a4	19815
8b44ee69-290f-4e89-94d2-a134710d6abf	19817
a81bea53-849b-44e5-8000-0643541595a4	19817
8b44ee69-290f-4e89-94d2-a134710d6abf	19816
a81bea53-849b-44e5-8000-0643541595a4	19816
8b44ee69-290f-4e89-94d2-a134710d6abf	19819
a81bea53-849b-44e5-8000-0643541595a4	19819
8b44ee69-290f-4e89-94d2-a134710d6abf	19818
a81bea53-849b-44e5-8000-0643541595a4	19818
8b44ee69-290f-4e89-94d2-a134710d6abf	19821
a81bea53-849b-44e5-8000-0643541595a4	19821
8b44ee69-290f-4e89-94d2-a134710d6abf	19820
a81bea53-849b-44e5-8000-0643541595a4	19820
8b44ee69-290f-4e89-94d2-a134710d6abf	19823
a81bea53-849b-44e5-8000-0643541595a4	19823
8b44ee69-290f-4e89-94d2-a134710d6abf	19822
a81bea53-849b-44e5-8000-0643541595a4	19822
8b44ee69-290f-4e89-94d2-a134710d6abf	19825
a81bea53-849b-44e5-8000-0643541595a4	19825
8b44ee69-290f-4e89-94d2-a134710d6abf	19824
a81bea53-849b-44e5-8000-0643541595a4	19824
8b44ee69-290f-4e89-94d2-a134710d6abf	19826
a81bea53-849b-44e5-8000-0643541595a4	19826
8b44ee69-290f-4e89-94d2-a134710d6abf	19827
a81bea53-849b-44e5-8000-0643541595a4	19827
8b44ee69-290f-4e89-94d2-a134710d6abf	19828
a81bea53-849b-44e5-8000-0643541595a4	19828
8b44ee69-290f-4e89-94d2-a134710d6abf	19829
a81bea53-849b-44e5-8000-0643541595a4	19829
8b44ee69-290f-4e89-94d2-a134710d6abf	19830
a81bea53-849b-44e5-8000-0643541595a4	19830
8b44ee69-290f-4e89-94d2-a134710d6abf	19812
a81bea53-849b-44e5-8000-0643541595a4	19812
8b44ee69-290f-4e89-94d2-a134710d6abf	19811
a81bea53-849b-44e5-8000-0643541595a4	19811
d21431c4-6241-40d2-99f1-a16f142d9eb8	19831
787fe754-91a4-44dc-9448-b6c96a08c2a8	19831
d21431c4-6241-40d2-99f1-a16f142d9eb8	19833
787fe754-91a4-44dc-9448-b6c96a08c2a8	19833
d21431c4-6241-40d2-99f1-a16f142d9eb8	19832
787fe754-91a4-44dc-9448-b6c96a08c2a8	19832
d21431c4-6241-40d2-99f1-a16f142d9eb8	19834
787fe754-91a4-44dc-9448-b6c96a08c2a8	19834
d21431c4-6241-40d2-99f1-a16f142d9eb8	19836
787fe754-91a4-44dc-9448-b6c96a08c2a8	19836
d21431c4-6241-40d2-99f1-a16f142d9eb8	19835
787fe754-91a4-44dc-9448-b6c96a08c2a8	19835
d21431c4-6241-40d2-99f1-a16f142d9eb8	19837
787fe754-91a4-44dc-9448-b6c96a08c2a8	19837
d21431c4-6241-40d2-99f1-a16f142d9eb8	19838
787fe754-91a4-44dc-9448-b6c96a08c2a8	19838
d21431c4-6241-40d2-99f1-a16f142d9eb8	19839
787fe754-91a4-44dc-9448-b6c96a08c2a8	19839
d21431c4-6241-40d2-99f1-a16f142d9eb8	19840
787fe754-91a4-44dc-9448-b6c96a08c2a8	19840
d21431c4-6241-40d2-99f1-a16f142d9eb8	19841
787fe754-91a4-44dc-9448-b6c96a08c2a8	19841
d21431c4-6241-40d2-99f1-a16f142d9eb8	19842
787fe754-91a4-44dc-9448-b6c96a08c2a8	19842
d21431c4-6241-40d2-99f1-a16f142d9eb8	19843
787fe754-91a4-44dc-9448-b6c96a08c2a8	19843
d21431c4-6241-40d2-99f1-a16f142d9eb8	19844
787fe754-91a4-44dc-9448-b6c96a08c2a8	19844
d21431c4-6241-40d2-99f1-a16f142d9eb8	19846
787fe754-91a4-44dc-9448-b6c96a08c2a8	19846
d21431c4-6241-40d2-99f1-a16f142d9eb8	19845
787fe754-91a4-44dc-9448-b6c96a08c2a8	19845
d21431c4-6241-40d2-99f1-a16f142d9eb8	19847
787fe754-91a4-44dc-9448-b6c96a08c2a8	19847
d21431c4-6241-40d2-99f1-a16f142d9eb8	19848
787fe754-91a4-44dc-9448-b6c96a08c2a8	19848
d21431c4-6241-40d2-99f1-a16f142d9eb8	19849
787fe754-91a4-44dc-9448-b6c96a08c2a8	19849
d21431c4-6241-40d2-99f1-a16f142d9eb8	19850
787fe754-91a4-44dc-9448-b6c96a08c2a8	19850
d21431c4-6241-40d2-99f1-a16f142d9eb8	19853
787fe754-91a4-44dc-9448-b6c96a08c2a8	19853
d21431c4-6241-40d2-99f1-a16f142d9eb8	19851
787fe754-91a4-44dc-9448-b6c96a08c2a8	19851
d21431c4-6241-40d2-99f1-a16f142d9eb8	19854
787fe754-91a4-44dc-9448-b6c96a08c2a8	19854
d21431c4-6241-40d2-99f1-a16f142d9eb8	19852
787fe754-91a4-44dc-9448-b6c96a08c2a8	19852
d21431c4-6241-40d2-99f1-a16f142d9eb8	19856
787fe754-91a4-44dc-9448-b6c96a08c2a8	19856
d21431c4-6241-40d2-99f1-a16f142d9eb8	19855
787fe754-91a4-44dc-9448-b6c96a08c2a8	19855
d21431c4-6241-40d2-99f1-a16f142d9eb8	19857
787fe754-91a4-44dc-9448-b6c96a08c2a8	19857
d21431c4-6241-40d2-99f1-a16f142d9eb8	19862
787fe754-91a4-44dc-9448-b6c96a08c2a8	19862
d21431c4-6241-40d2-99f1-a16f142d9eb8	19861
787fe754-91a4-44dc-9448-b6c96a08c2a8	19861
d21431c4-6241-40d2-99f1-a16f142d9eb8	19860
787fe754-91a4-44dc-9448-b6c96a08c2a8	19860
d21431c4-6241-40d2-99f1-a16f142d9eb8	19859
787fe754-91a4-44dc-9448-b6c96a08c2a8	19859
d21431c4-6241-40d2-99f1-a16f142d9eb8	19858
787fe754-91a4-44dc-9448-b6c96a08c2a8	19858
d21431c4-6241-40d2-99f1-a16f142d9eb8	19865
787fe754-91a4-44dc-9448-b6c96a08c2a8	19865
d21431c4-6241-40d2-99f1-a16f142d9eb8	19863
787fe754-91a4-44dc-9448-b6c96a08c2a8	19863
d21431c4-6241-40d2-99f1-a16f142d9eb8	19864
787fe754-91a4-44dc-9448-b6c96a08c2a8	19864
d21431c4-6241-40d2-99f1-a16f142d9eb8	19867
787fe754-91a4-44dc-9448-b6c96a08c2a8	19867
d21431c4-6241-40d2-99f1-a16f142d9eb8	19866
787fe754-91a4-44dc-9448-b6c96a08c2a8	19866
d21431c4-6241-40d2-99f1-a16f142d9eb8	19868
787fe754-91a4-44dc-9448-b6c96a08c2a8	19868
d21431c4-6241-40d2-99f1-a16f142d9eb8	19869
787fe754-91a4-44dc-9448-b6c96a08c2a8	19869
d21431c4-6241-40d2-99f1-a16f142d9eb8	19871
787fe754-91a4-44dc-9448-b6c96a08c2a8	19871
d21431c4-6241-40d2-99f1-a16f142d9eb8	19870
787fe754-91a4-44dc-9448-b6c96a08c2a8	19870
d21431c4-6241-40d2-99f1-a16f142d9eb8	19872
787fe754-91a4-44dc-9448-b6c96a08c2a8	19872
d21431c4-6241-40d2-99f1-a16f142d9eb8	19873
787fe754-91a4-44dc-9448-b6c96a08c2a8	19873
d21431c4-6241-40d2-99f1-a16f142d9eb8	19874
787fe754-91a4-44dc-9448-b6c96a08c2a8	19874
d21431c4-6241-40d2-99f1-a16f142d9eb8	19875
787fe754-91a4-44dc-9448-b6c96a08c2a8	19875
d21431c4-6241-40d2-99f1-a16f142d9eb8	19876
787fe754-91a4-44dc-9448-b6c96a08c2a8	19876
d21431c4-6241-40d2-99f1-a16f142d9eb8	19877
787fe754-91a4-44dc-9448-b6c96a08c2a8	19877
d21431c4-6241-40d2-99f1-a16f142d9eb8	19878
787fe754-91a4-44dc-9448-b6c96a08c2a8	19878
d21431c4-6241-40d2-99f1-a16f142d9eb8	19879
787fe754-91a4-44dc-9448-b6c96a08c2a8	19879
d21431c4-6241-40d2-99f1-a16f142d9eb8	19880
787fe754-91a4-44dc-9448-b6c96a08c2a8	19880
d21431c4-6241-40d2-99f1-a16f142d9eb8	19881
787fe754-91a4-44dc-9448-b6c96a08c2a8	19881
d21431c4-6241-40d2-99f1-a16f142d9eb8	19882
787fe754-91a4-44dc-9448-b6c96a08c2a8	19882
d21431c4-6241-40d2-99f1-a16f142d9eb8	19883
787fe754-91a4-44dc-9448-b6c96a08c2a8	19883
d21431c4-6241-40d2-99f1-a16f142d9eb8	19884
787fe754-91a4-44dc-9448-b6c96a08c2a8	19884
d21431c4-6241-40d2-99f1-a16f142d9eb8	19885
787fe754-91a4-44dc-9448-b6c96a08c2a8	19885
d21431c4-6241-40d2-99f1-a16f142d9eb8	19886
787fe754-91a4-44dc-9448-b6c96a08c2a8	19886
d21431c4-6241-40d2-99f1-a16f142d9eb8	19888
787fe754-91a4-44dc-9448-b6c96a08c2a8	19888
d21431c4-6241-40d2-99f1-a16f142d9eb8	19887
787fe754-91a4-44dc-9448-b6c96a08c2a8	19887
d21431c4-6241-40d2-99f1-a16f142d9eb8	19889
787fe754-91a4-44dc-9448-b6c96a08c2a8	19889
d21431c4-6241-40d2-99f1-a16f142d9eb8	19891
787fe754-91a4-44dc-9448-b6c96a08c2a8	19891
d21431c4-6241-40d2-99f1-a16f142d9eb8	19890
787fe754-91a4-44dc-9448-b6c96a08c2a8	19890
d21431c4-6241-40d2-99f1-a16f142d9eb8	19892
787fe754-91a4-44dc-9448-b6c96a08c2a8	19892
d21431c4-6241-40d2-99f1-a16f142d9eb8	19893
787fe754-91a4-44dc-9448-b6c96a08c2a8	19893
d21431c4-6241-40d2-99f1-a16f142d9eb8	19898
787fe754-91a4-44dc-9448-b6c96a08c2a8	19898
d21431c4-6241-40d2-99f1-a16f142d9eb8	19894
787fe754-91a4-44dc-9448-b6c96a08c2a8	19894
d21431c4-6241-40d2-99f1-a16f142d9eb8	19896
787fe754-91a4-44dc-9448-b6c96a08c2a8	19896
d21431c4-6241-40d2-99f1-a16f142d9eb8	19895
787fe754-91a4-44dc-9448-b6c96a08c2a8	19895
d21431c4-6241-40d2-99f1-a16f142d9eb8	19897
787fe754-91a4-44dc-9448-b6c96a08c2a8	19897
13d764be-65a7-4974-8eaf-ef21b1fae49f	19909
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19909
13d764be-65a7-4974-8eaf-ef21b1fae49f	19908
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19908
13d764be-65a7-4974-8eaf-ef21b1fae49f	19910
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19910
13d764be-65a7-4974-8eaf-ef21b1fae49f	19911
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19911
13d764be-65a7-4974-8eaf-ef21b1fae49f	19912
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19912
13d764be-65a7-4974-8eaf-ef21b1fae49f	19899
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19899
13d764be-65a7-4974-8eaf-ef21b1fae49f	19900
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19900
13d764be-65a7-4974-8eaf-ef21b1fae49f	19902
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19902
13d764be-65a7-4974-8eaf-ef21b1fae49f	19901
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19901
13d764be-65a7-4974-8eaf-ef21b1fae49f	19903
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19903
13d764be-65a7-4974-8eaf-ef21b1fae49f	19905
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19905
13d764be-65a7-4974-8eaf-ef21b1fae49f	19904
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19904
13d764be-65a7-4974-8eaf-ef21b1fae49f	19906
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19906
13d764be-65a7-4974-8eaf-ef21b1fae49f	19907
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	19907
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19913
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19913
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19914
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19914
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19915
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19915
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19916
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19916
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19917
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19917
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19918
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19918
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19919
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19919
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19920
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19920
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19922
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19922
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19921
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19921
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19923
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19923
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19924
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19924
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19925
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19925
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19926
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19926
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19928
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19928
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19927
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19927
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19930
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19930
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19929
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19929
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19931
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19931
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19932
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19932
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19933
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19933
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19934
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19934
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19935
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19935
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19936
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19936
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19937
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19937
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19938
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19938
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19939
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19939
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19941
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19941
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19940
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19940
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19942
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19942
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19943
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19943
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19944
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19944
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19945
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19945
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19946
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19946
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19947
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19947
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19948
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19948
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19949
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19949
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19950
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19950
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19951
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19951
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19952
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19952
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19954
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19954
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19953
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19953
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19955
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19955
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19956
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19956
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19957
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19957
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19958
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19958
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19959
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19959
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19961
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19961
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19960
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19960
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19962
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19962
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19963
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19963
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	19964
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	19964
954d9d73-09fb-4898-acab-d422ea7f5a08	19979
dd410656-e94b-42e8-b446-6e25af60292a	19979
954d9d73-09fb-4898-acab-d422ea7f5a08	19980
dd410656-e94b-42e8-b446-6e25af60292a	19980
954d9d73-09fb-4898-acab-d422ea7f5a08	19981
dd410656-e94b-42e8-b446-6e25af60292a	19981
954d9d73-09fb-4898-acab-d422ea7f5a08	19982
dd410656-e94b-42e8-b446-6e25af60292a	19982
954d9d73-09fb-4898-acab-d422ea7f5a08	19983
dd410656-e94b-42e8-b446-6e25af60292a	19983
954d9d73-09fb-4898-acab-d422ea7f5a08	19984
dd410656-e94b-42e8-b446-6e25af60292a	19984
954d9d73-09fb-4898-acab-d422ea7f5a08	19985
dd410656-e94b-42e8-b446-6e25af60292a	19985
954d9d73-09fb-4898-acab-d422ea7f5a08	19986
dd410656-e94b-42e8-b446-6e25af60292a	19986
954d9d73-09fb-4898-acab-d422ea7f5a08	19987
dd410656-e94b-42e8-b446-6e25af60292a	19987
954d9d73-09fb-4898-acab-d422ea7f5a08	19988
dd410656-e94b-42e8-b446-6e25af60292a	19988
954d9d73-09fb-4898-acab-d422ea7f5a08	19990
dd410656-e94b-42e8-b446-6e25af60292a	19990
954d9d73-09fb-4898-acab-d422ea7f5a08	19989
dd410656-e94b-42e8-b446-6e25af60292a	19989
954d9d73-09fb-4898-acab-d422ea7f5a08	19991
dd410656-e94b-42e8-b446-6e25af60292a	19991
954d9d73-09fb-4898-acab-d422ea7f5a08	19992
dd410656-e94b-42e8-b446-6e25af60292a	19992
954d9d73-09fb-4898-acab-d422ea7f5a08	19993
dd410656-e94b-42e8-b446-6e25af60292a	19993
954d9d73-09fb-4898-acab-d422ea7f5a08	19994
dd410656-e94b-42e8-b446-6e25af60292a	19994
954d9d73-09fb-4898-acab-d422ea7f5a08	19995
dd410656-e94b-42e8-b446-6e25af60292a	19995
954d9d73-09fb-4898-acab-d422ea7f5a08	19996
dd410656-e94b-42e8-b446-6e25af60292a	19996
954d9d73-09fb-4898-acab-d422ea7f5a08	19997
dd410656-e94b-42e8-b446-6e25af60292a	19997
954d9d73-09fb-4898-acab-d422ea7f5a08	19998
dd410656-e94b-42e8-b446-6e25af60292a	19998
954d9d73-09fb-4898-acab-d422ea7f5a08	19999
dd410656-e94b-42e8-b446-6e25af60292a	19999
954d9d73-09fb-4898-acab-d422ea7f5a08	20001
dd410656-e94b-42e8-b446-6e25af60292a	20001
954d9d73-09fb-4898-acab-d422ea7f5a08	20000
dd410656-e94b-42e8-b446-6e25af60292a	20000
954d9d73-09fb-4898-acab-d422ea7f5a08	20002
dd410656-e94b-42e8-b446-6e25af60292a	20002
954d9d73-09fb-4898-acab-d422ea7f5a08	19965
dd410656-e94b-42e8-b446-6e25af60292a	19965
954d9d73-09fb-4898-acab-d422ea7f5a08	19966
dd410656-e94b-42e8-b446-6e25af60292a	19966
954d9d73-09fb-4898-acab-d422ea7f5a08	19967
dd410656-e94b-42e8-b446-6e25af60292a	19967
954d9d73-09fb-4898-acab-d422ea7f5a08	19968
dd410656-e94b-42e8-b446-6e25af60292a	19968
954d9d73-09fb-4898-acab-d422ea7f5a08	19969
dd410656-e94b-42e8-b446-6e25af60292a	19969
954d9d73-09fb-4898-acab-d422ea7f5a08	19970
dd410656-e94b-42e8-b446-6e25af60292a	19970
954d9d73-09fb-4898-acab-d422ea7f5a08	19972
dd410656-e94b-42e8-b446-6e25af60292a	19972
954d9d73-09fb-4898-acab-d422ea7f5a08	19971
dd410656-e94b-42e8-b446-6e25af60292a	19971
954d9d73-09fb-4898-acab-d422ea7f5a08	19973
dd410656-e94b-42e8-b446-6e25af60292a	19973
954d9d73-09fb-4898-acab-d422ea7f5a08	19975
dd410656-e94b-42e8-b446-6e25af60292a	19975
954d9d73-09fb-4898-acab-d422ea7f5a08	19974
dd410656-e94b-42e8-b446-6e25af60292a	19974
954d9d73-09fb-4898-acab-d422ea7f5a08	19977
dd410656-e94b-42e8-b446-6e25af60292a	19977
954d9d73-09fb-4898-acab-d422ea7f5a08	19976
dd410656-e94b-42e8-b446-6e25af60292a	19976
954d9d73-09fb-4898-acab-d422ea7f5a08	19978
dd410656-e94b-42e8-b446-6e25af60292a	19978
dd9755ca-fa58-4011-baf6-e809284f590e	20003
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20003
dd9755ca-fa58-4011-baf6-e809284f590e	20004
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20004
dd9755ca-fa58-4011-baf6-e809284f590e	20005
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20005
dd9755ca-fa58-4011-baf6-e809284f590e	20006
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20006
dd9755ca-fa58-4011-baf6-e809284f590e	20007
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20007
dd9755ca-fa58-4011-baf6-e809284f590e	20008
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20008
dd9755ca-fa58-4011-baf6-e809284f590e	20009
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20009
dd9755ca-fa58-4011-baf6-e809284f590e	20010
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20010
dd9755ca-fa58-4011-baf6-e809284f590e	20011
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20011
dd9755ca-fa58-4011-baf6-e809284f590e	20012
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20012
dd9755ca-fa58-4011-baf6-e809284f590e	20013
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20013
dd9755ca-fa58-4011-baf6-e809284f590e	20015
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20015
dd9755ca-fa58-4011-baf6-e809284f590e	20014
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20014
dd9755ca-fa58-4011-baf6-e809284f590e	20016
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20016
dd9755ca-fa58-4011-baf6-e809284f590e	20017
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20017
dd9755ca-fa58-4011-baf6-e809284f590e	20018
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20018
dd9755ca-fa58-4011-baf6-e809284f590e	20020
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20020
dd9755ca-fa58-4011-baf6-e809284f590e	20019
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20019
dd9755ca-fa58-4011-baf6-e809284f590e	20021
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20021
dd9755ca-fa58-4011-baf6-e809284f590e	20022
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20022
dd9755ca-fa58-4011-baf6-e809284f590e	20023
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20023
dd9755ca-fa58-4011-baf6-e809284f590e	20025
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20025
dd9755ca-fa58-4011-baf6-e809284f590e	20024
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20024
dd9755ca-fa58-4011-baf6-e809284f590e	20026
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20026
dd9755ca-fa58-4011-baf6-e809284f590e	20027
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20027
dd9755ca-fa58-4011-baf6-e809284f590e	20028
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20028
dd9755ca-fa58-4011-baf6-e809284f590e	20029
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20029
dd9755ca-fa58-4011-baf6-e809284f590e	20030
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20030
dd9755ca-fa58-4011-baf6-e809284f590e	20040
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20040
dd9755ca-fa58-4011-baf6-e809284f590e	20041
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20041
dd9755ca-fa58-4011-baf6-e809284f590e	20042
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20042
dd9755ca-fa58-4011-baf6-e809284f590e	20031
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20031
dd9755ca-fa58-4011-baf6-e809284f590e	20032
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20032
dd9755ca-fa58-4011-baf6-e809284f590e	20033
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20033
dd9755ca-fa58-4011-baf6-e809284f590e	20035
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20035
dd9755ca-fa58-4011-baf6-e809284f590e	20034
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20034
dd9755ca-fa58-4011-baf6-e809284f590e	20036
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20036
dd9755ca-fa58-4011-baf6-e809284f590e	20037
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20037
dd9755ca-fa58-4011-baf6-e809284f590e	20039
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20039
dd9755ca-fa58-4011-baf6-e809284f590e	20038
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20038
dd9755ca-fa58-4011-baf6-e809284f590e	20043
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20043
dd9755ca-fa58-4011-baf6-e809284f590e	20045
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20045
dd9755ca-fa58-4011-baf6-e809284f590e	20044
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20044
dd9755ca-fa58-4011-baf6-e809284f590e	20047
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20047
dd9755ca-fa58-4011-baf6-e809284f590e	20046
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20046
dd9755ca-fa58-4011-baf6-e809284f590e	20048
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20048
dd9755ca-fa58-4011-baf6-e809284f590e	20050
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20050
dd9755ca-fa58-4011-baf6-e809284f590e	20049
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20049
dd9755ca-fa58-4011-baf6-e809284f590e	20051
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20051
dd9755ca-fa58-4011-baf6-e809284f590e	20052
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20052
dd9755ca-fa58-4011-baf6-e809284f590e	20053
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20053
dd9755ca-fa58-4011-baf6-e809284f590e	20054
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20054
dd9755ca-fa58-4011-baf6-e809284f590e	20056
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20056
dd9755ca-fa58-4011-baf6-e809284f590e	20055
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20055
dd9755ca-fa58-4011-baf6-e809284f590e	20057
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20057
dd9755ca-fa58-4011-baf6-e809284f590e	20058
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20058
dd9755ca-fa58-4011-baf6-e809284f590e	20059
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20059
dd9755ca-fa58-4011-baf6-e809284f590e	20060
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	20060
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20070
ee46a503-065b-4760-8c7d-933f3c0a551c	20070
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20071
ee46a503-065b-4760-8c7d-933f3c0a551c	20071
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20072
ee46a503-065b-4760-8c7d-933f3c0a551c	20072
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20073
ee46a503-065b-4760-8c7d-933f3c0a551c	20073
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20074
ee46a503-065b-4760-8c7d-933f3c0a551c	20074
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20075
ee46a503-065b-4760-8c7d-933f3c0a551c	20075
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20076
ee46a503-065b-4760-8c7d-933f3c0a551c	20076
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20078
ee46a503-065b-4760-8c7d-933f3c0a551c	20078
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20077
ee46a503-065b-4760-8c7d-933f3c0a551c	20077
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20079
ee46a503-065b-4760-8c7d-933f3c0a551c	20079
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20080
ee46a503-065b-4760-8c7d-933f3c0a551c	20080
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20081
ee46a503-065b-4760-8c7d-933f3c0a551c	20081
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20082
ee46a503-065b-4760-8c7d-933f3c0a551c	20082
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20083
ee46a503-065b-4760-8c7d-933f3c0a551c	20083
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20084
ee46a503-065b-4760-8c7d-933f3c0a551c	20084
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20061
ee46a503-065b-4760-8c7d-933f3c0a551c	20061
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20062
ee46a503-065b-4760-8c7d-933f3c0a551c	20062
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20063
ee46a503-065b-4760-8c7d-933f3c0a551c	20063
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20065
ee46a503-065b-4760-8c7d-933f3c0a551c	20065
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20064
ee46a503-065b-4760-8c7d-933f3c0a551c	20064
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20066
ee46a503-065b-4760-8c7d-933f3c0a551c	20066
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20067
ee46a503-065b-4760-8c7d-933f3c0a551c	20067
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20068
ee46a503-065b-4760-8c7d-933f3c0a551c	20068
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	20069
ee46a503-065b-4760-8c7d-933f3c0a551c	20069
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20085
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20085
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20086
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20086
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20087
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20087
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20088
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20088
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20089
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20089
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20091
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20091
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20090
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20090
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20092
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20092
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20093
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20093
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20094
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20094
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20095
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20095
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20097
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20097
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20096
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20096
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20098
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20098
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20099
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20099
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20100
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20100
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20101
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20101
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20102
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20102
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20103
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20103
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20104
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20104
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20105
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20105
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20109
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20109
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20110
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20110
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20119
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20119
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20118
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20118
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20107
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20107
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20106
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20106
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20108
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20108
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20111
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20111
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20112
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20112
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20113
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20113
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20114
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20114
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20115
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20115
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20116
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20116
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20117
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20117
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20121
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20121
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20120
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20120
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20122
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20122
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20124
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20124
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20123
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20123
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20125
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20125
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20127
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20127
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20126
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20126
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20128
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20128
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20130
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20130
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20129
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20129
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20131
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20131
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20133
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20133
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20132
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20132
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20134
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20134
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20135
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20135
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20136
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20136
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	20137
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	20137
8915f3d9-b351-4152-a2b5-21a1ccde0249	20152
72910f1c-05bc-4eae-845e-351e6cb632a8	20152
8915f3d9-b351-4152-a2b5-21a1ccde0249	20150
72910f1c-05bc-4eae-845e-351e6cb632a8	20150
8915f3d9-b351-4152-a2b5-21a1ccde0249	20151
72910f1c-05bc-4eae-845e-351e6cb632a8	20151
8915f3d9-b351-4152-a2b5-21a1ccde0249	20153
72910f1c-05bc-4eae-845e-351e6cb632a8	20153
8915f3d9-b351-4152-a2b5-21a1ccde0249	20154
72910f1c-05bc-4eae-845e-351e6cb632a8	20154
8915f3d9-b351-4152-a2b5-21a1ccde0249	20156
72910f1c-05bc-4eae-845e-351e6cb632a8	20156
8915f3d9-b351-4152-a2b5-21a1ccde0249	20155
72910f1c-05bc-4eae-845e-351e6cb632a8	20155
8915f3d9-b351-4152-a2b5-21a1ccde0249	20157
72910f1c-05bc-4eae-845e-351e6cb632a8	20157
8915f3d9-b351-4152-a2b5-21a1ccde0249	20159
72910f1c-05bc-4eae-845e-351e6cb632a8	20159
8915f3d9-b351-4152-a2b5-21a1ccde0249	20158
72910f1c-05bc-4eae-845e-351e6cb632a8	20158
8915f3d9-b351-4152-a2b5-21a1ccde0249	20161
72910f1c-05bc-4eae-845e-351e6cb632a8	20161
8915f3d9-b351-4152-a2b5-21a1ccde0249	20160
72910f1c-05bc-4eae-845e-351e6cb632a8	20160
8915f3d9-b351-4152-a2b5-21a1ccde0249	20162
72910f1c-05bc-4eae-845e-351e6cb632a8	20162
8915f3d9-b351-4152-a2b5-21a1ccde0249	20164
72910f1c-05bc-4eae-845e-351e6cb632a8	20164
8915f3d9-b351-4152-a2b5-21a1ccde0249	20163
72910f1c-05bc-4eae-845e-351e6cb632a8	20163
8915f3d9-b351-4152-a2b5-21a1ccde0249	20165
72910f1c-05bc-4eae-845e-351e6cb632a8	20165
8915f3d9-b351-4152-a2b5-21a1ccde0249	20166
72910f1c-05bc-4eae-845e-351e6cb632a8	20166
8915f3d9-b351-4152-a2b5-21a1ccde0249	20167
72910f1c-05bc-4eae-845e-351e6cb632a8	20167
8915f3d9-b351-4152-a2b5-21a1ccde0249	20168
72910f1c-05bc-4eae-845e-351e6cb632a8	20168
8915f3d9-b351-4152-a2b5-21a1ccde0249	20169
72910f1c-05bc-4eae-845e-351e6cb632a8	20169
8915f3d9-b351-4152-a2b5-21a1ccde0249	20170
72910f1c-05bc-4eae-845e-351e6cb632a8	20170
8915f3d9-b351-4152-a2b5-21a1ccde0249	20139
72910f1c-05bc-4eae-845e-351e6cb632a8	20139
8915f3d9-b351-4152-a2b5-21a1ccde0249	20138
72910f1c-05bc-4eae-845e-351e6cb632a8	20138
8915f3d9-b351-4152-a2b5-21a1ccde0249	20140
72910f1c-05bc-4eae-845e-351e6cb632a8	20140
8915f3d9-b351-4152-a2b5-21a1ccde0249	20141
72910f1c-05bc-4eae-845e-351e6cb632a8	20141
8915f3d9-b351-4152-a2b5-21a1ccde0249	20142
72910f1c-05bc-4eae-845e-351e6cb632a8	20142
8915f3d9-b351-4152-a2b5-21a1ccde0249	20143
72910f1c-05bc-4eae-845e-351e6cb632a8	20143
8915f3d9-b351-4152-a2b5-21a1ccde0249	20144
72910f1c-05bc-4eae-845e-351e6cb632a8	20144
8915f3d9-b351-4152-a2b5-21a1ccde0249	20145
72910f1c-05bc-4eae-845e-351e6cb632a8	20145
8915f3d9-b351-4152-a2b5-21a1ccde0249	20146
72910f1c-05bc-4eae-845e-351e6cb632a8	20146
8915f3d9-b351-4152-a2b5-21a1ccde0249	20147
72910f1c-05bc-4eae-845e-351e6cb632a8	20147
8915f3d9-b351-4152-a2b5-21a1ccde0249	20149
72910f1c-05bc-4eae-845e-351e6cb632a8	20149
8915f3d9-b351-4152-a2b5-21a1ccde0249	20148
72910f1c-05bc-4eae-845e-351e6cb632a8	20148
a38293da-2a84-4d50-b568-3ae02ab7defa	20171
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20171
a38293da-2a84-4d50-b568-3ae02ab7defa	20172
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20172
a38293da-2a84-4d50-b568-3ae02ab7defa	20173
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20173
a38293da-2a84-4d50-b568-3ae02ab7defa	20174
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20174
a38293da-2a84-4d50-b568-3ae02ab7defa	20175
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20175
a38293da-2a84-4d50-b568-3ae02ab7defa	20177
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20177
a38293da-2a84-4d50-b568-3ae02ab7defa	20176
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20176
a38293da-2a84-4d50-b568-3ae02ab7defa	20178
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20178
a38293da-2a84-4d50-b568-3ae02ab7defa	20179
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20179
a38293da-2a84-4d50-b568-3ae02ab7defa	20181
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20181
a38293da-2a84-4d50-b568-3ae02ab7defa	20180
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20180
a38293da-2a84-4d50-b568-3ae02ab7defa	20182
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20182
a38293da-2a84-4d50-b568-3ae02ab7defa	20184
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20184
a38293da-2a84-4d50-b568-3ae02ab7defa	20183
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20183
a38293da-2a84-4d50-b568-3ae02ab7defa	20185
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20185
a38293da-2a84-4d50-b568-3ae02ab7defa	20186
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20186
a38293da-2a84-4d50-b568-3ae02ab7defa	20187
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20187
a38293da-2a84-4d50-b568-3ae02ab7defa	20188
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20188
a38293da-2a84-4d50-b568-3ae02ab7defa	20189
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20189
a38293da-2a84-4d50-b568-3ae02ab7defa	20190
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20190
a38293da-2a84-4d50-b568-3ae02ab7defa	20191
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20191
a38293da-2a84-4d50-b568-3ae02ab7defa	20192
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20192
a38293da-2a84-4d50-b568-3ae02ab7defa	20193
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20193
a38293da-2a84-4d50-b568-3ae02ab7defa	20194
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20194
a38293da-2a84-4d50-b568-3ae02ab7defa	20195
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20195
a38293da-2a84-4d50-b568-3ae02ab7defa	20196
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20196
a38293da-2a84-4d50-b568-3ae02ab7defa	20198
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20198
a38293da-2a84-4d50-b568-3ae02ab7defa	20197
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20197
a38293da-2a84-4d50-b568-3ae02ab7defa	20199
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20199
a38293da-2a84-4d50-b568-3ae02ab7defa	20200
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20200
a38293da-2a84-4d50-b568-3ae02ab7defa	20201
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20201
a38293da-2a84-4d50-b568-3ae02ab7defa	20202
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20202
a38293da-2a84-4d50-b568-3ae02ab7defa	20204
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20204
a38293da-2a84-4d50-b568-3ae02ab7defa	20203
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20203
a38293da-2a84-4d50-b568-3ae02ab7defa	20205
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20205
a38293da-2a84-4d50-b568-3ae02ab7defa	20206
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20206
a38293da-2a84-4d50-b568-3ae02ab7defa	20207
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20207
a38293da-2a84-4d50-b568-3ae02ab7defa	20208
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20208
a38293da-2a84-4d50-b568-3ae02ab7defa	20209
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20209
a38293da-2a84-4d50-b568-3ae02ab7defa	20210
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20210
a38293da-2a84-4d50-b568-3ae02ab7defa	20211
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20211
a38293da-2a84-4d50-b568-3ae02ab7defa	20212
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20212
a38293da-2a84-4d50-b568-3ae02ab7defa	20214
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20214
a38293da-2a84-4d50-b568-3ae02ab7defa	20213
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20213
a38293da-2a84-4d50-b568-3ae02ab7defa	20215
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20215
a38293da-2a84-4d50-b568-3ae02ab7defa	20216
b49f332e-cd74-47bf-b9b0-781d2b3e887e	20216
07df0c06-007c-4987-adce-c956632c6582	20228
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20228
07df0c06-007c-4987-adce-c956632c6582	20227
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20227
07df0c06-007c-4987-adce-c956632c6582	20230
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20230
07df0c06-007c-4987-adce-c956632c6582	20229
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20229
07df0c06-007c-4987-adce-c956632c6582	20231
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20231
07df0c06-007c-4987-adce-c956632c6582	20232
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20232
07df0c06-007c-4987-adce-c956632c6582	20217
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20217
07df0c06-007c-4987-adce-c956632c6582	20218
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20218
07df0c06-007c-4987-adce-c956632c6582	20219
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20219
07df0c06-007c-4987-adce-c956632c6582	20220
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20220
07df0c06-007c-4987-adce-c956632c6582	20221
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20221
07df0c06-007c-4987-adce-c956632c6582	20222
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20222
07df0c06-007c-4987-adce-c956632c6582	20223
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20223
07df0c06-007c-4987-adce-c956632c6582	20224
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20224
07df0c06-007c-4987-adce-c956632c6582	20226
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20226
07df0c06-007c-4987-adce-c956632c6582	20225
a3c2f437-4d1c-40fd-a339-1b66eda062b9	20225
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20233
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20233
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20234
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20234
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20235
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20235
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20236
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20236
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20237
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20237
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20238
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20238
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20239
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20239
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20240
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20240
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20241
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20241
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20242
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20242
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20243
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20243
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20244
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20244
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20245
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20245
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20246
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20246
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20248
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20248
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20247
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20247
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20250
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20250
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20249
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20249
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20251
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20251
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20254
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20254
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20253
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20253
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20257
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20257
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20258
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20258
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20259
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20259
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20260
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20260
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20264
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20264
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20266
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20266
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20267
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20267
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20269
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20269
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20268
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20268
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20252
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20252
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20255
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20255
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20256
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20256
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20261
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20261
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20262
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20262
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20263
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20263
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20265
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20265
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20271
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20271
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20270
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20270
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20272
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20272
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20274
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20274
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20273
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20273
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20275
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20275
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20277
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20277
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20276
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20276
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20278
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20278
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20279
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20279
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20280
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20280
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20281
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20281
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20282
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20282
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20283
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20283
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20284
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20284
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20286
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20286
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20285
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20285
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20287
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20287
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20289
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20289
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20288
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20288
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20290
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20290
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20291
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20291
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20292
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20292
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20293
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20293
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20294
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20294
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	20295
7281b4cd-ab55-4859-bae4-4f01a6f125e3	20295
\.


--
-- Data for Name: processed_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.processed_events (id, algorithm_id, direction, tag_epc, user_id, group_id, confidence, centroid_separation_factor, cluster_size_factor, bilateral_coverage_factor, rssi_trend_consistency_factor, "timestamp", cluster_started_at, cluster_ended_at, metadata, synced_to_integration, created_at, navigo3_record_id) FROM stdin;
de96e099-401f-4191-afa8-728c8e1def69	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.19712068	0.5187386	1	0.76	0.5	2026-05-09 12:56:00.4+02	2026-05-09 12:55:59.295+02	2026-05-09 12:56:03.319+02	{"rssiTrend": {"inside": {"r2": 0.07449568162118436, "slope": 0.002185672176775945}, "outside": {"r2": 0.000053038746222755506, "slope": -0.00005559763310146519}}, "rssiWeights": {"inside": [0.31999999999999995, 0.31999999999999995, 0.43999999999999995, 0.33999999999999997, 0.4, 0.45999999999999996, 0.43999999999999995, 0.54, 0.4, 0.42000000000000004, 0.52, 0.52, 0.56, 0.5, 0.5, 0.26, 0.45999999999999996, 0.43999999999999995, 0.38], "outside": [0.31999999999999995, 0.38, 0.48, 0.33999999999999997, 0.54, 0.42000000000000004, 0.6, 0.4, 0.5, 0.52, 0.52, 0.5800000000000001, 0.5800000000000001, 0.52, 0.56, 0.52, 0.5800000000000001, 0.56, 0.52, 0.43999999999999995, 0.42000000000000004, 0.4, 0.43999999999999995, 0.33999999999999997, 0.31999999999999995]}, "centroidDeltaMs": 2087.404296875, "insideScanCount": 19, "insideCentroidMs": 1778324162487.8318, "outsideScanCount": 25, "clusterDurationMs": 4024, "outsideCentroidMs": 1778324160400.4275}	f	2026-05-09 12:56:09.103326+02	\N
2bc37173-543c-46a7-871a-642a18790940	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.38929626	0.5122319	1	0.76	\N	2026-05-09 12:56:00.401+02	2026-05-09 12:55:59.295+02	2026-05-09 12:56:03.319+02	{"centroidDeltaMs": 2061.22119140625, "insideScanCount": 19, "insideCentroidMs": 1778324162462.4211, "outsideScanCount": 25, "clusterDurationMs": 4024, "outsideCentroidMs": 1778324160401.2}	t	2026-05-09 12:56:09.103326+02	\N
859d64f3-c923-4a07-8f5e-33fb82604345	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.2613733	0.51859784	1	0.72	0.7	2026-05-09 12:56:17.898+02	2026-05-09 12:56:16.688+02	2026-05-09 12:56:20.751+02	{"rssiTrend": {"inside": {"r2": 0.08133162721536236, "slope": 0.003310461205665599}, "outside": {"r2": 0.3725193922713781, "slope": 0.005866468557495649}}, "rssiWeights": {"inside": [0.28, 0.38, 0.33999999999999997, 0.38, 0.33999999999999997, 0.4, 0.6, 0.54, 0.6599999999999999, 0.54, 0.56, 0.5800000000000001, 0.64, 0.54, 0.4, 0.54, 0.33999999999999997, 0.26], "outside": [0.26, 0.19999999999999996, 0.26, 0.33999999999999997, 0.36, 0.31999999999999995, 0.38, 0.43999999999999995, 0.38, 0.31999999999999995, 0.31999999999999995, 0.33999999999999997, 0.4, 0.42000000000000004, 0.45999999999999996, 0.54, 0.5800000000000001, 0.56, 0.5800000000000001, 0.5800000000000001, 0.5800000000000001, 0.45999999999999996, 0.52, 0.4, 0.19999999999999996]}, "centroidDeltaMs": 2107.06298828125, "insideScanCount": 18, "insideCentroidMs": 1778324177898.5842, "outsideScanCount": 25, "clusterDurationMs": 4063, "outsideCentroidMs": 1778324180005.6472}	f	2026-05-09 12:56:25.11721+02	\N
73502188-5f8c-4dab-a2b1-ef5f779938f6	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3616319	0.5022665	1	0.72	\N	2026-05-09 12:56:17.857+02	2026-05-09 12:56:16.688+02	2026-05-09 12:56:20.751+02	{"centroidDeltaMs": 2040.708984375, "insideScanCount": 18, "insideCentroidMs": 1778324177857.611, "outsideScanCount": 25, "clusterDurationMs": 4063, "outsideCentroidMs": 1778324179898.32}	t	2026-05-09 12:56:25.11721+02	\N
c36310ef-c11f-42a6-887e-e78859098ac2	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.32556027	0.49092424	1	0.94736844	0.7	2026-05-09 12:56:29.325+02	2026-05-09 12:56:27.796+02	2026-05-09 12:56:32.265+02	{"rssiTrend": {"inside": {"r2": 0.4042068975126857, "slope": 0.004693448827933405}, "outside": {"r2": 0.059025223959841444, "slope": 0.0025035874661392806}}, "rssiWeights": {"inside": [0.38, 0.33999999999999997, 0.33999999999999997, 0.33999999999999997, 0.38, 0.4, 0.43999999999999995, 0.38, 0.5, 0.36, 0.43999999999999995, 0.5, 0.52, 0.6, 0.45999999999999996, 0.4, 0.38, 0.6], "outside": [0.28, 0.31999999999999995, 0.38, 0.21999999999999997, 0.54, 0.45999999999999996, 0.52, 0.62, 0.62, 0.62, 0.62, 0.56, 0.4, 0.54, 0.33999999999999997, 0.31999999999999995, 0.36, 0.4, 0.4]}, "centroidDeltaMs": 2193.9404296875, "insideScanCount": 18, "insideCentroidMs": 1778324191519.356, "outsideScanCount": 19, "clusterDurationMs": 4469, "outsideCentroidMs": 1778324189325.4155}	f	2026-05-09 12:56:37.125218+02	\N
9dfaae2b-8acc-4298-a00b-e9e80fe48888	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.45994416	0.4854966	1	0.94736844	\N	2026-05-09 12:56:29.284+02	2026-05-09 12:56:27.796+02	2026-05-09 12:56:32.265+02	{"centroidDeltaMs": 2169.684326171875, "insideScanCount": 18, "insideCentroidMs": 1778324191454, "outsideScanCount": 19, "clusterDurationMs": 4469, "outsideCentroidMs": 1778324189284.3157}	t	2026-05-09 12:56:37.125218+02	\N
a81bea53-849b-44e5-8000-0643541595a4	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.04534689	0.816244	1	0.11111111	0.5	2026-05-09 12:56:41.263+02	2026-05-09 12:56:41.263+02	2026-05-09 12:56:44.895+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.0848758619192358, "slope": -0.0025735917916080396}}, "rssiWeights": {"inside": [0.33999999999999997, 0.33999999999999997], "outside": [0.42000000000000004, 0.6, 0.54, 0.54, 0.52, 0.64, 0.64, 0.52, 0.64, 0.5, 0.4, 0.45999999999999996, 0.56, 0.56, 0.56, 0.45999999999999996, 0.43999999999999995, 0.45999999999999996]}, "centroidDeltaMs": 2964.59814453125, "insideScanCount": 2, "insideCentroidMs": 1778324201263, "outsideScanCount": 18, "clusterDurationMs": 3632, "outsideCentroidMs": 1778324204227.5981}	f	2026-05-09 12:56:49.134067+02	\N
8b44ee69-290f-4e89-94d2-a134710d6abf	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.091209136	0.82088226	1	0.11111111	\N	2026-05-09 12:56:41.263+02	2026-05-09 12:56:41.263+02	2026-05-09 12:56:44.895+02	{"centroidDeltaMs": 2981.4443359375, "insideScanCount": 2, "insideCentroidMs": 1778324201263, "outsideScanCount": 18, "clusterDurationMs": 3632, "outsideCentroidMs": 1778324204244.4443}	t	2026-05-09 12:56:49.134067+02	\N
d21431c4-6241-40d2-99f1-a16f142d9eb8	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.33187395	0.42037368	1	0.7894737	\N	2026-05-09 12:56:52.742+02	2026-05-09 12:56:51.345+02	2026-05-09 12:56:56.862+02	{"centroidDeltaMs": 2319.20166015625, "insideScanCount": 38, "insideCentroidMs": 1778324215061.8684, "outsideScanCount": 30, "clusterDurationMs": 5517, "outsideCentroidMs": 1778324212742.6667}	t	2026-05-09 12:57:01.148719+02	\N
4d19d6fa-bc92-44ae-926e-3c79fd5657f4	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.4704784	0.50811666	1	0.9259259	\N	2026-05-09 12:57:16.433+02	2026-05-09 12:57:15.362+02	2026-05-09 12:57:19.968+02	{"centroidDeltaMs": 2340.38525390625, "insideScanCount": 25, "insideCentroidMs": 1778324238774.2, "outsideScanCount": 27, "clusterDurationMs": 4606, "outsideCentroidMs": 1778324236433.8147}	t	2026-05-09 12:57:25.168211+02	\N
a3c2f437-4d1c-40fd-a339-1b66eda062b9	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23516458	0.78388196	1	0.6	0.5	2026-05-09 12:58:45.621+02	2026-05-09 12:58:45.181+02	2026-05-09 12:58:48.055+02	{"rssiTrend": {"inside": {"r2": 0.1528820323722374, "slope": 0.00312097814509522}, "outside": {"r2": 0.03322110492607866, "slope": 0.004459208714909918}}, "rssiWeights": {"inside": [0.43999999999999995, 0.38, 0.45999999999999996, 0.54, 0.43999999999999995, 0.45999999999999996, 0.38, 0.52, 0.52, 0.45999999999999996], "outside": [0.45999999999999996, 0.42000000000000004, 0.5, 0.38, 0.54, 0.45999999999999996]}, "centroidDeltaMs": 2252.876708984375, "insideScanCount": 10, "insideCentroidMs": 1778324325621.2827, "outsideScanCount": 6, "clusterDurationMs": 2874, "outsideCentroidMs": 1778324327874.1594}	f	2026-05-09 12:58:53.244049+02	\N
787fe754-91a4-44dc-9448-b6c96a08c2a8	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.13570224	0.42972374	1	0.7894737	0.4	2026-05-09 12:56:52.823+02	2026-05-09 12:56:51.345+02	2026-05-09 12:56:56.862+02	{"rssiTrend": {"inside": {"r2": 0.2863798650531668, "slope": 0.0030957410202896063}, "outside": {"r2": 0.3880376207920113, "slope": 0.004422807996921572}}, "rssiWeights": {"inside": [0.43999999999999995, 0.31999999999999995, 0.38, 0.36, 0.31999999999999995, 0.33999999999999997, 0.26, 0.43999999999999995, 0.42000000000000004, 0.45999999999999996, 0.33999999999999997, 0.52, 0.5, 0.54, 0.52, 0.5, 0.52, 0.52, 0.54, 0.56, 0.56, 0.62, 0.6599999999999999, 0.5800000000000001, 0.62, 0.64, 0.7, 0.7, 0.62, 0.6599999999999999, 0.64, 0.56, 0.62, 0.62, 0.56, 0.33999999999999997, 0.43999999999999995, 0.31999999999999995], "outside": [0.38, 0.38, 0.52, 0.42000000000000004, 0.52, 0.5, 0.56, 0.5800000000000001, 0.5800000000000001, 0.64, 0.54, 0.52, 0.45999999999999996, 0.6, 0.6799999999999999, 0.62, 0.5800000000000001, 0.78, 0.6799999999999999, 0.74, 0.7, 0.7, 0.7, 0.7, 0.6799999999999999, 0.7, 0.62, 0.62, 0.45999999999999996, 0.5800000000000001]}, "centroidDeltaMs": 2370.785888671875, "insideScanCount": 38, "insideCentroidMs": 1778324215194.1028, "outsideScanCount": 30, "clusterDurationMs": 5517, "outsideCentroidMs": 1778324212823.317}	f	2026-05-09 12:57:01.148719+02	\N
c38b7120-bcf6-41e9-8d00-e6e7fd2d6395	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.12835906	0.5776158	1	0.5555556	0.4	2026-05-09 12:57:05.177+02	2026-05-09 12:57:03.461+02	2026-05-09 12:57:07.846+02	{"rssiTrend": {"inside": {"r2": 0.426743218050351, "slope": 0.0032429880228503918}, "outside": {"r2": 0.876654041025136, "slope": 0.015549215406562055}}, "rssiWeights": {"inside": [0.33999999999999997, 0.33999999999999997, 0.45999999999999996, 0.43999999999999995, 0.54, 0.5, 0.45999999999999996, 0.45999999999999996, 0.43999999999999995], "outside": [0.43999999999999995, 0.45999999999999996, 0.48, 0.56, 0.52]}, "centroidDeltaMs": 2532.84521484375, "insideScanCount": 9, "insideCentroidMs": 1778324225177.789, "outsideScanCount": 5, "clusterDurationMs": 4385, "outsideCentroidMs": 1778324227710.6343}	f	2026-05-09 12:57:13.161513+02	\N
13d764be-65a7-4974-8eaf-ef21b1fae49f	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3268297	0.58829343	1	0.5555556	\N	2026-05-09 12:57:05.12+02	2026-05-09 12:57:03.461+02	2026-05-09 12:57:07.846+02	{"centroidDeltaMs": 2579.666748046875, "insideScanCount": 9, "insideCentroidMs": 1778324225120.3333, "outsideScanCount": 5, "clusterDurationMs": 4385, "outsideCentroidMs": 1778324227700}	t	2026-05-09 12:57:13.161513+02	\N
2b19f217-69dc-4bd7-a4d2-7b2182af9d6e	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.27914926	0.4578639	1	0.87096775	0.7	2026-05-09 12:57:43.765+02	2026-05-09 12:57:42.062+02	2026-05-09 12:57:47.419+02	{"rssiTrend": {"inside": {"r2": 0.2373927520604998, "slope": 0.004049376552236308}, "outside": {"r2": 0.00000752007807436339, "slope": -0.000011273319210868423}}, "rssiWeights": {"inside": [0.4, 0.38, 0.54, 0.38, 0.38, 0.38, 0.4, 0.56, 0.45999999999999996, 0.6599999999999999, 0.6, 0.5800000000000001, 0.64, 0.62, 0.72, 0.62, 0.76, 0.64, 0.62, 0.7, 0.64, 0.78, 0.72, 0.64, 0.5800000000000001, 0.43999999999999995, 0.33999999999999997], "outside": [0.31999999999999995, 0.45999999999999996, 0.45999999999999996, 0.5, 0.45999999999999996, 0.33999999999999997, 0.45999999999999996, 0.5, 0.5, 0.52, 0.52, 0.54, 0.64, 0.54, 0.45999999999999996, 0.45999999999999996, 0.5, 0.5, 0.6, 0.6, 0.43999999999999995, 0.52, 0.56, 0.43999999999999995, 0.54, 0.5, 0.38, 0.4, 0.31999999999999995, 0.45999999999999996, 0.38]}, "centroidDeltaMs": 2452.77685546875, "insideScanCount": 27, "insideCentroidMs": 1778324266218.593, "outsideScanCount": 31, "clusterDurationMs": 5357, "outsideCentroidMs": 1778324263765.8162}	f	2026-05-09 12:57:53.195334+02	\N
dd9755ca-fa58-4011-baf6-e809284f590e	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.38421783	0.441139	1	0.87096775	\N	2026-05-09 12:57:43.766+02	2026-05-09 12:57:42.062+02	2026-05-09 12:57:47.419+02	{"centroidDeltaMs": 2363.181640625, "insideScanCount": 27, "insideCentroidMs": 1778324266129.4075, "outsideScanCount": 31, "clusterDurationMs": 5357, "outsideCentroidMs": 1778324263766.2258}	t	2026-05-09 12:57:53.195334+02	\N
ee46a503-065b-4760-8c7d-933f3c0a551c	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.29038864	0.6914015	1	0.6	0.7	2026-05-09 12:57:58.233+02	2026-05-09 12:57:57.761+02	2026-05-09 12:58:00.795+02	{"rssiTrend": {"inside": {"r2": 0.006227649396768897, "slope": 0.0011059512094690554}, "outside": {"r2": 0.7142333336895059, "slope": 0.013865924484224556}}, "rssiWeights": {"inside": [0.43999999999999995, 0.56, 0.5800000000000001, 0.64, 0.5800000000000001, 0.64, 0.6599999999999999, 0.5, 0.45999999999999996], "outside": [0.26, 0.43999999999999995, 0.38, 0.42000000000000004, 0.4, 0.45999999999999996, 0.4, 0.5, 0.6, 0.62, 0.6799999999999999, 0.7, 0.5800000000000001, 0.72, 0.54]}, "centroidDeltaMs": 2097.712158203125, "insideScanCount": 9, "insideCentroidMs": 1778324278233.0906, "outsideScanCount": 15, "clusterDurationMs": 3034, "outsideCentroidMs": 1778324280330.8027}	f	2026-05-09 12:58:05.206778+02	\N
2a64ad30-0fc9-46dc-adf3-bc387dfa764d	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.39859813	0.66433024	1	0.6	\N	2026-05-09 12:57:58.23+02	2026-05-09 12:57:57.761+02	2026-05-09 12:58:00.795+02	{"centroidDeltaMs": 2015.577880859375, "insideScanCount": 9, "insideCentroidMs": 1778324278230.2222, "outsideScanCount": 15, "clusterDurationMs": 3034, "outsideCentroidMs": 1778324280245.8}	t	2026-05-09 12:58:05.206778+02	\N
dc9128a7-5b15-4655-8ea9-3d6dd21fe359	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.4084335	0.4574455	1	0.89285713	\N	2026-05-09 12:58:08.913+02	2026-05-09 12:58:07.56+02	2026-05-09 12:58:12.946+02	{"centroidDeltaMs": 2463.801513671875, "insideScanCount": 28, "insideCentroidMs": 1778324291377.3215, "outsideScanCount": 25, "clusterDurationMs": 5386, "outsideCentroidMs": 1778324288913.52}	t	2026-05-09 12:58:17.218915+02	\N
07df0c06-007c-4987-adce-c956632c6582	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.47290188	0.7881698	1	0.6	\N	2026-05-09 12:58:45.606+02	2026-05-09 12:58:45.181+02	2026-05-09 12:58:48.055+02	{"centroidDeltaMs": 2265.199951171875, "insideScanCount": 10, "insideCentroidMs": 1778324325606.8, "outsideScanCount": 6, "clusterDurationMs": 2874, "outsideCentroidMs": 1778324327872}	t	2026-05-09 12:58:53.244049+02	\N
40e5bd51-22f0-4875-a7ed-52f30f9c2e4b	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3984793	0.43832722	1	0.90909094	\N	2026-05-09 12:59:01.048+02	2026-05-09 12:58:59.596+02	2026-05-09 12:59:05.269+02	{"centroidDeltaMs": 2486.63037109375, "insideScanCount": 33, "insideCentroidMs": 1778324343534.697, "outsideScanCount": 30, "clusterDurationMs": 5673, "outsideCentroidMs": 1778324341048.0667}	t	2026-05-09 12:59:11.264934+02	\N
2d8bdecb-b6d2-4cba-b3e7-9da4c2dc2d9d	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23895015	0.5161323	1	0.9259259	0.5	2026-05-09 12:57:16.435+02	2026-05-09 12:57:15.362+02	2026-05-09 12:57:19.968+02	{"rssiTrend": {"inside": {"r2": 0.09384353580975424, "slope": 0.0018224737967831722}, "outside": {"r2": 0.00045115177674304174, "slope": 0.00010429364472415828}}, "rssiWeights": {"inside": [0.45999999999999996, 0.33999999999999997, 0.45999999999999996, 0.56, 0.54, 0.43999999999999995, 0.38, 0.45999999999999996, 0.5800000000000001, 0.56, 0.56, 0.5800000000000001, 0.54, 0.64, 0.5800000000000001, 0.6599999999999999, 0.5800000000000001, 0.64, 0.5800000000000001, 0.5800000000000001, 0.56, 0.64, 0.54, 0.33999999999999997, 0.43999999999999995], "outside": [0.54, 0.62, 0.64, 0.64, 0.5800000000000001, 0.56, 0.5800000000000001, 0.64, 0.5800000000000001, 0.5800000000000001, 0.5800000000000001, 0.72, 0.6799999999999999, 0.7, 0.76, 0.72, 0.6799999999999999, 0.6799999999999999, 0.64, 0.5800000000000001, 0.72, 0.64, 0.54, 0.52, 0.64, 0.64, 0.5]}, "centroidDeltaMs": 2377.305419921875, "insideScanCount": 25, "insideCentroidMs": 1778324238812.644, "outsideScanCount": 27, "clusterDurationMs": 4606, "outsideCentroidMs": 1778324236435.3386}	f	2026-05-09 12:57:25.168211+02	\N
dd410656-e94b-42e8-b446-6e25af60292a	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.16371913	0.56132275	1	0.5833333	0.5	2026-05-09 12:57:29.885+02	2026-05-09 12:57:28.969+02	2026-05-09 12:57:33.345+02	{"rssiTrend": {"inside": {"r2": 0.7124126238589719, "slope": 0.009475732107461398}, "outside": {"r2": 0.00898348962418305, "slope": -0.0007390733940165712}}, "rssiWeights": {"inside": [0.38, 0.33999999999999997, 0.52, 0.45999999999999996, 0.43999999999999995, 0.42000000000000004, 0.56, 0.43999999999999995, 0.56, 0.56, 0.5800000000000001, 0.72, 0.6, 0.64], "outside": [0.42000000000000004, 0.4, 0.38, 0.52, 0.38, 0.5, 0.56, 0.56, 0.56, 0.56, 0.64, 0.5800000000000001, 0.64, 0.5800000000000001, 0.52, 0.5, 0.52, 0.54, 0.38, 0.52, 0.31999999999999995, 0.52, 0.42000000000000004, 0.26]}, "centroidDeltaMs": 2456.348388671875, "insideScanCount": 14, "insideCentroidMs": 1778324249885.4294, "outsideScanCount": 24, "clusterDurationMs": 4376, "outsideCentroidMs": 1778324252341.7778}	f	2026-05-09 12:57:39.179831+02	\N
954d9d73-09fb-4898-acab-d422ea7f5a08	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.339205	0.5814943	1	0.5833333	\N	2026-05-09 12:57:29.808+02	2026-05-09 12:57:28.969+02	2026-05-09 12:57:33.345+02	{"centroidDeltaMs": 2544.618896484375, "insideScanCount": 14, "insideCentroidMs": 1778324249808.7144, "outsideScanCount": 24, "clusterDurationMs": 4376, "outsideCentroidMs": 1778324252353.3333}	t	2026-05-09 12:57:39.179831+02	\N
72910f1c-05bc-4eae-845e-351e6cb632a8	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.11445856	0.5007562	1	0.5714286	0.4	2026-05-09 12:58:20.792+02	2026-05-09 12:58:19.221+02	2026-05-09 12:58:23.895+02	{"rssiTrend": {"inside": {"r2": 0.1039571516164074, "slope": 0.0014845923471481456}, "outside": {"r2": 0.19265896263644122, "slope": 0.003616790795041841}}, "rssiWeights": {"inside": [0.4, 0.5, 0.43999999999999995, 0.45999999999999996, 0.43999999999999995, 0.45999999999999996, 0.52, 0.56, 0.56, 0.5800000000000001, 0.36, 0.56], "outside": [0.4, 0.52, 0.45999999999999996, 0.43999999999999995, 0.52, 0.62, 0.6, 0.54, 0.64, 0.52, 0.6799999999999999, 0.6799999999999999, 0.64, 0.62, 0.64, 0.6599999999999999, 0.72, 0.64, 0.52, 0.56, 0.43999999999999995]}, "centroidDeltaMs": 2340.534423828125, "insideScanCount": 12, "insideCentroidMs": 1778324300792.2534, "outsideScanCount": 21, "clusterDurationMs": 4674, "outsideCentroidMs": 1778324303132.7878}	f	2026-05-09 12:58:29.226364+02	\N
8915f3d9-b351-4152-a2b5-21a1ccde0249	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.28573757	0.50004077	1	0.5714286	\N	2026-05-09 12:58:20.759+02	2026-05-09 12:58:19.221+02	2026-05-09 12:58:23.895+02	{"centroidDeltaMs": 2337.1904296875, "insideScanCount": 12, "insideCentroidMs": 1778324300759, "outsideScanCount": 21, "clusterDurationMs": 4674, "outsideCentroidMs": 1778324303096.1904}	t	2026-05-09 12:58:29.226364+02	\N
291147a7-aa7a-4f5c-a9bd-b6f0fe8c46bf	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.20285162	0.45438763	1	0.89285713	0.5	2026-05-09 12:58:08.916+02	2026-05-09 12:58:07.56+02	2026-05-09 12:58:12.946+02	{"rssiTrend": {"inside": {"r2": 0.005237953469598544, "slope": -0.0004261029101640813}, "outside": {"r2": 0.0009095207606760747, "slope": 0.0001875062485122323}}, "rssiWeights": {"inside": [0.38, 0.4, 0.54, 0.4, 0.52, 0.6, 0.56, 0.45999999999999996, 0.5, 0.56, 0.6599999999999999, 0.5800000000000001, 0.6799999999999999, 0.6799999999999999, 0.7, 0.7, 0.43999999999999995, 0.6599999999999999, 0.43999999999999995, 0.5, 0.54, 0.5800000000000001, 0.52, 0.43999999999999995, 0.56, 0.4, 0.43999999999999995, 0.28], "outside": [0.42000000000000004, 0.52, 0.54, 0.45999999999999996, 0.5800000000000001, 0.6799999999999999, 0.6799999999999999, 0.6799999999999999, 0.64, 0.64, 0.72, 0.6799999999999999, 0.64, 0.64, 0.56, 0.56, 0.45999999999999996, 0.64, 0.62, 0.6799999999999999, 0.5800000000000001, 0.64, 0.5800000000000001, 0.45999999999999996, 0.45999999999999996]}, "centroidDeltaMs": 2447.331787109375, "insideScanCount": 28, "insideCentroidMs": 1778324291363.7979, "outsideScanCount": 25, "clusterDurationMs": 5386, "outsideCentroidMs": 1778324288916.466}	f	2026-05-09 12:58:17.218915+02	\N
b49f332e-cd74-47bf-b9b0-781d2b3e887e	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.2026713	0.4825507	1	0.84	0.5	2026-05-09 12:58:32.543+02	2026-05-09 12:58:31.395+02	2026-05-09 12:58:36.161+02	{"rssiTrend": {"inside": {"r2": 0.0010026183173393877, "slope": 0.0002716168541684638}, "outside": {"r2": 0.008985613608220366, "slope": 0.0011929400028014292}}, "rssiWeights": {"inside": [0.43999999999999995, 0.28, 0.38, 0.43999999999999995, 0.45999999999999996, 0.45999999999999996, 0.45999999999999996, 0.5800000000000001, 0.76, 0.88, 0.78, 0.6799999999999999, 0.76, 0.56, 0.54, 0.56, 0.52, 0.5, 0.54, 0.52, 0.43999999999999995, 0.38, 0.52, 0.43999999999999995, 0.4], "outside": [0.31999999999999995, 0.26, 0.31999999999999995, 0.5, 0.43999999999999995, 0.5800000000000001, 0.56, 0.62, 0.62, 0.6599999999999999, 0.6599999999999999, 0.78, 0.64, 0.7, 0.56, 0.52, 0.31999999999999995, 0.4, 0.33999999999999997, 0.42000000000000004, 0.33999999999999997]}, "centroidDeltaMs": 2299.836669921875, "insideScanCount": 25, "insideCentroidMs": 1778324314843.736, "outsideScanCount": 21, "clusterDurationMs": 4766, "outsideCentroidMs": 1778324312543.8994}	f	2026-05-09 12:58:41.234943+02	\N
a38293da-2a84-4d50-b568-3ae02ab7defa	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.40701902	0.48454645	1	0.84	\N	2026-05-09 12:58:32.527+02	2026-05-09 12:58:31.395+02	2026-05-09 12:58:36.161+02	{"centroidDeltaMs": 2309.348388671875, "insideScanCount": 25, "insideCentroidMs": 1778324314836.92, "outsideScanCount": 21, "clusterDurationMs": 4766, "outsideCentroidMs": 1778324312527.5715}	t	2026-05-09 12:58:41.234943+02	\N
7281b4cd-ab55-4859-bae4-4f01a6f125e3	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.2837642	0.44591516	1	0.90909094	0.7	2026-05-09 12:59:01.07+02	2026-05-09 12:58:59.596+02	2026-05-09 12:59:05.269+02	{"rssiTrend": {"inside": {"r2": 0.15202287174438034, "slope": 0.0017574800606723832}, "outside": {"r2": 0.020133179459793205, "slope": 0.0009095475319173887}}, "rssiWeights": {"inside": [0.52, 0.38, 0.45999999999999996, 0.43999999999999995, 0.38, 0.5800000000000001, 0.52, 0.43999999999999995, 0.54, 0.43999999999999995, 0.48, 0.56, 0.5800000000000001, 0.64, 0.6799999999999999, 0.64, 0.5800000000000001, 0.56, 0.5800000000000001, 0.6799999999999999, 0.6799999999999999, 0.7, 0.6799999999999999, 0.7, 0.62, 0.6, 0.56, 0.5800000000000001, 0.56, 0.4, 0.5, 0.56, 0.5], "outside": [0.4, 0.48, 0.43999999999999995, 0.5, 0.45999999999999996, 0.5, 0.43999999999999995, 0.43999999999999995, 0.72, 0.5800000000000001, 0.45999999999999996, 0.45999999999999996, 0.62, 0.6799999999999999, 0.6799999999999999, 0.7, 0.64, 0.64, 0.64, 0.6799999999999999, 0.6799999999999999, 0.6799999999999999, 0.56, 0.54, 0.5, 0.45999999999999996, 0.45999999999999996, 0.52, 0.4, 0.38]}, "centroidDeltaMs": 2529.6767578125, "insideScanCount": 33, "insideCentroidMs": 1778324343600.0508, "outsideScanCount": 30, "clusterDurationMs": 5673, "outsideCentroidMs": 1778324341070.374}	f	2026-05-09 12:59:11.264934+02	\N
\.


--
-- Data for Name: raw_scans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.raw_scans (id, lighthouse_id, epc, epc_length, rssi_dbm, antenna_id, frequency, sequence_number, detection_confidence, timestamp_ms, "timestamp", received_at, processed_at, orphaned_at, orphan_reason, source, time_basis, created_at) FROM stdin;
19944	9	E28011704000021D53DAB0CB	\N	-63	0	40	\N	\N	1778324237887	2026-05-09 12:57:17.887+02	2026-05-09 12:57:18.486657+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.486657+02
19947	9	E28011704000021D53DAB0CB	\N	-67	0	11	\N	\N	1778324238318	2026-05-09 12:57:18.318+02	2026-05-09 12:57:18.681128+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.681128+02
19949	9	E28011704000021D53DAB0CB	\N	-62	0	43	\N	\N	1778324238461	2026-05-09 12:57:18.461+02	2026-05-09 12:57:18.700191+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.700191+02
19951	9	E28011704000021D53DAB0CB	\N	-61	0	31	\N	\N	1778324238628	2026-05-09 12:57:18.628+02	2026-05-09 12:57:18.75454+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.75454+02
19953	9	E28011704000021D53DAB0CB	\N	-61	0	11	\N	\N	1778324238912	2026-05-09 12:57:18.912+02	2026-05-09 12:57:19.881429+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:19.881429+02
19955	9	E28011704000021D53DAB0CB	\N	-57	0	41	\N	\N	1778324239086	2026-05-09 12:57:19.086+02	2026-05-09 12:57:19.945657+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:19.945657+02
19957	9	E28011704000021D53DAB0CB	\N	-58	0	15	\N	\N	1778324239211	2026-05-09 12:57:19.211+02	2026-05-09 12:57:20.040419+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.040419+02
19960	9	E28011704000021D53DAB0CB	\N	-58	0	27	\N	\N	1778324239661	2026-05-09 12:57:19.661+02	2026-05-09 12:57:20.097281+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.097281+02
19962	9	E28011704000021D53DAB0CB	\N	-63	0	17	\N	\N	1778324239816	2026-05-09 12:57:19.816+02	2026-05-09 12:57:20.157807+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.157807+02
19964	9	E28011704000021D53DAB0CB	\N	-68	0	57	\N	\N	1778324239968	2026-05-09 12:57:19.968+02	2026-05-09 12:57:20.186104+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.186104+02
19920	10	E28011704000021D53DAB0CB	\N	-58	0	16	\N	\N	1778324235961	2026-05-09 12:57:15.961+02	2026-05-09 12:57:16.350996+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.350996+02
19922	10	E28011704000021D53DAB0CB	\N	-61	0	10	\N	\N	1778324236097	2026-05-09 12:57:16.097+02	2026-05-09 12:57:16.390468+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.390468+02
19924	10	E28011704000021D53DAB0CB	\N	-54	0	50	\N	\N	1778324236255	2026-05-09 12:57:16.255+02	2026-05-09 12:57:16.418512+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.418512+02
19926	10	E28011704000021D53DAB0CB	\N	-55	0	46	\N	\N	1778324236395	2026-05-09 12:57:16.395+02	2026-05-09 12:57:16.450618+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.450618+02
19932	10	E28011704000021D53DAB0CB	\N	-61	0	16	\N	\N	1778324237013	2026-05-09 12:57:17.013+02	2026-05-09 12:57:17.987985+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.987985+02
19934	10	E28011704000021D53DAB0CB	\N	-58	0	25	\N	\N	1778324237145	2026-05-09 12:57:17.145+02	2026-05-09 12:57:18.02204+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.02204+02
19936	10	E28011704000021D53DAB0CB	\N	-64	0	43	\N	\N	1778324237296	2026-05-09 12:57:17.296+02	2026-05-09 12:57:18.035115+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.035115+02
19938	10	E28011704000021D53DAB0CB	\N	-58	0	15	\N	\N	1778324237445	2026-05-09 12:57:17.445+02	2026-05-09 12:57:18.066392+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.066392+02
19943	9	E28011704000021D53DAB0CB	\N	-62	0	32	\N	\N	1778324237887	2026-05-09 12:57:17.887+02	2026-05-09 12:57:18.48451+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.48451+02
19945	9	E28011704000021D53DAB0CB	\N	-68	0	52	\N	\N	1778324238012	2026-05-09 12:57:18.012+02	2026-05-09 12:57:18.568967+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.568967+02
19948	9	E28011704000021D53DAB0CB	\N	-61	0	54	\N	\N	1778324238461	2026-05-09 12:57:18.461+02	2026-05-09 12:57:18.697811+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.697811+02
19687	10	E28011704000021D53DAB0CB	\N	-74	0	10	\N	\N	1778324159295	2026-05-09 12:55:59.295+02	2026-05-09 12:55:59.907612+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:55:59.907612+02
19688	10	E28011704000021D53DAB0CB	\N	-71	0	31	\N	\N	1778324159595	2026-05-09 12:55:59.595+02	2026-05-09 12:56:00.341424+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.341424+02
19689	10	E28011704000021D53DAB0CB	\N	-66	0	21	\N	\N	1778324159595	2026-05-09 12:55:59.595+02	2026-05-09 12:56:00.344472+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.344472+02
19690	10	E28011704000021D53DAB0CB	\N	-73	0	16	\N	\N	1778324159745	2026-05-09 12:55:59.745+02	2026-05-09 12:56:00.36027+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.36027+02
19691	10	E28011704000021D53DAB0CB	\N	-63	0	53	\N	\N	1778324159745	2026-05-09 12:55:59.745+02	2026-05-09 12:56:00.362484+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.362484+02
19692	10	E28011704000021D53DAB0CB	\N	-69	0	47	\N	\N	1778324159745	2026-05-09 12:55:59.745+02	2026-05-09 12:56:00.36532+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.36532+02
19693	10	E28011704000021D53DAB0CB	\N	-60	0	33	\N	\N	1778324159895	2026-05-09 12:55:59.895+02	2026-05-09 12:56:00.399037+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.399037+02
19694	10	E28011704000021D53DAB0CB	\N	-70	0	43	\N	\N	1778324160045	2026-05-09 12:56:00.045+02	2026-05-09 12:56:00.409503+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.409503+02
19695	10	E28011704000021D53DAB0CB	\N	-65	0	50	\N	\N	1778324160197	2026-05-09 12:56:00.197+02	2026-05-09 12:56:00.440418+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.440418+02
19696	10	E28011704000021D53DAB0CB	\N	-64	0	36	\N	\N	1778324160197	2026-05-09 12:56:00.197+02	2026-05-09 12:56:00.442537+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.442537+02
19697	10	E28011704000021D53DAB0CB	\N	-64	0	47	\N	\N	1778324160345	2026-05-09 12:56:00.345+02	2026-05-09 12:56:00.490308+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.490308+02
19698	10	E28011704000021D53DAB0CB	\N	-61	0	39	\N	\N	1778324160345	2026-05-09 12:56:00.345+02	2026-05-09 12:56:00.492895+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:00.492895+02
19699	10	E28011704000021D53DAB0CB	\N	-61	0	41	\N	\N	1778324160495	2026-05-09 12:56:00.495+02	2026-05-09 12:56:01.545156+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.545156+02
19700	10	E28011704000021D53DAB0CB	\N	-64	0	32	\N	\N	1778324160495	2026-05-09 12:56:00.495+02	2026-05-09 12:56:01.547102+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.547102+02
19701	10	E28011704000021D53DAB0CB	\N	-62	0	43	\N	\N	1778324160495	2026-05-09 12:56:00.495+02	2026-05-09 12:56:01.548967+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.548967+02
19702	10	E28011704000021D53DAB0CB	\N	-64	0	25	\N	\N	1778324160652	2026-05-09 12:56:00.652+02	2026-05-09 12:56:01.55972+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.55972+02
19731	9	E28011704000021D53DAB0CB	\N	-76	0	8	\N	\N	1778324176688	2026-05-09 12:56:16.688+02	2026-05-09 12:56:17.240051+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:17.240051+02
19732	9	E28011704000021D53DAB0CB	\N	-71	0	14	\N	\N	1778324177142	2026-05-09 12:56:17.142+02	2026-05-09 12:56:17.271077+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:17.271077+02
19735	9	E28011704000021D53DAB0CB	\N	-71	0	18	\N	\N	1778324177455	2026-05-09 12:56:17.455+02	2026-05-09 12:56:18.443497+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.443497+02
19736	9	E28011704000021D53DAB0CB	\N	-70	0	34	\N	\N	1778324177561	2026-05-09 12:56:17.561+02	2026-05-09 12:56:18.627455+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.627455+02
19737	9	E28011704000021D53DAB0CB	\N	-63	0	50	\N	\N	1778324177712	2026-05-09 12:56:17.712+02	2026-05-09 12:56:18.652692+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.652692+02
19740	9	E28011704000021D53DAB0CB	\N	-63	0	41	\N	\N	1778324177869	2026-05-09 12:56:17.869+02	2026-05-09 12:56:18.737672+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.737672+02
19741	9	E28011704000021D53DAB0CB	\N	-62	0	19	\N	\N	1778324178036	2026-05-09 12:56:18.036+02	2026-05-09 12:56:18.828347+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.828347+02
19742	9	E28011704000021D53DAB0CB	\N	-61	0	29	\N	\N	1778324178162	2026-05-09 12:56:18.162+02	2026-05-09 12:56:18.849061+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.849061+02
19746	9	E28011704000021D53DAB0CB	\N	-63	0	17	\N	\N	1778324178461	2026-05-09 12:56:18.461+02	2026-05-09 12:56:18.938591+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.938591+02
19747	9	E28011704000021D53DAB0CB	\N	-73	0	17	\N	\N	1778324178611	2026-05-09 12:56:18.611+02	2026-05-09 12:56:19.038383+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.038383+02
19750	10	E28011704000021D53DAB0CB	\N	-80	0	48	\N	\N	1778324178952	2026-05-09 12:56:18.952+02	2026-05-09 12:56:19.568016+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.568016+02
19753	10	E28011704000021D53DAB0CB	\N	-73	0	27	\N	\N	1778324179095	2026-05-09 12:56:19.095+02	2026-05-09 12:56:19.594331+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.594331+02
19754	10	E28011704000021D53DAB0CB	\N	-74	0	48	\N	\N	1778324179395	2026-05-09 12:56:19.395+02	2026-05-09 12:56:19.622128+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.622128+02
19755	10	E28011704000021D53DAB0CB	\N	-71	0	17	\N	\N	1778324179562	2026-05-09 12:56:19.562+02	2026-05-09 12:56:19.676126+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.676126+02
19758	10	E28011704000021D53DAB0CB	\N	-74	0	25	\N	\N	1778324179696	2026-05-09 12:56:19.696+02	2026-05-09 12:56:20.829589+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:20.829589+02
19703	10	E28011704000021D53DAB0CB	\N	-61	0	30	\N	\N	1778324160652	2026-05-09 12:56:00.652+02	2026-05-09 12:56:01.563946+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.563946+02
19704	10	E28011704000021D53DAB0CB	\N	-62	0	37	\N	\N	1778324160795	2026-05-09 12:56:00.795+02	2026-05-09 12:56:01.588978+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.588978+02
19705	10	E28011704000021D53DAB0CB	\N	-64	0	29	\N	\N	1778324160795	2026-05-09 12:56:00.795+02	2026-05-09 12:56:01.591926+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.591926+02
19706	10	E28011704000021D53DAB0CB	\N	-68	0	14	\N	\N	1778324160955	2026-05-09 12:56:00.955+02	2026-05-09 12:56:01.606109+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.606109+02
19707	10	E28011704000021D53DAB0CB	\N	-69	0	20	\N	\N	1778324161095	2026-05-09 12:56:01.095+02	2026-05-09 12:56:01.616048+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.616048+02
19708	10	E28011704000021D53DAB0CB	\N	-70	0	17	\N	\N	1778324161095	2026-05-09 12:56:01.095+02	2026-05-09 12:56:01.61802+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.61802+02
19709	10	E28011704000021D53DAB0CB	\N	-68	0	52	\N	\N	1778324161254	2026-05-09 12:56:01.254+02	2026-05-09 12:56:01.648115+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.648115+02
19710	10	E28011704000021D53DAB0CB	\N	-73	0	24	\N	\N	1778324161254	2026-05-09 12:56:01.254+02	2026-05-09 12:56:01.650058+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.650058+02
19711	10	E28011704000021D53DAB0CB	\N	-74	0	25	\N	\N	1778324161254	2026-05-09 12:56:01.254+02	2026-05-09 12:56:01.65202+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:01.65202+02
19712	9	E28011704000021D53DAB0CB	\N	-74	0	27	\N	\N	1778324161512	2026-05-09 12:56:01.512+02	2026-05-09 12:56:02.236966+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.236966+02
19713	9	E28011704000021D53DAB0CB	\N	-74	0	57	\N	\N	1778324161661	2026-05-09 12:56:01.661+02	2026-05-09 12:56:02.310367+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.310367+02
19714	9	E28011704000021D53DAB0CB	\N	-68	0	43	\N	\N	1778324161812	2026-05-09 12:56:01.812+02	2026-05-09 12:56:02.353559+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.353559+02
19715	9	E28011704000021D53DAB0CB	\N	-73	0	48	\N	\N	1778324161964	2026-05-09 12:56:01.964+02	2026-05-09 12:56:02.384006+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.384006+02
19716	9	E28011704000021D53DAB0CB	\N	-70	0	42	\N	\N	1778324162111	2026-05-09 12:56:02.111+02	2026-05-09 12:56:02.411114+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.411114+02
19717	9	E28011704000021D53DAB0CB	\N	-67	0	32	\N	\N	1778324162111	2026-05-09 12:56:02.111+02	2026-05-09 12:56:02.412931+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.412931+02
19718	9	E28011704000021D53DAB0CB	\N	-68	0	28	\N	\N	1778324162261	2026-05-09 12:56:02.261+02	2026-05-09 12:56:02.454512+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.454512+02
19719	9	E28011704000021D53DAB0CB	\N	-63	0	49	\N	\N	1778324162261	2026-05-09 12:56:02.261+02	2026-05-09 12:56:02.460075+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.460075+02
19720	9	E28011704000021D53DAB0CB	\N	-70	0	33	\N	\N	1778324162411	2026-05-09 12:56:02.411+02	2026-05-09 12:56:02.477458+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:02.477458+02
19721	9	E28011704000021D53DAB0CB	\N	-69	0	14	\N	\N	1778324162561	2026-05-09 12:56:02.561+02	2026-05-09 12:56:03.593118+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.593118+02
19722	9	E28011704000021D53DAB0CB	\N	-64	0	34	\N	\N	1778324162561	2026-05-09 12:56:02.561+02	2026-05-09 12:56:03.595439+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.595439+02
19723	9	E28011704000021D53DAB0CB	\N	-64	0	32	\N	\N	1778324162724	2026-05-09 12:56:02.724+02	2026-05-09 12:56:03.61196+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.61196+02
19724	9	E28011704000021D53DAB0CB	\N	-62	0	57	\N	\N	1778324162724	2026-05-09 12:56:02.724+02	2026-05-09 12:56:03.61388+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.61388+02
19725	9	E28011704000021D53DAB0CB	\N	-65	0	13	\N	\N	1778324162724	2026-05-09 12:56:02.724+02	2026-05-09 12:56:03.615874+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.615874+02
19726	9	E28011704000021D53DAB0CB	\N	-65	0	27	\N	\N	1778324162881	2026-05-09 12:56:02.881+02	2026-05-09 12:56:03.636444+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.636444+02
19727	9	E28011704000021D53DAB0CB	\N	-77	0	52	\N	\N	1778324163011	2026-05-09 12:56:03.011+02	2026-05-09 12:56:03.648481+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.648481+02
19728	9	E28011704000021D53DAB0CB	\N	-67	0	36	\N	\N	1778324163011	2026-05-09 12:56:03.011+02	2026-05-09 12:56:03.65059+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.65059+02
19729	9	E28011704000021D53DAB0CB	\N	-68	0	9	\N	\N	1778324163166	2026-05-09 12:56:03.166+02	2026-05-09 12:56:03.702869+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.702869+02
19730	9	E28011704000021D53DAB0CB	\N	-71	0	58	\N	\N	1778324163319	2026-05-09 12:56:03.319+02	2026-05-09 12:56:03.722171+02	2026-05-09 12:56:09.113+02	\N	\N	realtime	synced	2026-05-09 12:56:03.722171+02
20142	9	E28011704000021D53DAB0CB	\N	-68	0	19	\N	\N	1778324300885	2026-05-09 12:58:20.885+02	2026-05-09 12:58:21.245333+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.245333+02
20144	9	E28011704000021D53DAB0CB	\N	-64	0	43	\N	\N	1778324301012	2026-05-09 12:58:21.012+02	2026-05-09 12:58:21.301129+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.301129+02
20146	9	E28011704000021D53DAB0CB	\N	-62	0	8	\N	\N	1778324301163	2026-05-09 12:58:21.163+02	2026-05-09 12:58:21.396013+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.396013+02
20152	10	E28011704000021D53DAB0CB	\N	-70	0	18	\N	\N	1778324302245	2026-05-09 12:58:22.245+02	2026-05-09 12:58:22.554994+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:22.554994+02
19965	9	E28011704000021D53DAB0CB	\N	-71	0	10	\N	\N	1778324248969	2026-05-09 12:57:28.969+02	2026-05-09 12:57:29.711565+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:29.711565+02
19968	9	E28011704000021D53DAB0CB	\N	-67	0	49	\N	\N	1778324249413	2026-05-09 12:57:29.413+02	2026-05-09 12:57:29.964942+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:29.964942+02
19971	9	E28011704000021D53DAB0CB	\N	-68	0	18	\N	\N	1778324249896	2026-05-09 12:57:29.896+02	2026-05-09 12:57:30.17395+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.17395+02
19733	9	E28011704000021D53DAB0CB	\N	-73	0	24	\N	\N	1778324177142	2026-05-09 12:56:17.142+02	2026-05-09 12:56:17.275742+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:17.275742+02
19734	9	E28011704000021D53DAB0CB	\N	-73	0	52	\N	\N	1778324177455	2026-05-09 12:56:17.455+02	2026-05-09 12:56:18.441441+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.441441+02
19738	9	E28011704000021D53DAB0CB	\N	-60	0	12	\N	\N	1778324177712	2026-05-09 12:56:17.712+02	2026-05-09 12:56:18.654866+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.654866+02
19777	10	E28011704000021D53DAB0CB	\N	-71	0	19	\N	\N	1778324188858	2026-05-09 12:56:28.858+02	2026-05-09 12:56:29.400009+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.400009+02
19778	10	E28011704000021D53DAB0CB	\N	-67	0	41	\N	\N	1778324188995	2026-05-09 12:56:28.995+02	2026-05-09 12:56:29.538476+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.538476+02
19781	10	E28011704000021D53DAB0CB	\N	-59	0	21	\N	\N	1778324189145	2026-05-09 12:56:29.145+02	2026-05-09 12:56:29.578529+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.578529+02
19782	10	E28011704000021D53DAB0CB	\N	-59	0	54	\N	\N	1778324189298	2026-05-09 12:56:29.298+02	2026-05-09 12:56:29.616639+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.616639+02
19783	10	E28011704000021D53DAB0CB	\N	-59	0	55	\N	\N	1778324189445	2026-05-09 12:56:29.445+02	2026-05-09 12:56:29.658811+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.658811+02
19785	10	E28011704000021D53DAB0CB	\N	-62	0	40	\N	\N	1778324189596	2026-05-09 12:56:29.596+02	2026-05-09 12:56:29.69193+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.69193+02
19789	10	E28011704000021D53DAB0CB	\N	-73	0	55	\N	\N	1778324189745	2026-05-09 12:56:29.745+02	2026-05-09 12:56:30.8331+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.8331+02
19790	10	E28011704000021D53DAB0CB	\N	-70	0	27	\N	\N	1778324189912	2026-05-09 12:56:29.912+02	2026-05-09 12:56:30.845952+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.845952+02
19739	9	E28011704000021D53DAB0CB	\N	-57	0	50	\N	\N	1778324177869	2026-05-09 12:56:17.869+02	2026-05-09 12:56:18.733926+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.733926+02
19743	9	E28011704000021D53DAB0CB	\N	-58	0	54	\N	\N	1778324178162	2026-05-09 12:56:18.162+02	2026-05-09 12:56:18.851504+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.851504+02
19744	9	E28011704000021D53DAB0CB	\N	-63	0	46	\N	\N	1778324178328	2026-05-09 12:56:18.328+02	2026-05-09 12:56:18.872977+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.872977+02
19745	9	E28011704000021D53DAB0CB	\N	-70	0	39	\N	\N	1778324178461	2026-05-09 12:56:18.461+02	2026-05-09 12:56:18.936579+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:18.936579+02
19748	9	E28011704000021D53DAB0CB	\N	-77	0	25	\N	\N	1778324178611	2026-05-09 12:56:18.611+02	2026-05-09 12:56:19.040579+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.040579+02
19749	10	E28011704000021D53DAB0CB	\N	-77	0	57	\N	\N	1778324178654	2026-05-09 12:56:18.654+02	2026-05-09 12:56:19.260033+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.260033+02
19751	10	E28011704000021D53DAB0CB	\N	-77	0	20	\N	\N	1778324178952	2026-05-09 12:56:18.952+02	2026-05-09 12:56:19.572066+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.572066+02
19752	10	E28011704000021D53DAB0CB	\N	-72	0	38	\N	\N	1778324179095	2026-05-09 12:56:19.095+02	2026-05-09 12:56:19.592012+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.592012+02
19756	10	E28011704000021D53DAB0CB	\N	-68	0	51	\N	\N	1778324179562	2026-05-09 12:56:19.562+02	2026-05-09 12:56:19.67803+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:19.67803+02
19757	10	E28011704000021D53DAB0CB	\N	-71	0	36	\N	\N	1778324179696	2026-05-09 12:56:19.696+02	2026-05-09 12:56:20.827127+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:20.827127+02
19759	10	E28011704000021D53DAB0CB	\N	-73	0	7	\N	\N	1778324179854	2026-05-09 12:56:19.854+02	2026-05-09 12:56:21.004663+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.004663+02
19760	10	E28011704000021D53DAB0CB	\N	-74	0	21	\N	\N	1778324179854	2026-05-09 12:56:19.854+02	2026-05-09 12:56:21.006736+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.006736+02
19761	10	E28011704000021D53DAB0CB	\N	-70	0	20	\N	\N	1778324180004	2026-05-09 12:56:20.004+02	2026-05-09 12:56:21.483054+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.483054+02
19762	10	E28011704000021D53DAB0CB	\N	-69	0	35	\N	\N	1778324180004	2026-05-09 12:56:20.004+02	2026-05-09 12:56:21.484898+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.484898+02
19763	10	E28011704000021D53DAB0CB	\N	-67	0	31	\N	\N	1778324180145	2026-05-09 12:56:20.145+02	2026-05-09 12:56:21.653128+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.653128+02
19764	10	E28011704000021D53DAB0CB	\N	-63	0	31	\N	\N	1778324180145	2026-05-09 12:56:20.145+02	2026-05-09 12:56:21.656712+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.656712+02
19765	10	E28011704000021D53DAB0CB	\N	-61	0	11	\N	\N	1778324180145	2026-05-09 12:56:20.145+02	2026-05-09 12:56:21.65903+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.65903+02
19766	10	E28011704000021D53DAB0CB	\N	-62	0	29	\N	\N	1778324180295	2026-05-09 12:56:20.295+02	2026-05-09 12:56:21.685528+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.685528+02
19767	10	E28011704000021D53DAB0CB	\N	-61	0	49	\N	\N	1778324180453	2026-05-09 12:56:20.453+02	2026-05-09 12:56:21.70437+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.70437+02
19768	10	E28011704000021D53DAB0CB	\N	-61	0	37	\N	\N	1778324180453	2026-05-09 12:56:20.453+02	2026-05-09 12:56:21.706505+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.706505+02
19769	10	E28011704000021D53DAB0CB	\N	-61	0	12	\N	\N	1778324180597	2026-05-09 12:56:20.597+02	2026-05-09 12:56:21.714669+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.714669+02
19770	10	E28011704000021D53DAB0CB	\N	-67	0	31	\N	\N	1778324180597	2026-05-09 12:56:20.597+02	2026-05-09 12:56:21.718863+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.718863+02
19771	10	E28011704000021D53DAB0CB	\N	-64	0	55	\N	\N	1778324180751	2026-05-09 12:56:20.751+02	2026-05-09 12:56:21.73678+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.73678+02
19772	10	E28011704000021D53DAB0CB	\N	-70	0	42	\N	\N	1778324180751	2026-05-09 12:56:20.751+02	2026-05-09 12:56:21.738947+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.738947+02
19773	10	E28011704000021D53DAB0CB	\N	-80	0	22	\N	\N	1778324180751	2026-05-09 12:56:20.751+02	2026-05-09 12:56:21.740616+02	2026-05-09 12:56:25.123+02	\N	\N	realtime	synced	2026-05-09 12:56:21.740616+02
20145	9	E28011704000021D53DAB0CB	\N	-62	0	30	\N	\N	1778324301163	2026-05-09 12:58:21.163+02	2026-05-09 12:58:21.393893+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.393893+02
19774	10	E28011704000021D53DAB0CB	\N	-76	0	56	\N	\N	1778324187796	2026-05-09 12:56:27.796+02	2026-05-09 12:56:28.271375+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:28.271375+02
19775	10	E28011704000021D53DAB0CB	\N	-74	0	48	\N	\N	1778324187954	2026-05-09 12:56:27.954+02	2026-05-09 12:56:28.322913+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:28.322913+02
19776	10	E28011704000021D53DAB0CB	\N	-79	0	59	\N	\N	1778324188858	2026-05-09 12:56:28.858+02	2026-05-09 12:56:29.398144+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.398144+02
19779	10	E28011704000021D53DAB0CB	\N	-63	0	35	\N	\N	1778324188995	2026-05-09 12:56:28.995+02	2026-05-09 12:56:29.542128+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.542128+02
19780	10	E28011704000021D53DAB0CB	\N	-64	0	20	\N	\N	1778324189145	2026-05-09 12:56:29.145+02	2026-05-09 12:56:29.57676+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.57676+02
19784	10	E28011704000021D53DAB0CB	\N	-59	0	46	\N	\N	1778324189445	2026-05-09 12:56:29.445+02	2026-05-09 12:56:29.661342+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.661342+02
19786	10	E28011704000021D53DAB0CB	\N	-70	0	43	\N	\N	1778324189596	2026-05-09 12:56:29.596+02	2026-05-09 12:56:29.694113+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:29.694113+02
19787	9	E28011704000021D53DAB0CB	\N	-71	0	11	\N	\N	1778324190312	2026-05-09 12:56:30.312+02	2026-05-09 12:56:30.422097+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.422097+02
19788	10	E28011704000021D53DAB0CB	\N	-63	0	19	\N	\N	1778324189745	2026-05-09 12:56:29.745+02	2026-05-09 12:56:30.83128+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.83128+02
19791	10	E28011704000021D53DAB0CB	\N	-72	0	35	\N	\N	1778324189912	2026-05-09 12:56:29.912+02	2026-05-09 12:56:30.851027+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.851027+02
19799	9	E28011704000021D53DAB0CB	\N	-68	0	45	\N	\N	1778324191211	2026-05-09 12:56:31.211+02	2026-05-09 12:56:31.794753+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.794753+02
19800	9	E28011704000021D53DAB0CB	\N	-71	0	55	\N	\N	1778324191369	2026-05-09 12:56:31.369+02	2026-05-09 12:56:31.870298+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.870298+02
19801	9	E28011704000021D53DAB0CB	\N	-65	0	16	\N	\N	1778324191512	2026-05-09 12:56:31.512+02	2026-05-09 12:56:31.920619+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.920619+02
19804	9	E28011704000021D53DAB0CB	\N	-65	0	59	\N	\N	1778324191672	2026-05-09 12:56:31.672+02	2026-05-09 12:56:31.947708+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.947708+02
19805	9	E28011704000021D53DAB0CB	\N	-64	0	18	\N	\N	1778324191812	2026-05-09 12:56:31.812+02	2026-05-09 12:56:32.039129+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:32.039129+02
19806	9	E28011704000021D53DAB0CB	\N	-67	0	54	\N	\N	1778324191978	2026-05-09 12:56:31.978+02	2026-05-09 12:56:32.776878+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:32.776878+02
19812	9	E28011704000021D53DAB0CB	\N	-73	0	24	\N	\N	1778324201263	2026-05-09 12:56:41.263+02	2026-05-09 12:56:41.585124+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:41.585124+02
19813	10	E28011704000021D53DAB0CB	\N	-69	0	19	\N	\N	1778324203555	2026-05-09 12:56:43.555+02	2026-05-09 12:56:43.631486+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:43.631486+02
19814	10	E28011704000021D53DAB0CB	\N	-60	0	23	\N	\N	1778324203711	2026-05-09 12:56:43.711+02	2026-05-09 12:56:44.76412+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.76412+02
19817	10	E28011704000021D53DAB0CB	\N	-63	0	21	\N	\N	1778324203846	2026-05-09 12:56:43.846+02	2026-05-09 12:56:44.917049+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.917049+02
19818	10	E28011704000021D53DAB0CB	\N	-58	0	14	\N	\N	1778324204009	2026-05-09 12:56:44.009+02	2026-05-09 12:56:44.936132+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.936132+02
19821	10	E28011704000021D53DAB0CB	\N	-64	0	52	\N	\N	1778324204147	2026-05-09 12:56:44.147+02	2026-05-09 12:56:44.970879+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.970879+02
19792	10	E28011704000021D53DAB0CB	\N	-74	0	13	\N	\N	1778324189912	2026-05-09 12:56:29.912+02	2026-05-09 12:56:30.853699+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.853699+02
19793	10	E28011704000021D53DAB0CB	\N	-70	0	19	\N	\N	1778324190050	2026-05-09 12:56:30.05+02	2026-05-09 12:56:30.867645+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:30.867645+02
19794	9	E28011704000021D53DAB0CB	\N	-73	0	39	\N	\N	1778324190637	2026-05-09 12:56:30.637+02	2026-05-09 12:56:31.548224+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.548224+02
19795	9	E28011704000021D53DAB0CB	\N	-73	0	50	\N	\N	1778324190761	2026-05-09 12:56:30.761+02	2026-05-09 12:56:31.623596+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.623596+02
19796	9	E28011704000021D53DAB0CB	\N	-73	0	52	\N	\N	1778324190913	2026-05-09 12:56:30.913+02	2026-05-09 12:56:31.697237+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.697237+02
19797	9	E28011704000021D53DAB0CB	\N	-71	0	48	\N	\N	1778324191071	2026-05-09 12:56:31.071+02	2026-05-09 12:56:31.717221+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.717221+02
19798	9	E28011704000021D53DAB0CB	\N	-70	0	46	\N	\N	1778324191211	2026-05-09 12:56:31.211+02	2026-05-09 12:56:31.791909+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.791909+02
19802	9	E28011704000021D53DAB0CB	\N	-72	0	8	\N	\N	1778324191512	2026-05-09 12:56:31.512+02	2026-05-09 12:56:31.922929+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.922929+02
19803	9	E28011704000021D53DAB0CB	\N	-68	0	26	\N	\N	1778324191672	2026-05-09 12:56:31.672+02	2026-05-09 12:56:31.945476+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:31.945476+02
19807	9	E28011704000021D53DAB0CB	\N	-60	0	22	\N	\N	1778324191978	2026-05-09 12:56:31.978+02	2026-05-09 12:56:32.779403+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:32.779403+02
19808	9	E28011704000021D53DAB0CB	\N	-70	0	21	\N	\N	1778324192143	2026-05-09 12:56:32.143+02	2026-05-09 12:56:32.914867+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:32.914867+02
19809	9	E28011704000021D53DAB0CB	\N	-71	0	55	\N	\N	1778324192143	2026-05-09 12:56:32.143+02	2026-05-09 12:56:32.916882+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:32.916882+02
19810	9	E28011704000021D53DAB0CB	\N	-60	0	27	\N	\N	1778324192265	2026-05-09 12:56:32.265+02	2026-05-09 12:56:32.969122+02	2026-05-09 12:56:37.134+02	\N	\N	realtime	synced	2026-05-09 12:56:32.969122+02
20141	9	E28011704000021D53DAB0CB	\N	-67	0	17	\N	\N	1778324300711	2026-05-09 12:58:20.711+02	2026-05-09 12:58:21.219409+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.219409+02
19967	9	E28011704000021D53DAB0CB	\N	-64	0	30	\N	\N	1778324249292	2026-05-09 12:57:29.292+02	2026-05-09 12:57:29.941001+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:29.941001+02
19970	9	E28011704000021D53DAB0CB	\N	-69	0	59	\N	\N	1778324249717	2026-05-09 12:57:29.717+02	2026-05-09 12:57:30.115989+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.115989+02
19972	9	E28011704000021D53DAB0CB	\N	-62	0	51	\N	\N	1778324249896	2026-05-09 12:57:29.896+02	2026-05-09 12:57:30.176104+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.176104+02
19983	10	E28011704000021D53DAB0CB	\N	-71	0	38	\N	\N	1778324251695	2026-05-09 12:57:31.695+02	2026-05-09 12:57:32.535627+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.535627+02
19985	10	E28011704000021D53DAB0CB	\N	-62	0	44	\N	\N	1778324251847	2026-05-09 12:57:31.847+02	2026-05-09 12:57:32.575646+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.575646+02
19811	9	E28011704000021D53DAB0CB	\N	-73	0	15	\N	\N	1778324201263	2026-05-09 12:56:41.263+02	2026-05-09 12:56:41.58334+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:41.58334+02
19815	10	E28011704000021D53DAB0CB	\N	-63	0	45	\N	\N	1778324203711	2026-05-09 12:56:43.711+02	2026-05-09 12:56:44.766335+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.766335+02
19816	10	E28011704000021D53DAB0CB	\N	-64	0	34	\N	\N	1778324203846	2026-05-09 12:56:43.846+02	2026-05-09 12:56:44.912443+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.912443+02
19819	10	E28011704000021D53DAB0CB	\N	-58	0	30	\N	\N	1778324204009	2026-05-09 12:56:44.009+02	2026-05-09 12:56:44.938269+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.938269+02
19820	10	E28011704000021D53DAB0CB	\N	-58	0	21	\N	\N	1778324204147	2026-05-09 12:56:44.147+02	2026-05-09 12:56:44.969022+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.969022+02
19823	10	E28011704000021D53DAB0CB	\N	-65	0	56	\N	\N	1778324204295	2026-05-09 12:56:44.295+02	2026-05-09 12:56:44.988024+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.988024+02
19824	10	E28011704000021D53DAB0CB	\N	-62	0	20	\N	\N	1778324204459	2026-05-09 12:56:44.459+02	2026-05-09 12:56:45.000927+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.000927+02
19828	10	E28011704000021D53DAB0CB	\N	-67	0	35	\N	\N	1778324204763	2026-05-09 12:56:44.763+02	2026-05-09 12:56:45.071618+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.071618+02
19829	10	E28011704000021D53DAB0CB	\N	-68	0	38	\N	\N	1778324204895	2026-05-09 12:56:44.895+02	2026-05-09 12:56:45.112119+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.112119+02
19973	9	E28011704000021D53DAB0CB	\N	-62	0	53	\N	\N	1778324250021	2026-05-09 12:57:30.021+02	2026-05-09 12:57:30.189078+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.189078+02
19975	9	E28011704000021D53DAB0CB	\N	-62	0	26	\N	\N	1778324250166	2026-05-09 12:57:30.166+02	2026-05-09 12:57:30.269508+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.269508+02
19977	9	E28011704000021D53DAB0CB	\N	-54	0	33	\N	\N	1778324250312	2026-05-09 12:57:30.312+02	2026-05-09 12:57:30.493104+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.493104+02
19979	10	E28011704000021D53DAB0CB	\N	-69	0	49	\N	\N	1778324251247	2026-05-09 12:57:31.247+02	2026-05-09 12:57:31.452476+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:31.452476+02
19981	10	E28011704000021D53DAB0CB	\N	-71	0	59	\N	\N	1778324251396	2026-05-09 12:57:31.396+02	2026-05-09 12:57:31.475652+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:31.475652+02
19984	10	E28011704000021D53DAB0CB	\N	-65	0	53	\N	\N	1778324251847	2026-05-09 12:57:31.847+02	2026-05-09 12:57:32.573649+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.573649+02
19986	10	E28011704000021D53DAB0CB	\N	-62	0	34	\N	\N	1778324251995	2026-05-09 12:57:31.995+02	2026-05-09 12:57:32.605703+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.605703+02
19988	10	E28011704000021D53DAB0CB	\N	-62	0	26	\N	\N	1778324252150	2026-05-09 12:57:32.15+02	2026-05-09 12:57:32.645092+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.645092+02
19990	10	E28011704000021D53DAB0CB	\N	-58	0	46	\N	\N	1778324252296	2026-05-09 12:57:32.296+02	2026-05-09 12:57:32.704764+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.704764+02
19992	10	E28011704000021D53DAB0CB	\N	-61	0	38	\N	\N	1778324252451	2026-05-09 12:57:32.451+02	2026-05-09 12:57:32.753825+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.753825+02
19998	10	E28011704000021D53DAB0CB	\N	-64	0	25	\N	\N	1778324253051	2026-05-09 12:57:33.051+02	2026-05-09 12:57:33.937708+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.937708+02
20000	10	E28011704000021D53DAB0CB	\N	-69	0	32	\N	\N	1778324253195	2026-05-09 12:57:33.195+02	2026-05-09 12:57:33.965086+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.965086+02
20002	10	E28011704000021D53DAB0CB	\N	-77	0	30	\N	\N	1778324253345	2026-05-09 12:57:33.345+02	2026-05-09 12:57:33.977532+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.977532+02
19966	9	E28011704000021D53DAB0CB	\N	-73	0	57	\N	\N	1778324249129	2026-05-09 12:57:29.129+02	2026-05-09 12:57:29.910141+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:29.910141+02
19969	9	E28011704000021D53DAB0CB	\N	-68	0	40	\N	\N	1778324249561	2026-05-09 12:57:29.561+02	2026-05-09 12:57:30.029039+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.029039+02
19974	9	E28011704000021D53DAB0CB	\N	-61	0	52	\N	\N	1778324250166	2026-05-09 12:57:30.166+02	2026-05-09 12:57:30.267423+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.267423+02
19976	9	E28011704000021D53DAB0CB	\N	-60	0	42	\N	\N	1778324250312	2026-05-09 12:57:30.312+02	2026-05-09 12:57:30.490812+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:30.490812+02
19978	9	E28011704000021D53DAB0CB	\N	-58	0	25	\N	\N	1778324250472	2026-05-09 12:57:30.472+02	2026-05-09 12:57:31.145673+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:31.145673+02
19980	10	E28011704000021D53DAB0CB	\N	-70	0	35	\N	\N	1778324251396	2026-05-09 12:57:31.396+02	2026-05-09 12:57:31.47301+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:31.47301+02
19833	10	E28011704000021D53DAB0CB	\N	-71	0	50	\N	\N	1778324211645	2026-05-09 12:56:51.645+02	2026-05-09 12:56:51.844533+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:51.844533+02
19834	10	E28011704000021D53DAB0CB	\N	-69	0	42	\N	\N	1778324211795	2026-05-09 12:56:51.795+02	2026-05-09 12:56:51.904898+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:51.904898+02
19835	10	E28011704000021D53DAB0CB	\N	-65	0	17	\N	\N	1778324211945	2026-05-09 12:56:51.945+02	2026-05-09 12:56:52.053809+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:52.053809+02
19838	10	E28011704000021D53DAB0CB	\N	-61	0	49	\N	\N	1778324212112	2026-05-09 12:56:52.112+02	2026-05-09 12:56:52.471914+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:52.471914+02
19839	10	E28011704000021D53DAB0CB	\N	-61	0	47	\N	\N	1778324212245	2026-05-09 12:56:52.245+02	2026-05-09 12:56:52.661522+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:52.661522+02
19842	10	E28011704000021D53DAB0CB	\N	-64	0	17	\N	\N	1778324212401	2026-05-09 12:56:52.401+02	2026-05-09 12:56:53.06682+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.06682+02
19843	10	E28011704000021D53DAB0CB	\N	-67	0	28	\N	\N	1778324212546	2026-05-09 12:56:52.546+02	2026-05-09 12:56:53.084908+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.084908+02
19846	10	E28011704000021D53DAB0CB	\N	-56	0	33	\N	\N	1778324212696	2026-05-09 12:56:52.696+02	2026-05-09 12:56:53.108727+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.108727+02
19822	10	E28011704000021D53DAB0CB	\N	-70	0	38	\N	\N	1778324204295	2026-05-09 12:56:44.295+02	2026-05-09 12:56:44.986092+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:44.986092+02
19825	10	E28011704000021D53DAB0CB	\N	-67	0	47	\N	\N	1778324204459	2026-05-09 12:56:44.459+02	2026-05-09 12:56:45.002914+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.002914+02
19826	10	E28011704000021D53DAB0CB	\N	-62	0	59	\N	\N	1778324204595	2026-05-09 12:56:44.595+02	2026-05-09 12:56:45.0384+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.0384+02
19827	10	E28011704000021D53DAB0CB	\N	-62	0	51	\N	\N	1778324204763	2026-05-09 12:56:44.763+02	2026-05-09 12:56:45.069572+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.069572+02
19830	10	E28011704000021D53DAB0CB	\N	-67	0	39	\N	\N	1778324204895	2026-05-09 12:56:44.895+02	2026-05-09 12:56:45.114735+02	2026-05-09 12:56:49.138+02	\N	\N	realtime	synced	2026-05-09 12:56:45.114735+02
19913	10	E28011704000021D53DAB0CB	\N	-63	0	30	\N	\N	1778324235362	2026-05-09 12:57:15.362+02	2026-05-09 12:57:16.093105+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.093105+02
19915	10	E28011704000021D53DAB0CB	\N	-58	0	36	\N	\N	1778324235496	2026-05-09 12:57:15.496+02	2026-05-09 12:57:16.220752+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.220752+02
19917	10	E28011704000021D53DAB0CB	\N	-61	0	23	\N	\N	1778324235658	2026-05-09 12:57:15.658+02	2026-05-09 12:57:16.300315+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.300315+02
19919	10	E28011704000021D53DAB0CB	\N	-61	0	57	\N	\N	1778324235796	2026-05-09 12:57:15.796+02	2026-05-09 12:57:16.334689+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.334689+02
19927	10	E28011704000021D53DAB0CB	\N	-54	0	14	\N	\N	1778324236546	2026-05-09 12:57:16.546+02	2026-05-09 12:57:17.628909+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.628909+02
19929	10	E28011704000021D53DAB0CB	\N	-56	0	38	\N	\N	1778324236696	2026-05-09 12:57:16.696+02	2026-05-09 12:57:17.936013+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.936013+02
19931	10	E28011704000021D53DAB0CB	\N	-58	0	19	\N	\N	1778324236845	2026-05-09 12:57:16.845+02	2026-05-09 12:57:17.978545+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.978545+02
19933	10	E28011704000021D53DAB0CB	\N	-54	0	11	\N	\N	1778324237013	2026-05-09 12:57:17.013+02	2026-05-09 12:57:17.990284+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.990284+02
19935	10	E28011704000021D53DAB0CB	\N	-63	0	20	\N	\N	1778324237145	2026-05-09 12:57:17.145+02	2026-05-09 12:57:18.024221+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.024221+02
19940	9	E28011704000021D53DAB0CB	\N	-73	0	11	\N	\N	1778324237561	2026-05-09 12:57:17.561+02	2026-05-09 12:57:18.345027+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.345027+02
19942	9	E28011704000021D53DAB0CB	\N	-67	0	13	\N	\N	1778324237726	2026-05-09 12:57:17.726+02	2026-05-09 12:57:18.464395+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.464395+02
20143	9	E28011704000021D53DAB0CB	\N	-67	0	57	\N	\N	1778324300885	2026-05-09 12:58:20.885+02	2026-05-09 12:58:21.247705+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.247705+02
20148	9	E28011704000021D53DAB0CB	\N	-62	0	13	\N	\N	1778324301482	2026-05-09 12:58:21.482+02	2026-05-09 12:58:21.518069+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.518069+02
19995	10	E28011704000021D53DAB0CB	\N	-64	0	13	\N	\N	1778324252745	2026-05-09 12:57:32.745+02	2026-05-09 12:57:32.820528+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.820528+02
19996	10	E28011704000021D53DAB0CB	\N	-63	0	9	\N	\N	1778324252895	2026-05-09 12:57:32.895+02	2026-05-09 12:57:33.911002+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.911002+02
20150	10	E28011704000021D53DAB0CB	\N	-64	0	22	\N	\N	1778324302245	2026-05-09 12:58:22.245+02	2026-05-09 12:58:22.551237+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:22.551237+02
20155	10	E28011704000021D53DAB0CB	\N	-60	0	41	\N	\N	1778324302696	2026-05-09 12:58:22.696+02	2026-05-09 12:58:23.779508+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.779508+02
20154	10	E28011704000021D53DAB0CB	\N	-64	0	52	\N	\N	1778324302545	2026-05-09 12:58:22.545+02	2026-05-09 12:58:22.693782+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:22.693782+02
20158	10	E28011704000021D53DAB0CB	\N	-64	0	22	\N	\N	1778324302996	2026-05-09 12:58:22.996+02	2026-05-09 12:58:23.83959+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.83959+02
20160	10	E28011704000021D53DAB0CB	\N	-56	0	44	\N	\N	1778324303145	2026-05-09 12:58:23.145+02	2026-05-09 12:58:23.898571+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.898571+02
20162	10	E28011704000021D53DAB0CB	\N	-58	0	21	\N	\N	1778324303295	2026-05-09 12:58:23.295+02	2026-05-09 12:58:23.939189+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.939189+02
20164	10	E28011704000021D53DAB0CB	\N	-59	0	44	\N	\N	1778324303445	2026-05-09 12:58:23.445+02	2026-05-09 12:58:23.958918+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.958918+02
20166	10	E28011704000021D53DAB0CB	\N	-54	0	29	\N	\N	1778324303597	2026-05-09 12:58:23.597+02	2026-05-09 12:58:23.993296+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.993296+02
20168	10	E28011704000021D53DAB0CB	\N	-64	0	8	\N	\N	1778324303750	2026-05-09 12:58:23.75+02	2026-05-09 12:58:24.018121+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:24.018121+02
20170	10	E28011704000021D53DAB0CB	\N	-68	0	47	\N	\N	1778324303895	2026-05-09 12:58:23.895+02	2026-05-09 12:58:24.051868+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:24.051868+02
20006	10	E28011704000021D53DAB0CB	\N	-65	0	55	\N	\N	1778324262345	2026-05-09 12:57:42.345+02	2026-05-09 12:57:43.331054+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.331054+02
19847	10	E28011704000021D53DAB0CB	\N	-61	0	16	\N	\N	1778324212860	2026-05-09 12:56:52.86+02	2026-05-09 12:56:53.137301+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.137301+02
19848	10	E28011704000021D53DAB0CB	\N	-51	0	56	\N	\N	1778324212995	2026-05-09 12:56:52.995+02	2026-05-09 12:56:53.165478+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.165478+02
19851	10	E28011704000021D53DAB0CB	\N	-55	0	33	\N	\N	1778324213301	2026-05-09 12:56:53.301+02	2026-05-09 12:56:56.250653+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.250653+02
19853	10	E28011704000021D53DAB0CB	\N	-55	0	44	\N	\N	1778324213301	2026-05-09 12:56:53.301+02	2026-05-09 12:56:56.252629+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.252629+02
19856	10	E28011704000021D53DAB0CB	\N	-56	0	47	\N	\N	1778324213595	2026-05-09 12:56:53.595+02	2026-05-09 12:56:56.260624+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.260624+02
19857	10	E28011704000021D53DAB0CB	\N	-59	0	26	\N	\N	1778324213745	2026-05-09 12:56:53.745+02	2026-05-09 12:56:56.270365+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.270365+02
19858	9	E28011704000021D53DAB0CB	\N	-74	0	21	\N	\N	1778324213411	2026-05-09 12:56:53.411+02	2026-05-09 12:56:56.285178+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.285178+02
19861	10	E28011704000021D53DAB0CB	\N	-67	0	8	\N	\N	1778324213895	2026-05-09 12:56:53.895+02	2026-05-09 12:56:56.302019+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.302019+02
19862	10	E28011704000021D53DAB0CB	\N	-59	0	26	\N	\N	1778324213745	2026-05-09 12:56:53.745+02	2026-05-09 12:56:56.311362+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.311362+02
19864	9	E28011704000021D53DAB0CB	\N	-74	0	43	\N	\N	1778324213711	2026-05-09 12:56:53.711+02	2026-05-09 12:56:57.520985+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.520985+02
19866	9	E28011704000021D53DAB0CB	\N	-77	0	40	\N	\N	1778324213865	2026-05-09 12:56:53.865+02	2026-05-09 12:56:57.530564+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.530564+02
19868	9	E28011704000021D53DAB0CB	\N	-68	0	48	\N	\N	1778324214043	2026-05-09 12:56:54.043+02	2026-05-09 12:56:57.534523+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.534523+02
19870	9	E28011704000021D53DAB0CB	\N	-73	0	23	\N	\N	1778324214161	2026-05-09 12:56:54.161+02	2026-05-09 12:56:57.548316+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.548316+02
19872	9	E28011704000021D53DAB0CB	\N	-64	0	39	\N	\N	1778324214313	2026-05-09 12:56:54.313+02	2026-05-09 12:56:57.591779+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.591779+02
19874	9	E28011704000021D53DAB0CB	\N	-63	0	22	\N	\N	1778324214461	2026-05-09 12:56:54.461+02	2026-05-09 12:56:57.603469+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.603469+02
19881	9	E28011704000021D53DAB0CB	\N	-62	0	25	\N	\N	1778324215211	2026-05-09 12:56:55.211+02	2026-05-09 12:56:57.703125+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.703125+02
19883	9	E28011704000021D53DAB0CB	\N	-57	0	40	\N	\N	1778324215378	2026-05-09 12:56:55.378+02	2026-05-09 12:56:57.71604+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.71604+02
19901	9	E28011704000021D53DAB0CB	\N	-68	0	15	\N	\N	1778324225139	2026-05-09 12:57:05.139+02	2026-05-09 12:57:05.251112+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:05.251112+02
19903	9	E28011704000021D53DAB0CB	\N	-63	0	46	\N	\N	1778324225262	2026-05-09 12:57:05.262+02	2026-05-09 12:57:05.310911+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:05.310911+02
19905	9	E28011704000021D53DAB0CB	\N	-65	0	43	\N	\N	1778324225418	2026-05-09 12:57:05.418+02	2026-05-09 12:57:05.960601+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:05.960601+02
19909	10	E28011704000021D53DAB0CB	\N	-68	0	21	\N	\N	1778324227556	2026-05-09 12:57:07.556+02	2026-05-09 12:57:08.006167+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:08.006167+02
20062	9	E28011704000021D53DAB0CB	\N	-62	0	52	\N	\N	1778324277911	2026-05-09 12:57:57.911+02	2026-05-09 12:57:58.233191+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.233191+02
20072	10	E28011704000021D53DAB0CB	\N	-71	0	16	\N	\N	1778324279754	2026-05-09 12:57:59.754+02	2026-05-09 12:58:00.868498+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:00.868498+02
20074	10	E28011704000021D53DAB0CB	\N	-70	0	10	\N	\N	1778324280046	2026-05-09 12:58:00.046+02	2026-05-09 12:58:01.270127+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.270127+02
20076	10	E28011704000021D53DAB0CB	\N	-70	0	48	\N	\N	1778324280196	2026-05-09 12:58:00.196+02	2026-05-09 12:58:01.305863+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.305863+02
20077	10	E28011704000021D53DAB0CB	\N	-60	0	8	\N	\N	1778324280345	2026-05-09 12:58:00.345+02	2026-05-09 12:58:01.321007+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.321007+02
19914	10	E28011704000021D53DAB0CB	\N	-59	0	25	\N	\N	1778324235362	2026-05-09 12:57:15.362+02	2026-05-09 12:57:16.095499+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.095499+02
19897	9	E28011704000021D53DAB0CB	\N	-74	0	37	\N	\N	1778324216862	2026-05-09 12:56:56.862+02	2026-05-09 12:56:57.96774+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.96774+02
19916	10	E28011704000021D53DAB0CB	\N	-58	0	17	\N	\N	1778324235496	2026-05-09 12:57:15.496+02	2026-05-09 12:57:16.222714+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.222714+02
19918	10	E28011704000021D53DAB0CB	\N	-62	0	59	\N	\N	1778324235658	2026-05-09 12:57:15.658+02	2026-05-09 12:57:16.302954+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.302954+02
19921	10	E28011704000021D53DAB0CB	\N	-61	0	30	\N	\N	1778324236097	2026-05-09 12:57:16.097+02	2026-05-09 12:57:16.388177+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.388177+02
19923	10	E28011704000021D53DAB0CB	\N	-61	0	58	\N	\N	1778324236255	2026-05-09 12:57:16.255+02	2026-05-09 12:57:16.416431+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.416431+02
19925	10	E28011704000021D53DAB0CB	\N	-56	0	50	\N	\N	1778324236395	2026-05-09 12:57:16.395+02	2026-05-09 12:57:16.448687+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:16.448687+02
19900	9	E28011704000021D53DAB0CB	\N	-73	0	28	\N	\N	1778324224966	2026-05-09 12:57:04.966+02	2026-05-09 12:57:05.188292+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:05.188292+02
19902	9	E28011704000021D53DAB0CB	\N	-67	0	45	\N	\N	1778324225139	2026-05-09 12:57:05.139+02	2026-05-09 12:57:05.253049+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:05.253049+02
19904	9	E28011704000021D53DAB0CB	\N	-67	0	47	\N	\N	1778324225418	2026-05-09 12:57:05.418+02	2026-05-09 12:57:05.95705+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:05.95705+02
19907	9	E28011704000021D53DAB0CB	\N	-68	0	24	\N	\N	1778324225712	2026-05-09 12:57:05.712+02	2026-05-09 12:57:06.008974+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:06.008974+02
19911	10	E28011704000021D53DAB0CB	\N	-62	0	10	\N	\N	1778324227846	2026-05-09 12:57:07.846+02	2026-05-09 12:57:08.725429+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:08.725429+02
20147	9	E28011704000021D53DAB0CB	\N	-61	0	57	\N	\N	1778324301311	2026-05-09 12:58:21.311+02	2026-05-09 12:58:21.430151+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.430151+02
20149	9	E28011704000021D53DAB0CB	\N	-72	0	14	\N	\N	1778324301482	2026-05-09 12:58:21.482+02	2026-05-09 12:58:21.520221+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:21.520221+02
20151	10	E28011704000021D53DAB0CB	\N	-67	0	25	\N	\N	1778324302245	2026-05-09 12:58:22.245+02	2026-05-09 12:58:22.55309+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:22.55309+02
20153	10	E28011704000021D53DAB0CB	\N	-68	0	36	\N	\N	1778324302545	2026-05-09 12:58:22.545+02	2026-05-09 12:58:22.691488+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:22.691488+02
20156	10	E28011704000021D53DAB0CB	\N	-59	0	55	\N	\N	1778324302696	2026-05-09 12:58:22.696+02	2026-05-09 12:58:23.782875+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.782875+02
20163	10	E28011704000021D53DAB0CB	\N	-58	0	54	\N	\N	1778324303445	2026-05-09 12:58:23.445+02	2026-05-09 12:58:23.956642+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.956642+02
20165	10	E28011704000021D53DAB0CB	\N	-57	0	28	\N	\N	1778324303597	2026-05-09 12:58:23.597+02	2026-05-09 12:58:23.990569+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.990569+02
19928	10	E28011704000021D53DAB0CB	\N	-52	0	12	\N	\N	1778324236546	2026-05-09 12:57:16.546+02	2026-05-09 12:57:17.630775+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.630775+02
19930	10	E28011704000021D53DAB0CB	\N	-56	0	8	\N	\N	1778324236696	2026-05-09 12:57:16.696+02	2026-05-09 12:57:17.939224+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:17.939224+02
19937	10	E28011704000021D53DAB0CB	\N	-58	0	30	\N	\N	1778324237445	2026-05-09 12:57:17.445+02	2026-05-09 12:57:18.06181+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.06181+02
19939	10	E28011704000021D53DAB0CB	\N	-65	0	40	\N	\N	1778324237599	2026-05-09 12:57:17.599+02	2026-05-09 12:57:18.101714+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.101714+02
19941	9	E28011704000021D53DAB0CB	\N	-67	0	22	\N	\N	1778324237561	2026-05-09 12:57:17.561+02	2026-05-09 12:57:18.34741+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.34741+02
19946	9	E28011704000021D53DAB0CB	\N	-71	0	45	\N	\N	1778324238161	2026-05-09 12:57:18.161+02	2026-05-09 12:57:18.639595+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.639595+02
19954	9	E28011704000021D53DAB0CB	\N	-58	0	18	\N	\N	1778324238912	2026-05-09 12:57:18.912+02	2026-05-09 12:57:19.885256+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:19.885256+02
19959	9	E28011704000021D53DAB0CB	\N	-61	0	20	\N	\N	1778324239531	2026-05-09 12:57:19.531+02	2026-05-09 12:57:20.067405+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.067405+02
19961	9	E28011704000021D53DAB0CB	\N	-62	0	45	\N	\N	1778324239661	2026-05-09 12:57:19.661+02	2026-05-09 12:57:20.099822+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.099822+02
19982	10	E28011704000021D53DAB0CB	\N	-64	0	22	\N	\N	1778324251551	2026-05-09 12:57:31.551+02	2026-05-09 12:57:32.504593+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.504593+02
19987	10	E28011704000021D53DAB0CB	\N	-62	0	56	\N	\N	1778324252150	2026-05-09 12:57:32.15+02	2026-05-09 12:57:32.642988+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.642988+02
19989	10	E28011704000021D53DAB0CB	\N	-61	0	9	\N	\N	1778324252296	2026-05-09 12:57:32.296+02	2026-05-09 12:57:32.701702+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.701702+02
19991	10	E28011704000021D53DAB0CB	\N	-58	0	37	\N	\N	1778324252451	2026-05-09 12:57:32.451+02	2026-05-09 12:57:32.752001+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.752001+02
19993	10	E28011704000021D53DAB0CB	\N	-64	0	59	\N	\N	1778324252595	2026-05-09 12:57:32.595+02	2026-05-09 12:57:32.802028+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.802028+02
19994	10	E28011704000021D53DAB0CB	\N	-65	0	41	\N	\N	1778324252745	2026-05-09 12:57:32.745+02	2026-05-09 12:57:32.818546+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:32.818546+02
19997	10	E28011704000021D53DAB0CB	\N	-71	0	22	\N	\N	1778324252895	2026-05-09 12:57:32.895+02	2026-05-09 12:57:33.913909+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.913909+02
19999	10	E28011704000021D53DAB0CB	\N	-74	0	11	\N	\N	1778324253051	2026-05-09 12:57:33.051+02	2026-05-09 12:57:33.940004+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.940004+02
20001	10	E28011704000021D53DAB0CB	\N	-64	0	50	\N	\N	1778324253195	2026-05-09 12:57:33.195+02	2026-05-09 12:57:33.967383+02	2026-05-09 12:57:39.184+02	\N	\N	realtime	synced	2026-05-09 12:57:33.967383+02
20003	10	E28011704000021D53DAB0CB	\N	-74	0	43	\N	\N	1778324262062	2026-05-09 12:57:42.062+02	2026-05-09 12:57:42.206079+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:42.206079+02
20005	10	E28011704000021D53DAB0CB	\N	-67	0	44	\N	\N	1778324262195	2026-05-09 12:57:42.195+02	2026-05-09 12:57:42.228811+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:42.228811+02
20009	10	E28011704000021D53DAB0CB	\N	-67	0	15	\N	\N	1778324262946	2026-05-09 12:57:42.946+02	2026-05-09 12:57:43.418217+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.418217+02
20011	10	E28011704000021D53DAB0CB	\N	-65	0	19	\N	\N	1778324263096	2026-05-09 12:57:43.096+02	2026-05-09 12:57:43.476746+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.476746+02
20013	10	E28011704000021D53DAB0CB	\N	-64	0	37	\N	\N	1778324263396	2026-05-09 12:57:43.396+02	2026-05-09 12:57:43.562681+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.562681+02
20015	10	E28011704000021D53DAB0CB	\N	-63	0	21	\N	\N	1778324263545	2026-05-09 12:57:43.545+02	2026-05-09 12:57:43.602828+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.602828+02
20024	10	E28011704000021D53DAB0CB	\N	-62	0	51	\N	\N	1778324264462	2026-05-09 12:57:44.462+02	2026-05-09 12:57:44.85107+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.85107+02
20026	10	E28011704000021D53DAB0CB	\N	-68	0	35	\N	\N	1778324264601	2026-05-09 12:57:44.601+02	2026-05-09 12:57:44.881049+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.881049+02
20028	10	E28011704000021D53DAB0CB	\N	-65	0	46	\N	\N	1778324264747	2026-05-09 12:57:44.747+02	2026-05-09 12:57:44.920359+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.920359+02
20078	10	E28011704000021D53DAB0CB	\N	-65	0	45	\N	\N	1778324280345	2026-05-09 12:58:00.345+02	2026-05-09 12:58:01.323139+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.323139+02
20079	10	E28011704000021D53DAB0CB	\N	-59	0	43	\N	\N	1778324280495	2026-05-09 12:58:00.495+02	2026-05-09 12:58:01.341867+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.341867+02
20080	10	E28011704000021D53DAB0CB	\N	-56	0	50	\N	\N	1778324280495	2026-05-09 12:58:00.495+02	2026-05-09 12:58:01.344072+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.344072+02
20081	10	E28011704000021D53DAB0CB	\N	-55	0	37	\N	\N	1778324280645	2026-05-09 12:58:00.645+02	2026-05-09 12:58:01.366783+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.366783+02
20082	10	E28011704000021D53DAB0CB	\N	-61	0	30	\N	\N	1778324280645	2026-05-09 12:58:00.645+02	2026-05-09 12:58:01.368901+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.368901+02
20083	10	E28011704000021D53DAB0CB	\N	-54	0	19	\N	\N	1778324280795	2026-05-09 12:58:00.795+02	2026-05-09 12:58:01.387039+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.387039+02
20084	10	E28011704000021D53DAB0CB	\N	-63	0	34	\N	\N	1778324280795	2026-05-09 12:58:00.795+02	2026-05-09 12:58:01.388961+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.388961+02
20063	9	E28011704000021D53DAB0CB	\N	-61	0	47	\N	\N	1778324278061	2026-05-09 12:57:58.061+02	2026-05-09 12:57:58.26239+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.26239+02
20065	9	E28011704000021D53DAB0CB	\N	-58	0	59	\N	\N	1778324278217	2026-05-09 12:57:58.217+02	2026-05-09 12:57:58.412072+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.412072+02
20067	9	E28011704000021D53DAB0CB	\N	-57	0	52	\N	\N	1778324278361	2026-05-09 12:57:58.361+02	2026-05-09 12:57:58.764016+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.764016+02
20069	9	E28011704000021D53DAB0CB	\N	-67	0	25	\N	\N	1778324278662	2026-05-09 12:57:58.662+02	2026-05-09 12:57:59.236844+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:59.236844+02
19885	9	E28011704000021D53DAB0CB	\N	-59	0	46	\N	\N	1778324215514	2026-05-09 12:56:55.514+02	2026-05-09 12:56:57.768016+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.768016+02
19890	9	E28011704000021D53DAB0CB	\N	-58	0	29	\N	\N	1778324216114	2026-05-09 12:56:56.114+02	2026-05-09 12:56:57.856367+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.856367+02
19892	9	E28011704000021D53DAB0CB	\N	-62	0	20	\N	\N	1778324216263	2026-05-09 12:56:56.263+02	2026-05-09 12:56:57.874912+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.874912+02
19895	9	E28011704000021D53DAB0CB	\N	-68	0	20	\N	\N	1778324216712	2026-05-09 12:56:56.712+02	2026-05-09 12:56:57.962587+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.962587+02
19831	10	E28011704000021D53DAB0CB	\N	-71	0	8	\N	\N	1778324211345	2026-05-09 12:56:51.345+02	2026-05-09 12:56:51.823945+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:51.823945+02
19832	10	E28011704000021D53DAB0CB	\N	-64	0	53	\N	\N	1778324211645	2026-05-09 12:56:51.645+02	2026-05-09 12:56:51.842364+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:51.842364+02
19836	10	E28011704000021D53DAB0CB	\N	-64	0	41	\N	\N	1778324211945	2026-05-09 12:56:51.945+02	2026-05-09 12:56:52.056427+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:52.056427+02
19837	10	E28011704000021D53DAB0CB	\N	-62	0	40	\N	\N	1778324212112	2026-05-09 12:56:52.112+02	2026-05-09 12:56:52.468106+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:52.468106+02
19840	10	E28011704000021D53DAB0CB	\N	-58	0	47	\N	\N	1778324212245	2026-05-09 12:56:52.245+02	2026-05-09 12:56:52.664206+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:52.664206+02
19841	10	E28011704000021D53DAB0CB	\N	-63	0	30	\N	\N	1778324212401	2026-05-09 12:56:52.401+02	2026-05-09 12:56:53.064948+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.064948+02
19844	10	E28011704000021D53DAB0CB	\N	-60	0	21	\N	\N	1778324212546	2026-05-09 12:56:52.546+02	2026-05-09 12:56:53.086713+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.086713+02
19845	10	E28011704000021D53DAB0CB	\N	-59	0	41	\N	\N	1778324212696	2026-05-09 12:56:52.696+02	2026-05-09 12:56:53.107029+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.107029+02
19849	10	E28011704000021D53DAB0CB	\N	-56	0	57	\N	\N	1778324212995	2026-05-09 12:56:52.995+02	2026-05-09 12:56:53.167449+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:53.167449+02
19850	10	E28011704000021D53DAB0CB	\N	-53	0	37	\N	\N	1778324213146	2026-05-09 12:56:53.146+02	2026-05-09 12:56:56.003769+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.003769+02
19852	10	E28011704000021D53DAB0CB	\N	-55	0	21	\N	\N	1778324213446	2026-05-09 12:56:53.446+02	2026-05-09 12:56:56.250911+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.250911+02
19854	10	E28011704000021D53DAB0CB	\N	-55	0	54	\N	\N	1778324213446	2026-05-09 12:56:53.446+02	2026-05-09 12:56:56.253673+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.253673+02
19855	10	E28011704000021D53DAB0CB	\N	-55	0	15	\N	\N	1778324213595	2026-05-09 12:56:53.595+02	2026-05-09 12:56:56.258602+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.258602+02
19859	9	E28011704000021D53DAB0CB	\N	-68	0	19	\N	\N	1778324213411	2026-05-09 12:56:53.411+02	2026-05-09 12:56:56.287045+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.287045+02
19860	10	E28011704000021D53DAB0CB	\N	-61	0	37	\N	\N	1778324213895	2026-05-09 12:56:53.895+02	2026-05-09 12:56:56.297549+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:56.297549+02
19863	9	E28011704000021D53DAB0CB	\N	-72	0	26	\N	\N	1778324213563	2026-05-09 12:56:53.563+02	2026-05-09 12:56:57.520937+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.520937+02
19865	9	E28011704000021D53DAB0CB	\N	-71	0	43	\N	\N	1778324213563	2026-05-09 12:56:53.563+02	2026-05-09 12:56:57.522831+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.522831+02
19867	9	E28011704000021D53DAB0CB	\N	-73	0	16	\N	\N	1778324213865	2026-05-09 12:56:53.865+02	2026-05-09 12:56:57.532918+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.532918+02
19869	9	E28011704000021D53DAB0CB	\N	-69	0	9	\N	\N	1778324214043	2026-05-09 12:56:54.043+02	2026-05-09 12:56:57.538513+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.538513+02
19871	9	E28011704000021D53DAB0CB	\N	-67	0	21	\N	\N	1778324214161	2026-05-09 12:56:54.161+02	2026-05-09 12:56:57.550521+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.550521+02
19873	9	E28011704000021D53DAB0CB	\N	-65	0	9	\N	\N	1778324214461	2026-05-09 12:56:54.461+02	2026-05-09 12:56:57.598661+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.598661+02
19875	9	E28011704000021D53DAB0CB	\N	-64	0	17	\N	\N	1778324214628	2026-05-09 12:56:54.628+02	2026-05-09 12:56:57.619114+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.619114+02
19876	9	E28011704000021D53DAB0CB	\N	-65	0	39	\N	\N	1778324214762	2026-05-09 12:56:54.762+02	2026-05-09 12:56:57.627619+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.627619+02
19877	9	E28011704000021D53DAB0CB	\N	-64	0	48	\N	\N	1778324214762	2026-05-09 12:56:54.762+02	2026-05-09 12:56:57.630318+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.630318+02
19878	9	E28011704000021D53DAB0CB	\N	-64	0	33	\N	\N	1778324214925	2026-05-09 12:56:54.925+02	2026-05-09 12:56:57.681004+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.681004+02
19879	9	E28011704000021D53DAB0CB	\N	-63	0	54	\N	\N	1778324214925	2026-05-09 12:56:54.925+02	2026-05-09 12:56:57.682885+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.682885+02
19880	9	E28011704000021D53DAB0CB	\N	-62	0	27	\N	\N	1778324215061	2026-05-09 12:56:55.061+02	2026-05-09 12:56:57.688156+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.688156+02
19882	9	E28011704000021D53DAB0CB	\N	-59	0	56	\N	\N	1778324215211	2026-05-09 12:56:55.211+02	2026-05-09 12:56:57.705102+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.705102+02
19884	9	E28011704000021D53DAB0CB	\N	-61	0	53	\N	\N	1778324215514	2026-05-09 12:56:55.514+02	2026-05-09 12:56:57.76637+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.76637+02
19886	9	E28011704000021D53DAB0CB	\N	-58	0	59	\N	\N	1778324215661	2026-05-09 12:56:55.661+02	2026-05-09 12:56:57.784573+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.784573+02
19887	9	E28011704000021D53DAB0CB	\N	-55	0	46	\N	\N	1778324215821	2026-05-09 12:56:55.821+02	2026-05-09 12:56:57.794892+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.794892+02
19888	9	E28011704000021D53DAB0CB	\N	-55	0	8	\N	\N	1778324215821	2026-05-09 12:56:55.821+02	2026-05-09 12:56:57.797095+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.797095+02
19889	9	E28011704000021D53DAB0CB	\N	-59	0	15	\N	\N	1778324215963	2026-05-09 12:56:55.963+02	2026-05-09 12:56:57.806833+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.806833+02
19891	9	E28011704000021D53DAB0CB	\N	-57	0	41	\N	\N	1778324216114	2026-05-09 12:56:56.114+02	2026-05-09 12:56:57.860014+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.860014+02
19893	9	E28011704000021D53DAB0CB	\N	-59	0	36	\N	\N	1778324216412	2026-05-09 12:56:56.412+02	2026-05-09 12:56:57.893692+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.893692+02
19894	9	E28011704000021D53DAB0CB	\N	-62	0	42	\N	\N	1778324216561	2026-05-09 12:56:56.561+02	2026-05-09 12:56:57.942546+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.942546+02
19896	9	E28011704000021D53DAB0CB	\N	-73	0	15	\N	\N	1778324216712	2026-05-09 12:56:56.712+02	2026-05-09 12:56:57.964514+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:57.964514+02
19898	9	E28011704000021D53DAB0CB	\N	-59	0	36	\N	\N	1778324216412	2026-05-09 12:56:56.412+02	2026-05-09 12:56:58.024481+02	2026-05-09 12:57:01.158+02	\N	\N	realtime	synced	2026-05-09 12:56:58.024481+02
20167	10	E28011704000021D53DAB0CB	\N	-58	0	13	\N	\N	1778324303750	2026-05-09 12:58:23.75+02	2026-05-09 12:58:24.016191+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:24.016191+02
20169	10	E28011704000021D53DAB0CB	\N	-62	0	42	\N	\N	1778324303895	2026-05-09 12:58:23.895+02	2026-05-09 12:58:24.049821+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:24.049821+02
20157	10	E28011704000021D53DAB0CB	\N	-63	0	24	\N	\N	1778324302852	2026-05-09 12:58:22.852+02	2026-05-09 12:58:23.808057+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.808057+02
20159	10	E28011704000021D53DAB0CB	\N	-58	0	37	\N	\N	1778324302996	2026-05-09 12:58:22.996+02	2026-05-09 12:58:23.841711+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.841711+02
20161	10	E28011704000021D53DAB0CB	\N	-56	0	58	\N	\N	1778324303145	2026-05-09 12:58:23.145+02	2026-05-09 12:58:23.900437+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:23.900437+02
19899	9	E28011704000021D53DAB0CB	\N	-73	0	11	\N	\N	1778324223461	2026-05-09 12:57:03.461+02	2026-05-09 12:57:04.157623+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:04.157623+02
19906	9	E28011704000021D53DAB0CB	\N	-67	0	47	\N	\N	1778324225568	2026-05-09 12:57:05.568+02	2026-05-09 12:57:06.000751+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:06.000751+02
19908	10	E28011704000021D53DAB0CB	\N	-67	0	49	\N	\N	1778324227556	2026-05-09 12:57:07.556+02	2026-05-09 12:57:08.002852+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:08.002852+02
19910	10	E28011704000021D53DAB0CB	\N	-66	0	14	\N	\N	1778324227696	2026-05-09 12:57:07.696+02	2026-05-09 12:57:08.412525+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:08.412525+02
19912	10	E28011704000021D53DAB0CB	\N	-64	0	13	\N	\N	1778324227846	2026-05-09 12:57:07.846+02	2026-05-09 12:57:08.72796+02	2026-05-09 12:57:13.166+02	\N	\N	realtime	synced	2026-05-09 12:57:08.72796+02
19950	9	E28011704000021D53DAB0CB	\N	-62	0	31	\N	\N	1778324238628	2026-05-09 12:57:18.628+02	2026-05-09 12:57:18.75073+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.75073+02
19952	9	E28011704000021D53DAB0CB	\N	-63	0	8	\N	\N	1778324238765	2026-05-09 12:57:18.765+02	2026-05-09 12:57:18.790707+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:18.790707+02
19956	9	E28011704000021D53DAB0CB	\N	-61	0	32	\N	\N	1778324239211	2026-05-09 12:57:19.211+02	2026-05-09 12:57:20.03849+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.03849+02
19958	9	E28011704000021D53DAB0CB	\N	-61	0	22	\N	\N	1778324239362	2026-05-09 12:57:19.362+02	2026-05-09 12:57:20.051222+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.051222+02
19963	9	E28011704000021D53DAB0CB	\N	-73	0	54	\N	\N	1778324239968	2026-05-09 12:57:19.968+02	2026-05-09 12:57:20.184132+02	2026-05-09 12:57:25.175+02	\N	\N	realtime	synced	2026-05-09 12:57:20.184132+02
20004	10	E28011704000021D53DAB0CB	\N	-67	0	28	\N	\N	1778324262195	2026-05-09 12:57:42.195+02	2026-05-09 12:57:42.226978+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:42.226978+02
20007	10	E28011704000021D53DAB0CB	\N	-67	0	39	\N	\N	1778324262345	2026-05-09 12:57:42.345+02	2026-05-09 12:57:43.333943+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.333943+02
20012	10	E28011704000021D53DAB0CB	\N	-64	0	17	\N	\N	1778324263396	2026-05-09 12:57:43.396+02	2026-05-09 12:57:43.560576+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.560576+02
20014	10	E28011704000021D53DAB0CB	\N	-58	0	32	\N	\N	1778324263545	2026-05-09 12:57:43.545+02	2026-05-09 12:57:43.600071+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.600071+02
20016	10	E28011704000021D53DAB0CB	\N	-63	0	16	\N	\N	1778324263712	2026-05-09 12:57:43.712+02	2026-05-09 12:57:44.667885+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.667885+02
20018	10	E28011704000021D53DAB0CB	\N	-67	0	56	\N	\N	1778324263845	2026-05-09 12:57:43.845+02	2026-05-09 12:57:44.692662+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.692662+02
20020	10	E28011704000021D53DAB0CB	\N	-65	0	23	\N	\N	1778324263995	2026-05-09 12:57:43.995+02	2026-05-09 12:57:44.720641+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.720641+02
20022	10	E28011704000021D53DAB0CB	\N	-60	0	24	\N	\N	1778324264145	2026-05-09 12:57:44.145+02	2026-05-09 12:57:44.792209+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.792209+02
20029	10	E28011704000021D53DAB0CB	\N	-71	0	21	\N	\N	1778324264904	2026-05-09 12:57:44.904+02	2026-05-09 12:57:44.944572+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.944572+02
20033	9	E28011704000021D53DAB0CB	\N	-63	0	24	\N	\N	1778324265011	2026-05-09 12:57:45.011+02	2026-05-09 12:57:45.860594+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.860594+02
20035	9	E28011704000021D53DAB0CB	\N	-71	0	21	\N	\N	1778324265161	2026-05-09 12:57:45.161+02	2026-05-09 12:57:45.944924+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.944924+02
20038	9	E28011704000021D53DAB0CB	\N	-67	0	25	\N	\N	1778324265611	2026-05-09 12:57:45.611+02	2026-05-09 12:57:46.021314+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.021314+02
20040	10	E28011704000021D53DAB0CB	\N	-74	0	30	\N	\N	1778324265046	2026-05-09 12:57:45.046+02	2026-05-09 12:57:46.028028+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.028028+02
20042	10	E28011704000021D53DAB0CB	\N	-71	0	27	\N	\N	1778324265195	2026-05-09 12:57:45.195+02	2026-05-09 12:57:46.042828+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.042828+02
20048	9	E28011704000021D53DAB0CB	\N	-54	0	33	\N	\N	1778324266213	2026-05-09 12:57:46.213+02	2026-05-09 12:57:47.325219+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.325219+02
20050	9	E28011704000021D53DAB0CB	\N	-59	0	58	\N	\N	1778324266371	2026-05-09 12:57:46.371+02	2026-05-09 12:57:47.706894+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.706894+02
20008	10	E28011704000021D53DAB0CB	\N	-73	0	51	\N	\N	1778324262796	2026-05-09 12:57:42.796+02	2026-05-09 12:57:43.378158+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.378158+02
20010	10	E28011704000021D53DAB0CB	\N	-65	0	30	\N	\N	1778324262946	2026-05-09 12:57:42.946+02	2026-05-09 12:57:43.420408+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:43.420408+02
20017	10	E28011704000021D53DAB0CB	\N	-67	0	46	\N	\N	1778324263845	2026-05-09 12:57:43.845+02	2026-05-09 12:57:44.690412+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.690412+02
20019	10	E28011704000021D53DAB0CB	\N	-65	0	43	\N	\N	1778324263995	2026-05-09 12:57:43.995+02	2026-05-09 12:57:44.7187+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.7187+02
20021	10	E28011704000021D53DAB0CB	\N	-60	0	55	\N	\N	1778324264145	2026-05-09 12:57:44.145+02	2026-05-09 12:57:44.789748+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.789748+02
20023	10	E28011704000021D53DAB0CB	\N	-68	0	44	\N	\N	1778324264295	2026-05-09 12:57:44.295+02	2026-05-09 12:57:44.816361+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.816361+02
20025	10	E28011704000021D53DAB0CB	\N	-64	0	33	\N	\N	1778324264462	2026-05-09 12:57:44.462+02	2026-05-09 12:57:44.855548+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.855548+02
20027	10	E28011704000021D53DAB0CB	\N	-63	0	8	\N	\N	1778324264601	2026-05-09 12:57:44.601+02	2026-05-09 12:57:44.882819+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.882819+02
20031	9	E28011704000021D53DAB0CB	\N	-70	0	57	\N	\N	1778324264711	2026-05-09 12:57:44.711+02	2026-05-09 12:57:45.481188+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.481188+02
20034	9	E28011704000021D53DAB0CB	\N	-71	0	50	\N	\N	1778324265161	2026-05-09 12:57:45.161+02	2026-05-09 12:57:45.942968+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.942968+02
20036	9	E28011704000021D53DAB0CB	\N	-71	0	40	\N	\N	1778324265311	2026-05-09 12:57:45.311+02	2026-05-09 12:57:45.954642+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.954642+02
20041	10	E28011704000021D53DAB0CB	\N	-67	0	40	\N	\N	1778324265046	2026-05-09 12:57:45.046+02	2026-05-09 12:57:46.030446+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.030446+02
20044	9	E28011704000021D53DAB0CB	\N	-61	0	59	\N	\N	1778324265931	2026-05-09 12:57:45.931+02	2026-05-09 12:57:46.096752+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.096752+02
20046	9	E28011704000021D53DAB0CB	\N	-59	0	43	\N	\N	1778324266065	2026-05-09 12:57:46.065+02	2026-05-09 12:57:46.116132+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.116132+02
20052	9	E28011704000021D53DAB0CB	\N	-59	0	54	\N	\N	1778324266685	2026-05-09 12:57:46.685+02	2026-05-09 12:57:47.776691+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.776691+02
20054	9	E28011704000021D53DAB0CB	\N	-58	0	11	\N	\N	1778324266813	2026-05-09 12:57:46.813+02	2026-05-09 12:57:47.859614+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.859614+02
20056	9	E28011704000021D53DAB0CB	\N	-51	0	20	\N	\N	1778324266963	2026-05-09 12:57:46.963+02	2026-05-09 12:57:47.876714+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.876714+02
20030	10	E28011704000021D53DAB0CB	\N	-70	0	40	\N	\N	1778324264904	2026-05-09 12:57:44.904+02	2026-05-09 12:57:44.946743+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:44.946743+02
20032	9	E28011704000021D53DAB0CB	\N	-71	0	13	\N	\N	1778324264890	2026-05-09 12:57:44.89+02	2026-05-09 12:57:45.788845+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.788845+02
20037	9	E28011704000021D53DAB0CB	\N	-70	0	26	\N	\N	1778324265476	2026-05-09 12:57:45.476+02	2026-05-09 12:57:45.984752+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:45.984752+02
20039	9	E28011704000021D53DAB0CB	\N	-62	0	19	\N	\N	1778324265611	2026-05-09 12:57:45.611+02	2026-05-09 12:57:46.02661+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.02661+02
20043	9	E28011704000021D53DAB0CB	\N	-57	0	38	\N	\N	1778324265762	2026-05-09 12:57:45.762+02	2026-05-09 12:57:46.076329+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.076329+02
20045	9	E28011704000021D53DAB0CB	\N	-60	0	53	\N	\N	1778324265931	2026-05-09 12:57:45.931+02	2026-05-09 12:57:46.09932+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.09932+02
20047	9	E28011704000021D53DAB0CB	\N	-58	0	26	\N	\N	1778324266065	2026-05-09 12:57:46.065+02	2026-05-09 12:57:46.118009+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:46.118009+02
20049	9	E28011704000021D53DAB0CB	\N	-52	0	49	\N	\N	1778324266371	2026-05-09 12:57:46.371+02	2026-05-09 12:57:47.704695+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.704695+02
20051	9	E28011704000021D53DAB0CB	\N	-58	0	12	\N	\N	1778324266511	2026-05-09 12:57:46.511+02	2026-05-09 12:57:47.716549+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.716549+02
20058	9	E28011704000021D53DAB0CB	\N	-61	0	34	\N	\N	1778324267282	2026-05-09 12:57:47.282+02	2026-05-09 12:57:47.927949+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.927949+02
20060	9	E28011704000021D53DAB0CB	\N	-73	0	45	\N	\N	1778324267419	2026-05-09 12:57:47.419+02	2026-05-09 12:57:47.946656+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.946656+02
20053	9	E28011704000021D53DAB0CB	\N	-55	0	30	\N	\N	1778324266813	2026-05-09 12:57:46.813+02	2026-05-09 12:57:47.857409+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.857409+02
20055	9	E28011704000021D53DAB0CB	\N	-54	0	36	\N	\N	1778324266963	2026-05-09 12:57:46.963+02	2026-05-09 12:57:47.874649+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.874649+02
20057	9	E28011704000021D53DAB0CB	\N	-58	0	15	\N	\N	1778324267111	2026-05-09 12:57:47.111+02	2026-05-09 12:57:47.89371+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.89371+02
20059	9	E28011704000021D53DAB0CB	\N	-68	0	56	\N	\N	1778324267282	2026-05-09 12:57:47.282+02	2026-05-09 12:57:47.930237+02	2026-05-09 12:57:53.203+02	\N	\N	realtime	synced	2026-05-09 12:57:47.930237+02
20071	10	E28011704000021D53DAB0CB	\N	-68	0	48	\N	\N	1778324279595	2026-05-09 12:57:59.595+02	2026-05-09 12:58:00.436453+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:00.436453+02
20073	10	E28011704000021D53DAB0CB	\N	-69	0	14	\N	\N	1778324279895	2026-05-09 12:57:59.895+02	2026-05-09 12:58:01.251176+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.251176+02
20075	10	E28011704000021D53DAB0CB	\N	-67	0	12	\N	\N	1778324280046	2026-05-09 12:58:00.046+02	2026-05-09 12:58:01.272228+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:01.272228+02
20061	9	E28011704000021D53DAB0CB	\N	-68	0	54	\N	\N	1778324277761	2026-05-09 12:57:57.761+02	2026-05-09 12:57:58.204463+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.204463+02
20064	9	E28011704000021D53DAB0CB	\N	-61	0	26	\N	\N	1778324278217	2026-05-09 12:57:58.217+02	2026-05-09 12:57:58.410123+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.410123+02
20066	9	E28011704000021D53DAB0CB	\N	-58	0	33	\N	\N	1778324278361	2026-05-09 12:57:58.361+02	2026-05-09 12:57:58.761421+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:58.761421+02
20068	9	E28011704000021D53DAB0CB	\N	-65	0	46	\N	\N	1778324278521	2026-05-09 12:57:58.521+02	2026-05-09 12:57:59.167761+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:57:59.167761+02
20070	10	E28011704000021D53DAB0CB	\N	-77	0	44	\N	\N	1778324279595	2026-05-09 12:57:59.595+02	2026-05-09 12:58:00.434684+02	2026-05-09 12:58:05.211+02	\N	\N	realtime	synced	2026-05-09 12:58:00.434684+02
20197	9	E28011704000021D53DAB0CB	\N	-67	0	22	\N	\N	1778324314063	2026-05-09 12:58:34.063+02	2026-05-09 12:58:34.224547+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.224547+02
20199	9	E28011704000021D53DAB0CB	\N	-61	0	48	\N	\N	1778324314216	2026-05-09 12:58:34.216+02	2026-05-09 12:58:34.249985+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.249985+02
20203	9	E28011704000021D53DAB0CB	\N	-52	0	15	\N	\N	1778324314812	2026-05-09 12:58:34.812+02	2026-05-09 12:58:35.360993+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.360993+02
20205	9	E28011704000021D53DAB0CB	\N	-62	0	16	\N	\N	1778324314962	2026-05-09 12:58:34.962+02	2026-05-09 12:58:35.429774+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.429774+02
20210	9	E28011704000021D53DAB0CB	\N	-63	0	24	\N	\N	1778324315561	2026-05-09 12:58:35.561+02	2026-05-09 12:58:36.612634+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.612634+02
20212	9	E28011704000021D53DAB0CB	\N	-68	0	47	\N	\N	1778324315713	2026-05-09 12:58:35.713+02	2026-05-09 12:58:36.631356+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.631356+02
20214	9	E28011704000021D53DAB0CB	\N	-71	0	48	\N	\N	1778324315862	2026-05-09 12:58:35.862+02	2026-05-09 12:58:36.651809+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.651809+02
20086	10	E28011704000021D53DAB0CB	\N	-64	0	25	\N	\N	1778324287846	2026-05-09 12:58:07.846+02	2026-05-09 12:58:08.829138+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:08.829138+02
20088	10	E28011704000021D53DAB0CB	\N	-67	0	26	\N	\N	1778324288151	2026-05-09 12:58:08.151+02	2026-05-09 12:58:09.304739+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.304739+02
20090	10	E28011704000021D53DAB0CB	\N	-56	0	59	\N	\N	1778324288295	2026-05-09 12:58:08.295+02	2026-05-09 12:58:09.338694+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.338694+02
20092	10	E28011704000021D53DAB0CB	\N	-56	0	17	\N	\N	1778324288445	2026-05-09 12:58:08.445+02	2026-05-09 12:58:09.390958+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.390958+02
20101	10	E28011704000021D53DAB0CB	\N	-67	0	42	\N	\N	1778324289370	2026-05-09 12:58:09.37+02	2026-05-09 12:58:09.642666+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.642666+02
20103	10	E28011704000021D53DAB0CB	\N	-59	0	58	\N	\N	1778324289513	2026-05-09 12:58:09.513+02	2026-05-09 12:58:09.675461+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.675461+02
20105	10	E28011704000021D53DAB0CB	\N	-61	0	22	\N	\N	1778324289662	2026-05-09 12:58:09.662+02	2026-05-09 12:58:09.710708+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.710708+02
20107	9	E28011704000021D53DAB0CB	\N	-71	0	47	\N	\N	1778324289635	2026-05-09 12:58:09.635+02	2026-05-09 12:58:09.957601+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.957601+02
20112	9	E28011704000021D53DAB0CB	\N	-64	0	53	\N	\N	1778324290512	2026-05-09 12:58:10.512+02	2026-05-09 12:58:11.087454+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.087454+02
20114	9	E28011704000021D53DAB0CB	\N	-62	0	43	\N	\N	1778324290662	2026-05-09 12:58:10.662+02	2026-05-09 12:58:11.12462+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.12462+02
20116	9	E28011704000021D53DAB0CB	\N	-65	0	48	\N	\N	1778324290847	2026-05-09 12:58:10.847+02	2026-05-09 12:58:11.146548+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.146548+02
20118	10	E28011704000021D53DAB0CB	\N	-67	0	25	\N	\N	1778324289946	2026-05-09 12:58:09.946+02	2026-05-09 12:58:11.239769+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.239769+02
20093	10	E28011704000021D53DAB0CB	\N	-58	0	31	\N	\N	1778324288596	2026-05-09 12:58:08.596+02	2026-05-09 12:58:09.418379+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.418379+02
20095	10	E28011704000021D53DAB0CB	\N	-54	0	52	\N	\N	1778324288745	2026-05-09 12:58:08.745+02	2026-05-09 12:58:09.478814+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.478814+02
20097	10	E28011704000021D53DAB0CB	\N	-56	0	58	\N	\N	1778324288896	2026-05-09 12:58:08.896+02	2026-05-09 12:58:09.534933+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.534933+02
20099	10	E28011704000021D53DAB0CB	\N	-62	0	16	\N	\N	1778324289046	2026-05-09 12:58:09.046+02	2026-05-09 12:58:09.560929+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.560929+02
20106	9	E28011704000021D53DAB0CB	\N	-70	0	57	\N	\N	1778324289635	2026-05-09 12:58:09.635+02	2026-05-09 12:58:09.955106+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.955106+02
20108	9	E28011704000021D53DAB0CB	\N	-63	0	56	\N	\N	1778324289761	2026-05-09 12:58:09.761+02	2026-05-09 12:58:09.990613+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.990613+02
20110	10	E28011704000021D53DAB0CB	\N	-61	0	48	\N	\N	1778324289798	2026-05-09 12:58:09.798+02	2026-05-09 12:58:10.881048+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:10.881048+02
20085	10	E28011704000021D53DAB0CB	\N	-69	0	33	\N	\N	1778324287560	2026-05-09 12:58:07.56+02	2026-05-09 12:58:08.624714+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:08.624714+02
20087	10	E28011704000021D53DAB0CB	\N	-63	0	26	\N	\N	1778324288013	2026-05-09 12:58:08.013+02	2026-05-09 12:58:09.238776+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.238776+02
20089	10	E28011704000021D53DAB0CB	\N	-61	0	20	\N	\N	1778324288151	2026-05-09 12:58:08.151+02	2026-05-09 12:58:09.307013+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.307013+02
20091	10	E28011704000021D53DAB0CB	\N	-56	0	44	\N	\N	1778324288295	2026-05-09 12:58:08.295+02	2026-05-09 12:58:09.340579+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.340579+02
20094	10	E28011704000021D53DAB0CB	\N	-58	0	37	\N	\N	1778324288745	2026-05-09 12:58:08.745+02	2026-05-09 12:58:09.477044+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.477044+02
20096	10	E28011704000021D53DAB0CB	\N	-58	0	7	\N	\N	1778324288896	2026-05-09 12:58:08.896+02	2026-05-09 12:58:09.531992+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.531992+02
20098	10	E28011704000021D53DAB0CB	\N	-58	0	51	\N	\N	1778324289046	2026-05-09 12:58:09.046+02	2026-05-09 12:58:09.558957+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.558957+02
20100	10	E28011704000021D53DAB0CB	\N	-62	0	48	\N	\N	1778324289196	2026-05-09 12:58:09.196+02	2026-05-09 12:58:09.59901+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.59901+02
20102	10	E28011704000021D53DAB0CB	\N	-58	0	51	\N	\N	1778324289370	2026-05-09 12:58:09.37+02	2026-05-09 12:58:09.646576+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.646576+02
20104	10	E28011704000021D53DAB0CB	\N	-56	0	46	\N	\N	1778324289513	2026-05-09 12:58:09.513+02	2026-05-09 12:58:09.678467+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:09.678467+02
20109	10	E28011704000021D53DAB0CB	\N	-58	0	44	\N	\N	1778324289798	2026-05-09 12:58:09.798+02	2026-05-09 12:58:10.877222+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:10.877222+02
20111	9	E28011704000021D53DAB0CB	\N	-70	0	58	\N	\N	1778324290390	2026-05-09 12:58:10.39+02	2026-05-09 12:58:11.032817+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.032817+02
20220	9	E28011704000021D53DAB0CB	\N	-63	0	35	\N	\N	1778324325462	2026-05-09 12:58:45.462+02	2026-05-09 12:58:46.08672+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.08672+02
20222	9	E28011704000021D53DAB0CB	\N	-67	0	33	\N	\N	1778324325611	2026-05-09 12:58:45.611+02	2026-05-09 12:58:46.112656+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.112656+02
20225	9	E28011704000021D53DAB0CB	\N	-67	0	59	\N	\N	1778324326082	2026-05-09 12:58:46.082+02	2026-05-09 12:58:46.203853+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.203853+02
20228	10	E28011704000021D53DAB0CB	\N	-67	0	38	\N	\N	1778324327746	2026-05-09 12:58:47.746+02	2026-05-09 12:58:47.950172+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:47.950172+02
20230	10	E28011704000021D53DAB0CB	\N	-65	0	18	\N	\N	1778324327895	2026-05-09 12:58:47.895+02	2026-05-09 12:58:48.255072+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:48.255072+02
20232	10	E28011704000021D53DAB0CB	\N	-67	0	20	\N	\N	1778324328055	2026-05-09 12:58:48.055+02	2026-05-09 12:58:48.267819+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:48.267819+02
20139	9	E28011704000021D53DAB0CB	\N	-70	0	8	\N	\N	1778324299221	2026-05-09 12:58:19.221+02	2026-05-09 12:58:19.550891+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:19.550891+02
20202	9	E28011704000021D53DAB0CB	\N	-51	0	53	\N	\N	1778324314683	2026-05-09 12:58:34.683+02	2026-05-09 12:58:35.344887+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.344887+02
20204	9	E28011704000021D53DAB0CB	\N	-56	0	20	\N	\N	1778324314812	2026-05-09 12:58:34.812+02	2026-05-09 12:58:35.363444+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.363444+02
20115	9	E28011704000021D53DAB0CB	\N	-67	0	47	\N	\N	1778324290847	2026-05-09 12:58:10.847+02	2026-05-09 12:58:11.144337+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.144337+02
20117	9	E28011704000021D53DAB0CB	\N	-62	0	40	\N	\N	1778324290966	2026-05-09 12:58:10.966+02	2026-05-09 12:58:11.239386+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.239386+02
20119	10	E28011704000021D53DAB0CB	\N	-67	0	25	\N	\N	1778324289946	2026-05-09 12:58:09.946+02	2026-05-09 12:58:11.251979+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.251979+02
20121	9	E28011704000021D53DAB0CB	\N	-57	0	14	\N	\N	1778324291113	2026-05-09 12:58:11.113+02	2026-05-09 12:58:11.277901+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.277901+02
20126	9	E28011704000021D53DAB0CB	\N	-57	0	20	\N	\N	1778324291712	2026-05-09 12:58:11.712+02	2026-05-09 12:58:12.550821+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.550821+02
20128	9	E28011704000021D53DAB0CB	\N	-68	0	47	\N	\N	1778324291886	2026-05-09 12:58:11.886+02	2026-05-09 12:58:12.563829+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.563829+02
20130	9	E28011704000021D53DAB0CB	\N	-65	0	7	\N	\N	1778324292011	2026-05-09 12:58:12.011+02	2026-05-09 12:58:12.638822+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.638822+02
20134	9	E28011704000021D53DAB0CB	\N	-62	0	56	\N	\N	1778324292462	2026-05-09 12:58:12.462+02	2026-05-09 12:58:13.242312+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:13.242312+02
20137	9	E28011704000021D53DAB0CB	\N	-76	0	48	\N	\N	1778324292946	2026-05-09 12:58:12.946+02	2026-05-09 12:58:13.361087+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:13.361087+02
20207	9	E28011704000021D53DAB0CB	\N	-62	0	53	\N	\N	1778324315298	2026-05-09 12:58:35.298+02	2026-05-09 12:58:35.480895+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.480895+02
20209	9	E28011704000021D53DAB0CB	\N	-65	0	19	\N	\N	1778324315412	2026-05-09 12:58:35.412+02	2026-05-09 12:58:35.506324+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.506324+02
20211	9	E28011704000021D53DAB0CB	\N	-64	0	20	\N	\N	1778324315561	2026-05-09 12:58:35.561+02	2026-05-09 12:58:36.614612+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.614612+02
20216	9	E28011704000021D53DAB0CB	\N	-70	0	8	\N	\N	1778324316161	2026-05-09 12:58:36.161+02	2026-05-09 12:58:36.719884+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.719884+02
20217	9	E28011704000021D53DAB0CB	\N	-68	0	22	\N	\N	1778324325181	2026-05-09 12:58:45.181+02	2026-05-09 12:58:46.001166+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.001166+02
20219	9	E28011704000021D53DAB0CB	\N	-67	0	51	\N	\N	1778324325312	2026-05-09 12:58:45.312+02	2026-05-09 12:58:46.020863+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.020863+02
20221	9	E28011704000021D53DAB0CB	\N	-68	0	53	\N	\N	1778324325462	2026-05-09 12:58:45.462+02	2026-05-09 12:58:46.088593+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.088593+02
20224	9	E28011704000021D53DAB0CB	\N	-64	0	51	\N	\N	1778324325912	2026-05-09 12:58:45.912+02	2026-05-09 12:58:46.185593+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.185593+02
20226	9	E28011704000021D53DAB0CB	\N	-64	0	55	\N	\N	1778324326082	2026-05-09 12:58:46.082+02	2026-05-09 12:58:46.205795+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.205795+02
20231	10	E28011704000021D53DAB0CB	\N	-63	0	9	\N	\N	1778324327895	2026-05-09 12:58:47.895+02	2026-05-09 12:58:48.257306+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:48.257306+02
20234	10	E28011704000021D53DAB0CB	\N	-66	0	16	\N	\N	1778324339596	2026-05-09 12:58:59.596+02	2026-05-09 12:58:59.929515+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:58:59.929515+02
20236	10	E28011704000021D53DAB0CB	\N	-65	0	41	\N	\N	1778324339895	2026-05-09 12:58:59.895+02	2026-05-09 12:59:00.068494+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:00.068494+02
20238	10	E28011704000021D53DAB0CB	\N	-65	0	43	\N	\N	1778324340045	2026-05-09 12:59:00.045+02	2026-05-09 12:59:00.091819+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:00.091819+02
20244	10	E28011704000021D53DAB0CB	\N	-67	0	55	\N	\N	1778324340798	2026-05-09 12:59:00.798+02	2026-05-09 12:59:01.282748+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.282748+02
20246	10	E28011704000021D53DAB0CB	\N	-56	0	37	\N	\N	1778324340946	2026-05-09 12:59:00.946+02	2026-05-09 12:59:01.325906+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.325906+02
20248	10	E28011704000021D53DAB0CB	\N	-56	0	39	\N	\N	1778324341096	2026-05-09 12:59:01.096+02	2026-05-09 12:59:01.383839+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.383839+02
20237	10	E28011704000021D53DAB0CB	\N	-67	0	20	\N	\N	1778324339895	2026-05-09 12:58:59.895+02	2026-05-09 12:59:00.070697+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:00.070697+02
20240	10	E28011704000021D53DAB0CB	\N	-68	0	51	\N	\N	1778324340496	2026-05-09 12:59:00.496+02	2026-05-09 12:59:01.201435+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.201435+02
20242	10	E28011704000021D53DAB0CB	\N	-61	0	55	\N	\N	1778324340647	2026-05-09 12:59:00.647+02	2026-05-09 12:59:01.228893+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.228893+02
20252	9	E28011704000021D53DAB0CB	\N	-64	0	37	\N	\N	1778324341663	2026-05-09 12:59:01.663+02	2026-05-09 12:59:01.677286+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.677286+02
20254	10	E28011704000021D53DAB0CB	\N	-56	0	14	\N	\N	1778324341552	2026-05-09 12:59:01.552+02	2026-05-09 12:59:02.747064+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:02.747064+02
20257	10	E28011704000021D53DAB0CB	\N	-56	0	12	\N	\N	1778324341695	2026-05-09 12:59:01.695+02	2026-05-09 12:59:03.029233+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.029233+02
20259	10	E28011704000021D53DAB0CB	\N	-63	0	23	\N	\N	1778324341850	2026-05-09 12:59:01.85+02	2026-05-09 12:59:03.222565+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.222565+02
20265	9	E28011704000021D53DAB0CB	\N	-64	0	42	\N	\N	1778324342588	2026-05-09 12:59:02.588+02	2026-05-09 12:59:03.844073+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.844073+02
20172	10	E28011704000021D53DAB0CB	\N	-77	0	43	\N	\N	1778324311550	2026-05-09 12:58:31.55+02	2026-05-09 12:58:32.530089+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.530089+02
20182	10	E28011704000021D53DAB0CB	\N	-51	0	59	\N	\N	1778324312596	2026-05-09 12:58:32.596+02	2026-05-09 12:58:32.705954+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.705954+02
20186	10	E28011704000021D53DAB0CB	\N	-64	0	26	\N	\N	1778324313059	2026-05-09 12:58:33.059+02	2026-05-09 12:58:33.849605+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.849605+02
20188	10	E28011704000021D53DAB0CB	\N	-70	0	21	\N	\N	1778324313195	2026-05-09 12:58:33.195+02	2026-05-09 12:58:33.864733+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.864733+02
20190	10	E28011704000021D53DAB0CB	\N	-69	0	8	\N	\N	1778324313345	2026-05-09 12:58:33.345+02	2026-05-09 12:58:33.897998+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.897998+02
20123	9	E28011704000021D53DAB0CB	\N	-55	0	9	\N	\N	1778324291413	2026-05-09 12:58:11.413+02	2026-05-09 12:58:12.462619+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.462619+02
20125	9	E28011704000021D53DAB0CB	\N	-55	0	16	\N	\N	1778324291561	2026-05-09 12:58:11.561+02	2026-05-09 12:58:12.480912+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.480912+02
20127	9	E28011704000021D53DAB0CB	\N	-68	0	46	\N	\N	1778324291712	2026-05-09 12:58:11.712+02	2026-05-09 12:58:12.554934+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.554934+02
20132	9	E28011704000021D53DAB0CB	\N	-68	0	14	\N	\N	1778324292311	2026-05-09 12:58:12.311+02	2026-05-09 12:58:13.186433+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:13.186433+02
20136	9	E28011704000021D53DAB0CB	\N	-68	0	27	\N	\N	1778324292761	2026-05-09 12:58:12.761+02	2026-05-09 12:58:13.330912+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:13.330912+02
20193	9	E28011704000021D53DAB0CB	\N	-76	0	43	\N	\N	1778324313612	2026-05-09 12:58:33.612+02	2026-05-09 12:58:34.04906+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.04906+02
20195	9	E28011704000021D53DAB0CB	\N	-68	0	48	\N	\N	1778324313765	2026-05-09 12:58:33.765+02	2026-05-09 12:58:34.07892+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.07892+02
20201	9	E28011704000021D53DAB0CB	\N	-46	0	54	\N	\N	1778324314513	2026-05-09 12:58:34.513+02	2026-05-09 12:58:35.321628+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.321628+02
20206	9	E28011704000021D53DAB0CB	\N	-63	0	11	\N	\N	1778324315136	2026-05-09 12:58:35.136+02	2026-05-09 12:58:35.467986+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.467986+02
20208	9	E28011704000021D53DAB0CB	\N	-64	0	51	\N	\N	1778324315298	2026-05-09 12:58:35.298+02	2026-05-09 12:58:35.48268+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.48268+02
20213	9	E28011704000021D53DAB0CB	\N	-64	0	46	\N	\N	1778324315862	2026-05-09 12:58:35.862+02	2026-05-09 12:58:36.649525+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.649525+02
20215	9	E28011704000021D53DAB0CB	\N	-68	0	59	\N	\N	1778324316041	2026-05-09 12:58:36.041+02	2026-05-09 12:58:36.704906+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:36.704906+02
20173	10	E28011704000021D53DAB0CB	\N	-74	0	58	\N	\N	1778324311695	2026-05-09 12:58:31.695+02	2026-05-09 12:58:32.557521+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.557521+02
20175	10	E28011704000021D53DAB0CB	\N	-68	0	23	\N	\N	1778324311995	2026-05-09 12:58:31.995+02	2026-05-09 12:58:32.612856+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.612856+02
20177	10	E28011704000021D53DAB0CB	\N	-61	0	25	\N	\N	1778324312151	2026-05-09 12:58:32.151+02	2026-05-09 12:58:32.650631+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.650631+02
20179	10	E28011704000021D53DAB0CB	\N	-59	0	52	\N	\N	1778324312295	2026-05-09 12:58:32.295+02	2026-05-09 12:58:32.664041+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.664041+02
20181	10	E28011704000021D53DAB0CB	\N	-57	0	10	\N	\N	1778324312596	2026-05-09 12:58:32.596+02	2026-05-09 12:58:32.704062+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.704062+02
20184	10	E28011704000021D53DAB0CB	\N	-58	0	35	\N	\N	1778324312757	2026-05-09 12:58:32.757+02	2026-05-09 12:58:33.816857+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.816857+02
20191	10	E28011704000021D53DAB0CB	\N	-73	0	22	\N	\N	1778324313506	2026-05-09 12:58:33.506+02	2026-05-09 12:58:33.908535+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.908535+02
20196	9	E28011704000021D53DAB0CB	\N	-67	0	52	\N	\N	1778324313931	2026-05-09 12:58:33.931+02	2026-05-09 12:58:34.159431+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.159431+02
20198	9	E28011704000021D53DAB0CB	\N	-67	0	44	\N	\N	1778324314063	2026-05-09 12:58:34.063+02	2026-05-09 12:58:34.226619+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.226619+02
20200	9	E28011704000021D53DAB0CB	\N	-52	0	49	\N	\N	1778324314513	2026-05-09 12:58:34.513+02	2026-05-09 12:58:35.319447+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:35.319447+02
20171	10	E28011704000021D53DAB0CB	\N	-74	0	20	\N	\N	1778324311395	2026-05-09 12:58:31.395+02	2026-05-09 12:58:32.247114+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.247114+02
20174	10	E28011704000021D53DAB0CB	\N	-65	0	41	\N	\N	1778324311995	2026-05-09 12:58:31.995+02	2026-05-09 12:58:32.610722+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.610722+02
20176	10	E28011704000021D53DAB0CB	\N	-62	0	20	\N	\N	1778324312151	2026-05-09 12:58:32.151+02	2026-05-09 12:58:32.648621+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.648621+02
20178	10	E28011704000021D53DAB0CB	\N	-59	0	27	\N	\N	1778324312295	2026-05-09 12:58:32.295+02	2026-05-09 12:58:32.661948+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.661948+02
20180	10	E28011704000021D53DAB0CB	\N	-57	0	15	\N	\N	1778324312596	2026-05-09 12:58:32.596+02	2026-05-09 12:58:32.702194+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:32.702194+02
20183	10	E28011704000021D53DAB0CB	\N	-55	0	38	\N	\N	1778324312757	2026-05-09 12:58:32.757+02	2026-05-09 12:58:33.814719+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.814719+02
20185	10	E28011704000021D53DAB0CB	\N	-62	0	43	\N	\N	1778324312896	2026-05-09 12:58:32.896+02	2026-05-09 12:58:33.827232+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.827232+02
20187	10	E28011704000021D53DAB0CB	\N	-74	0	57	\N	\N	1778324313059	2026-05-09 12:58:33.059+02	2026-05-09 12:58:33.85177+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.85177+02
20189	10	E28011704000021D53DAB0CB	\N	-73	0	32	\N	\N	1778324313195	2026-05-09 12:58:33.195+02	2026-05-09 12:58:33.866921+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.866921+02
20192	9	E28011704000021D53DAB0CB	\N	-68	0	35	\N	\N	1778324313461	2026-05-09 12:58:33.461+02	2026-05-09 12:58:33.982778+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:33.982778+02
20194	9	E28011704000021D53DAB0CB	\N	-71	0	43	\N	\N	1778324313612	2026-05-09 12:58:33.612+02	2026-05-09 12:58:34.050759+02	2026-05-09 12:58:41.24+02	\N	\N	realtime	synced	2026-05-09 12:58:34.050759+02
20218	9	E28011704000021D53DAB0CB	\N	-71	0	42	\N	\N	1778324325181	2026-05-09 12:58:45.181+02	2026-05-09 12:58:46.003948+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.003948+02
20223	9	E28011704000021D53DAB0CB	\N	-71	0	25	\N	\N	1778324325783	2026-05-09 12:58:45.783+02	2026-05-09 12:58:46.137089+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:46.137089+02
20227	10	E28011704000021D53DAB0CB	\N	-69	0	29	\N	\N	1778324327746	2026-05-09 12:58:47.746+02	2026-05-09 12:58:47.946333+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:47.946333+02
20229	10	E28011704000021D53DAB0CB	\N	-71	0	40	\N	\N	1778324327895	2026-05-09 12:58:47.895+02	2026-05-09 12:58:48.253237+02	2026-05-09 12:58:53.247+02	\N	\N	realtime	synced	2026-05-09 12:58:48.253237+02
20113	9	E28011704000021D53DAB0CB	\N	-60	0	47	\N	\N	1778324290512	2026-05-09 12:58:10.512+02	2026-05-09 12:58:11.0899+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.0899+02
20120	9	E28011704000021D53DAB0CB	\N	-61	0	22	\N	\N	1778324291113	2026-05-09 12:58:11.113+02	2026-05-09 12:58:11.276041+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.276041+02
20122	9	E28011704000021D53DAB0CB	\N	-56	0	56	\N	\N	1778324291262	2026-05-09 12:58:11.262+02	2026-05-09 12:58:11.32798+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:11.32798+02
20124	9	E28011704000021D53DAB0CB	\N	-56	0	19	\N	\N	1778324291413	2026-05-09 12:58:11.413+02	2026-05-09 12:58:12.466315+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.466315+02
20129	9	E28011704000021D53DAB0CB	\N	-63	0	33	\N	\N	1778324292011	2026-05-09 12:58:12.011+02	2026-05-09 12:58:12.637024+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.637024+02
20131	9	E28011704000021D53DAB0CB	\N	-61	0	34	\N	\N	1778324292179	2026-05-09 12:58:12.179+02	2026-05-09 12:58:12.823494+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:12.823494+02
20133	9	E28011704000021D53DAB0CB	\N	-64	0	55	\N	\N	1778324292311	2026-05-09 12:58:12.311+02	2026-05-09 12:58:13.188979+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:13.188979+02
20135	9	E28011704000021D53DAB0CB	\N	-70	0	40	\N	\N	1778324292621	2026-05-09 12:58:12.621+02	2026-05-09 12:58:13.276949+02	2026-05-09 12:58:17.226+02	\N	\N	realtime	synced	2026-05-09 12:58:13.276949+02
20138	9	E28011704000021D53DAB0CB	\N	-65	0	31	\N	\N	1778324299221	2026-05-09 12:58:19.221+02	2026-05-09 12:58:19.547094+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:19.547094+02
20140	9	E28011704000021D53DAB0CB	\N	-68	0	35	\N	\N	1778324300572	2026-05-09 12:58:20.572+02	2026-05-09 12:58:20.713113+02	2026-05-09 12:58:29.232+02	\N	\N	realtime	synced	2026-05-09 12:58:20.713113+02
20267	10	E28011704000021D53DAB0CB	\N	-64	0	9	\N	\N	1778324342145	2026-05-09 12:59:02.145+02	2026-05-09 12:59:03.890413+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.890413+02
20269	10	E28011704000021D53DAB0CB	\N	-70	0	52	\N	\N	1778324342307	2026-05-09 12:59:02.307+02	2026-05-09 12:59:03.900129+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.900129+02
20271	9	E28011704000021D53DAB0CB	\N	-68	0	54	\N	\N	1778324342717	2026-05-09 12:59:02.717+02	2026-05-09 12:59:04.230915+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.230915+02
20276	9	E28011704000021D53DAB0CB	\N	-56	0	16	\N	\N	1778324343311	2026-05-09 12:59:03.311+02	2026-05-09 12:59:04.496935+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.496935+02
20278	9	E28011704000021D53DAB0CB	\N	-58	0	33	\N	\N	1778324343467	2026-05-09 12:59:03.467+02	2026-05-09 12:59:04.533679+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.533679+02
20280	9	E28011704000021D53DAB0CB	\N	-62	0	47	\N	\N	1778324343611	2026-05-09 12:59:03.611+02	2026-05-09 12:59:04.5854+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.5854+02
20282	9	E28011704000021D53DAB0CB	\N	-56	0	11	\N	\N	1778324343915	2026-05-09 12:59:03.915+02	2026-05-09 12:59:04.682965+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.682965+02
20284	9	E28011704000021D53DAB0CB	\N	-55	0	34	\N	\N	1778324344061	2026-05-09 12:59:04.061+02	2026-05-09 12:59:04.701532+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.701532+02
20285	9	E28011704000021D53DAB0CB	\N	-55	0	54	\N	\N	1778324344221	2026-05-09 12:59:04.221+02	2026-05-09 12:59:04.716708+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.716708+02
20286	9	E28011704000021D53DAB0CB	\N	-56	0	18	\N	\N	1778324344221	2026-05-09 12:59:04.221+02	2026-05-09 12:59:04.719079+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.719079+02
20287	9	E28011704000021D53DAB0CB	\N	-59	0	45	\N	\N	1778324344363	2026-05-09 12:59:04.363+02	2026-05-09 12:59:04.769632+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.769632+02
20289	9	E28011704000021D53DAB0CB	\N	-60	0	10	\N	\N	1778324344511	2026-05-09 12:59:04.511+02	2026-05-09 12:59:04.850823+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.850823+02
20291	9	E28011704000021D53DAB0CB	\N	-62	0	20	\N	\N	1778324344840	2026-05-09 12:59:04.84+02	2026-05-09 12:59:04.903188+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.903188+02
20293	9	E28011704000021D53DAB0CB	\N	-65	0	16	\N	\N	1778324344962	2026-05-09 12:59:04.962+02	2026-05-09 12:59:06.071551+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:06.071551+02
20294	9	E28011704000021D53DAB0CB	\N	-62	0	8	\N	\N	1778324345111	2026-05-09 12:59:05.111+02	2026-05-09 12:59:06.362884+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:06.362884+02
20233	10	E28011704000021D53DAB0CB	\N	-70	0	58	\N	\N	1778324339596	2026-05-09 12:58:59.596+02	2026-05-09 12:58:59.927422+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:58:59.927422+02
20235	10	E28011704000021D53DAB0CB	\N	-68	0	36	\N	\N	1778324339895	2026-05-09 12:58:59.895+02	2026-05-09 12:59:00.063049+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:00.063049+02
20239	10	E28011704000021D53DAB0CB	\N	-68	0	32	\N	\N	1778324340346	2026-05-09 12:59:00.346+02	2026-05-09 12:59:01.156693+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.156693+02
20241	10	E28011704000021D53DAB0CB	\N	-54	0	49	\N	\N	1778324340496	2026-05-09 12:59:00.496+02	2026-05-09 12:59:01.203353+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.203353+02
20243	10	E28011704000021D53DAB0CB	\N	-67	0	26	\N	\N	1778324340647	2026-05-09 12:59:00.647+02	2026-05-09 12:59:01.231066+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.231066+02
20245	10	E28011704000021D53DAB0CB	\N	-59	0	8	\N	\N	1778324340946	2026-05-09 12:59:00.946+02	2026-05-09 12:59:01.323691+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.323691+02
20247	10	E28011704000021D53DAB0CB	\N	-55	0	46	\N	\N	1778324341096	2026-05-09 12:59:01.096+02	2026-05-09 12:59:01.38197+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.38197+02
20249	10	E28011704000021D53DAB0CB	\N	-58	0	53	\N	\N	1778324341258	2026-05-09 12:59:01.258+02	2026-05-09 12:59:01.429888+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.429888+02
20251	10	E28011704000021D53DAB0CB	\N	-58	0	57	\N	\N	1778324341397	2026-05-09 12:59:01.397+02	2026-05-09 12:59:01.458876+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.458876+02
20256	9	E28011704000021D53DAB0CB	\N	-67	0	58	\N	\N	1778324341961	2026-05-09 12:59:01.961+02	2026-05-09 12:59:02.901299+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:02.901299+02
20258	10	E28011704000021D53DAB0CB	\N	-62	0	35	\N	\N	1778324341695	2026-05-09 12:59:01.695+02	2026-05-09 12:59:03.031416+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.031416+02
20260	10	E28011704000021D53DAB0CB	\N	-65	0	44	\N	\N	1778324341850	2026-05-09 12:59:01.85+02	2026-05-09 12:59:03.225369+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.225369+02
20262	9	E28011704000021D53DAB0CB	\N	-71	0	45	\N	\N	1778324342261	2026-05-09 12:59:02.261+02	2026-05-09 12:59:03.530631+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.530631+02
20264	10	E28011704000021D53DAB0CB	\N	-67	0	9	\N	\N	1778324341995	2026-05-09 12:59:01.995+02	2026-05-09 12:59:03.625574+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.625574+02
20273	9	E28011704000021D53DAB0CB	\N	-62	0	27	\N	\N	1778324343012	2026-05-09 12:59:03.012+02	2026-05-09 12:59:04.409654+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.409654+02
20250	10	E28011704000021D53DAB0CB	\N	-58	0	59	\N	\N	1778324341258	2026-05-09 12:59:01.258+02	2026-05-09 12:59:01.434493+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:01.434493+02
20253	10	E28011704000021D53DAB0CB	\N	-56	0	45	\N	\N	1778324341552	2026-05-09 12:59:01.552+02	2026-05-09 12:59:02.745186+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:02.745186+02
20275	9	E28011704000021D53DAB0CB	\N	-61	0	59	\N	\N	1778324343188	2026-05-09 12:59:03.188+02	2026-05-09 12:59:04.466858+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.466858+02
20277	9	E28011704000021D53DAB0CB	\N	-58	0	14	\N	\N	1778324343311	2026-05-09 12:59:03.311+02	2026-05-09 12:59:04.500907+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.500907+02
20255	9	E28011704000021D53DAB0CB	\N	-71	0	9	\N	\N	1778324341811	2026-05-09 12:59:01.811+02	2026-05-09 12:59:02.779143+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:02.779143+02
20261	9	E28011704000021D53DAB0CB	\N	-68	0	53	\N	\N	1778324342112	2026-05-09 12:59:02.112+02	2026-05-09 12:59:03.352728+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.352728+02
20263	9	E28011704000021D53DAB0CB	\N	-61	0	47	\N	\N	1778324342261	2026-05-09 12:59:02.261+02	2026-05-09 12:59:03.532566+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.532566+02
20266	10	E28011704000021D53DAB0CB	\N	-67	0	51	\N	\N	1778324342145	2026-05-09 12:59:02.145+02	2026-05-09 12:59:03.888066+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.888066+02
20268	10	E28011704000021D53DAB0CB	\N	-71	0	19	\N	\N	1778324342307	2026-05-09 12:59:02.307+02	2026-05-09 12:59:03.898415+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:03.898415+02
20270	9	E28011704000021D53DAB0CB	\N	-63	0	34	\N	\N	1778324342717	2026-05-09 12:59:02.717+02	2026-05-09 12:59:04.228934+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.228934+02
20272	9	E28011704000021D53DAB0CB	\N	-68	0	56	\N	\N	1778324342861	2026-05-09 12:59:02.861+02	2026-05-09 12:59:04.372059+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.372059+02
20274	9	E28011704000021D53DAB0CB	\N	-66	0	24	\N	\N	1778324343012	2026-05-09 12:59:03.012+02	2026-05-09 12:59:04.411434+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.411434+02
20279	9	E28011704000021D53DAB0CB	\N	-61	0	43	\N	\N	1778324343611	2026-05-09 12:59:03.611+02	2026-05-09 12:59:04.583122+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.583122+02
20281	9	E28011704000021D53DAB0CB	\N	-61	0	19	\N	\N	1778324343763	2026-05-09 12:59:03.763+02	2026-05-09 12:59:04.620757+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.620757+02
20283	9	E28011704000021D53DAB0CB	\N	-56	0	29	\N	\N	1778324343915	2026-05-09 12:59:03.915+02	2026-05-09 12:59:04.684934+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.684934+02
20288	9	E28011704000021D53DAB0CB	\N	-62	0	22	\N	\N	1778324344511	2026-05-09 12:59:04.511+02	2026-05-09 12:59:04.848605+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.848605+02
20290	9	E28011704000021D53DAB0CB	\N	-61	0	15	\N	\N	1778324344667	2026-05-09 12:59:04.667+02	2026-05-09 12:59:04.87577+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.87577+02
20292	9	E28011704000021D53DAB0CB	\N	-70	0	16	\N	\N	1778324344840	2026-05-09 12:59:04.84+02	2026-05-09 12:59:04.904855+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:04.904855+02
20295	9	E28011704000021D53DAB0CB	\N	-65	0	28	\N	\N	1778324345269	2026-05-09 12:59:05.269+02	2026-05-09 12:59:06.397682+02	2026-05-09 12:59:11.274+02	\N	\N	realtime	synced	2026-05-09 12:59:06.397682+02
\.


--
-- Data for Name: tag_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tag_assignments (id, user_id, tag_epc, assigned_at, deactivated_at, notes, created_at) FROM stdin;
bcfc66c5-9c3a-4967-ab2f-97b6356d87c9	\N	E28011704000021D53DAB0CB	2026-05-08 22:41:26.244+02	2026-05-08 22:48:04.44+02	\N	2026-05-08 22:41:26.244+02
35905927-6d51-4a83-b2fe-2df54d382e9f	f908224d-2e38-409a-bc7f-81902406f95b	E28011704000021D53DAB0CB	2026-05-08 22:50:24.28+02	\N	\N	2026-05-08 22:50:24.28+02
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, sync_id, name, email, is_active, created_at, updated_at) FROM stdin;
f908224d-2e38-409a-bc7f-81902406f95b	153	Richard Adamec	\N	t	2026-05-08 22:50:24.28+02	2026-05-08 22:50:24.28+02
\.


--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 1, false);


--
-- Name: lighthouse_connection_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_connection_events_id_seq', 306, true);


--
-- Name: lighthouse_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_groups_id_seq', 5, true);


--
-- Name: lighthouse_health_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_health_snapshots_id_seq', 7580, true);


--
-- Name: lighthouses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouses_id_seq', 10, true);


--
-- Name: processed_event_scans_raw_scan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.processed_event_scans_raw_scan_id_seq', 1, false);


--
-- Name: raw_scans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.raw_scans_id_seq', 20295, true);


--
-- Name: raw_scans_timestamp_ms_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.raw_scans_timestamp_ms_seq', 1, false);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: dashboard_users dashboard_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dashboard_users
    ADD CONSTRAINT dashboard_users_pkey PRIMARY KEY (id);


--
-- Name: dashboard_users dashboard_users_username_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dashboard_users
    ADD CONSTRAINT dashboard_users_username_unique UNIQUE (username);


--
-- Name: lighthouse_connection_events lighthouse_connection_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_connection_events
    ADD CONSTRAINT lighthouse_connection_events_pkey PRIMARY KEY (id);


--
-- Name: lighthouse_groups lighthouse_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_groups
    ADD CONSTRAINT lighthouse_groups_pkey PRIMARY KEY (id);


--
-- Name: lighthouse_health_snapshots lighthouse_health_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_health_snapshots
    ADD CONSTRAINT lighthouse_health_snapshots_pkey PRIMARY KEY (id);


--
-- Name: lighthouses lighthouses_deviceId_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouses
    ADD CONSTRAINT "lighthouses_deviceId_unique" UNIQUE (device_id);


--
-- Name: lighthouses lighthouses_name_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouses
    ADD CONSTRAINT lighthouses_name_unique UNIQUE (name);


--
-- Name: lighthouses lighthouses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouses
    ADD CONSTRAINT lighthouses_pkey PRIMARY KEY (id);


--
-- Name: mqtt_clients mqtt_clients_clientId_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mqtt_clients
    ADD CONSTRAINT "mqtt_clients_clientId_unique" UNIQUE (client_id);


--
-- Name: mqtt_clients mqtt_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mqtt_clients
    ADD CONSTRAINT mqtt_clients_pkey PRIMARY KEY (id);


--
-- Name: processed_event_scans processed_event_scans_processed_event_id_raw_scan_id_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_event_scans
    ADD CONSTRAINT processed_event_scans_processed_event_id_raw_scan_id_pk PRIMARY KEY (processed_event_id, raw_scan_id);


--
-- Name: processed_events processed_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT processed_events_pkey PRIMARY KEY (id);


--
-- Name: raw_scans raw_scans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_scans
    ADD CONSTRAINT raw_scans_pkey PRIMARY KEY (id);


--
-- Name: tag_assignments tag_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tag_assignments
    ADD CONSTRAINT tag_assignments_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_logs_resource_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_resource_type ON public.audit_logs USING btree (resource_type);


--
-- Name: idx_audit_logs_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_timestamp ON public.audit_logs USING btree ("timestamp");


--
-- Name: idx_audit_logsuser_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logsuser_id ON public.audit_logs USING btree (user_id);


--
-- Name: idx_connection_events_lighthouse_recorded; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_connection_events_lighthouse_recorded ON public.lighthouse_connection_events USING btree (lighthouse_id, recorded_at);


--
-- Name: idx_connection_events_recorded; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_connection_events_recorded ON public.lighthouse_connection_events USING btree (recorded_at);


--
-- Name: idx_dashboard_users_username; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dashboard_users_username ON public.dashboard_users USING btree (username);


--
-- Name: idx_health_snapshots_lighthouse_recorded; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_health_snapshots_lighthouse_recorded ON public.lighthouse_health_snapshots USING btree (lighthouse_id, recorded_at);


--
-- Name: idx_health_snapshots_recorded; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_health_snapshots_recorded ON public.lighthouse_health_snapshots USING btree (recorded_at);


--
-- Name: idx_lighthouse_groups_label; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_lighthouse_groups_label ON public.lighthouse_groups USING btree (label);


--
-- Name: idx_lighthouses_device_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_lighthouses_device_id ON public.lighthouses USING btree (device_id);


--
-- Name: idx_lighthouses_group_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_lighthouses_group_id ON public.lighthouses USING btree (group_id);


--
-- Name: idx_lighthouses_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_lighthouses_name ON public.lighthouses USING btree (name);


--
-- Name: idx_mqtt_clients_client_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_mqtt_clients_client_id ON public.mqtt_clients USING btree (client_id);


--
-- Name: idx_mqtt_clients_lighthouse_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_mqtt_clients_lighthouse_id ON public.mqtt_clients USING btree (lighthouse_id);


--
-- Name: idx_processed_event_scans_raw_scan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_event_scans_raw_scan ON public.processed_event_scans USING btree (raw_scan_id);


--
-- Name: idx_processed_events_algorithm; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_events_algorithm ON public.processed_events USING btree (algorithm_id, "timestamp");


--
-- Name: idx_processed_events_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_events_group ON public.processed_events USING btree (group_id, "timestamp");


--
-- Name: idx_processed_events_synced; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_events_synced ON public.processed_events USING btree (synced_to_integration);


--
-- Name: idx_processed_events_tag_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_events_tag_timestamp ON public.processed_events USING btree (tag_epc, "timestamp");


--
-- Name: idx_processed_events_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_events_timestamp ON public.processed_events USING btree ("timestamp");


--
-- Name: idx_processed_events_user_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_processed_events_user_timestamp ON public.processed_events USING btree (user_id, "timestamp");


--
-- Name: idx_raw_scans_epc_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_raw_scans_epc_timestamp ON public.raw_scans USING btree (epc, "timestamp");


--
-- Name: idx_raw_scans_lighthouse_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_raw_scans_lighthouse_timestamp ON public.raw_scans USING btree (lighthouse_id, "timestamp");


--
-- Name: idx_raw_scans_orphaned; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_raw_scans_orphaned ON public.raw_scans USING btree (orphaned_at) WHERE (orphaned_at IS NOT NULL);


--
-- Name: idx_raw_scans_unprocessed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_raw_scans_unprocessed ON public.raw_scans USING btree (epc, "timestamp") WHERE ((processed_at IS NULL) AND (orphaned_at IS NULL));


--
-- Name: idx_tag_assignments_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_tag_assignments_active ON public.tag_assignments USING btree (tag_epc) WHERE (deactivated_at IS NULL);


--
-- Name: idx_tag_assignments_epc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tag_assignments_epc ON public.tag_assignments USING btree (tag_epc);


--
-- Name: idx_tag_assignments_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tag_assignments_user_id ON public.tag_assignments USING btree (user_id);


--
-- Name: idx_users_sync_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_sync_id ON public.users USING btree (sync_id);


--
-- Name: lighthouse_connection_events lighthouse_connection_events_lighthouse_id_lighthouses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_connection_events
    ADD CONSTRAINT lighthouse_connection_events_lighthouse_id_lighthouses_id_fk FOREIGN KEY (lighthouse_id) REFERENCES public.lighthouses(id);


--
-- Name: lighthouse_health_snapshots lighthouse_health_snapshots_lighthouse_id_lighthouses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouse_health_snapshots
    ADD CONSTRAINT lighthouse_health_snapshots_lighthouse_id_lighthouses_id_fk FOREIGN KEY (lighthouse_id) REFERENCES public.lighthouses(id);


--
-- Name: lighthouses lighthouses_group_id_lighthouse_groups_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lighthouses
    ADD CONSTRAINT lighthouses_group_id_lighthouse_groups_id_fk FOREIGN KEY (group_id) REFERENCES public.lighthouse_groups(id) ON DELETE SET NULL;


--
-- Name: mqtt_clients mqtt_clients_lighthouse_id_lighthouses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mqtt_clients
    ADD CONSTRAINT mqtt_clients_lighthouse_id_lighthouses_id_fk FOREIGN KEY (lighthouse_id) REFERENCES public.lighthouses(id);


--
-- Name: processed_event_scans processed_event_scans_processed_event_id_processed_events_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_event_scans
    ADD CONSTRAINT processed_event_scans_processed_event_id_processed_events_id_fk FOREIGN KEY (processed_event_id) REFERENCES public.processed_events(id) ON DELETE CASCADE;


--
-- Name: processed_event_scans processed_event_scans_raw_scan_id_raw_scans_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_event_scans
    ADD CONSTRAINT processed_event_scans_raw_scan_id_raw_scans_id_fk FOREIGN KEY (raw_scan_id) REFERENCES public.raw_scans(id);


--
-- Name: processed_events processed_events_group_id_lighthouse_groups_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT processed_events_group_id_lighthouse_groups_id_fk FOREIGN KEY (group_id) REFERENCES public.lighthouse_groups(id);


--
-- Name: raw_scans raw_scans_lighthouse_id_lighthouses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_scans
    ADD CONSTRAINT raw_scans_lighthouse_id_lighthouses_id_fk FOREIGN KEY (lighthouse_id) REFERENCES public.lighthouses(id);


--
-- Name: tag_assignments tag_assignments_user_id_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tag_assignments
    ADD CONSTRAINT tag_assignments_user_id_users_id_fk FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict lWdcdQEggVTn21u2EQqDNrxnPYcm0MP7kYzRHgtQl2aSU7TEBuZwPCCSX9u25uI

