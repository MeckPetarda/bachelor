--
-- PostgreSQL database dump
--

\restrict KHcP2x9vOs2lhovZfeCAPzfm5b8Es1JWbDtbDJR3FQ2f9x0eygDWRy9oMoi0a1k

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
7302	9	46	170408	165456	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 11:58:47.019304+02
7306	9	56	170408	165456	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 11:58:57.054339+02
7307	10	42	170384	166008	-37	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:00.43383+02
7310	9	66	170408	165456	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:07.19334+02
7311	10	52	170384	166008	-36	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:10.571037+02
7313	10	57	170384	166008	-39	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:15.589073+02
7317	10	72	170384	166008	-35	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:29.925197+02
7318	9	91	170408	165456	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:31.563653+02
7319	10	77	170384	166008	-37	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:35.147531+02
7322	10	88	170384	161588	-36	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:45.89937+02
7323	9	107	170408	165456	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 11:59:47.332801+02
7325	10	96	170384	161588	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:59:54.711121+02
7327	10	104	170384	161588	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:02.181126+02
7328	10	111	170244	161588	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:09.657792+02
7332	10	126	170272	159920	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:24.40196+02
7335	10	141	170272	159920	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:39.660061+02
7336	9	161	170428	161664	-73	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:42.219454+02
7337	10	149	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:46.828574+02
7338	9	172	170404	161664	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:52.460931+02
7341	10	163	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:00.857522+02
7344	10	178	170272	159844	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:15.90994+02
7348	10	193	166416	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:31.188744+02
7352	10	208	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:46.322778+02
7353	9	231	170428	161644	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:51.442599+02
7356	10	224	170280	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:02.092746+02
7359	9	253	170428	161644	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:14.07363+02
7360	10	239	170280	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:17.145552+02
7361	9	261	170428	161644	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:21.753505+02
7362	10	246	170280	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:24.728606+02
7364	10	254	170280	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:32.198175+02
7365	9	277	170296	161644	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:38.137573+02
7367	9	284	170296	161644	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:45.100766+02
7369	9	291	170296	161644	-73	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:52.166527+02
7373	9	305	170296	161644	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:06.093603+02
7374	10	292	170404	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:10.086761+02
7375	9	315	170296	161512	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:15.718536+02
7376	10	300	170404	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:17.86908+02
7377	10	308	170404	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:25.857297+02
7379	10	316	170404	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:34.048484+02
7381	10	323	170404	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:41.627429+02
7382	9	344	170296	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:44.800192+02
7383	10	331	170404	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:49.101479+02
7385	10	338	170404	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:56.474265+02
7391	9	381	170296	161448	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:21.460025+02
7392	10	369	170272	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:26.887661+02
7394	10	376	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:34.674967+02
7398	10	391	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:49.619892+02
7399	10	399	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:57.198112+02
7400	9	418	170296	161448	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:59.040981+02
7402	9	428	170296	161448	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:08.771425+02
7404	9	435	170296	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:15.738458+02
7405	10	422	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:19.931314+02
7406	9	442	170296	161448	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:22.798326+02
7408	9	449	169736	161448	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:30.068376+02
7409	10	437	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:35.291376+02
7410	9	459	170296	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:39.69554+02
7411	10	444	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:42.766843+02
7414	9	475	170296	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:56.181064+02
7416	10	467	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:05.807228+02
7419	9	493	170296	161448	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:13.611113+02
7421	10	483	169528	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:21.166554+02
7422	10	491	168708	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:29.153603+02
7423	9	509	170292	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:29.666436+02
7425	9	519	170296	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:39.803577+02
7428	10	513	170272	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:51.4766+02
7429	10	521	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:59.285794+02
7431	10	528	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:06.741559+02
7432	9	549	170296	161448	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:09.640903+02
7433	10	537	170272	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:14.927406+02
7435	10	544	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:22.204951+02
7437	9	569	169284	161448	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:30.162903+02
7439	9	579	170296	161448	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:40.117749+02
7440	10	567	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:45.134744+02
7442	10	574	170272	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:52.717739+02
7444	10	583	170272	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:00.802372+02
7446	9	609	170424	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:09.963926+02
7447	10	597	170412	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:15.656048+02
7449	10	605	170412	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:23.740316+02
7451	10	613	170412	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:31.420591+02
7452	10	621	170412	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:38.896538+02
7453	9	639	165232	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:39.655075+02
7456	10	636	170412	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:54.461291+02
7303	10	32	170384	166008	-38	POWERED_OFF	t	t	129.3	0	2026-05-09 11:58:50.296496+02
7304	9	51	170408	165456	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 11:58:52.03819+02
7305	10	37	170384	166008	-38	POWERED_OFF	t	t	129.3	0	2026-05-09 11:58:55.415739+02
7308	9	61	170408	165456	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:02.175115+02
7309	10	47	170384	166008	-37	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:05.553543+02
7312	9	72	170408	165456	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:12.209321+02
7314	9	79	170408	165456	-65	UNKNOWN	t	t	129.3	0	2026-05-09 11:59:19.480292+02
7315	10	65	170384	166008	-39	UNKNOWN	t	t	129.3	0	2026-05-09 11:59:23.371643+02
7316	9	86	170408	165456	-71	UNKNOWN	t	t	129.3	0	2026-05-09 11:59:26.443217+02
7320	9	98	170408	165456	-69	UNKNOWN	t	t	129.3	0	2026-05-09 11:59:38.736385+02
7321	10	82	170384	161588	-36	POWERED_OFF	t	t	129.3	0	2026-05-09 11:59:40.472017+02
7324	9	114	170408	165456	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 11:59:54.399186+02
7326	9	121	170428	165456	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:01.362726+02
7329	9	131	170428	161664	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:12.011321+02
7330	10	119	170244	159920	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:17.029429+02
7331	9	141	170428	161664	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:22.149208+02
7333	10	134	170272	159920	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:32.186102+02
7334	9	151	170428	161664	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:32.186308+02
7339	10	156	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:00:53.894012+02
7340	9	180	170428	161664	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:00.65776+02
7342	9	187	168584	161664	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:07.859825+02
7343	10	170	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:08.536694+02
7345	9	195	170428	161664	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:16.217032+02
7346	9	202	170428	161664	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:23.179914+02
7347	10	185	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:23.487804+02
7349	9	211	170428	161664	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:31.474633+02
7350	10	200	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:38.751179+02
7351	9	221	170428	161644	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:41.407882+02
7354	10	216	170280	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:01:54.003077+02
7355	9	239	170428	161644	-73	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:00.147257+02
7357	9	246	170428	161644	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:07.109927+02
7358	10	231	170256	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:09.570061+02
7363	9	270	170296	161644	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:31.071847+02
7366	10	261	170280	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:39.776379+02
7368	10	269	170280	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:47.763434+02
7370	10	277	170404	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:55.238546+02
7371	9	298	170296	161644	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:02:59.129936+02
7372	10	284	170404	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:02.611525+02
7378	9	325	170296	161512	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:25.893976+02
7380	9	334	170296	161512	-84	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:34.765858+02
7384	9	352	170296	161448	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 12:03:52.993621+02
7386	9	360	170296	161448	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:01.082587+02
7387	10	346	170272	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:04.461927+02
7388	9	371	170296	161448	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:11.321918+02
7389	10	354	170272	159844	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:11.93703+02
7390	10	361	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:19.309369+02
7393	9	389	170296	161448	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:30.164318+02
7395	9	398	170296	161448	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:38.670393+02
7396	10	384	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:42.04277+02
7397	9	408	170296	161448	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:04:49.108045+02
7401	10	407	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:04.775453+02
7403	10	414	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:12.251092+02
7407	10	430	170272	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:28.020596+02
7412	9	466	170296	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:46.662494+02
7413	10	452	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:50.242569+02
7415	10	460	170272	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:05:58.332085+02
7417	9	485	170296	161448	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:06.011516+02
7418	10	475	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:13.426457+02
7420	9	500	170296	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:20.666003+02
7424	10	498	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:36.21956+02
7426	10	506	170272	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:43.796773+02
7427	9	529	170296	161448	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 12:06:50.043687+02
7430	9	539	170296	161448	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:01.657692+02
7434	9	559	170296	161448	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:19.806741+02
7436	10	551	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:29.574928+02
7438	10	559	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:37.661076+02
7441	9	589	170296	161448	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:07:50.05059+02
7443	9	599	170428	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:00.08567+02
7445	10	590	168708	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:08.621167+02
7448	9	619	170428	161448	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:19.763413+02
7450	9	629	170428	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:29.88406+02
7454	10	628	170412	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:46.780545+02
7455	9	649	170424	161448	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:49.647692+02
7457	9	659	170428	161448	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 12:08:59.991006+02
7458	10	644	168596	159844	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:02.447968+02
7459	9	669	170424	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:09.94934+02
7460	10	652	170412	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:09.949317+02
7461	10	659	170272	159844	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:17.60288+02
7462	9	679	170428	161448	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:19.754346+02
7463	10	668	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:25.795353+02
7464	9	689	170428	161448	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:29.481929+02
7465	10	675	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:33.270356+02
7466	9	699	170428	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:39.527449+02
7467	10	683	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:40.927829+02
7468	10	690	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:48.427178+02
7469	9	709	170296	161448	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:49.449921+02
7470	10	698	166868	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:56.311498+02
7471	9	718	170296	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:09:59.178269+02
7472	10	705	168708	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:03.888216+02
7473	9	729	170296	161448	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:09.418072+02
7474	10	714	170272	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:11.856936+02
7475	10	721	170272	159844	-40	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:19.359028+02
7476	9	739	170296	161448	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:19.384893+02
7477	9	746	170296	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:26.621686+02
7478	10	728	170272	159844	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 12:10:26.621725+02
\.


--
-- Data for Name: lighthouses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouses (id, name, device_id, placement, comment, firmware_version, last_seen_at, is_active, config, group_id, created_at, canged_at) FROM stdin;
9	Yellow	00:70:07:25:15:00	INSIDE	\N	\N	2026-05-09 12:10:26.643+02	t	{}	5	2026-05-08 22:51:30.087+02	2026-05-08 22:51:30.088128+02
10	Red	68:FE:71:0D:D0:74	OUTSIDE	\N	\N	2026-05-09 12:10:26.644+02	t	{}	5	2026-05-08 22:52:09.26+02	2026-05-08 22:52:09.261586+02
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
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19193
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19193
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19194
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19194
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19195
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19195
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19196
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19196
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19197
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19197
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19198
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19198
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19199
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19199
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19200
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19200
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19201
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19201
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19202
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19202
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19203
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19203
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19204
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19204
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19205
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19205
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19206
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19206
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19207
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19207
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19209
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19209
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19208
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19208
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19210
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19210
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19212
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19212
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	19211
c73d4632-3a10-47ad-a81c-bf2f04527f1f	19211
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19219
c758572d-5e5d-421d-ba3f-0680f5295e61	19219
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19220
c758572d-5e5d-421d-ba3f-0680f5295e61	19220
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19221
c758572d-5e5d-421d-ba3f-0680f5295e61	19221
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19222
c758572d-5e5d-421d-ba3f-0680f5295e61	19222
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19223
c758572d-5e5d-421d-ba3f-0680f5295e61	19223
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19224
c758572d-5e5d-421d-ba3f-0680f5295e61	19224
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19225
c758572d-5e5d-421d-ba3f-0680f5295e61	19225
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19226
c758572d-5e5d-421d-ba3f-0680f5295e61	19226
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19227
c758572d-5e5d-421d-ba3f-0680f5295e61	19227
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19228
c758572d-5e5d-421d-ba3f-0680f5295e61	19228
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19229
c758572d-5e5d-421d-ba3f-0680f5295e61	19229
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19230
c758572d-5e5d-421d-ba3f-0680f5295e61	19230
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	19231
c758572d-5e5d-421d-ba3f-0680f5295e61	19231
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19238
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19238
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19239
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19239
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19240
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19240
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19241
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19241
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19242
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19242
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19243
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19243
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19244
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19244
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19245
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19245
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19246
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19246
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19247
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19247
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19248
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19248
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19249
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19249
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19232
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19232
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19233
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19233
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19234
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19234
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19235
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19235
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19236
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19236
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	19237
9bfaf441-5118-4df6-aa6c-e9fd50f68737	19237
2632a87e-f818-4ff5-8321-fe093580753f	19286
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19286
2632a87e-f818-4ff5-8321-fe093580753f	19288
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19288
2632a87e-f818-4ff5-8321-fe093580753f	19287
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19287
2632a87e-f818-4ff5-8321-fe093580753f	19290
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19290
2632a87e-f818-4ff5-8321-fe093580753f	19289
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19289
2632a87e-f818-4ff5-8321-fe093580753f	19292
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19292
2632a87e-f818-4ff5-8321-fe093580753f	19291
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19291
2632a87e-f818-4ff5-8321-fe093580753f	19294
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19294
2632a87e-f818-4ff5-8321-fe093580753f	19293
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19293
2632a87e-f818-4ff5-8321-fe093580753f	19296
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19296
2632a87e-f818-4ff5-8321-fe093580753f	19295
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19295
2632a87e-f818-4ff5-8321-fe093580753f	19297
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19297
2632a87e-f818-4ff5-8321-fe093580753f	19281
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19281
2632a87e-f818-4ff5-8321-fe093580753f	19282
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19282
2632a87e-f818-4ff5-8321-fe093580753f	19283
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19283
2632a87e-f818-4ff5-8321-fe093580753f	19284
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19284
2632a87e-f818-4ff5-8321-fe093580753f	19285
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	19285
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19298
0280d920-d806-4c46-a874-1c1bf9e377ee	19298
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19299
0280d920-d806-4c46-a874-1c1bf9e377ee	19299
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19300
0280d920-d806-4c46-a874-1c1bf9e377ee	19300
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19301
0280d920-d806-4c46-a874-1c1bf9e377ee	19301
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19303
0280d920-d806-4c46-a874-1c1bf9e377ee	19303
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19302
0280d920-d806-4c46-a874-1c1bf9e377ee	19302
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19304
0280d920-d806-4c46-a874-1c1bf9e377ee	19304
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19305
0280d920-d806-4c46-a874-1c1bf9e377ee	19305
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19306
0280d920-d806-4c46-a874-1c1bf9e377ee	19306
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19307
0280d920-d806-4c46-a874-1c1bf9e377ee	19307
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19308
0280d920-d806-4c46-a874-1c1bf9e377ee	19308
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19309
0280d920-d806-4c46-a874-1c1bf9e377ee	19309
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19310
0280d920-d806-4c46-a874-1c1bf9e377ee	19310
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19311
0280d920-d806-4c46-a874-1c1bf9e377ee	19311
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19313
0280d920-d806-4c46-a874-1c1bf9e377ee	19313
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19312
0280d920-d806-4c46-a874-1c1bf9e377ee	19312
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19314
0280d920-d806-4c46-a874-1c1bf9e377ee	19314
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19315
0280d920-d806-4c46-a874-1c1bf9e377ee	19315
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19316
0280d920-d806-4c46-a874-1c1bf9e377ee	19316
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19317
0280d920-d806-4c46-a874-1c1bf9e377ee	19317
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19318
0280d920-d806-4c46-a874-1c1bf9e377ee	19318
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19319
0280d920-d806-4c46-a874-1c1bf9e377ee	19319
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19320
0280d920-d806-4c46-a874-1c1bf9e377ee	19320
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19322
0280d920-d806-4c46-a874-1c1bf9e377ee	19322
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19321
0280d920-d806-4c46-a874-1c1bf9e377ee	19321
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19324
0280d920-d806-4c46-a874-1c1bf9e377ee	19324
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19323
0280d920-d806-4c46-a874-1c1bf9e377ee	19323
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19326
0280d920-d806-4c46-a874-1c1bf9e377ee	19326
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19325
0280d920-d806-4c46-a874-1c1bf9e377ee	19325
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19329
0280d920-d806-4c46-a874-1c1bf9e377ee	19329
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19327
0280d920-d806-4c46-a874-1c1bf9e377ee	19327
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19328
0280d920-d806-4c46-a874-1c1bf9e377ee	19328
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19330
0280d920-d806-4c46-a874-1c1bf9e377ee	19330
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19331
0280d920-d806-4c46-a874-1c1bf9e377ee	19331
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	19332
0280d920-d806-4c46-a874-1c1bf9e377ee	19332
29462daa-66f9-47c5-89d5-a64921af9789	19339
cc226522-c507-4f29-b6b8-81528901438a	19339
29462daa-66f9-47c5-89d5-a64921af9789	19341
cc226522-c507-4f29-b6b8-81528901438a	19341
29462daa-66f9-47c5-89d5-a64921af9789	19340
cc226522-c507-4f29-b6b8-81528901438a	19340
29462daa-66f9-47c5-89d5-a64921af9789	19342
cc226522-c507-4f29-b6b8-81528901438a	19342
29462daa-66f9-47c5-89d5-a64921af9789	19343
cc226522-c507-4f29-b6b8-81528901438a	19343
29462daa-66f9-47c5-89d5-a64921af9789	19344
cc226522-c507-4f29-b6b8-81528901438a	19344
29462daa-66f9-47c5-89d5-a64921af9789	19347
cc226522-c507-4f29-b6b8-81528901438a	19347
29462daa-66f9-47c5-89d5-a64921af9789	19345
cc226522-c507-4f29-b6b8-81528901438a	19345
29462daa-66f9-47c5-89d5-a64921af9789	19346
cc226522-c507-4f29-b6b8-81528901438a	19346
29462daa-66f9-47c5-89d5-a64921af9789	19348
cc226522-c507-4f29-b6b8-81528901438a	19348
29462daa-66f9-47c5-89d5-a64921af9789	19333
cc226522-c507-4f29-b6b8-81528901438a	19333
29462daa-66f9-47c5-89d5-a64921af9789	19334
cc226522-c507-4f29-b6b8-81528901438a	19334
29462daa-66f9-47c5-89d5-a64921af9789	19335
cc226522-c507-4f29-b6b8-81528901438a	19335
29462daa-66f9-47c5-89d5-a64921af9789	19337
cc226522-c507-4f29-b6b8-81528901438a	19337
29462daa-66f9-47c5-89d5-a64921af9789	19336
cc226522-c507-4f29-b6b8-81528901438a	19336
29462daa-66f9-47c5-89d5-a64921af9789	19338
cc226522-c507-4f29-b6b8-81528901438a	19338
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19349
7e944acf-e803-441a-b71c-b134405c29ed	19349
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19350
7e944acf-e803-441a-b71c-b134405c29ed	19350
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19351
7e944acf-e803-441a-b71c-b134405c29ed	19351
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19353
7e944acf-e803-441a-b71c-b134405c29ed	19353
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19352
7e944acf-e803-441a-b71c-b134405c29ed	19352
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19355
7e944acf-e803-441a-b71c-b134405c29ed	19355
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19354
7e944acf-e803-441a-b71c-b134405c29ed	19354
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19356
7e944acf-e803-441a-b71c-b134405c29ed	19356
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19357
7e944acf-e803-441a-b71c-b134405c29ed	19357
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19358
7e944acf-e803-441a-b71c-b134405c29ed	19358
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19359
7e944acf-e803-441a-b71c-b134405c29ed	19359
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19361
7e944acf-e803-441a-b71c-b134405c29ed	19361
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19360
7e944acf-e803-441a-b71c-b134405c29ed	19360
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	19362
7e944acf-e803-441a-b71c-b134405c29ed	19362
0610fa6d-ee11-4e16-829a-5650c7383217	19364
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	19364
0610fa6d-ee11-4e16-829a-5650c7383217	19365
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	19365
0610fa6d-ee11-4e16-829a-5650c7383217	19366
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	19366
0610fa6d-ee11-4e16-829a-5650c7383217	19367
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	19367
0610fa6d-ee11-4e16-829a-5650c7383217	19368
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	19368
0610fa6d-ee11-4e16-829a-5650c7383217	19363
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	19363
4f826740-f1ee-4cff-90ea-623284c54a00	19369
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19369
4f826740-f1ee-4cff-90ea-623284c54a00	19370
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19370
4f826740-f1ee-4cff-90ea-623284c54a00	19372
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19372
4f826740-f1ee-4cff-90ea-623284c54a00	19371
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19371
4f826740-f1ee-4cff-90ea-623284c54a00	19375
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19375
4f826740-f1ee-4cff-90ea-623284c54a00	19373
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19373
4f826740-f1ee-4cff-90ea-623284c54a00	19374
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19374
4f826740-f1ee-4cff-90ea-623284c54a00	19376
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19376
4f826740-f1ee-4cff-90ea-623284c54a00	19377
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19377
4f826740-f1ee-4cff-90ea-623284c54a00	19378
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19378
4f826740-f1ee-4cff-90ea-623284c54a00	19379
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19379
4f826740-f1ee-4cff-90ea-623284c54a00	19380
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19380
4f826740-f1ee-4cff-90ea-623284c54a00	19381
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19381
4f826740-f1ee-4cff-90ea-623284c54a00	19382
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	19382
5329ce3d-f2cd-4866-a238-3717dccc34df	19388
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19388
5329ce3d-f2cd-4866-a238-3717dccc34df	19387
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19387
5329ce3d-f2cd-4866-a238-3717dccc34df	19389
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19389
5329ce3d-f2cd-4866-a238-3717dccc34df	19390
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19390
5329ce3d-f2cd-4866-a238-3717dccc34df	19391
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19391
5329ce3d-f2cd-4866-a238-3717dccc34df	19392
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19392
5329ce3d-f2cd-4866-a238-3717dccc34df	19393
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19393
5329ce3d-f2cd-4866-a238-3717dccc34df	19394
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19394
5329ce3d-f2cd-4866-a238-3717dccc34df	19395
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19395
5329ce3d-f2cd-4866-a238-3717dccc34df	19396
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19396
5329ce3d-f2cd-4866-a238-3717dccc34df	19398
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19398
5329ce3d-f2cd-4866-a238-3717dccc34df	19397
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19397
5329ce3d-f2cd-4866-a238-3717dccc34df	19399
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19399
5329ce3d-f2cd-4866-a238-3717dccc34df	19401
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19401
5329ce3d-f2cd-4866-a238-3717dccc34df	19400
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19400
5329ce3d-f2cd-4866-a238-3717dccc34df	19383
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19383
5329ce3d-f2cd-4866-a238-3717dccc34df	19384
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19384
5329ce3d-f2cd-4866-a238-3717dccc34df	19386
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19386
5329ce3d-f2cd-4866-a238-3717dccc34df	19385
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	19385
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19402
ab5e82f0-834b-422f-9714-6f40c028f983	19402
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19403
ab5e82f0-834b-422f-9714-6f40c028f983	19403
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19404
ab5e82f0-834b-422f-9714-6f40c028f983	19404
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19405
ab5e82f0-834b-422f-9714-6f40c028f983	19405
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19406
ab5e82f0-834b-422f-9714-6f40c028f983	19406
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19407
ab5e82f0-834b-422f-9714-6f40c028f983	19407
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19408
ab5e82f0-834b-422f-9714-6f40c028f983	19408
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19409
ab5e82f0-834b-422f-9714-6f40c028f983	19409
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19410
ab5e82f0-834b-422f-9714-6f40c028f983	19410
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19411
ab5e82f0-834b-422f-9714-6f40c028f983	19411
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19412
ab5e82f0-834b-422f-9714-6f40c028f983	19412
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19413
ab5e82f0-834b-422f-9714-6f40c028f983	19413
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19414
ab5e82f0-834b-422f-9714-6f40c028f983	19414
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19415
ab5e82f0-834b-422f-9714-6f40c028f983	19415
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19416
ab5e82f0-834b-422f-9714-6f40c028f983	19416
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19417
ab5e82f0-834b-422f-9714-6f40c028f983	19417
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19418
ab5e82f0-834b-422f-9714-6f40c028f983	19418
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19419
ab5e82f0-834b-422f-9714-6f40c028f983	19419
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19420
ab5e82f0-834b-422f-9714-6f40c028f983	19420
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19421
ab5e82f0-834b-422f-9714-6f40c028f983	19421
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19422
ab5e82f0-834b-422f-9714-6f40c028f983	19422
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	19423
ab5e82f0-834b-422f-9714-6f40c028f983	19423
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19429
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19429
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19430
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19430
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19431
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19431
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19432
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19432
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19433
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19433
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19434
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19434
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19435
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19435
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19424
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19424
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19425
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19425
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19426
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19426
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19427
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19427
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	19428
2377c61f-5d43-42e4-b9bd-a14abe92ea61	19428
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19437
e48bde6d-b176-458b-b3b8-6576c22243b3	19437
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19436
e48bde6d-b176-458b-b3b8-6576c22243b3	19436
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19438
e48bde6d-b176-458b-b3b8-6576c22243b3	19438
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19439
e48bde6d-b176-458b-b3b8-6576c22243b3	19439
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19440
e48bde6d-b176-458b-b3b8-6576c22243b3	19440
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19441
e48bde6d-b176-458b-b3b8-6576c22243b3	19441
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19442
e48bde6d-b176-458b-b3b8-6576c22243b3	19442
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19444
e48bde6d-b176-458b-b3b8-6576c22243b3	19444
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19443
e48bde6d-b176-458b-b3b8-6576c22243b3	19443
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19446
e48bde6d-b176-458b-b3b8-6576c22243b3	19446
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19445
e48bde6d-b176-458b-b3b8-6576c22243b3	19445
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19447
e48bde6d-b176-458b-b3b8-6576c22243b3	19447
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19448
e48bde6d-b176-458b-b3b8-6576c22243b3	19448
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19450
e48bde6d-b176-458b-b3b8-6576c22243b3	19450
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19449
e48bde6d-b176-458b-b3b8-6576c22243b3	19449
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19451
e48bde6d-b176-458b-b3b8-6576c22243b3	19451
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	19452
e48bde6d-b176-458b-b3b8-6576c22243b3	19452
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19466
503bb163-3c55-481c-8048-f3a788370850	19466
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19465
503bb163-3c55-481c-8048-f3a788370850	19465
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19467
503bb163-3c55-481c-8048-f3a788370850	19467
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19468
503bb163-3c55-481c-8048-f3a788370850	19468
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19469
503bb163-3c55-481c-8048-f3a788370850	19469
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19471
503bb163-3c55-481c-8048-f3a788370850	19471
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19470
503bb163-3c55-481c-8048-f3a788370850	19470
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19472
503bb163-3c55-481c-8048-f3a788370850	19472
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19473
503bb163-3c55-481c-8048-f3a788370850	19473
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19453
503bb163-3c55-481c-8048-f3a788370850	19453
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19454
503bb163-3c55-481c-8048-f3a788370850	19454
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19455
503bb163-3c55-481c-8048-f3a788370850	19455
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19456
503bb163-3c55-481c-8048-f3a788370850	19456
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19457
503bb163-3c55-481c-8048-f3a788370850	19457
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19458
503bb163-3c55-481c-8048-f3a788370850	19458
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19460
503bb163-3c55-481c-8048-f3a788370850	19460
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19459
503bb163-3c55-481c-8048-f3a788370850	19459
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19461
503bb163-3c55-481c-8048-f3a788370850	19461
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19462
503bb163-3c55-481c-8048-f3a788370850	19462
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19463
503bb163-3c55-481c-8048-f3a788370850	19463
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	19464
503bb163-3c55-481c-8048-f3a788370850	19464
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19474
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19474
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19475
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19475
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19476
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19476
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19477
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19477
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19478
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19478
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19479
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19479
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19481
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19481
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19480
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19480
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19482
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19482
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19483
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19483
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19484
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19484
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	19485
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	19485
5307438b-a61d-425b-8d8b-3cc39d6123ca	19493
525791a5-ba8c-4755-92b9-3a16e934b10d	19493
5307438b-a61d-425b-8d8b-3cc39d6123ca	19495
525791a5-ba8c-4755-92b9-3a16e934b10d	19495
5307438b-a61d-425b-8d8b-3cc39d6123ca	19496
525791a5-ba8c-4755-92b9-3a16e934b10d	19496
5307438b-a61d-425b-8d8b-3cc39d6123ca	19494
525791a5-ba8c-4755-92b9-3a16e934b10d	19494
5307438b-a61d-425b-8d8b-3cc39d6123ca	19498
525791a5-ba8c-4755-92b9-3a16e934b10d	19498
5307438b-a61d-425b-8d8b-3cc39d6123ca	19497
525791a5-ba8c-4755-92b9-3a16e934b10d	19497
5307438b-a61d-425b-8d8b-3cc39d6123ca	19499
525791a5-ba8c-4755-92b9-3a16e934b10d	19499
5307438b-a61d-425b-8d8b-3cc39d6123ca	19500
525791a5-ba8c-4755-92b9-3a16e934b10d	19500
5307438b-a61d-425b-8d8b-3cc39d6123ca	19501
525791a5-ba8c-4755-92b9-3a16e934b10d	19501
5307438b-a61d-425b-8d8b-3cc39d6123ca	19502
525791a5-ba8c-4755-92b9-3a16e934b10d	19502
5307438b-a61d-425b-8d8b-3cc39d6123ca	19503
525791a5-ba8c-4755-92b9-3a16e934b10d	19503
5307438b-a61d-425b-8d8b-3cc39d6123ca	19486
525791a5-ba8c-4755-92b9-3a16e934b10d	19486
5307438b-a61d-425b-8d8b-3cc39d6123ca	19487
525791a5-ba8c-4755-92b9-3a16e934b10d	19487
5307438b-a61d-425b-8d8b-3cc39d6123ca	19488
525791a5-ba8c-4755-92b9-3a16e934b10d	19488
5307438b-a61d-425b-8d8b-3cc39d6123ca	19489
525791a5-ba8c-4755-92b9-3a16e934b10d	19489
5307438b-a61d-425b-8d8b-3cc39d6123ca	19490
525791a5-ba8c-4755-92b9-3a16e934b10d	19490
5307438b-a61d-425b-8d8b-3cc39d6123ca	19491
525791a5-ba8c-4755-92b9-3a16e934b10d	19491
5307438b-a61d-425b-8d8b-3cc39d6123ca	19492
525791a5-ba8c-4755-92b9-3a16e934b10d	19492
5007f8da-cf86-4908-aa57-17c089c9ec08	19504
b9412d48-552d-423f-9876-15ecd89dd281	19504
5007f8da-cf86-4908-aa57-17c089c9ec08	19505
b9412d48-552d-423f-9876-15ecd89dd281	19505
5007f8da-cf86-4908-aa57-17c089c9ec08	19506
b9412d48-552d-423f-9876-15ecd89dd281	19506
5007f8da-cf86-4908-aa57-17c089c9ec08	19507
b9412d48-552d-423f-9876-15ecd89dd281	19507
5007f8da-cf86-4908-aa57-17c089c9ec08	19509
b9412d48-552d-423f-9876-15ecd89dd281	19509
5007f8da-cf86-4908-aa57-17c089c9ec08	19508
b9412d48-552d-423f-9876-15ecd89dd281	19508
5007f8da-cf86-4908-aa57-17c089c9ec08	19510
b9412d48-552d-423f-9876-15ecd89dd281	19510
5007f8da-cf86-4908-aa57-17c089c9ec08	19511
b9412d48-552d-423f-9876-15ecd89dd281	19511
5007f8da-cf86-4908-aa57-17c089c9ec08	19512
b9412d48-552d-423f-9876-15ecd89dd281	19512
5007f8da-cf86-4908-aa57-17c089c9ec08	19513
b9412d48-552d-423f-9876-15ecd89dd281	19513
5007f8da-cf86-4908-aa57-17c089c9ec08	19514
b9412d48-552d-423f-9876-15ecd89dd281	19514
5007f8da-cf86-4908-aa57-17c089c9ec08	19515
b9412d48-552d-423f-9876-15ecd89dd281	19515
5007f8da-cf86-4908-aa57-17c089c9ec08	19516
b9412d48-552d-423f-9876-15ecd89dd281	19516
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19525
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19525
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19527
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19527
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19526
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19526
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19528
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19528
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19529
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19529
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19530
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19530
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19533
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19533
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19531
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19531
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19532
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19532
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19517
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19517
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19518
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19518
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19519
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19519
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19520
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19520
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19522
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19522
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19521
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19521
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19523
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19523
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	19524
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	19524
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19534
0b0c8c1b-1128-4f96-acac-525913612d7b	19534
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19535
0b0c8c1b-1128-4f96-acac-525913612d7b	19535
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19536
0b0c8c1b-1128-4f96-acac-525913612d7b	19536
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19537
0b0c8c1b-1128-4f96-acac-525913612d7b	19537
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19540
0b0c8c1b-1128-4f96-acac-525913612d7b	19540
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19539
0b0c8c1b-1128-4f96-acac-525913612d7b	19539
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19538
0b0c8c1b-1128-4f96-acac-525913612d7b	19538
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19541
0b0c8c1b-1128-4f96-acac-525913612d7b	19541
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19542
0b0c8c1b-1128-4f96-acac-525913612d7b	19542
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19543
0b0c8c1b-1128-4f96-acac-525913612d7b	19543
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19546
0b0c8c1b-1128-4f96-acac-525913612d7b	19546
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19544
0b0c8c1b-1128-4f96-acac-525913612d7b	19544
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19545
0b0c8c1b-1128-4f96-acac-525913612d7b	19545
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	19547
0b0c8c1b-1128-4f96-acac-525913612d7b	19547
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	19550
2b98ff2a-0237-44cc-9928-03105bf89a35	19550
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	19551
2b98ff2a-0237-44cc-9928-03105bf89a35	19551
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	19553
2b98ff2a-0237-44cc-9928-03105bf89a35	19553
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	19552
2b98ff2a-0237-44cc-9928-03105bf89a35	19552
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	19548
2b98ff2a-0237-44cc-9928-03105bf89a35	19548
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	19549
2b98ff2a-0237-44cc-9928-03105bf89a35	19549
\.


--
-- Data for Name: processed_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.processed_events (id, algorithm_id, direction, tag_epc, user_id, group_id, confidence, centroid_separation_factor, cluster_size_factor, bilateral_coverage_factor, rssi_trend_consistency_factor, "timestamp", cluster_started_at, cluster_ended_at, metadata, synced_to_integration, created_at, navigo3_record_id) FROM stdin;
feddd9fc-84f3-43d3-9ae2-7c2671c5340b	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.15462826	0.74221563	1	0.41666666	0.5	2026-05-09 12:03:07.846+02	2026-05-09 12:03:07.167+02	2026-05-09 12:03:11.624+02	{"rssiTrend": {"inside": {"r2": 0.023732447754818753, "slope": 0.0009825281298696488}, "outside": {"r2": 0.1744035871235602, "slope": -0.005488882026307352}}, "rssiWeights": {"inside": [0.28, 0.42000000000000004, 0.36, 0.28, 0.42000000000000004], "outside": [0.4, 0.48, 0.33999999999999997, 0.4, 0.26, 0.19999999999999996, 0.4, 0.31999999999999995, 0.31999999999999995, 0.31999999999999995, 0.31999999999999995, 0.31999999999999995]}, "centroidDeltaMs": 3308.05517578125, "insideScanCount": 5, "insideCentroidMs": 1778320987846.7046, "outsideScanCount": 12, "clusterDurationMs": 4457, "outsideCentroidMs": 1778320991154.7598}	f	2026-05-09 12:03:16.509422+02	\N
2632a87e-f818-4ff5-8321-fe093580753f	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3126449	0.7503478	1	0.41666666	\N	2026-05-09 12:03:07.833+02	2026-05-09 12:03:07.167+02	2026-05-09 12:03:11.624+02	{"centroidDeltaMs": 3344.300048828125, "insideScanCount": 5, "insideCentroidMs": 1778320987833.2, "outsideScanCount": 12, "clusterDurationMs": 4457, "outsideCentroidMs": 1778320991177.5}	t	2026-05-09 12:03:16.509422+02	\N
466aee3b-ee78-4cb3-8dbf-0f6d5d1ceca9	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.047643706	0.9528741	0.5	0.2	0.5	2026-05-09 12:04:56.967+02	2026-05-09 12:04:56.967+02	2026-05-09 12:05:00.08+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.5142865762296991, "slope": 0.016584720560764567}}, "rssiWeights": {"inside": [0.33999999999999997], "outside": [0.21999999999999997, 0.28, 0.21999999999999997, 0.43999999999999995, 0.31999999999999995]}, "centroidDeltaMs": 2966.297119140625, "insideScanCount": 1, "insideCentroidMs": 1778321096967, "outsideScanCount": 5, "clusterDurationMs": 3113, "outsideCentroidMs": 1778321099933.297}	f	2026-05-09 12:05:04.603262+02	\N
0610fa6d-ee11-4e16-829a-5650c7383217	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.09417283	0.9417283	0.5	0.2	\N	2026-05-09 12:04:56.967+02	2026-05-09 12:04:56.967+02	2026-05-09 12:05:00.08+02	{"centroidDeltaMs": 2931.60009765625, "insideScanCount": 1, "insideCentroidMs": 1778321096967, "outsideScanCount": 5, "clusterDurationMs": 3113, "outsideCentroidMs": 1778321099898.6}	t	2026-05-09 12:05:04.603262+02	\N
20e71bf4-3bae-4ed6-8c93-a2be47e6bd12	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.05938188	0.7125825	1	0.16666667	0.5	2026-05-09 12:05:26.491+02	2026-05-09 12:05:25.432+02	2026-05-09 12:05:29.392+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.18102453976281074, "slope": 0.004600489629076258}}, "rssiWeights": {"inside": [0.31999999999999995, 0.31999999999999995], "outside": [0.26, 0.33999999999999997, 0.33999999999999997, 0.36, 0.43999999999999995, 0.38, 0.36, 0.38, 0.6, 0.4, 0.26, 0.33999999999999997]}, "centroidDeltaMs": 2821.826904296875, "insideScanCount": 2, "insideCentroidMs": 1778321129313.5, "outsideScanCount": 12, "clusterDurationMs": 3960, "outsideCentroidMs": 1778321126491.673}	f	2026-05-09 12:05:34.619095+02	\N
4f826740-f1ee-4cff-90ea-623284c54a00	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.120359845	0.7221591	1	0.16666667	\N	2026-05-09 12:05:26.453+02	2026-05-09 12:05:25.432+02	2026-05-09 12:05:29.392+02	{"centroidDeltaMs": 2859.75, "insideScanCount": 2, "insideCentroidMs": 1778321129313.5, "outsideScanCount": 12, "clusterDurationMs": 3960, "outsideCentroidMs": 1778321126453.75}	t	2026-05-09 12:05:34.619095+02	\N
2377c61f-5d43-42e4-b9bd-a14abe92ea61	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3091684	0.8656715	1	0.71428573	0.5	2026-05-09 12:06:42.603+02	2026-05-09 12:06:42.417+02	2026-05-09 12:06:45.382+02	{"rssiTrend": {"inside": {"r2": 0.8324527221891993, "slope": 0.015135504039803623}, "outside": {"r2": 0.03218169216972844, "slope": 0.003293648665558356}}, "rssiWeights": {"inside": [0.26, 0.19999999999999996, 0.28, 0.33999999999999997, 0.31999999999999995], "outside": [0.19999999999999996, 0.28, 0.4, 0.38, 0.33999999999999997, 0.28, 0.26]}, "centroidDeltaMs": 2566.716064453125, "insideScanCount": 5, "insideCentroidMs": 1778321202603.1714, "outsideScanCount": 7, "clusterDurationMs": 2965, "outsideCentroidMs": 1778321205169.8875}	f	2026-05-09 12:06:50.664789+02	\N
3a781928-098c-4d0a-8a7f-c4fb3b9f7425	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.62235606	0.87129843	1	0.71428573	\N	2026-05-09 12:06:42.579+02	2026-05-09 12:06:42.417+02	2026-05-09 12:06:45.382+02	{"centroidDeltaMs": 2583.39990234375, "insideScanCount": 5, "insideCentroidMs": 1778321202579.6, "outsideScanCount": 7, "clusterDurationMs": 2965, "outsideCentroidMs": 1778321205163}	t	2026-05-09 12:06:50.664789+02	\N
17c5eb27-3ef0-445a-89a7-20ab0f65a08e	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.52729833	0.70306444	1	0.75	\N	2026-05-09 12:07:29.136+02	2026-05-09 12:07:28.317+02	2026-05-09 12:07:32.474+02	{"centroidDeltaMs": 2922.638916015625, "insideScanCount": 12, "insideCentroidMs": 1778321249136.9167, "outsideScanCount": 9, "clusterDurationMs": 4157, "outsideCentroidMs": 1778321252059.5557}	t	2026-05-09 12:07:36.684831+02	\N
525791a5-ba8c-4755-92b9-3a16e934b10d	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.34763244	0.7803993	1	0.6363636	0.7	2026-05-09 12:08:18.589+02	2026-05-09 12:08:18.268+02	2026-05-09 12:08:21.683+02	{"rssiTrend": {"inside": {"r2": 0.5058930141747926, "slope": -0.014057276995305165}, "outside": {"r2": 0.07452250512315461, "slope": -0.003891293966048024}}, "rssiWeights": {"inside": [0.62, 0.43999999999999995, 0.5800000000000001, 0.56, 0.45999999999999996, 0.43999999999999995, 0.38], "outside": [0.28, 0.43999999999999995, 0.5, 0.52, 0.43999999999999995, 0.45999999999999996, 0.33999999999999997, 0.33999999999999997, 0.28, 0.30000000000000004, 0.36]}, "centroidDeltaMs": 2665.063720703125, "insideScanCount": 7, "insideCentroidMs": 1778321298589.9883, "outsideScanCount": 11, "clusterDurationMs": 3415, "outsideCentroidMs": 1778321301255.052}	f	2026-05-09 12:08:26.713721+02	\N
5307438b-a61d-425b-8d8b-3cc39d6123ca	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.4952627	0.77827	1	0.6363636	\N	2026-05-09 12:08:18.614+02	2026-05-09 12:08:18.268+02	2026-05-09 12:08:21.683+02	{"centroidDeltaMs": 2657.7919921875, "insideScanCount": 7, "insideCentroidMs": 1778321298614.5715, "outsideScanCount": 11, "clusterDurationMs": 3415, "outsideCentroidMs": 1778321301272.3635}	t	2026-05-09 12:08:26.713721+02	\N
5007f8da-cf86-4908-aa57-17c089c9ec08	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.15868337	0.87275857	1	0.18181819	\N	2026-05-09 12:08:42.563+02	2026-05-09 12:08:42.223+02	2026-05-09 12:08:45.417+02	{"centroidDeltaMs": 2787.5908203125, "insideScanCount": 2, "insideCentroidMs": 1778321325351.5, "outsideScanCount": 11, "clusterDurationMs": 3194, "outsideCentroidMs": 1778321322563.9092}	t	2026-05-09 12:08:50.729497+02	\N
bced11c3-b5ac-4b44-b277-ebe3cd4eea1a	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.083468705	0.83468705	1	0.1	\N	2026-05-09 12:09:22.355+02	2026-05-09 12:09:21.823+02	2026-05-09 12:09:25.043+02	{"centroidDeltaMs": 2687.6923828125, "insideScanCount": 1, "insideCentroidMs": 1778321365043, "outsideScanCount": 13, "clusterDurationMs": 3220, "outsideCentroidMs": 1778321362355.3076}	t	2026-05-09 12:09:30.749592+02	\N
9d61ccea-f2e2-4340-804c-7cd6d06d59c3	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23503591	0.94014364	0.5	0.5	\N	2026-05-09 12:09:52.092+02	2026-05-09 12:09:52.017+02	2026-05-09 12:09:54.523+02	{"centroidDeltaMs": 2356, "insideScanCount": 2, "insideCentroidMs": 1778321392092, "outsideScanCount": 4, "clusterDurationMs": 2506, "outsideCentroidMs": 1778321394448}	t	2026-05-09 12:09:58.766227+02	\N
0280d920-d806-4c46-a874-1c1bf9e377ee	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.027565442	0.5513089	1	0.1	0.5	2026-05-09 12:03:27.368+02	2026-05-09 12:03:21.374+02	2026-05-09 12:03:35.075+02	{"rssiTrend": {"inside": {"r2": 0.44525065963060606, "slope": -0.009894459102902375}, "outside": {"r2": 0.038315104720895055, "slope": -0.00014680246350735134}}, "rssiWeights": {"inside": [0.4, 0.31999999999999995, 0.33999999999999997], "outside": [0.21999999999999997, 0.21999999999999997, 0.28, 0.4, 0.4, 0.4, 0.33999999999999997, 0.4, 0.43999999999999995, 0.45999999999999996, 0.45999999999999996, 0.43999999999999995, 0.43999999999999995, 0.4, 0.28, 0.28, 0.31999999999999995, 0.33999999999999997, 0.38, 0.36, 0.43999999999999995, 0.43999999999999995, 0.31999999999999995, 0.4, 0.48, 0.4, 0.28, 0.36, 0.33999999999999997, 0.26, 0.26, 0.28]}, "centroidDeltaMs": 7553.482666015625, "insideScanCount": 3, "insideCentroidMs": 1778321014921.6414, "outsideScanCount": 32, "clusterDurationMs": 13701, "outsideCentroidMs": 1778321007368.1587}	f	2026-05-09 12:03:40.534077+02	\N
8c44c509-7f5d-4bc5-8f4c-a566ba18611b	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.05374927	0.5374927	1	0.1	\N	2026-05-09 12:03:27.564+02	2026-05-09 12:03:21.374+02	2026-05-09 12:03:35.075+02	{"centroidDeltaMs": 7364.1875, "insideScanCount": 3, "insideCentroidMs": 1778321014929, "outsideScanCount": 32, "clusterDurationMs": 13701, "outsideCentroidMs": 1778321007564.8125}	t	2026-05-09 12:03:40.534077+02	\N
7e944acf-e803-441a-b71c-b134405c29ed	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.13491803	0.4497268	1	0.75	0.4	2026-05-09 12:04:30.633+02	2026-05-09 12:04:26.924+02	2026-05-09 12:04:34.017+02	{"rssiTrend": {"inside": {"r2": 0.24120559373763972, "slope": 0.023315774265964304}, "outside": {"r2": 0.2550471447839391, "slope": 0.00317148094866389}}, "rssiWeights": {"inside": [0.26, 0.28, 0.52, 0.62, 0.5, 0.4], "outside": [0.31999999999999995, 0.28, 0.5800000000000001, 0.64, 0.74, 0.45999999999999996, 0.72, 0.38]}, "centroidDeltaMs": 3189.912109375, "insideScanCount": 6, "insideCentroidMs": 1778321073823.8296, "outsideScanCount": 8, "clusterDurationMs": 7093, "outsideCentroidMs": 1778321070633.9175}	f	2026-05-09 12:04:38.590891+02	\N
e51f44c0-ad0d-4cde-9f1c-7825ad832aca	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.35857096	0.4780946	1	0.75	\N	2026-05-09 12:04:30.412+02	2026-05-09 12:04:26.924+02	2026-05-09 12:04:34.017+02	{"centroidDeltaMs": 3391.125, "insideScanCount": 6, "insideCentroidMs": 1778321073803.5, "outsideScanCount": 8, "clusterDurationMs": 7093, "outsideCentroidMs": 1778321070412.375}	t	2026-05-09 12:04:38.590891+02	\N
0ed8fc61-241c-4ff5-beb9-b89a09c29b3e	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.08851779	0.8298543	1	0.26666668	0.4	2026-05-09 12:05:48.329+02	2026-05-09 12:05:48.128+02	2026-05-09 12:05:51.673+02	{"rssiTrend": {"inside": {"r2": 0.5835888332089565, "slope": 0.018473315583592862}, "outside": {"r2": 0.23601676968568763, "slope": 0.006297121172788682}}, "rssiWeights": {"inside": [0.26, 0.26, 0.31999999999999995, 0.4], "outside": [0.30000000000000004, 0.21999999999999997, 0.33999999999999997, 0.33999999999999997, 0.33999999999999997, 0.26, 0.26, 0.28, 0.31999999999999995, 0.28, 0.52, 0.4, 0.19999999999999996, 0.48, 0.43999999999999995]}, "centroidDeltaMs": 2941.83349609375, "insideScanCount": 4, "insideCentroidMs": 1778321148329.5647, "outsideScanCount": 15, "clusterDurationMs": 3545, "outsideCentroidMs": 1778321151271.3982}	f	2026-05-09 12:05:56.632908+02	\N
5329ce3d-f2cd-4866-a238-3717dccc34df	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.21914433	0.82179123	1	0.26666668	\N	2026-05-09 12:05:48.312+02	2026-05-09 12:05:48.128+02	2026-05-09 12:05:51.673+02	{"centroidDeltaMs": 2913.25, "insideScanCount": 4, "insideCentroidMs": 1778321148312.75, "outsideScanCount": 15, "clusterDurationMs": 3545, "outsideCentroidMs": 1778321151226}	t	2026-05-09 12:05:56.632908+02	\N
e48bde6d-b176-458b-b3b8-6576c22243b3	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.053359915	0.8003987	1	0.13333334	0.5	2026-05-09 12:07:09.504+02	2026-05-09 12:07:08.936+02	2026-05-09 12:07:12.117+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.1341095308176975, "slope": 0.004688232444992224}}, "rssiWeights": {"inside": [0.26, 0.31999999999999995], "outside": [0.28, 0.26, 0.31999999999999995, 0.42000000000000004, 0.38, 0.45999999999999996, 0.45999999999999996, 0.45999999999999996, 0.45999999999999996, 0.5, 0.5, 0.5, 0.45999999999999996, 0.26, 0.33999999999999997]}, "centroidDeltaMs": 2546.068359375, "insideScanCount": 2, "insideCentroidMs": 1778321232050.2068, "outsideScanCount": 15, "clusterDurationMs": 3181, "outsideCentroidMs": 1778321229504.1384}	f	2026-05-09 12:07:16.672823+02	\N
e7b55260-1bdb-49e8-95b7-53f2d45c4aa3	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.10750637	0.8062978	1	0.13333334	\N	2026-05-09 12:07:09.477+02	2026-05-09 12:07:08.936+02	2026-05-09 12:07:12.117+02	{"centroidDeltaMs": 2564.833251953125, "insideScanCount": 2, "insideCentroidMs": 1778321232042.5, "outsideScanCount": 15, "clusterDurationMs": 3181, "outsideCentroidMs": 1778321229477.6667}	t	2026-05-09 12:07:16.672823+02	\N
0eb15f63-da3d-4c87-99b4-f8e67b1697b0	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.085606195	0.85606194	1	0.2	0.5	2026-05-09 12:07:55.405+02	2026-05-09 12:07:54.973+02	2026-05-09 12:07:58.317+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.04917823657646603, "slope": 0.0027600896433945133}}, "rssiWeights": {"inside": [0.38, 0.52], "outside": [0.19999999999999996, 0.33999999999999997, 0.43999999999999995, 0.38, 0.31999999999999995, 0.28, 0.31999999999999995, 0.38, 0.38, 0.31999999999999995]}, "centroidDeltaMs": 2862.671142578125, "insideScanCount": 2, "insideCentroidMs": 1778321278268.0225, "outsideScanCount": 10, "clusterDurationMs": 3344, "outsideCentroidMs": 1778321275405.3513}	f	2026-05-09 12:08:02.700288+02	\N
ae64b36d-f3a7-4980-b06b-6dfd1c2a1e6c	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.17129187	0.8564593	1	0.2	\N	2026-05-09 12:07:55.395+02	2026-05-09 12:07:54.973+02	2026-05-09 12:07:58.317+02	{"centroidDeltaMs": 2864, "insideScanCount": 2, "insideCentroidMs": 1778321278259, "outsideScanCount": 10, "clusterDurationMs": 3344, "outsideCentroidMs": 1778321275395}	t	2026-05-09 12:08:02.700288+02	\N
b9412d48-552d-423f-9876-15ecd89dd281	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.078858234	0.8674406	1	0.18181819	0.5	2026-05-09 12:08:42.589+02	2026-05-09 12:08:42.223+02	2026-05-09 12:08:45.417+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.38241048273351874, "slope": 0.00881720430107527}}, "rssiWeights": {"inside": [0.19999999999999996, 0.26], "outside": [0.31999999999999995, 0.33999999999999997, 0.28, 0.38, 0.38, 0.43999999999999995, 0.45999999999999996, 0.45999999999999996, 0.52, 0.43999999999999995, 0.36]}, "centroidDeltaMs": 2770.605224609375, "insideScanCount": 2, "insideCentroidMs": 1778321325360.0437, "outsideScanCount": 11, "clusterDurationMs": 3194, "outsideCentroidMs": 1778321322589.4385}	f	2026-05-09 12:08:50.729497+02	\N
0a8cb9cd-7a69-42ee-a0d3-98b021c8cf5c	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.6682597	0.75179213	1	0.8888889	\N	2026-05-09 12:08:58.927+02	2026-05-09 12:08:58.483+02	2026-05-09 12:09:01.273+02	{"centroidDeltaMs": 2097.5, "insideScanCount": 8, "insideCentroidMs": 1778321338927.5, "outsideScanCount": 9, "clusterDurationMs": 2790, "outsideCentroidMs": 1778321341025}	t	2026-05-09 12:09:06.737151+02	\N
cc226522-c507-4f29-b6b8-81528901438a	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23734275	0.7911425	1	0.6	0.5	2026-05-09 12:03:57.917+02	2026-05-09 12:03:57.567+02	2026-05-09 12:04:00.973+02	{"rssiTrend": {"inside": {"r2": 0.32257522124452875, "slope": 0.008140787237265032}, "outside": {"r2": 0.0029018627793463425, "slope": -0.0007580748343337185}}, "rssiWeights": {"inside": [0.21999999999999997, 0.30000000000000004, 0.33999999999999997, 0.24, 0.38, 0.33999999999999997], "outside": [0.33999999999999997, 0.31999999999999995, 0.26, 0.19999999999999996, 0.33999999999999997, 0.36, 0.30000000000000004, 0.42000000000000004, 0.31999999999999995, 0.19999999999999996]}, "centroidDeltaMs": 2694.63134765625, "insideScanCount": 6, "insideCentroidMs": 1778321037917.2637, "outsideScanCount": 10, "clusterDurationMs": 3406, "outsideCentroidMs": 1778321040611.895}	f	2026-05-09 12:04:06.570349+02	\N
29462daa-66f9-47c5-89d5-a64921af9789	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.47890782	0.7981797	1	0.6	\N	2026-05-09 12:03:57.896+02	2026-05-09 12:03:57.567+02	2026-05-09 12:04:00.973+02	{"centroidDeltaMs": 2718.60009765625, "insideScanCount": 6, "insideCentroidMs": 1778321037896, "outsideScanCount": 10, "clusterDurationMs": 3406, "outsideCentroidMs": 1778321040614.6}	t	2026-05-09 12:04:06.570349+02	\N
ab5e82f0-834b-422f-9714-6f40c028f983	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.079807445	0.34203193	1	0.46666667	0.5	2026-05-09 12:06:20.044+02	2026-05-09 12:06:12.524+02	2026-05-09 12:06:24.417+02	{"rssiTrend": {"inside": {"r2": 0.08899957919200108, "slope": -0.003847860109181875}, "outside": {"r2": 0.004518028159883336, "slope": 0.00011140401655352444}}, "rssiWeights": {"inside": [0.33999999999999997, 0.4, 0.43999999999999995, 0.45999999999999996, 0.31999999999999995, 0.31999999999999995, 0.30000000000000004], "outside": [0.33999999999999997, 0.43999999999999995, 0.21999999999999997, 0.28, 0.33999999999999997, 0.42000000000000004, 0.33999999999999997, 0.4, 0.4, 0.4, 0.56, 0.56, 0.54, 0.33999999999999997, 0.31999999999999995]}, "centroidDeltaMs": 4067.78564453125, "insideScanCount": 7, "insideCentroidMs": 1778321184112.0776, "outsideScanCount": 15, "clusterDurationMs": 11893, "outsideCentroidMs": 1778321180044.292}	f	2026-05-09 12:06:28.650843+02	\N
3f22bb8e-9d49-4aa7-9268-a9f622df49d1	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.16193354	0.34700045	1	0.46666667	\N	2026-05-09 12:06:19.996+02	2026-05-09 12:06:12.524+02	2026-05-09 12:06:24.417+02	{"centroidDeltaMs": 4126.876220703125, "insideScanCount": 7, "insideCentroidMs": 1778321184123.1428, "outsideScanCount": 15, "clusterDurationMs": 11893, "outsideCentroidMs": 1778321179996.2666}	t	2026-05-09 12:06:28.650843+02	\N
c73d4632-3a10-47ad-a81c-bf2f04527f1f	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.6611965	0.808129	1	0.8181818	1	2026-05-09 11:59:59.185+02	2026-05-09 11:59:58.873+02	2026-05-09 12:00:02.825+02	{"rssiTrend": {"inside": {"r2": 0.3238717846112519, "slope": 0.004201730604585219}, "outside": {"r2": 0.35957968024755094, "slope": -0.007952380952380952}}, "rssiWeights": {"inside": [0.28, 0.28, 0.31999999999999995, 0.26, 0.31999999999999995, 0.4, 0.33999999999999997, 0.28, 0.4, 0.42000000000000004, 0.33999999999999997], "outside": [0.31999999999999995, 0.26, 0.36, 0.33999999999999997, 0.31999999999999995, 0.31999999999999995, 0.31999999999999995, 0.21999999999999997, 0.19999999999999996]}, "centroidDeltaMs": 3193.725830078125, "insideScanCount": 11, "insideCentroidMs": 1778320802379.1323, "outsideScanCount": 9, "clusterDurationMs": 3952, "outsideCentroidMs": 1778320799185.4065}	f	2026-05-09 12:00:08.36334+02	\N
9c3fb5af-e0f9-4abe-844c-8fc74a16259e	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.6501364	0.79461116	1	0.8181818	\N	2026-05-09 11:59:59.206+02	2026-05-09 11:59:58.873+02	2026-05-09 12:00:02.825+02	{"centroidDeltaMs": 3140.30322265625, "insideScanCount": 11, "insideCentroidMs": 1778320802346.6365, "outsideScanCount": 9, "clusterDurationMs": 3952, "outsideCentroidMs": 1778320799206.3333}	t	2026-05-09 12:00:08.36334+02	\N
503bb163-3c55-481c-8048-f3a788370850	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.25825977	0.68869275	1	0.75	0.5	2026-05-09 12:07:29.194+02	2026-05-09 12:07:28.317+02	2026-05-09 12:07:32.474+02	{"rssiTrend": {"inside": {"r2": 0.3063003340401481, "slope": 0.0038768801940396117}, "outside": {"r2": 0.0073574301730184866, "slope": -0.0007626857193436864}}, "rssiWeights": {"inside": [0.36, 0.31999999999999995, 0.28, 0.28, 0.19999999999999996, 0.31999999999999995, 0.33999999999999997, 0.31999999999999995, 0.31999999999999995, 0.33999999999999997, 0.48, 0.43999999999999995], "outside": [0.38, 0.33999999999999997, 0.38, 0.31999999999999995, 0.28, 0.28, 0.36, 0.30000000000000004, 0.4]}, "centroidDeltaMs": 2862.895751953125, "insideScanCount": 12, "insideCentroidMs": 1778321249194.0652, "outsideScanCount": 9, "clusterDurationMs": 4157, "outsideCentroidMs": 1778321252056.961}	f	2026-05-09 12:07:36.684831+02	\N
c758572d-5e5d-421d-ba3f-0680f5295e61	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.043404937	0.86809874	1	0.1	0.5	2026-05-09 12:01:04.969+02	2026-05-09 12:01:04.59+02	2026-05-09 12:01:07.467+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.15357827193376739, "slope": 0.0050924502161699406}}, "rssiWeights": {"inside": [0.28], "outside": [0.42000000000000004, 0.31999999999999995, 0.28, 0.45999999999999996, 0.43999999999999995, 0.43999999999999995, 0.43999999999999995, 0.45999999999999996, 0.4, 0.38, 0.54, 0.38]}, "centroidDeltaMs": 2497.52001953125, "insideScanCount": 1, "insideCentroidMs": 1778320867467, "outsideScanCount": 12, "clusterDurationMs": 2877, "outsideCentroidMs": 1778320864969.48}	f	2026-05-09 12:01:12.416224+02	\N
7c368c7a-5282-4e2c-affe-ae6a16a4faf4	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.08735373	0.8735373	1	0.1	\N	2026-05-09 12:01:04.953+02	2026-05-09 12:01:04.59+02	2026-05-09 12:01:07.467+02	{"centroidDeltaMs": 2513.166748046875, "insideScanCount": 1, "insideCentroidMs": 1778320867467, "outsideScanCount": 12, "clusterDurationMs": 2877, "outsideCentroidMs": 1778320864953.8333}	t	2026-05-09 12:01:12.416224+02	\N
9bfaf441-5118-4df6-aa6c-e9fd50f68737	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.19449577	0.77798307	1	0.5	0.5	2026-05-09 12:01:27.669+02	2026-05-09 12:01:27.268+02	2026-05-09 12:01:30.823+02	{"rssiTrend": {"inside": {"r2": 0.18079621365602216, "slope": 0.007791862630485416}, "outside": {"r2": 0.019999357751243285, "slope": 0.002761024452827967}}, "rssiWeights": {"inside": [0.26, 0.31999999999999995, 0.45999999999999996, 0.43999999999999995, 0.43999999999999995, 0.30000000000000004], "outside": [0.4, 0.43999999999999995, 0.38, 0.30000000000000004, 0.45999999999999996, 0.6, 0.56, 0.64, 0.5800000000000001, 0.5, 0.28, 0.38]}, "centroidDeltaMs": 2765.729736328125, "insideScanCount": 6, "insideCentroidMs": 1778320887669.0454, "outsideScanCount": 12, "clusterDurationMs": 3555, "outsideCentroidMs": 1778320890434.7751}	f	2026-05-09 12:01:36.437076+02	\N
d45dd7db-968d-4a2c-aca7-5c65b630a2e7	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.39033052	0.78066105	1	0.5	\N	2026-05-09 12:01:27.649+02	2026-05-09 12:01:27.268+02	2026-05-09 12:01:30.823+02	{"centroidDeltaMs": 2775.25, "insideScanCount": 6, "insideCentroidMs": 1778320887649.5, "outsideScanCount": 12, "clusterDurationMs": 3555, "outsideCentroidMs": 1778320890424.75}	t	2026-05-09 12:01:36.437076+02	\N
ab6f55aa-6624-4b53-bc2f-c9eb60a6492e	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.33566418	0.7552444	1	0.8888889	0.5	2026-05-09 12:08:58.92+02	2026-05-09 12:08:58.483+02	2026-05-09 12:09:01.273+02	{"rssiTrend": {"inside": {"r2": 0.031298891283025654, "slope": -0.0018678876944233154}, "outside": {"r2": 0.0031652858210650114, "slope": 0.0011201085682068783}}, "rssiWeights": {"inside": [0.31999999999999995, 0.42000000000000004, 0.4, 0.33999999999999997, 0.26, 0.4, 0.4, 0.30000000000000004], "outside": [0.21999999999999997, 0.4, 0.43999999999999995, 0.43999999999999995, 0.45999999999999996, 0.48, 0.31999999999999995, 0.4, 0.28]}, "centroidDeltaMs": 2107.1318359375, "insideScanCount": 8, "insideCentroidMs": 1778321338920.479, "outsideScanCount": 9, "clusterDurationMs": 2790, "outsideCentroidMs": 1778321341027.6108}	f	2026-05-09 12:09:06.737151+02	\N
0b0c8c1b-1128-4f96-acac-525913612d7b	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.041439913	0.8287983	1	0.1	0.5	2026-05-09 12:09:22.374+02	2026-05-09 12:09:21.823+02	2026-05-09 12:09:25.043+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.08021534104199424, "slope": 0.004412118207790654}}, "rssiWeights": {"inside": [0.30000000000000004], "outside": [0.28, 0.33999999999999997, 0.28, 0.36, 0.52, 0.31999999999999995, 0.4, 0.52, 0.52, 0.42000000000000004, 0.26, 0.33999999999999997, 0.42000000000000004]}, "centroidDeltaMs": 2668.73046875, "insideScanCount": 1, "insideCentroidMs": 1778321365043, "outsideScanCount": 13, "clusterDurationMs": 3220, "outsideCentroidMs": 1778321362374.2695}	f	2026-05-09 12:09:30.749592+02	\N
2b98ff2a-0237-44cc-9928-03105bf89a35	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.1164506	0.9316048	0.5	0.5	0.5	2026-05-09 12:09:52.104+02	2026-05-09 12:09:52.017+02	2026-05-09 12:09:54.523+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.9607843137254902, "slope": -0.023333333333333334}}, "rssiWeights": {"inside": [0.19999999999999996, 0.28], "outside": [0.33999999999999997, 0.31999999999999995, 0.26, 0.26]}, "centroidDeltaMs": 2334.6015625, "insideScanCount": 2, "insideCentroidMs": 1778321392104.5, "outsideScanCount": 4, "clusterDurationMs": 2506, "outsideCentroidMs": 1778321394439.1016}	f	2026-05-09 12:09:58.766227+02	\N
\.


--
-- Data for Name: raw_scans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.raw_scans (id, lighthouse_id, epc, epc_length, rssi_dbm, antenna_id, frequency, sequence_number, detection_confidence, timestamp_ms, "timestamp", received_at, processed_at, orphaned_at, orphan_reason, source, time_basis, created_at) FROM stdin;
19349	10	E28011704000021D53DAB0CB	\N	-74	0	24	\N	\N	1778321066924	2026-05-09 12:04:26.924+02	2026-05-09 12:04:28.013707+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:28.013707+02
19267	10	E28011704000021D53DAB0CB	\N	-70	0	18	\N	\N	1778320962387	2026-05-09 12:02:42.387+02	2026-05-09 12:02:43.361646+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:43.361646+02
19271	10	E28011704000021D53DAB0CB	\N	-76	0	42	\N	\N	1778320965823	2026-05-09 12:02:45.823+02	2026-05-09 12:02:46.747584+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.747584+02
19274	10	E28011704000021D53DAB0CB	\N	-70	0	55	\N	\N	1778320966124	2026-05-09 12:02:46.124+02	2026-05-09 12:02:46.798531+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.798531+02
19277	10	E28011704000021D53DAB0CB	\N	-70	0	22	\N	\N	1778320966285	2026-05-09 12:02:46.285+02	2026-05-09 12:02:46.80629+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.80629+02
19280	10	E28011704000021D53DAB0CB	\N	-75	0	10	\N	\N	1778320966573	2026-05-09 12:02:46.573+02	2026-05-09 12:02:46.864461+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.864461+02
19350	10	E28011704000021D53DAB0CB	\N	-76	0	35	\N	\N	1778321070378	2026-05-09 12:04:30.378+02	2026-05-09 12:04:31.291149+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.291149+02
19182	10	E28011704000021D53DAB0CB	\N	-67	0	9	\N	\N	1778320759131	2026-05-09 11:59:19.131+02	2026-05-09 11:59:20.094806+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.094806+02
19183	10	E28011704000021D53DAB0CB	\N	-68	0	19	\N	\N	1778320759423	2026-05-09 11:59:19.423+02	2026-05-09 11:59:20.129682+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.129682+02
19184	10	E28011704000021D53DAB0CB	\N	-65	0	30	\N	\N	1778320759423	2026-05-09 11:59:19.423+02	2026-05-09 11:59:20.132091+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.132091+02
19185	10	E28011704000021D53DAB0CB	\N	-65	0	14	\N	\N	1778320759573	2026-05-09 11:59:19.573+02	2026-05-09 11:59:20.155041+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.155041+02
19186	10	E28011704000021D53DAB0CB	\N	-73	0	17	\N	\N	1778320759573	2026-05-09 11:59:19.573+02	2026-05-09 11:59:20.157859+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.157859+02
19187	10	E28011704000021D53DAB0CB	\N	-77	0	29	\N	\N	1778320759724	2026-05-09 11:59:19.724+02	2026-05-09 11:59:20.218814+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.218814+02
19188	10	E28011704000021D53DAB0CB	\N	-63	0	56	\N	\N	1778320759724	2026-05-09 11:59:19.724+02	2026-05-09 11:59:20.220959+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.220959+02
19189	10	E28011704000021D53DAB0CB	\N	-70	0	39	\N	\N	1778320759875	2026-05-09 11:59:19.875+02	2026-05-09 11:59:20.276586+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.276586+02
19190	10	E28011704000021D53DAB0CB	\N	-71	0	58	\N	\N	1778320759875	2026-05-09 11:59:19.875+02	2026-05-09 11:59:20.278877+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.278877+02
19191	10	E28011704000021D53DAB0CB	\N	-70	0	47	\N	\N	1778320760024	2026-05-09 11:59:20.024+02	2026-05-09 11:59:20.305774+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.305774+02
19192	10	E28011704000021D53DAB0CB	\N	-71	0	57	\N	\N	1778320760024	2026-05-09 11:59:20.024+02	2026-05-09 11:59:20.310118+02	\N	2026-05-09 11:59:28.332+02	insufficient_data	realtime	synced	2026-05-09 11:59:20.310118+02
19354	10	E28011704000021D53DAB0CB	\N	-54	0	51	\N	\N	1778321071124	2026-05-09 12:04:31.124+02	2026-05-09 12:04:31.629071+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.629071+02
19367	10	E28011704000021D53DAB0CB	\N	-68	0	35	\N	\N	1778321100080	2026-05-09 12:05:00.08+02	2026-05-09 12:05:01.416659+02	2026-05-09 12:05:04.605+02	\N	\N	realtime	synced	2026-05-09 12:05:01.416659+02
19364	10	E28011704000021D53DAB0CB	\N	-79	0	42	\N	\N	1778321099623	2026-05-09 12:04:59.623+02	2026-05-09 12:05:00.684479+02	2026-05-09 12:05:04.605+02	\N	\N	realtime	synced	2026-05-09 12:05:00.684479+02
19282	9	E28011704000021D53DAB0CB	\N	-69	0	55	\N	\N	1778320987319	2026-05-09 12:03:07.319+02	2026-05-09 12:03:08.448197+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:08.448197+02
19283	9	E28011704000021D53DAB0CB	\N	-72	0	8	\N	\N	1778320988096	2026-05-09 12:03:08.096+02	2026-05-09 12:03:08.859042+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:08.859042+02
19285	9	E28011704000021D53DAB0CB	\N	-69	0	52	\N	\N	1778320988367	2026-05-09 12:03:08.367+02	2026-05-09 12:03:08.887938+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:08.887938+02
19287	10	E28011704000021D53DAB0CB	\N	-73	0	53	\N	\N	1778320990873	2026-05-09 12:03:10.873+02	2026-05-09 12:03:11.878307+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.878307+02
19288	10	E28011704000021D53DAB0CB	\N	-66	0	12	\N	\N	1778320990873	2026-05-09 12:03:10.873+02	2026-05-09 12:03:11.880404+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.880404+02
19293	10	E28011704000021D53DAB0CB	\N	-74	0	56	\N	\N	1778320991323	2026-05-09 12:03:11.323+02	2026-05-09 12:03:11.935769+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.935769+02
19294	10	E28011704000021D53DAB0CB	\N	-74	0	43	\N	\N	1778320991323	2026-05-09 12:03:11.323+02	2026-05-09 12:03:11.937942+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.937942+02
19297	10	E28011704000021D53DAB0CB	\N	-74	0	41	\N	\N	1778320991624	2026-05-09 12:03:11.624+02	2026-05-09 12:03:11.984849+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.984849+02
19193	10	E28011704000021D53DAB0CB	\N	-74	0	38	\N	\N	1778320798873	2026-05-09 11:59:58.873+02	2026-05-09 11:59:59.928827+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 11:59:59.928827+02
19194	10	E28011704000021D53DAB0CB	\N	-77	0	52	\N	\N	1778320799023	2026-05-09 11:59:59.023+02	2026-05-09 12:00:00.338124+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.338124+02
19195	10	E28011704000021D53DAB0CB	\N	-72	0	50	\N	\N	1778320799023	2026-05-09 11:59:59.023+02	2026-05-09 12:00:00.340152+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.340152+02
19196	10	E28011704000021D53DAB0CB	\N	-73	0	20	\N	\N	1778320799173	2026-05-09 11:59:59.173+02	2026-05-09 12:00:00.358376+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.358376+02
19197	10	E28011704000021D53DAB0CB	\N	-74	0	45	\N	\N	1778320799173	2026-05-09 11:59:59.173+02	2026-05-09 12:00:00.360965+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.360965+02
19198	10	E28011704000021D53DAB0CB	\N	-74	0	56	\N	\N	1778320799323	2026-05-09 11:59:59.323+02	2026-05-09 12:00:00.372907+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.372907+02
19199	10	E28011704000021D53DAB0CB	\N	-74	0	41	\N	\N	1778320799323	2026-05-09 11:59:59.323+02	2026-05-09 12:00:00.374836+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.374836+02
19200	10	E28011704000021D53DAB0CB	\N	-79	0	9	\N	\N	1778320799473	2026-05-09 11:59:59.473+02	2026-05-09 12:00:00.404621+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.404621+02
19201	10	E28011704000021D53DAB0CB	\N	-80	0	15	\N	\N	1778320799473	2026-05-09 11:59:59.473+02	2026-05-09 12:00:00.406667+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:00.406667+02
19202	9	E28011704000021D53DAB0CB	\N	-76	0	52	\N	\N	1778320801467	2026-05-09 12:00:01.467+02	2026-05-09 12:00:02.252786+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:02.252786+02
19203	9	E28011704000021D53DAB0CB	\N	-76	0	7	\N	\N	1778320802099	2026-05-09 12:00:02.099+02	2026-05-09 12:00:02.316401+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:02.316401+02
19204	9	E28011704000021D53DAB0CB	\N	-74	0	31	\N	\N	1778320802099	2026-05-09 12:00:02.099+02	2026-05-09 12:00:02.318204+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:02.318204+02
19205	9	E28011704000021D53DAB0CB	\N	-77	0	52	\N	\N	1778320802217	2026-05-09 12:00:02.217+02	2026-05-09 12:00:02.344405+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:02.344405+02
19206	9	E28011704000021D53DAB0CB	\N	-74	0	45	\N	\N	1778320802367	2026-05-09 12:00:02.367+02	2026-05-09 12:00:03.410405+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.410405+02
19207	9	E28011704000021D53DAB0CB	\N	-70	0	49	\N	\N	1778320802367	2026-05-09 12:00:02.367+02	2026-05-09 12:00:03.41689+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.41689+02
19208	9	E28011704000021D53DAB0CB	\N	-76	0	42	\N	\N	1778320802519	2026-05-09 12:00:02.519+02	2026-05-09 12:00:03.453817+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.453817+02
19209	9	E28011704000021D53DAB0CB	\N	-73	0	32	\N	\N	1778320802519	2026-05-09 12:00:02.519+02	2026-05-09 12:00:03.455784+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.455784+02
19333	9	E28011704000021D53DAB0CB	\N	-79	0	13	\N	\N	1778321037567	2026-05-09 12:03:57.567+02	2026-05-09 12:03:57.907736+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:03:57.907736+02
19334	9	E28011704000021D53DAB0CB	\N	-75	0	25	\N	\N	1778321037734	2026-05-09 12:03:57.734+02	2026-05-09 12:03:58.112992+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:03:58.112992+02
19335	9	E28011704000021D53DAB0CB	\N	-73	0	21	\N	\N	1778321037874	2026-05-09 12:03:57.874+02	2026-05-09 12:03:58.260137+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:03:58.260137+02
19337	9	E28011704000021D53DAB0CB	\N	-78	0	43	\N	\N	1778321038017	2026-05-09 12:03:58.017+02	2026-05-09 12:03:58.27934+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:03:58.27934+02
19338	9	E28011704000021D53DAB0CB	\N	-73	0	27	\N	\N	1778321038167	2026-05-09 12:03:58.167+02	2026-05-09 12:03:58.3296+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:03:58.3296+02
19339	10	E28011704000021D53DAB0CB	\N	-73	0	34	\N	\N	1778321040223	2026-05-09 12:04:00.223+02	2026-05-09 12:04:01.118908+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.118908+02
19340	10	E28011704000021D53DAB0CB	\N	-77	0	26	\N	\N	1778321040378	2026-05-09 12:04:00.378+02	2026-05-09 12:04:01.145636+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.145636+02
19346	10	E28011704000021D53DAB0CB	\N	-74	0	11	\N	\N	1778321040824	2026-05-09 12:04:00.824+02	2026-05-09 12:04:01.205451+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.205451+02
19210	9	E28011704000021D53DAB0CB	\N	-70	0	13	\N	\N	1778320802667	2026-05-09 12:00:02.667+02	2026-05-09 12:00:03.477262+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.477262+02
19211	9	E28011704000021D53DAB0CB	\N	-73	0	23	\N	\N	1778320802825	2026-05-09 12:00:02.825+02	2026-05-09 12:00:03.500491+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.500491+02
19212	9	E28011704000021D53DAB0CB	\N	-69	0	48	\N	\N	1778320802667	2026-05-09 12:00:02.667+02	2026-05-09 12:00:03.508766+02	2026-05-09 12:00:08.367+02	\N	\N	realtime	synced	2026-05-09 12:00:03.508766+02
19265	9	E28011704000021D53DAB0CB	\N	-73	0	27	\N	\N	1778320939799	2026-05-09 12:02:19.799+02	2026-05-09 12:02:20.012602+02	\N	2026-05-09 12:02:28.481+02	insufficient_data	realtime	synced	2026-05-09 12:02:20.012602+02
19268	10	E28011704000021D53DAB0CB	\N	-60	0	52	\N	\N	1778320962387	2026-05-09 12:02:42.387+02	2026-05-09 12:02:43.364192+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:43.364192+02
19213	10	E28011704000021D53DAB0CB	\N	-76	0	31	\N	\N	1778320827223	2026-05-09 12:00:27.223+02	2026-05-09 12:00:28.088442+02	\N	2026-05-09 12:00:36.383+02	insufficient_data	realtime	synced	2026-05-09 12:00:28.088442+02
19214	10	E28011704000021D53DAB0CB	\N	-79	0	53	\N	\N	1778320827390	2026-05-09 12:00:27.39+02	2026-05-09 12:00:28.099142+02	\N	2026-05-09 12:00:36.383+02	insufficient_data	realtime	synced	2026-05-09 12:00:28.099142+02
19215	10	E28011704000021D53DAB0CB	\N	-74	0	24	\N	\N	1778320827523	2026-05-09 12:00:27.523+02	2026-05-09 12:00:28.135534+02	\N	2026-05-09 12:00:36.383+02	insufficient_data	realtime	synced	2026-05-09 12:00:28.135534+02
19216	10	E28011704000021D53DAB0CB	\N	-71	0	7	\N	\N	1778320827523	2026-05-09 12:00:27.523+02	2026-05-09 12:00:28.140084+02	\N	2026-05-09 12:00:36.383+02	insufficient_data	realtime	synced	2026-05-09 12:00:28.140084+02
19217	10	E28011704000021D53DAB0CB	\N	-73	0	17	\N	\N	1778320827690	2026-05-09 12:00:27.69+02	2026-05-09 12:00:28.150235+02	\N	2026-05-09 12:00:36.383+02	insufficient_data	realtime	synced	2026-05-09 12:00:28.150235+02
19218	10	E28011704000021D53DAB0CB	\N	-76	0	17	\N	\N	1778320827690	2026-05-09 12:00:27.69+02	2026-05-09 12:00:28.156816+02	\N	2026-05-09 12:00:36.383+02	insufficient_data	realtime	synced	2026-05-09 12:00:28.156816+02
19272	10	E28011704000021D53DAB0CB	\N	-74	0	45	\N	\N	1778320965973	2026-05-09 12:02:45.973+02	2026-05-09 12:02:46.779683+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.779683+02
19275	10	E28011704000021D53DAB0CB	\N	-71	0	23	\N	\N	1778320966124	2026-05-09 12:02:46.124+02	2026-05-09 12:02:46.8005+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.8005+02
19278	10	E28011704000021D53DAB0CB	\N	-74	0	58	\N	\N	1778320966425	2026-05-09 12:02:46.425+02	2026-05-09 12:02:46.844624+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.844624+02
19356	10	E28011704000021D53DAB0CB	\N	-71	0	9	\N	\N	1778321071124	2026-05-09 12:04:31.124+02	2026-05-09 12:04:31.635852+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.635852+02
19366	10	E28011704000021D53DAB0CB	\N	-79	0	55	\N	\N	1778321099923	2026-05-09 12:04:59.923+02	2026-05-09 12:05:01.397451+02	2026-05-09 12:05:04.605+02	\N	\N	realtime	synced	2026-05-09 12:05:01.397451+02
19372	10	E28011704000021D53DAB0CB	\N	-73	0	39	\N	\N	1778321126328	2026-05-09 12:05:26.328+02	2026-05-09 12:05:27.228734+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.228734+02
19284	9	E28011704000021D53DAB0CB	\N	-76	0	33	\N	\N	1778320988217	2026-05-09 12:03:08.217+02	2026-05-09 12:03:08.869623+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:08.869623+02
19286	10	E28011704000021D53DAB0CB	\N	-70	0	52	\N	\N	1778320990736	2026-05-09 12:03:10.736+02	2026-05-09 12:03:11.828885+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.828885+02
19291	10	E28011704000021D53DAB0CB	\N	-70	0	54	\N	\N	1778320991173	2026-05-09 12:03:11.173+02	2026-05-09 12:03:11.921658+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.921658+02
19292	10	E28011704000021D53DAB0CB	\N	-80	0	46	\N	\N	1778320991173	2026-05-09 12:03:11.173+02	2026-05-09 12:03:11.923975+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.923975+02
19379	10	E28011704000021D53DAB0CB	\N	-77	0	14	\N	\N	1778321126786	2026-05-09 12:05:26.786+02	2026-05-09 12:05:27.277098+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.277098+02
19219	10	E28011704000021D53DAB0CB	\N	-69	0	18	\N	\N	1778320864590	2026-05-09 12:01:04.59+02	2026-05-09 12:01:05.362539+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.362539+02
19220	10	E28011704000021D53DAB0CB	\N	-74	0	29	\N	\N	1778320864590	2026-05-09 12:01:04.59+02	2026-05-09 12:01:05.364809+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.364809+02
19221	10	E28011704000021D53DAB0CB	\N	-76	0	31	\N	\N	1778320864723	2026-05-09 12:01:04.723+02	2026-05-09 12:01:05.66954+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.66954+02
19222	10	E28011704000021D53DAB0CB	\N	-67	0	33	\N	\N	1778320864723	2026-05-09 12:01:04.723+02	2026-05-09 12:01:05.676961+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.676961+02
19223	10	E28011704000021D53DAB0CB	\N	-68	0	15	\N	\N	1778320864887	2026-05-09 12:01:04.887+02	2026-05-09 12:01:05.693338+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.693338+02
19224	10	E28011704000021D53DAB0CB	\N	-68	0	28	\N	\N	1778320864887	2026-05-09 12:01:04.887+02	2026-05-09 12:01:05.695993+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.695993+02
19225	10	E28011704000021D53DAB0CB	\N	-68	0	18	\N	\N	1778320865025	2026-05-09 12:01:05.025+02	2026-05-09 12:01:05.708735+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.708735+02
19226	10	E28011704000021D53DAB0CB	\N	-67	0	31	\N	\N	1778320865025	2026-05-09 12:01:05.025+02	2026-05-09 12:01:05.710471+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.710471+02
19227	10	E28011704000021D53DAB0CB	\N	-70	0	12	\N	\N	1778320865173	2026-05-09 12:01:05.173+02	2026-05-09 12:01:05.723391+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.723391+02
19228	10	E28011704000021D53DAB0CB	\N	-71	0	39	\N	\N	1778320865173	2026-05-09 12:01:05.173+02	2026-05-09 12:01:05.726144+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.726144+02
19229	10	E28011704000021D53DAB0CB	\N	-63	0	35	\N	\N	1778320865325	2026-05-09 12:01:05.325+02	2026-05-09 12:01:05.758584+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.758584+02
19230	10	E28011704000021D53DAB0CB	\N	-71	0	34	\N	\N	1778320865325	2026-05-09 12:01:05.325+02	2026-05-09 12:01:05.761737+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:05.761737+02
19231	9	E28011704000021D53DAB0CB	\N	-76	0	27	\N	\N	1778320867467	2026-05-09 12:01:07.467+02	2026-05-09 12:01:07.717503+02	2026-05-09 12:01:12.419+02	\N	\N	realtime	synced	2026-05-09 12:01:07.717503+02
19232	9	E28011704000021D53DAB0CB	\N	-77	0	8	\N	\N	1778320887268	2026-05-09 12:01:27.268+02	2026-05-09 12:01:27.583362+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:27.583362+02
19233	9	E28011704000021D53DAB0CB	\N	-74	0	22	\N	\N	1778320887567	2026-05-09 12:01:27.567+02	2026-05-09 12:01:27.648918+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:27.648918+02
19234	9	E28011704000021D53DAB0CB	\N	-67	0	18	\N	\N	1778320887567	2026-05-09 12:01:27.567+02	2026-05-09 12:01:27.650757+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:27.650757+02
19235	9	E28011704000021D53DAB0CB	\N	-68	0	52	\N	\N	1778320887717	2026-05-09 12:01:27.717+02	2026-05-09 12:01:28.812452+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:28.812452+02
19236	9	E28011704000021D53DAB0CB	\N	-68	0	34	\N	\N	1778320887889	2026-05-09 12:01:27.889+02	2026-05-09 12:01:29.119494+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:29.119494+02
19237	9	E28011704000021D53DAB0CB	\N	-75	0	41	\N	\N	1778320887889	2026-05-09 12:01:27.889+02	2026-05-09 12:01:29.121371+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:29.121371+02
19238	10	E28011704000021D53DAB0CB	\N	-70	0	20	\N	\N	1778320889924	2026-05-09 12:01:29.924+02	2026-05-09 12:01:30.660445+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:30.660445+02
19239	10	E28011704000021D53DAB0CB	\N	-68	0	48	\N	\N	1778320890073	2026-05-09 12:01:30.073+02	2026-05-09 12:01:30.867568+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:30.867568+02
19240	10	E28011704000021D53DAB0CB	\N	-71	0	8	\N	\N	1778320890073	2026-05-09 12:01:30.073+02	2026-05-09 12:01:30.869459+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:30.869459+02
19241	10	E28011704000021D53DAB0CB	\N	-75	0	25	\N	\N	1778320890223	2026-05-09 12:01:30.223+02	2026-05-09 12:01:30.894838+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:30.894838+02
19242	10	E28011704000021D53DAB0CB	\N	-67	0	11	\N	\N	1778320890383	2026-05-09 12:01:30.383+02	2026-05-09 12:01:31.167331+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.167331+02
19243	10	E28011704000021D53DAB0CB	\N	-60	0	57	\N	\N	1778320890383	2026-05-09 12:01:30.383+02	2026-05-09 12:01:31.169174+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.169174+02
19244	10	E28011704000021D53DAB0CB	\N	-62	0	20	\N	\N	1778320890523	2026-05-09 12:01:30.523+02	2026-05-09 12:01:31.242976+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.242976+02
19245	10	E28011704000021D53DAB0CB	\N	-58	0	54	\N	\N	1778320890523	2026-05-09 12:01:30.523+02	2026-05-09 12:01:31.245184+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.245184+02
19246	10	E28011704000021D53DAB0CB	\N	-61	0	54	\N	\N	1778320890673	2026-05-09 12:01:30.673+02	2026-05-09 12:01:31.265844+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.265844+02
19247	10	E28011704000021D53DAB0CB	\N	-65	0	29	\N	\N	1778320890673	2026-05-09 12:01:30.673+02	2026-05-09 12:01:31.267741+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.267741+02
19248	10	E28011704000021D53DAB0CB	\N	-76	0	14	\N	\N	1778320890823	2026-05-09 12:01:30.823+02	2026-05-09 12:01:31.277899+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.277899+02
19249	10	E28011704000021D53DAB0CB	\N	-71	0	46	\N	\N	1778320890823	2026-05-09 12:01:30.823+02	2026-05-09 12:01:31.279966+02	2026-05-09 12:01:36.441+02	\N	\N	realtime	synced	2026-05-09 12:01:31.279966+02
19250	10	E28011704000021D53DAB0CB	\N	-72	0	57	\N	\N	1778320916924	2026-05-09 12:01:56.924+02	2026-05-09 12:01:58.099707+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.099707+02
19251	10	E28011704000021D53DAB0CB	\N	-77	0	26	\N	\N	1778320916924	2026-05-09 12:01:56.924+02	2026-05-09 12:01:58.101508+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.101508+02
19252	10	E28011704000021D53DAB0CB	\N	-74	0	27	\N	\N	1778320917074	2026-05-09 12:01:57.074+02	2026-05-09 12:01:58.303367+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.303367+02
19253	10	E28011704000021D53DAB0CB	\N	-75	0	33	\N	\N	1778320917228	2026-05-09 12:01:57.228+02	2026-05-09 12:01:58.326519+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.326519+02
19254	10	E28011704000021D53DAB0CB	\N	-70	0	17	\N	\N	1778320917228	2026-05-09 12:01:57.228+02	2026-05-09 12:01:58.329709+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.329709+02
19255	10	E28011704000021D53DAB0CB	\N	-73	0	12	\N	\N	1778320917373	2026-05-09 12:01:57.373+02	2026-05-09 12:01:58.343318+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.343318+02
19256	10	E28011704000021D53DAB0CB	\N	-79	0	17	\N	\N	1778320917525	2026-05-09 12:01:57.525+02	2026-05-09 12:01:58.358667+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.358667+02
19257	10	E28011704000021D53DAB0CB	\N	-75	0	25	\N	\N	1778320917525	2026-05-09 12:01:57.525+02	2026-05-09 12:01:58.360817+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.360817+02
19258	10	E28011704000021D53DAB0CB	\N	-73	0	27	\N	\N	1778320917673	2026-05-09 12:01:57.673+02	2026-05-09 12:01:58.386401+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.386401+02
19259	10	E28011704000021D53DAB0CB	\N	-80	0	7	\N	\N	1778320917673	2026-05-09 12:01:57.673+02	2026-05-09 12:01:58.388129+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.388129+02
19260	10	E28011704000021D53DAB0CB	\N	-80	0	28	\N	\N	1778320917835	2026-05-09 12:01:57.835+02	2026-05-09 12:01:58.396485+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.396485+02
19261	10	E28011704000021D53DAB0CB	\N	-80	0	11	\N	\N	1778320917835	2026-05-09 12:01:57.835+02	2026-05-09 12:01:58.398427+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.398427+02
19262	10	E28011704000021D53DAB0CB	\N	-76	0	16	\N	\N	1778320917973	2026-05-09 12:01:57.973+02	2026-05-09 12:01:58.411024+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.411024+02
19263	10	E28011704000021D53DAB0CB	\N	-70	0	29	\N	\N	1778320917973	2026-05-09 12:01:57.973+02	2026-05-09 12:01:58.413003+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.413003+02
19264	10	E28011704000021D53DAB0CB	\N	-74	0	41	\N	\N	1778320917973	2026-05-09 12:01:57.973+02	2026-05-09 12:01:58.414876+02	\N	2026-05-09 12:02:06.461+02	insufficient_data	realtime	synced	2026-05-09 12:01:58.414876+02
19266	9	E28011704000021D53DAB0CB	\N	-74	0	13	\N	\N	1778320939799	2026-05-09 12:02:19.799+02	2026-05-09 12:02:20.014325+02	\N	2026-05-09 12:02:28.481+02	insufficient_data	realtime	synced	2026-05-09 12:02:20.014325+02
19351	10	E28011704000021D53DAB0CB	\N	-61	0	31	\N	\N	1778321070677	2026-05-09 12:04:30.677+02	2026-05-09 12:04:31.59759+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.59759+02
19355	10	E28011704000021D53DAB0CB	\N	-67	0	35	\N	\N	1778321071124	2026-05-09 12:04:31.124+02	2026-05-09 12:04:31.6341+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.6341+02
19358	9	E28011704000021D53DAB0CB	\N	-76	0	52	\N	\N	1778321073748	2026-05-09 12:04:33.748+02	2026-05-09 12:04:34.697363+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:34.697363+02
19269	10	E28011704000021D53DAB0CB	\N	-71	0	16	\N	\N	1778320962526	2026-05-09 12:02:42.526+02	2026-05-09 12:02:43.666783+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:43.666783+02
19270	10	E28011704000021D53DAB0CB	\N	-77	0	24	\N	\N	1778320965823	2026-05-09 12:02:45.823+02	2026-05-09 12:02:46.744665+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.744665+02
19273	10	E28011704000021D53DAB0CB	\N	-73	0	20	\N	\N	1778320966124	2026-05-09 12:02:46.124+02	2026-05-09 12:02:46.796479+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.796479+02
19276	10	E28011704000021D53DAB0CB	\N	-72	0	38	\N	\N	1778320966285	2026-05-09 12:02:46.285+02	2026-05-09 12:02:46.804528+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.804528+02
19279	10	E28011704000021D53DAB0CB	\N	-70	0	8	\N	\N	1778320966573	2026-05-09 12:02:46.573+02	2026-05-09 12:02:46.858473+02	\N	2026-05-09 12:02:56.496+02	insufficient_data	realtime	synced	2026-05-09 12:02:46.858473+02
19363	9	E28011704000021D53DAB0CB	\N	-73	0	49	\N	\N	1778321096967	2026-05-09 12:04:56.967+02	2026-05-09 12:04:57.70967+02	2026-05-09 12:05:04.605+02	\N	\N	realtime	synced	2026-05-09 12:04:57.70967+02
19281	9	E28011704000021D53DAB0CB	\N	-76	0	50	\N	\N	1778320987167	2026-05-09 12:03:07.167+02	2026-05-09 12:03:08.140924+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:08.140924+02
19289	10	E28011704000021D53DAB0CB	\N	-77	0	44	\N	\N	1778320991036	2026-05-09 12:03:11.036+02	2026-05-09 12:03:11.907537+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.907537+02
19290	10	E28011704000021D53DAB0CB	\N	-70	0	19	\N	\N	1778320991036	2026-05-09 12:03:11.036+02	2026-05-09 12:03:11.909477+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.909477+02
19295	10	E28011704000021D53DAB0CB	\N	-74	0	24	\N	\N	1778320991480	2026-05-09 12:03:11.48+02	2026-05-09 12:03:11.966755+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.966755+02
19296	10	E28011704000021D53DAB0CB	\N	-74	0	49	\N	\N	1778320991480	2026-05-09 12:03:11.48+02	2026-05-09 12:03:11.968852+02	2026-05-09 12:03:16.513+02	\N	\N	realtime	synced	2026-05-09 12:03:11.968852+02
19298	10	E28011704000021D53DAB0CB	\N	-79	0	27	\N	\N	1778321001374	2026-05-09 12:03:21.374+02	2026-05-09 12:03:22.375245+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.375245+02
19301	10	E28011704000021D53DAB0CB	\N	-70	0	28	\N	\N	1778321001673	2026-05-09 12:03:21.673+02	2026-05-09 12:03:22.766377+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.766377+02
19302	10	E28011704000021D53DAB0CB	\N	-70	0	45	\N	\N	1778321001832	2026-05-09 12:03:21.832+02	2026-05-09 12:03:22.799369+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.799369+02
19306	10	E28011704000021D53DAB0CB	\N	-68	0	59	\N	\N	1778321002274	2026-05-09 12:03:22.274+02	2026-05-09 12:03:22.860918+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.860918+02
19307	10	E28011704000021D53DAB0CB	\N	-67	0	24	\N	\N	1778321002274	2026-05-09 12:03:22.274+02	2026-05-09 12:03:22.862944+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.862944+02
19308	10	E28011704000021D53DAB0CB	\N	-67	0	39	\N	\N	1778321002274	2026-05-09 12:03:22.274+02	2026-05-09 12:03:22.86565+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.86565+02
19312	10	E28011704000021D53DAB0CB	\N	-76	0	25	\N	\N	1778321011124	2026-05-09 12:03:31.124+02	2026-05-09 12:03:32.103138+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.103138+02
19313	10	E28011704000021D53DAB0CB	\N	-76	0	7	\N	\N	1778321011124	2026-05-09 12:03:31.124+02	2026-05-09 12:03:32.105155+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.105155+02
19317	10	E28011704000021D53DAB0CB	\N	-72	0	29	\N	\N	1778321011574	2026-05-09 12:03:31.574+02	2026-05-09 12:03:32.139188+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.139188+02
19318	10	E28011704000021D53DAB0CB	\N	-68	0	42	\N	\N	1778321011574	2026-05-09 12:03:31.574+02	2026-05-09 12:03:32.141143+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.141143+02
19300	10	E28011704000021D53DAB0CB	\N	-76	0	43	\N	\N	1778321001524	2026-05-09 12:03:21.524+02	2026-05-09 12:03:22.743755+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.743755+02
19304	10	E28011704000021D53DAB0CB	\N	-73	0	56	\N	\N	1778321001974	2026-05-09 12:03:21.974+02	2026-05-09 12:03:22.815403+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.815403+02
19305	10	E28011704000021D53DAB0CB	\N	-70	0	27	\N	\N	1778321002126	2026-05-09 12:03:22.126+02	2026-05-09 12:03:22.829132+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.829132+02
19311	10	E28011704000021D53DAB0CB	\N	-70	0	8	\N	\N	1778321002573	2026-05-09 12:03:22.573+02	2026-05-09 12:03:22.889873+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.889873+02
19315	10	E28011704000021D53DAB0CB	\N	-73	0	45	\N	\N	1778321011438	2026-05-09 12:03:31.438+02	2026-05-09 12:03:32.125368+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.125368+02
19316	10	E28011704000021D53DAB0CB	\N	-71	0	25	\N	\N	1778321011438	2026-05-09 12:03:31.438+02	2026-05-09 12:03:32.128217+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.128217+02
19320	10	E28011704000021D53DAB0CB	\N	-74	0	34	\N	\N	1778321011873	2026-05-09 12:03:31.873+02	2026-05-09 12:03:32.171824+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.171824+02
19321	10	E28011704000021D53DAB0CB	\N	-66	0	42	\N	\N	1778321012023	2026-05-09 12:03:32.023+02	2026-05-09 12:03:33.332237+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.332237+02
19326	10	E28011704000021D53DAB0CB	\N	-72	0	14	\N	\N	1778321012323	2026-05-09 12:03:32.323+02	2026-05-09 12:03:33.388209+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.388209+02
19327	10	E28011704000021D53DAB0CB	\N	-77	0	19	\N	\N	1778321012487	2026-05-09 12:03:32.487+02	2026-05-09 12:03:33.417134+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.417134+02
19341	10	E28011704000021D53DAB0CB	\N	-74	0	37	\N	\N	1778321040378	2026-05-09 12:04:00.378+02	2026-05-09 12:04:01.149536+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.149536+02
19342	10	E28011704000021D53DAB0CB	\N	-80	0	48	\N	\N	1778321040523	2026-05-09 12:04:00.523+02	2026-05-09 12:04:01.1766+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.1766+02
19344	10	E28011704000021D53DAB0CB	\N	-72	0	13	\N	\N	1778321040676	2026-05-09 12:04:00.676+02	2026-05-09 12:04:01.190701+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.190701+02
19345	10	E28011704000021D53DAB0CB	\N	-69	0	19	\N	\N	1778321040824	2026-05-09 12:04:00.824+02	2026-05-09 12:04:01.203386+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.203386+02
19347	10	E28011704000021D53DAB0CB	\N	-75	0	22	\N	\N	1778321040824	2026-05-09 12:04:00.824+02	2026-05-09 12:04:01.207452+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.207452+02
19348	10	E28011704000021D53DAB0CB	\N	-80	0	12	\N	\N	1778321040973	2026-05-09 12:04:00.973+02	2026-05-09 12:04:02.311297+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:02.311297+02
19319	10	E28011704000021D53DAB0CB	\N	-68	0	55	\N	\N	1778321011873	2026-05-09 12:03:31.873+02	2026-05-09 12:03:32.169684+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.169684+02
19322	10	E28011704000021D53DAB0CB	\N	-70	0	50	\N	\N	1778321012023	2026-05-09 12:03:32.023+02	2026-05-09 12:03:33.33452+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.33452+02
19323	10	E28011704000021D53DAB0CB	\N	-76	0	51	\N	\N	1778321012187	2026-05-09 12:03:32.187+02	2026-05-09 12:03:33.373226+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.373226+02
19324	10	E28011704000021D53DAB0CB	\N	-70	0	11	\N	\N	1778321012187	2026-05-09 12:03:32.187+02	2026-05-09 12:03:33.375376+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.375376+02
19325	10	E28011704000021D53DAB0CB	\N	-73	0	44	\N	\N	1778321012323	2026-05-09 12:03:32.323+02	2026-05-09 12:03:33.386193+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.386193+02
19328	10	E28011704000021D53DAB0CB	\N	-76	0	10	\N	\N	1778321012487	2026-05-09 12:03:32.487+02	2026-05-09 12:03:33.419199+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.419199+02
19329	10	E28011704000021D53DAB0CB	\N	-77	0	44	\N	\N	1778321012487	2026-05-09 12:03:32.487+02	2026-05-09 12:03:33.4213+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:33.4213+02
19299	10	E28011704000021D53DAB0CB	\N	-79	0	36	\N	\N	1778321001524	2026-05-09 12:03:21.524+02	2026-05-09 12:03:22.74031+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.74031+02
19303	10	E28011704000021D53DAB0CB	\N	-70	0	21	\N	\N	1778321001832	2026-05-09 12:03:21.832+02	2026-05-09 12:03:22.801524+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.801524+02
19309	10	E28011704000021D53DAB0CB	\N	-68	0	18	\N	\N	1778321002428	2026-05-09 12:03:22.428+02	2026-05-09 12:03:22.875979+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.875979+02
19310	10	E28011704000021D53DAB0CB	\N	-68	0	28	\N	\N	1778321002573	2026-05-09 12:03:22.573+02	2026-05-09 12:03:22.88743+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:22.88743+02
19314	10	E28011704000021D53DAB0CB	\N	-74	0	25	\N	\N	1778321011274	2026-05-09 12:03:31.274+02	2026-05-09 12:03:32.112555+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:32.112555+02
19330	9	E28011704000021D53DAB0CB	\N	-70	0	28	\N	\N	1778321014795	2026-05-09 12:03:34.795+02	2026-05-09 12:03:35.379858+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:35.379858+02
19331	9	E28011704000021D53DAB0CB	\N	-74	0	29	\N	\N	1778321014917	2026-05-09 12:03:34.917+02	2026-05-09 12:03:35.584806+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:35.584806+02
19332	9	E28011704000021D53DAB0CB	\N	-73	0	14	\N	\N	1778321015075	2026-05-09 12:03:35.075+02	2026-05-09 12:03:35.994658+02	2026-05-09 12:03:40.538+02	\N	\N	realtime	synced	2026-05-09 12:03:35.994658+02
19336	9	E28011704000021D53DAB0CB	\N	-71	0	26	\N	\N	1778321038017	2026-05-09 12:03:58.017+02	2026-05-09 12:03:58.277228+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:03:58.277228+02
19343	10	E28011704000021D53DAB0CB	\N	-73	0	44	\N	\N	1778321040523	2026-05-09 12:04:00.523+02	2026-05-09 12:04:01.178332+02	2026-05-09 12:04:06.574+02	\N	\N	realtime	synced	2026-05-09 12:04:01.178332+02
19362	9	E28011704000021D53DAB0CB	\N	-70	0	25	\N	\N	1778321074017	2026-05-09 12:04:34.017+02	2026-05-09 12:04:34.770909+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:34.770909+02
19352	10	E28011704000021D53DAB0CB	\N	-53	0	31	\N	\N	1778321070974	2026-05-09 12:04:30.974+02	2026-05-09 12:04:31.609605+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.609605+02
19357	9	E28011704000021D53DAB0CB	\N	-77	0	23	\N	\N	1778321073574	2026-05-09 12:04:33.574+02	2026-05-09 12:04:33.645532+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:33.645532+02
19359	9	E28011704000021D53DAB0CB	\N	-64	0	26	\N	\N	1778321073748	2026-05-09 12:04:33.748+02	2026-05-09 12:04:34.699535+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:34.699535+02
19353	10	E28011704000021D53DAB0CB	\N	-58	0	31	\N	\N	1778321070974	2026-05-09 12:04:30.974+02	2026-05-09 12:04:31.611671+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:31.611671+02
19360	9	E28011704000021D53DAB0CB	\N	-65	0	57	\N	\N	1778321073867	2026-05-09 12:04:33.867+02	2026-05-09 12:04:34.716744+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:34.716744+02
19361	9	E28011704000021D53DAB0CB	\N	-59	0	38	\N	\N	1778321073867	2026-05-09 12:04:33.867+02	2026-05-09 12:04:34.718667+02	2026-05-09 12:04:38.596+02	\N	\N	realtime	synced	2026-05-09 12:04:34.718667+02
19453	9	E28011704000021D53DAB0CB	\N	-72	0	14	\N	\N	1778321248317	2026-05-09 12:07:28.317+02	2026-05-09 12:07:28.648868+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:28.648868+02
19365	10	E28011704000021D53DAB0CB	\N	-76	0	26	\N	\N	1778321099787	2026-05-09 12:04:59.787+02	2026-05-09 12:05:00.98866+02	2026-05-09 12:05:04.605+02	\N	\N	realtime	synced	2026-05-09 12:05:00.98866+02
19368	10	E28011704000021D53DAB0CB	\N	-74	0	53	\N	\N	1778321100080	2026-05-09 12:05:00.08+02	2026-05-09 12:05:01.418366+02	2026-05-09 12:05:04.605+02	\N	\N	realtime	synced	2026-05-09 12:05:01.418366+02
19457	9	E28011704000021D53DAB0CB	\N	-80	0	39	\N	\N	1778321248767	2026-05-09 12:07:28.767+02	2026-05-09 12:07:28.828484+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:28.828484+02
19454	9	E28011704000021D53DAB0CB	\N	-74	0	20	\N	\N	1778321248480	2026-05-09 12:07:28.48+02	2026-05-09 12:07:28.731992+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:28.731992+02
19455	9	E28011704000021D53DAB0CB	\N	-76	0	58	\N	\N	1778321248636	2026-05-09 12:07:28.636+02	2026-05-09 12:07:28.76644+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:28.76644+02
19464	9	E28011704000021D53DAB0CB	\N	-68	0	26	\N	\N	1778321249818	2026-05-09 12:07:29.818+02	2026-05-09 12:07:30.151935+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:30.151935+02
19456	9	E28011704000021D53DAB0CB	\N	-76	0	40	\N	\N	1778321248767	2026-05-09 12:07:28.767+02	2026-05-09 12:07:28.825706+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:28.825706+02
19460	9	E28011704000021D53DAB0CB	\N	-73	0	10	\N	\N	1778321249379	2026-05-09 12:07:29.379+02	2026-05-09 12:07:29.999659+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:29.999659+02
19467	10	E28011704000021D53DAB0CB	\N	-71	0	46	\N	\N	1778321251873	2026-05-09 12:07:31.873+02	2026-05-09 12:07:32.762908+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:32.762908+02
19472	10	E28011704000021D53DAB0CB	\N	-75	0	29	\N	\N	1778321252327	2026-05-09 12:07:32.327+02	2026-05-09 12:07:33.032757+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:33.032757+02
19378	10	E28011704000021D53DAB0CB	\N	-70	0	40	\N	\N	1778321126786	2026-05-09 12:05:26.786+02	2026-05-09 12:05:27.275423+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.275423+02
19374	10	E28011704000021D53DAB0CB	\N	-72	0	14	\N	\N	1778321126475	2026-05-09 12:05:26.475+02	2026-05-09 12:05:27.231887+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.231887+02
19375	10	E28011704000021D53DAB0CB	\N	-68	0	49	\N	\N	1778321126475	2026-05-09 12:05:26.475+02	2026-05-09 12:05:27.235039+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.235039+02
19369	10	E28011704000021D53DAB0CB	\N	-77	0	54	\N	\N	1778321125432	2026-05-09 12:05:25.432+02	2026-05-09 12:05:26.075221+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:26.075221+02
19370	10	E28011704000021D53DAB0CB	\N	-73	0	35	\N	\N	1778321126028	2026-05-09 12:05:26.028+02	2026-05-09 12:05:27.20155+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.20155+02
19371	10	E28011704000021D53DAB0CB	\N	-72	0	8	\N	\N	1778321126328	2026-05-09 12:05:26.328+02	2026-05-09 12:05:27.215703+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.215703+02
19373	10	E28011704000021D53DAB0CB	\N	-71	0	36	\N	\N	1778321126475	2026-05-09 12:05:26.475+02	2026-05-09 12:05:27.229573+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.229573+02
19376	10	E28011704000021D53DAB0CB	\N	-71	0	58	\N	\N	1778321126623	2026-05-09 12:05:26.623+02	2026-05-09 12:05:27.244629+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.244629+02
19377	10	E28011704000021D53DAB0CB	\N	-60	0	28	\N	\N	1778321126786	2026-05-09 12:05:26.786+02	2026-05-09 12:05:27.273697+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.273697+02
19380	10	E28011704000021D53DAB0CB	\N	-73	0	9	\N	\N	1778321126923	2026-05-09 12:05:26.923+02	2026-05-09 12:05:27.284671+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:27.284671+02
19381	9	E28011704000021D53DAB0CB	\N	-74	0	11	\N	\N	1778321129235	2026-05-09 12:05:29.235+02	2026-05-09 12:05:30.126919+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:30.126919+02
19382	9	E28011704000021D53DAB0CB	\N	-74	0	13	\N	\N	1778321129392	2026-05-09 12:05:29.392+02	2026-05-09 12:05:30.145219+02	2026-05-09 12:05:34.624+02	\N	\N	realtime	synced	2026-05-09 12:05:30.145219+02
19478	10	E28011704000021D53DAB0CB	\N	-74	0	10	\N	\N	1778321275426	2026-05-09 12:07:55.426+02	2026-05-09 12:07:56.05996+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.05996+02
19479	10	E28011704000021D53DAB0CB	\N	-76	0	24	\N	\N	1778321275426	2026-05-09 12:07:55.426+02	2026-05-09 12:07:56.062191+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.062191+02
19386	9	E28011704000021D53DAB0CB	\N	-74	0	12	\N	\N	1778321148417	2026-05-09 12:05:48.417+02	2026-05-09 12:05:48.907175+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:48.907175+02
19401	10	E28011704000021D53DAB0CB	\N	-66	0	55	\N	\N	1778321151673	2026-05-09 12:05:51.673+02	2026-05-09 12:05:52.339067+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.339067+02
19385	9	E28011704000021D53DAB0CB	\N	-70	0	43	\N	\N	1778321148417	2026-05-09 12:05:48.417+02	2026-05-09 12:05:48.905395+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:48.905395+02
19383	9	E28011704000021D53DAB0CB	\N	-77	0	56	\N	\N	1778321148128	2026-05-09 12:05:48.128+02	2026-05-09 12:05:48.809999+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:48.809999+02
19402	10	E28011704000021D53DAB0CB	\N	-73	0	19	\N	\N	1778321172524	2026-05-09 12:06:12.524+02	2026-05-09 12:06:12.974955+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:12.974955+02
19403	10	E28011704000021D53DAB0CB	\N	-68	0	26	\N	\N	1778321172686	2026-05-09 12:06:12.686+02	2026-05-09 12:06:13.123738+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:13.123738+02
19384	9	E28011704000021D53DAB0CB	\N	-77	0	40	\N	\N	1778321148289	2026-05-09 12:05:48.289+02	2026-05-09 12:05:48.886754+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:48.886754+02
19387	10	E28011704000021D53DAB0CB	\N	-79	0	46	\N	\N	1778321150623	2026-05-09 12:05:50.623+02	2026-05-09 12:05:51.982226+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:51.982226+02
19388	10	E28011704000021D53DAB0CB	\N	-75	0	30	\N	\N	1778321150623	2026-05-09 12:05:50.623+02	2026-05-09 12:05:51.984403+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:51.984403+02
19389	10	E28011704000021D53DAB0CB	\N	-73	0	50	\N	\N	1778321150933	2026-05-09 12:05:50.933+02	2026-05-09 12:05:52.251619+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.251619+02
19390	10	E28011704000021D53DAB0CB	\N	-73	0	35	\N	\N	1778321150933	2026-05-09 12:05:50.933+02	2026-05-09 12:05:52.254628+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.254628+02
19391	10	E28011704000021D53DAB0CB	\N	-73	0	22	\N	\N	1778321151074	2026-05-09 12:05:51.074+02	2026-05-09 12:05:52.265538+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.265538+02
19392	10	E28011704000021D53DAB0CB	\N	-77	0	55	\N	\N	1778321151074	2026-05-09 12:05:51.074+02	2026-05-09 12:05:52.269892+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.269892+02
19393	10	E28011704000021D53DAB0CB	\N	-77	0	53	\N	\N	1778321151074	2026-05-09 12:05:51.074+02	2026-05-09 12:05:52.271857+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.271857+02
19394	10	E28011704000021D53DAB0CB	\N	-76	0	55	\N	\N	1778321151231	2026-05-09 12:05:51.231+02	2026-05-09 12:05:52.277776+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.277776+02
19395	10	E28011704000021D53DAB0CB	\N	-74	0	51	\N	\N	1778321151374	2026-05-09 12:05:51.374+02	2026-05-09 12:05:52.304688+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.304688+02
19396	10	E28011704000021D53DAB0CB	\N	-76	0	58	\N	\N	1778321151374	2026-05-09 12:05:51.374+02	2026-05-09 12:05:52.306516+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.306516+02
19397	10	E28011704000021D53DAB0CB	\N	-70	0	56	\N	\N	1778321151529	2026-05-09 12:05:51.529+02	2026-05-09 12:05:52.322997+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.322997+02
19398	10	E28011704000021D53DAB0CB	\N	-64	0	33	\N	\N	1778321151529	2026-05-09 12:05:51.529+02	2026-05-09 12:05:52.325535+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.325535+02
19399	10	E28011704000021D53DAB0CB	\N	-80	0	46	\N	\N	1778321151673	2026-05-09 12:05:51.673+02	2026-05-09 12:05:52.335507+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.335507+02
19400	10	E28011704000021D53DAB0CB	\N	-68	0	53	\N	\N	1778321151673	2026-05-09 12:05:51.673+02	2026-05-09 12:05:52.337221+02	2026-05-09 12:05:56.637+02	\N	\N	realtime	synced	2026-05-09 12:05:52.337221+02
19458	9	E28011704000021D53DAB0CB	\N	-74	0	37	\N	\N	1778321249217	2026-05-09 12:07:29.217+02	2026-05-09 12:07:29.979782+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:29.979782+02
19468	10	E28011704000021D53DAB0CB	\N	-74	0	25	\N	\N	1778321252023	2026-05-09 12:07:32.023+02	2026-05-09 12:07:32.881633+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:32.881633+02
19470	10	E28011704000021D53DAB0CB	\N	-72	0	52	\N	\N	1778321252173	2026-05-09 12:07:32.173+02	2026-05-09 12:07:33.013943+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:33.013943+02
19480	10	E28011704000021D53DAB0CB	\N	-71	0	14	\N	\N	1778321275574	2026-05-09 12:07:55.574+02	2026-05-09 12:07:56.071204+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.071204+02
19482	10	E28011704000021D53DAB0CB	\N	-71	0	28	\N	\N	1778321275729	2026-05-09 12:07:55.729+02	2026-05-09 12:07:56.103951+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.103951+02
19485	9	E28011704000021D53DAB0CB	\N	-64	0	7	\N	\N	1778321278317	2026-05-09 12:07:58.317+02	2026-05-09 12:07:59.121471+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:59.121471+02
19490	9	E28011704000021D53DAB0CB	\N	-67	0	25	\N	\N	1778321298731	2026-05-09 12:08:18.731+02	2026-05-09 12:08:19.579824+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.579824+02
19496	10	E28011704000021D53DAB0CB	\N	-65	0	34	\N	\N	1778321301086	2026-05-09 12:08:21.086+02	2026-05-09 12:08:21.810043+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.810043+02
19404	10	E28011704000021D53DAB0CB	\N	-79	0	42	\N	\N	1778321180633	2026-05-09 12:06:20.633+02	2026-05-09 12:06:21.217039+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:21.217039+02
19405	10	E28011704000021D53DAB0CB	\N	-76	0	32	\N	\N	1778321180777	2026-05-09 12:06:20.777+02	2026-05-09 12:06:21.244687+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:21.244687+02
19406	10	E28011704000021D53DAB0CB	\N	-73	0	20	\N	\N	1778321180777	2026-05-09 12:06:20.777+02	2026-05-09 12:06:21.246862+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:21.246862+02
19407	10	E28011704000021D53DAB0CB	\N	-69	0	54	\N	\N	1778321180929	2026-05-09 12:06:20.929+02	2026-05-09 12:06:21.255791+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:21.255791+02
19408	10	E28011704000021D53DAB0CB	\N	-73	0	20	\N	\N	1778321180929	2026-05-09 12:06:20.929+02	2026-05-09 12:06:21.259438+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:21.259438+02
19409	10	E28011704000021D53DAB0CB	\N	-70	0	44	\N	\N	1778321181073	2026-05-09 12:06:21.073+02	2026-05-09 12:06:22.395359+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:22.395359+02
19410	10	E28011704000021D53DAB0CB	\N	-70	0	45	\N	\N	1778321181223	2026-05-09 12:06:21.223+02	2026-05-09 12:06:22.70795+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:22.70795+02
19411	10	E28011704000021D53DAB0CB	\N	-70	0	45	\N	\N	1778321181223	2026-05-09 12:06:21.223+02	2026-05-09 12:06:22.710567+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:22.710567+02
19412	10	E28011704000021D53DAB0CB	\N	-62	0	44	\N	\N	1778321181374	2026-05-09 12:06:21.374+02	2026-05-09 12:06:23.009807+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:23.009807+02
19413	10	E28011704000021D53DAB0CB	\N	-62	0	27	\N	\N	1778321181374	2026-05-09 12:06:21.374+02	2026-05-09 12:06:23.011641+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:23.011641+02
19414	10	E28011704000021D53DAB0CB	\N	-63	0	48	\N	\N	1778321181374	2026-05-09 12:06:21.374+02	2026-05-09 12:06:23.013392+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:23.013392+02
19415	10	E28011704000021D53DAB0CB	\N	-73	0	14	\N	\N	1778321181524	2026-05-09 12:06:21.524+02	2026-05-09 12:06:23.316719+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:23.316719+02
19416	10	E28011704000021D53DAB0CB	\N	-74	0	47	\N	\N	1778321181524	2026-05-09 12:06:21.524+02	2026-05-09 12:06:23.318449+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:23.318449+02
19417	9	E28011704000021D53DAB0CB	\N	-73	0	21	\N	\N	1778321183668	2026-05-09 12:06:23.668+02	2026-05-09 12:06:23.872041+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:23.872041+02
19418	9	E28011704000021D53DAB0CB	\N	-70	0	13	\N	\N	1778321183967	2026-05-09 12:06:23.967+02	2026-05-09 12:06:25.059508+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:25.059508+02
19419	9	E28011704000021D53DAB0CB	\N	-68	0	55	\N	\N	1778321184119	2026-05-09 12:06:24.119+02	2026-05-09 12:06:25.112134+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:25.112134+02
19420	9	E28011704000021D53DAB0CB	\N	-67	0	26	\N	\N	1778321184119	2026-05-09 12:06:24.119+02	2026-05-09 12:06:25.113992+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:25.113992+02
19421	9	E28011704000021D53DAB0CB	\N	-74	0	59	\N	\N	1778321184286	2026-05-09 12:06:24.286+02	2026-05-09 12:06:25.167092+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:25.167092+02
19422	9	E28011704000021D53DAB0CB	\N	-74	0	24	\N	\N	1778321184286	2026-05-09 12:06:24.286+02	2026-05-09 12:06:25.168824+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:25.168824+02
19423	9	E28011704000021D53DAB0CB	\N	-75	0	23	\N	\N	1778321184417	2026-05-09 12:06:24.417+02	2026-05-09 12:06:25.194621+02	2026-05-09 12:06:28.664+02	\N	\N	realtime	synced	2026-05-09 12:06:25.194621+02
19520	9	E28011704000021D53DAB0CB	\N	-73	0	43	\N	\N	1778321338917	2026-05-09 12:08:58.917+02	2026-05-09 12:08:59.184299+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.184299+02
19553	10	E28011704000021D53DAB0CB	\N	-77	0	59	\N	\N	1778321394523	2026-05-09 12:09:54.523+02	2026-05-09 12:09:56.311798+02	2026-05-09 12:09:58.769+02	\N	\N	realtime	synced	2026-05-09 12:09:56.311798+02
19424	9	E28011704000021D53DAB0CB	\N	-77	0	51	\N	\N	1778321202417	2026-05-09 12:06:42.417+02	2026-05-09 12:06:42.772627+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:42.772627+02
19425	9	E28011704000021D53DAB0CB	\N	-80	0	26	\N	\N	1778321202417	2026-05-09 12:06:42.417+02	2026-05-09 12:06:42.774301+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:42.774301+02
19426	9	E28011704000021D53DAB0CB	\N	-76	0	10	\N	\N	1778321202570	2026-05-09 12:06:42.57+02	2026-05-09 12:06:42.787388+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:42.787388+02
19427	9	E28011704000021D53DAB0CB	\N	-73	0	14	\N	\N	1778321202747	2026-05-09 12:06:42.747+02	2026-05-09 12:06:42.840751+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:42.840751+02
19428	9	E28011704000021D53DAB0CB	\N	-74	0	59	\N	\N	1778321202747	2026-05-09 12:06:42.747+02	2026-05-09 12:06:42.8426+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:42.8426+02
19429	10	E28011704000021D53DAB0CB	\N	-80	0	19	\N	\N	1778321204924	2026-05-09 12:06:44.924+02	2026-05-09 12:06:45.435521+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:45.435521+02
19430	10	E28011704000021D53DAB0CB	\N	-76	0	25	\N	\N	1778321204924	2026-05-09 12:06:44.924+02	2026-05-09 12:06:45.437577+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:45.437577+02
19431	10	E28011704000021D53DAB0CB	\N	-70	0	34	\N	\N	1778321205083	2026-05-09 12:06:45.083+02	2026-05-09 12:06:46.049956+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:46.049956+02
19432	10	E28011704000021D53DAB0CB	\N	-71	0	32	\N	\N	1778321205223	2026-05-09 12:06:45.223+02	2026-05-09 12:06:46.056316+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:46.056316+02
19433	10	E28011704000021D53DAB0CB	\N	-73	0	47	\N	\N	1778321205223	2026-05-09 12:06:45.223+02	2026-05-09 12:06:46.058894+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:46.058894+02
19434	10	E28011704000021D53DAB0CB	\N	-76	0	32	\N	\N	1778321205382	2026-05-09 12:06:45.382+02	2026-05-09 12:06:46.068264+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:46.068264+02
19435	10	E28011704000021D53DAB0CB	\N	-77	0	59	\N	\N	1778321205382	2026-05-09 12:06:45.382+02	2026-05-09 12:06:46.069983+02	2026-05-09 12:06:50.67+02	\N	\N	realtime	synced	2026-05-09 12:06:46.069983+02
19459	9	E28011704000021D53DAB0CB	\N	-74	0	8	\N	\N	1778321249379	2026-05-09 12:07:29.379+02	2026-05-09 12:07:29.994648+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:29.994648+02
19466	10	E28011704000021D53DAB0CB	\N	-71	0	42	\N	\N	1778321251735	2026-05-09 12:07:31.735+02	2026-05-09 12:07:32.74233+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:32.74233+02
19492	9	E28011704000021D53DAB0CB	\N	-71	0	48	\N	\N	1778321298868	2026-05-09 12:08:18.868+02	2026-05-09 12:08:19.633758+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.633758+02
19493	10	E28011704000021D53DAB0CB	\N	-76	0	31	\N	\N	1778321300624	2026-05-09 12:08:20.624+02	2026-05-09 12:08:21.795866+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.795866+02
19494	10	E28011704000021D53DAB0CB	\N	-64	0	41	\N	\N	1778321301086	2026-05-09 12:08:21.086+02	2026-05-09 12:08:21.804603+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.804603+02
19499	10	E28011704000021D53DAB0CB	\N	-73	0	43	\N	\N	1778321301373	2026-05-09 12:08:21.373+02	2026-05-09 12:08:21.869812+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.869812+02
19506	10	E28011704000021D53DAB0CB	\N	-76	0	58	\N	\N	1778321322373	2026-05-09 12:08:42.373+02	2026-05-09 12:08:43.435964+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.435964+02
19512	10	E28011704000021D53DAB0CB	\N	-64	0	33	\N	\N	1778321322823	2026-05-09 12:08:42.823+02	2026-05-09 12:08:43.492654+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.492654+02
19516	9	E28011704000021D53DAB0CB	\N	-77	0	32	\N	\N	1778321325417	2026-05-09 12:08:45.417+02	2026-05-09 12:08:45.962104+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:45.962104+02
19505	10	E28011704000021D53DAB0CB	\N	-73	0	9	\N	\N	1778321322223	2026-05-09 12:08:42.223+02	2026-05-09 12:08:43.403118+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.403118+02
19508	10	E28011704000021D53DAB0CB	\N	-68	0	53	\N	\N	1778321322523	2026-05-09 12:08:42.523+02	2026-05-09 12:08:43.448204+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.448204+02
19511	10	E28011704000021D53DAB0CB	\N	-67	0	17	\N	\N	1778321322673	2026-05-09 12:08:42.673+02	2026-05-09 12:08:43.463017+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.463017+02
19514	10	E28011704000021D53DAB0CB	\N	-72	0	38	\N	\N	1778321322973	2026-05-09 12:08:42.973+02	2026-05-09 12:08:43.512073+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.512073+02
19515	9	E28011704000021D53DAB0CB	\N	-80	0	49	\N	\N	1778321325286	2026-05-09 12:08:45.286+02	2026-05-09 12:08:45.551462+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:45.551462+02
19521	9	E28011704000021D53DAB0CB	\N	-70	0	14	\N	\N	1778321339067	2026-05-09 12:08:59.067+02	2026-05-09 12:08:59.250769+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.250769+02
19524	9	E28011704000021D53DAB0CB	\N	-75	0	52	\N	\N	1778321339237	2026-05-09 12:08:59.237+02	2026-05-09 12:08:59.27068+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.27068+02
19526	10	E28011704000021D53DAB0CB	\N	-68	0	39	\N	\N	1778321340829	2026-05-09 12:09:00.829+02	2026-05-09 12:09:02.140954+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:02.140954+02
19529	10	E28011704000021D53DAB0CB	\N	-67	0	42	\N	\N	1778321340974	2026-05-09 12:09:00.974+02	2026-05-09 12:09:02.757022+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:02.757022+02
19532	10	E28011704000021D53DAB0CB	\N	-76	0	42	\N	\N	1778321341273	2026-05-09 12:09:01.273+02	2026-05-09 12:09:03.372198+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:03.372198+02
19539	10	E28011704000021D53DAB0CB	\N	-74	0	22	\N	\N	1778321362273	2026-05-09 12:09:22.273+02	2026-05-09 12:09:23.352798+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.352798+02
19545	10	E28011704000021D53DAB0CB	\N	-69	0	38	\N	\N	1778321362723	2026-05-09 12:09:22.723+02	2026-05-09 12:09:23.411922+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.411922+02
19550	10	E28011704000021D53DAB0CB	\N	-73	0	50	\N	\N	1778321394373	2026-05-09 12:09:54.373+02	2026-05-09 12:09:55.286781+02	2026-05-09 12:09:58.769+02	\N	\N	realtime	synced	2026-05-09 12:09:55.286781+02
19556	10	E28011704000021D53DAB0CB	\N	-73	0	41	\N	\N	1778321410126	2026-05-09 12:10:10.126+02	2026-05-09 12:10:11.26181+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.26181+02
19562	10	E28011704000021D53DAB0CB	\N	-64	0	50	\N	\N	1778321410574	2026-05-09 12:10:10.574+02	2026-05-09 12:10:11.620716+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.620716+02
19448	10	E28011704000021D53DAB0CB	\N	-67	0	9	\N	\N	1778321229824	2026-05-09 12:07:09.824+02	2026-05-09 12:07:10.972456+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:10.972456+02
19452	9	E28011704000021D53DAB0CB	\N	-74	0	34	\N	\N	1778321232117	2026-05-09 12:07:12.117+02	2026-05-09 12:07:13.051065+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:13.051065+02
19461	9	E28011704000021D53DAB0CB	\N	-74	0	17	\N	\N	1778321249547	2026-05-09 12:07:29.547+02	2026-05-09 12:07:30.04963+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:30.04963+02
19473	10	E28011704000021D53DAB0CB	\N	-70	0	50	\N	\N	1778321252474	2026-05-09 12:07:32.474+02	2026-05-09 12:07:33.061461+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:33.061461+02
19474	10	E28011704000021D53DAB0CB	\N	-80	0	43	\N	\N	1778321274973	2026-05-09 12:07:54.973+02	2026-05-09 12:07:55.989867+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:55.989867+02
19486	9	E28011704000021D53DAB0CB	\N	-59	0	13	\N	\N	1778321298268	2026-05-09 12:08:18.268+02	2026-05-09 12:08:19.23521+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.23521+02
19491	9	E28011704000021D53DAB0CB	\N	-68	0	46	\N	\N	1778321298868	2026-05-09 12:08:18.868+02	2026-05-09 12:08:19.631875+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.631875+02
19503	10	E28011704000021D53DAB0CB	\N	-72	0	38	\N	\N	1778321301683	2026-05-09 12:08:21.683+02	2026-05-09 12:08:22.913802+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:22.913802+02
19487	9	E28011704000021D53DAB0CB	\N	-68	0	28	\N	\N	1778321298417	2026-05-09 12:08:18.417+02	2026-05-09 12:08:19.542286+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.542286+02
19495	10	E28011704000021D53DAB0CB	\N	-68	0	8	\N	\N	1778321301086	2026-05-09 12:08:21.086+02	2026-05-09 12:08:21.806953+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.806953+02
19500	10	E28011704000021D53DAB0CB	\N	-73	0	21	\N	\N	1778321301373	2026-05-09 12:08:21.373+02	2026-05-09 12:08:21.872009+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.872009+02
19501	10	E28011704000021D53DAB0CB	\N	-76	0	31	\N	\N	1778321301524	2026-05-09 12:08:21.524+02	2026-05-09 12:08:21.883341+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.883341+02
19504	10	E28011704000021D53DAB0CB	\N	-74	0	59	\N	\N	1778321322223	2026-05-09 12:08:42.223+02	2026-05-09 12:08:43.401124+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.401124+02
19510	10	E28011704000021D53DAB0CB	\N	-67	0	40	\N	\N	1778321322673	2026-05-09 12:08:42.673+02	2026-05-09 12:08:43.460651+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.460651+02
19525	10	E28011704000021D53DAB0CB	\N	-79	0	57	\N	\N	1778321340673	2026-05-09 12:09:00.673+02	2026-05-09 12:09:01.014295+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:01.014295+02
19517	9	E28011704000021D53DAB0CB	\N	-74	0	49	\N	\N	1778321338483	2026-05-09 12:08:58.483+02	2026-05-09 12:08:58.762312+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:58.762312+02
19522	9	E28011704000021D53DAB0CB	\N	-77	0	53	\N	\N	1778321339067	2026-05-09 12:08:59.067+02	2026-05-09 12:08:59.252896+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.252896+02
19531	10	E28011704000021D53DAB0CB	\N	-70	0	12	\N	\N	1778321341273	2026-05-09 12:09:01.273+02	2026-05-09 12:09:03.36935+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:03.36935+02
19533	10	E28011704000021D53DAB0CB	\N	-74	0	35	\N	\N	1778321341273	2026-05-09 12:09:01.273+02	2026-05-09 12:09:03.373984+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:03.373984+02
19537	10	E28011704000021D53DAB0CB	\N	-72	0	53	\N	\N	1778321362123	2026-05-09 12:09:22.123+02	2026-05-09 12:09:23.341881+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.341881+02
19543	10	E28011704000021D53DAB0CB	\N	-69	0	46	\N	\N	1778321362582	2026-05-09 12:09:22.582+02	2026-05-09 12:09:23.40479+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.40479+02
19541	10	E28011704000021D53DAB0CB	\N	-64	0	42	\N	\N	1778321362424	2026-05-09 12:09:22.424+02	2026-05-09 12:09:23.38854+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.38854+02
19552	10	E28011704000021D53DAB0CB	\N	-77	0	59	\N	\N	1778321394523	2026-05-09 12:09:54.523+02	2026-05-09 12:09:55.900812+02	2026-05-09 12:09:58.769+02	\N	\N	realtime	synced	2026-05-09 12:09:55.900812+02
19558	10	E28011704000021D53DAB0CB	\N	-74	0	58	\N	\N	1778321410273	2026-05-09 12:10:10.273+02	2026-05-09 12:10:11.568138+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.568138+02
19564	10	E28011704000021D53DAB0CB	\N	-74	0	52	\N	\N	1778321410737	2026-05-09 12:10:10.737+02	2026-05-09 12:10:11.651959+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.651959+02
19436	10	E28011704000021D53DAB0CB	\N	-77	0	11	\N	\N	1778321228936	2026-05-09 12:07:08.936+02	2026-05-09 12:07:09.677841+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.677841+02
19437	10	E28011704000021D53DAB0CB	\N	-76	0	42	\N	\N	1778321228936	2026-05-09 12:07:08.936+02	2026-05-09 12:07:09.67971+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.67971+02
19438	10	E28011704000021D53DAB0CB	\N	-74	0	37	\N	\N	1778321229073	2026-05-09 12:07:09.073+02	2026-05-09 12:07:09.737683+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.737683+02
19439	10	E28011704000021D53DAB0CB	\N	-69	0	29	\N	\N	1778321229237	2026-05-09 12:07:09.237+02	2026-05-09 12:07:09.819751+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.819751+02
19440	10	E28011704000021D53DAB0CB	\N	-71	0	20	\N	\N	1778321229237	2026-05-09 12:07:09.237+02	2026-05-09 12:07:09.821511+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.821511+02
19441	10	E28011704000021D53DAB0CB	\N	-67	0	31	\N	\N	1778321229374	2026-05-09 12:07:09.374+02	2026-05-09 12:07:09.878761+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.878761+02
19442	10	E28011704000021D53DAB0CB	\N	-67	0	30	\N	\N	1778321229374	2026-05-09 12:07:09.374+02	2026-05-09 12:07:09.882189+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.882189+02
19443	10	E28011704000021D53DAB0CB	\N	-67	0	30	\N	\N	1778321229523	2026-05-09 12:07:09.523+02	2026-05-09 12:07:09.926186+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.926186+02
19444	10	E28011704000021D53DAB0CB	\N	-67	0	41	\N	\N	1778321229523	2026-05-09 12:07:09.523+02	2026-05-09 12:07:09.93187+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.93187+02
19445	10	E28011704000021D53DAB0CB	\N	-65	0	11	\N	\N	1778321229673	2026-05-09 12:07:09.673+02	2026-05-09 12:07:09.948714+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.948714+02
19446	10	E28011704000021D53DAB0CB	\N	-65	0	51	\N	\N	1778321229673	2026-05-09 12:07:09.673+02	2026-05-09 12:07:09.95052+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:09.95052+02
19447	10	E28011704000021D53DAB0CB	\N	-65	0	25	\N	\N	1778321229824	2026-05-09 12:07:09.824+02	2026-05-09 12:07:10.970637+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:10.970637+02
19449	10	E28011704000021D53DAB0CB	\N	-73	0	17	\N	\N	1778321229979	2026-05-09 12:07:09.979+02	2026-05-09 12:07:11.006922+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:11.006922+02
19462	9	E28011704000021D53DAB0CB	\N	-73	0	12	\N	\N	1778321249668	2026-05-09 12:07:29.668+02	2026-05-09 12:07:30.127554+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:30.127554+02
19469	10	E28011704000021D53DAB0CB	\N	-76	0	42	\N	\N	1778321252023	2026-05-09 12:07:32.023+02	2026-05-09 12:07:32.883509+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:32.883509+02
19475	10	E28011704000021D53DAB0CB	\N	-73	0	7	\N	\N	1778321275123	2026-05-09 12:07:55.123+02	2026-05-09 12:07:56.007068+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.007068+02
19481	10	E28011704000021D53DAB0CB	\N	-74	0	15	\N	\N	1778321275574	2026-05-09 12:07:55.574+02	2026-05-09 12:07:56.073512+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.073512+02
19484	9	E28011704000021D53DAB0CB	\N	-71	0	50	\N	\N	1778321278201	2026-05-09 12:07:58.201+02	2026-05-09 12:07:59.061847+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:59.061847+02
19488	9	E28011704000021D53DAB0CB	\N	-61	0	56	\N	\N	1778321298575	2026-05-09 12:08:18.575+02	2026-05-09 12:08:19.563157+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.563157+02
19507	10	E28011704000021D53DAB0CB	\N	-71	0	14	\N	\N	1778321322373	2026-05-09 12:08:42.373+02	2026-05-09 12:08:43.441413+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.441413+02
19513	10	E28011704000021D53DAB0CB	\N	-68	0	47	\N	\N	1778321322823	2026-05-09 12:08:42.823+02	2026-05-09 12:08:43.4952+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.4952+02
19518	9	E28011704000021D53DAB0CB	\N	-69	0	40	\N	\N	1778321338645	2026-05-09 12:08:58.645+02	2026-05-09 12:08:59.068629+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.068629+02
19523	9	E28011704000021D53DAB0CB	\N	-70	0	52	\N	\N	1778321339237	2026-05-09 12:08:59.237+02	2026-05-09 12:08:59.268689+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.268689+02
19528	10	E28011704000021D53DAB0CB	\N	-68	0	20	\N	\N	1778321340974	2026-05-09 12:09:00.974+02	2026-05-09 12:09:02.754869+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:02.754869+02
19534	10	E28011704000021D53DAB0CB	\N	-76	0	34	\N	\N	1778321361823	2026-05-09 12:09:21.823+02	2026-05-09 12:09:22.211251+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:22.211251+02
19538	10	E28011704000021D53DAB0CB	\N	-70	0	47	\N	\N	1778321362273	2026-05-09 12:09:22.273+02	2026-05-09 12:09:23.351115+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.351115+02
19544	10	E28011704000021D53DAB0CB	\N	-73	0	45	\N	\N	1778321362723	2026-05-09 12:09:22.723+02	2026-05-09 12:09:23.410302+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.410302+02
19547	9	E28011704000021D53DAB0CB	\N	-75	0	41	\N	\N	1778321365043	2026-05-09 12:09:25.043+02	2026-05-09 12:09:26.102403+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:26.102403+02
19554	10	E28011704000021D53DAB0CB	\N	-74	0	58	\N	\N	1778321409974	2026-05-09 12:10:09.974+02	2026-05-09 12:10:10.955492+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:10.955492+02
19560	10	E28011704000021D53DAB0CB	\N	-62	0	46	\N	\N	1778321410427	2026-05-09 12:10:10.427+02	2026-05-09 12:10:11.60967+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.60967+02
19561	10	E28011704000021D53DAB0CB	\N	-63	0	38	\N	\N	1778321410574	2026-05-09 12:10:10.574+02	2026-05-09 12:10:11.618873+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.618873+02
19450	10	E28011704000021D53DAB0CB	\N	-77	0	25	\N	\N	1778321229979	2026-05-09 12:07:09.979+02	2026-05-09 12:07:11.008633+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:11.008633+02
19463	9	E28011704000021D53DAB0CB	\N	-66	0	26	\N	\N	1778321249668	2026-05-09 12:07:29.668+02	2026-05-09 12:07:30.12954+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:30.12954+02
19476	10	E28011704000021D53DAB0CB	\N	-68	0	18	\N	\N	1778321275123	2026-05-09 12:07:55.123+02	2026-05-09 12:07:56.009189+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.009189+02
19498	10	E28011704000021D53DAB0CB	\N	-68	0	34	\N	\N	1778321301239	2026-05-09 12:08:21.239+02	2026-05-09 12:08:21.833327+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.833327+02
19502	10	E28011704000021D53DAB0CB	\N	-75	0	46	\N	\N	1778321301683	2026-05-09 12:08:21.683+02	2026-05-09 12:08:22.911938+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:22.911938+02
19509	10	E28011704000021D53DAB0CB	\N	-71	0	44	\N	\N	1778321322523	2026-05-09 12:08:42.523+02	2026-05-09 12:08:43.451407+02	2026-05-09 12:08:50.732+02	\N	\N	realtime	synced	2026-05-09 12:08:43.451407+02
19530	10	E28011704000021D53DAB0CB	\N	-66	0	16	\N	\N	1778321341127	2026-05-09 12:09:01.127+02	2026-05-09 12:09:03.062423+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:03.062423+02
19535	10	E28011704000021D53DAB0CB	\N	-73	0	48	\N	\N	1778321361974	2026-05-09 12:09:21.974+02	2026-05-09 12:09:22.246084+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:22.246084+02
19540	10	E28011704000021D53DAB0CB	\N	-64	0	49	\N	\N	1778321362273	2026-05-09 12:09:22.273+02	2026-05-09 12:09:23.357727+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.357727+02
19546	10	E28011704000021D53DAB0CB	\N	-77	0	53	\N	\N	1778321362723	2026-05-09 12:09:22.723+02	2026-05-09 12:09:23.413757+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.413757+02
19548	9	E28011704000021D53DAB0CB	\N	-80	0	36	\N	\N	1778321392017	2026-05-09 12:09:52.017+02	2026-05-09 12:09:52.521843+02	2026-05-09 12:09:58.769+02	\N	\N	realtime	synced	2026-05-09 12:09:52.521843+02
19551	10	E28011704000021D53DAB0CB	\N	-74	0	50	\N	\N	1778321394373	2026-05-09 12:09:54.373+02	2026-05-09 12:09:55.289085+02	2026-05-09 12:09:58.769+02	\N	\N	realtime	synced	2026-05-09 12:09:55.289085+02
19555	10	E28011704000021D53DAB0CB	\N	-69	0	8	\N	\N	1778321409974	2026-05-09 12:10:09.974+02	2026-05-09 12:10:10.957975+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:10.957975+02
19557	10	E28011704000021D53DAB0CB	\N	-67	0	39	\N	\N	1778321410126	2026-05-09 12:10:10.126+02	2026-05-09 12:10:11.263875+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.263875+02
19563	10	E28011704000021D53DAB0CB	\N	-70	0	18	\N	\N	1778321410574	2026-05-09 12:10:10.574+02	2026-05-09 12:10:11.622436+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.622436+02
19565	10	E28011704000021D53DAB0CB	\N	-66	0	52	\N	\N	1778321410737	2026-05-09 12:10:10.737+02	2026-05-09 12:10:11.653831+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.653831+02
19451	9	E28011704000021D53DAB0CB	\N	-77	0	23	\N	\N	1778321231968	2026-05-09 12:07:11.968+02	2026-05-09 12:07:12.981575+02	2026-05-09 12:07:16.676+02	\N	\N	realtime	synced	2026-05-09 12:07:12.981575+02
19465	10	E28011704000021D53DAB0CB	\N	-73	0	59	\N	\N	1778321251735	2026-05-09 12:07:31.735+02	2026-05-09 12:07:32.738402+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:32.738402+02
19471	10	E28011704000021D53DAB0CB	\N	-76	0	25	\N	\N	1778321252173	2026-05-09 12:07:32.173+02	2026-05-09 12:07:33.015806+02	2026-05-09 12:07:36.688+02	\N	\N	realtime	synced	2026-05-09 12:07:33.015806+02
19477	10	E28011704000021D53DAB0CB	\N	-71	0	39	\N	\N	1778321275273	2026-05-09 12:07:55.273+02	2026-05-09 12:07:56.042463+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.042463+02
19483	10	E28011704000021D53DAB0CB	\N	-74	0	16	\N	\N	1778321275729	2026-05-09 12:07:55.729+02	2026-05-09 12:07:56.10587+02	2026-05-09 12:08:02.705+02	\N	\N	realtime	synced	2026-05-09 12:07:56.10587+02
19489	9	E28011704000021D53DAB0CB	\N	-62	0	50	\N	\N	1778321298575	2026-05-09 12:08:18.575+02	2026-05-09 12:08:19.565329+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:19.565329+02
19497	10	E28011704000021D53DAB0CB	\N	-67	0	43	\N	\N	1778321301239	2026-05-09 12:08:21.239+02	2026-05-09 12:08:21.831115+02	2026-05-09 12:08:26.717+02	\N	\N	realtime	synced	2026-05-09 12:08:21.831115+02
19519	9	E28011704000021D53DAB0CB	\N	-70	0	45	\N	\N	1778321338767	2026-05-09 12:08:58.767+02	2026-05-09 12:08:59.102921+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:08:59.102921+02
19527	10	E28011704000021D53DAB0CB	\N	-70	0	26	\N	\N	1778321340829	2026-05-09 12:09:00.829+02	2026-05-09 12:09:02.144617+02	2026-05-09 12:09:06.739+02	\N	\N	realtime	synced	2026-05-09 12:09:02.144617+02
19536	10	E28011704000021D53DAB0CB	\N	-76	0	20	\N	\N	1778321362123	2026-05-09 12:09:22.123+02	2026-05-09 12:09:23.33822+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.33822+02
19542	10	E28011704000021D53DAB0CB	\N	-64	0	51	\N	\N	1778321362582	2026-05-09 12:09:22.582+02	2026-05-09 12:09:23.400488+02	2026-05-09 12:09:30.752+02	\N	\N	realtime	synced	2026-05-09 12:09:23.400488+02
19549	9	E28011704000021D53DAB0CB	\N	-76	0	53	\N	\N	1778321392167	2026-05-09 12:09:52.167+02	2026-05-09 12:09:52.829564+02	2026-05-09 12:09:58.769+02	\N	\N	realtime	synced	2026-05-09 12:09:52.829564+02
19559	10	E28011704000021D53DAB0CB	\N	-71	0	41	\N	\N	1778321410427	2026-05-09 12:10:10.427+02	2026-05-09 12:10:11.60768+02	\N	2026-05-09 12:10:18.775+02	insufficient_data	realtime	synced	2026-05-09 12:10:11.60768+02
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

SELECT pg_catalog.setval('public.lighthouse_connection_events_id_seq', 300, true);


--
-- Name: lighthouse_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_groups_id_seq', 5, true);


--
-- Name: lighthouse_health_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_health_snapshots_id_seq', 7478, true);


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

SELECT pg_catalog.setval('public.raw_scans_id_seq', 19565, true);


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

\unrestrict KHcP2x9vOs2lhovZfeCAPzfm5b8Es1JWbDtbDJR3FQ2f9x0eygDWRy9oMoi0a1k

