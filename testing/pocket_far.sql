--
-- PostgreSQL database dump
--

\restrict CLgOxfG230hwJ8GgMgUGSdCd4SLxhRT2wY4EuMrgPuoSb9vu7P4EyHE8pbzOk2c

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
7190	10	2029	170424	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:49:44.909017+02
7192	10	2036	170424	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:49:51.872399+02
7195	10	2050	170424	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:05.836201+02
7196	9	2057	170288	161076	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:06.035626+02
7197	10	2057	170424	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:12.865089+02
7204	10	2085	170424	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:41.128364+02
7207	10	2099	170424	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:55.156975+02
7211	10	2113	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:09.184432+02
7212	10	2120	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:16.250744+02
7213	9	2128	170288	161076	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:16.865489+02
7214	10	2127	165984	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:23.521302+02
7215	9	2138	170288	161076	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:27.104873+02
7220	9	2158	170288	161076	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:46.868622+02
7221	10	2156	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:52.100004+02
7222	9	2169	170288	161076	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:57.415501+02
7223	10	2163	170284	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:58.75185+02
7227	9	2188	170288	161076	-61	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:16.974762+02
7230	9	2198	170288	161076	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:26.937722+02
7232	9	2208	170288	161076	-60	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:36.942322+02
7235	10	2212	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:47.796781+02
7237	9	2228	170288	161076	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:56.398609+02
7240	10	2233	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:08.798831+02
7241	10	2240	167520	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:15.957788+02
7243	10	2247	170284	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:22.920005+02
7245	10	2254	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:29.883238+02
7248	10	2268	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:43.912339+02
7252	10	2282	170292	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:57.94149+02
7254	9	2299	170420	159412	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:07.363176+02
7256	9	2309	170420	159412	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:17.603141+02
7265	10	2338	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:54.0577+02
7267	10	2345	170452	158916	-35	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:01.122924+02
7272	10	2366	170276	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:22.114617+02
7274	10	2373	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:29.077833+02
7276	9	2389	170264	159412	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:37.372248+02
7277	10	2387	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:43.107211+02
7247	9	2269	170420	159412	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:37.46106+02
7251	9	2289	170420	159412	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:57.584403+02
7253	10	2289	170292	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:04.904228+02
7191	9	2037	170288	161076	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 11:49:46.137858+02
7193	9	2048	170264	161076	-61	RESPONSIVE	t	t	129.3	0	2026-05-09 11:49:56.275456+02
7199	10	2064	170424	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:19.931409+02
7249	9	2279	170420	159412	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:47.702095+02
7255	10	2296	170292	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:11.969932+02
7194	10	2043	170424	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:49:58.938575+02
7198	9	2068	170288	161076	-64	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:16.448841+02
7258	10	2310	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:26.10179+02
7260	10	2317	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:33.064919+02
7263	10	2331	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:47.094569+02
7269	10	2352	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:08.085906+02
7270	10	2359	170276	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:15.048936+02
7279	10	2394	170276	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:50.070054+02
7281	10	2401	170276	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:57.056158+02
7283	9	2418	170288	159412	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 11:56:06.966868+02
7285	9	2428	170288	159412	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 11:56:17.104324+02
7200	9	2078	170008	161076	-61	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:26.693982+02
7202	10	2078	170424	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:34.164237+02
7208	9	2109	170288	161076	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:57.306047+02
7209	10	2106	170284	158916	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:02.222043+02
7210	9	2118	170288	161076	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:06.830971+02
7216	10	2134	170276	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:30.484314+02
7217	9	2149	169540	161076	-63	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:37.345056+02
7219	10	2149	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:44.820044+02
7224	10	2170	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:05.812801+02
7226	10	2177	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:12.776383+02
7259	9	2319	170420	159412	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:27.637261+02
7261	9	2329	169672	159412	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:37.366062+02
7264	9	2339	170420	159412	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:47.503459+02
7266	9	2349	168724	159412	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:57.586709+02
7268	9	2359	170288	159412	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:07.573935+02
7271	9	2369	170288	159412	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:17.200122+02
7275	10	2380	170276	158916	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:36.143815+02
7278	9	2398	170288	159412	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:46.895992+02
7280	9	2408	170288	159412	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:56.931088+02
7286	10	2422	170284	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:56:18.128699+02
7201	10	2071	170424	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:27.105706+02
7203	9	2088	170288	161076	-61	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:36.621677+02
7205	9	2098	170288	161076	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:47.066145+02
7206	10	2092	170424	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:50:48.090345+02
7218	10	2142	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:51:37.724358+02
7225	9	2179	170288	161076	-62	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:07.553056+02
7228	10	2184	170284	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:19.739105+02
7229	10	2191	168728	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:26.80474+02
7231	10	2198	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:33.767995+02
7233	10	2205	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:40.736033+02
7234	9	2218	170288	161076	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:46.97795+02
7236	10	2219	170284	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:52:54.760399+02
7238	10	2226	170284	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:01.826095+02
7239	9	2239	170288	161076	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:07.355613+02
7242	9	2249	170288	159412	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:17.574185+02
7244	9	2259	170420	159412	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:27.323666+02
7246	10	2261	170284	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:36.846945+02
7250	10	2275	170292	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:53:50.978375+02
7257	10	2303	170276	158916	-37	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:19.035944+02
7262	10	2324	170276	158916	-38	RESPONSIVE	t	t	129.3	0	2026-05-09 11:54:40.130606+02
7273	9	2379	170288	159412	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 11:55:27.439395+02
7282	10	2408	170276	158916	-36	RESPONSIVE	t	t	129.3	0	2026-05-09 11:56:04.099576+02
7284	10	2415	170284	158916	-39	RESPONSIVE	t	t	129.3	0	2026-05-09 11:56:11.062691+02
\.


--
-- Data for Name: lighthouses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouses (id, name, device_id, placement, comment, firmware_version, last_seen_at, is_active, config, group_id, created_at, canged_at) FROM stdin;
9	Yellow	00:70:07:25:15:00	INSIDE	\N	\N	2026-05-09 11:56:17.106+02	t	{}	5	2026-05-08 22:51:30.087+02	2026-05-08 22:51:30.088128+02
10	Red	68:FE:71:0D:D0:74	OUTSIDE	\N	\N	2026-05-09 11:56:18.13+02	t	{}	5	2026-05-08 22:52:09.26+02	2026-05-08 22:52:09.261586+02
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
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18498
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18498
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18499
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18499
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18500
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18500
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18501
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18501
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18502
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18502
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18503
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18503
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18504
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18504
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18505
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18505
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18506
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18506
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18507
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18507
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18508
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18508
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18509
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18509
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18510
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18510
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18511
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18511
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18512
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18512
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18513
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18513
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18514
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18514
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18515
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18515
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18516
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18516
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18517
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18517
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18518
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18518
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18519
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18519
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18520
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18520
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18521
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18521
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18522
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18522
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18523
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18523
aa7f92ba-593a-4bac-9dd0-3df2dd899388	18524
d3606ddd-e03c-4be5-adf6-42a0353ba43f	18524
3e87204c-e249-4587-9383-66b90dd93b8f	18530
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18530
3e87204c-e249-4587-9383-66b90dd93b8f	18531
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18531
3e87204c-e249-4587-9383-66b90dd93b8f	18532
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18532
3e87204c-e249-4587-9383-66b90dd93b8f	18533
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18533
3e87204c-e249-4587-9383-66b90dd93b8f	18534
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18534
3e87204c-e249-4587-9383-66b90dd93b8f	18535
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18535
3e87204c-e249-4587-9383-66b90dd93b8f	18536
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18536
3e87204c-e249-4587-9383-66b90dd93b8f	18537
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18537
3e87204c-e249-4587-9383-66b90dd93b8f	18538
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18538
3e87204c-e249-4587-9383-66b90dd93b8f	18539
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18539
3e87204c-e249-4587-9383-66b90dd93b8f	18540
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18540
3e87204c-e249-4587-9383-66b90dd93b8f	18541
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18541
3e87204c-e249-4587-9383-66b90dd93b8f	18542
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18542
3e87204c-e249-4587-9383-66b90dd93b8f	18543
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18543
3e87204c-e249-4587-9383-66b90dd93b8f	18544
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18544
3e87204c-e249-4587-9383-66b90dd93b8f	18545
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18545
3e87204c-e249-4587-9383-66b90dd93b8f	18546
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18546
3e87204c-e249-4587-9383-66b90dd93b8f	18547
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18547
3e87204c-e249-4587-9383-66b90dd93b8f	18548
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18548
3e87204c-e249-4587-9383-66b90dd93b8f	18550
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18550
3e87204c-e249-4587-9383-66b90dd93b8f	18549
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18549
3e87204c-e249-4587-9383-66b90dd93b8f	18551
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18551
3e87204c-e249-4587-9383-66b90dd93b8f	18552
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18552
3e87204c-e249-4587-9383-66b90dd93b8f	18553
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18553
3e87204c-e249-4587-9383-66b90dd93b8f	18554
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18554
3e87204c-e249-4587-9383-66b90dd93b8f	18555
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18555
3e87204c-e249-4587-9383-66b90dd93b8f	18556
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18556
3e87204c-e249-4587-9383-66b90dd93b8f	18559
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18559
3e87204c-e249-4587-9383-66b90dd93b8f	18558
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18558
3e87204c-e249-4587-9383-66b90dd93b8f	18557
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18557
3e87204c-e249-4587-9383-66b90dd93b8f	18560
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18560
3e87204c-e249-4587-9383-66b90dd93b8f	18561
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18561
3e87204c-e249-4587-9383-66b90dd93b8f	18562
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18562
3e87204c-e249-4587-9383-66b90dd93b8f	18563
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18563
3e87204c-e249-4587-9383-66b90dd93b8f	18564
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18564
3e87204c-e249-4587-9383-66b90dd93b8f	18565
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18565
3e87204c-e249-4587-9383-66b90dd93b8f	18566
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	18566
5eafa64e-669e-47e7-b519-23e09884ba1b	18601
67044c7a-5acf-422c-b921-5209e83d4771	18601
5eafa64e-669e-47e7-b519-23e09884ba1b	18602
67044c7a-5acf-422c-b921-5209e83d4771	18602
5eafa64e-669e-47e7-b519-23e09884ba1b	18603
67044c7a-5acf-422c-b921-5209e83d4771	18603
5eafa64e-669e-47e7-b519-23e09884ba1b	18604
67044c7a-5acf-422c-b921-5209e83d4771	18604
5eafa64e-669e-47e7-b519-23e09884ba1b	18605
67044c7a-5acf-422c-b921-5209e83d4771	18605
5eafa64e-669e-47e7-b519-23e09884ba1b	18606
67044c7a-5acf-422c-b921-5209e83d4771	18606
5eafa64e-669e-47e7-b519-23e09884ba1b	18609
67044c7a-5acf-422c-b921-5209e83d4771	18609
5eafa64e-669e-47e7-b519-23e09884ba1b	18610
67044c7a-5acf-422c-b921-5209e83d4771	18610
5eafa64e-669e-47e7-b519-23e09884ba1b	18607
67044c7a-5acf-422c-b921-5209e83d4771	18607
5eafa64e-669e-47e7-b519-23e09884ba1b	18608
67044c7a-5acf-422c-b921-5209e83d4771	18608
5eafa64e-669e-47e7-b519-23e09884ba1b	18567
67044c7a-5acf-422c-b921-5209e83d4771	18567
5eafa64e-669e-47e7-b519-23e09884ba1b	18568
67044c7a-5acf-422c-b921-5209e83d4771	18568
5eafa64e-669e-47e7-b519-23e09884ba1b	18569
67044c7a-5acf-422c-b921-5209e83d4771	18569
5eafa64e-669e-47e7-b519-23e09884ba1b	18570
67044c7a-5acf-422c-b921-5209e83d4771	18570
5eafa64e-669e-47e7-b519-23e09884ba1b	18571
67044c7a-5acf-422c-b921-5209e83d4771	18571
5eafa64e-669e-47e7-b519-23e09884ba1b	18572
67044c7a-5acf-422c-b921-5209e83d4771	18572
5eafa64e-669e-47e7-b519-23e09884ba1b	18573
67044c7a-5acf-422c-b921-5209e83d4771	18573
5eafa64e-669e-47e7-b519-23e09884ba1b	18574
67044c7a-5acf-422c-b921-5209e83d4771	18574
5eafa64e-669e-47e7-b519-23e09884ba1b	18575
67044c7a-5acf-422c-b921-5209e83d4771	18575
5eafa64e-669e-47e7-b519-23e09884ba1b	18576
67044c7a-5acf-422c-b921-5209e83d4771	18576
5eafa64e-669e-47e7-b519-23e09884ba1b	18577
67044c7a-5acf-422c-b921-5209e83d4771	18577
5eafa64e-669e-47e7-b519-23e09884ba1b	18578
67044c7a-5acf-422c-b921-5209e83d4771	18578
5eafa64e-669e-47e7-b519-23e09884ba1b	18580
67044c7a-5acf-422c-b921-5209e83d4771	18580
5eafa64e-669e-47e7-b519-23e09884ba1b	18579
67044c7a-5acf-422c-b921-5209e83d4771	18579
5eafa64e-669e-47e7-b519-23e09884ba1b	18581
67044c7a-5acf-422c-b921-5209e83d4771	18581
5eafa64e-669e-47e7-b519-23e09884ba1b	18582
67044c7a-5acf-422c-b921-5209e83d4771	18582
5eafa64e-669e-47e7-b519-23e09884ba1b	18583
67044c7a-5acf-422c-b921-5209e83d4771	18583
5eafa64e-669e-47e7-b519-23e09884ba1b	18584
67044c7a-5acf-422c-b921-5209e83d4771	18584
5eafa64e-669e-47e7-b519-23e09884ba1b	18585
67044c7a-5acf-422c-b921-5209e83d4771	18585
5eafa64e-669e-47e7-b519-23e09884ba1b	18586
67044c7a-5acf-422c-b921-5209e83d4771	18586
5eafa64e-669e-47e7-b519-23e09884ba1b	18587
67044c7a-5acf-422c-b921-5209e83d4771	18587
5eafa64e-669e-47e7-b519-23e09884ba1b	18588
67044c7a-5acf-422c-b921-5209e83d4771	18588
5eafa64e-669e-47e7-b519-23e09884ba1b	18590
67044c7a-5acf-422c-b921-5209e83d4771	18590
5eafa64e-669e-47e7-b519-23e09884ba1b	18589
67044c7a-5acf-422c-b921-5209e83d4771	18589
5eafa64e-669e-47e7-b519-23e09884ba1b	18591
67044c7a-5acf-422c-b921-5209e83d4771	18591
5eafa64e-669e-47e7-b519-23e09884ba1b	18592
67044c7a-5acf-422c-b921-5209e83d4771	18592
5eafa64e-669e-47e7-b519-23e09884ba1b	18593
67044c7a-5acf-422c-b921-5209e83d4771	18593
5eafa64e-669e-47e7-b519-23e09884ba1b	18594
67044c7a-5acf-422c-b921-5209e83d4771	18594
5eafa64e-669e-47e7-b519-23e09884ba1b	18595
67044c7a-5acf-422c-b921-5209e83d4771	18595
5eafa64e-669e-47e7-b519-23e09884ba1b	18596
67044c7a-5acf-422c-b921-5209e83d4771	18596
5eafa64e-669e-47e7-b519-23e09884ba1b	18597
67044c7a-5acf-422c-b921-5209e83d4771	18597
5eafa64e-669e-47e7-b519-23e09884ba1b	18599
67044c7a-5acf-422c-b921-5209e83d4771	18599
5eafa64e-669e-47e7-b519-23e09884ba1b	18598
67044c7a-5acf-422c-b921-5209e83d4771	18598
5eafa64e-669e-47e7-b519-23e09884ba1b	18600
67044c7a-5acf-422c-b921-5209e83d4771	18600
687ba46a-9082-45dd-b387-a61064ba6452	18611
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18611
687ba46a-9082-45dd-b387-a61064ba6452	18612
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18612
687ba46a-9082-45dd-b387-a61064ba6452	18613
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18613
687ba46a-9082-45dd-b387-a61064ba6452	18614
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18614
687ba46a-9082-45dd-b387-a61064ba6452	18615
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18615
687ba46a-9082-45dd-b387-a61064ba6452	18616
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18616
687ba46a-9082-45dd-b387-a61064ba6452	18617
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18617
687ba46a-9082-45dd-b387-a61064ba6452	18618
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	18618
4de3b292-c150-4d81-9e29-84da51e83a3d	18624
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18624
4de3b292-c150-4d81-9e29-84da51e83a3d	18623
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18623
4de3b292-c150-4d81-9e29-84da51e83a3d	18627
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18627
4de3b292-c150-4d81-9e29-84da51e83a3d	18626
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18626
4de3b292-c150-4d81-9e29-84da51e83a3d	18625
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18625
4de3b292-c150-4d81-9e29-84da51e83a3d	18628
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18628
4de3b292-c150-4d81-9e29-84da51e83a3d	18629
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18629
4de3b292-c150-4d81-9e29-84da51e83a3d	18619
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18619
4de3b292-c150-4d81-9e29-84da51e83a3d	18620
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18620
4de3b292-c150-4d81-9e29-84da51e83a3d	18621
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18621
4de3b292-c150-4d81-9e29-84da51e83a3d	18622
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	18622
\.


--
-- Data for Name: processed_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.processed_events (id, algorithm_id, direction, tag_epc, user_id, group_id, confidence, centroid_separation_factor, cluster_size_factor, bilateral_coverage_factor, rssi_trend_consistency_factor, "timestamp", cluster_started_at, cluster_ended_at, metadata, synced_to_integration, created_at, navigo3_record_id) FROM stdin;
d3606ddd-e03c-4be5-adf6-42a0353ba43f	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23354818	0.6672805	1	0.5	0.7	2026-05-09 11:50:24.841+02	2026-05-09 11:50:24.134+02	2026-05-09 11:50:27.5+02	{"rssiTrend": {"inside": {"r2": 0.11845371036383834, "slope": 0.002497668451553899}, "outside": {"r2": 0.0151744581412121, "slope": 0.0012028144808358563}}, "rssiWeights": {"inside": [0.31999999999999995, 0.31999999999999995, 0.31999999999999995, 0.36, 0.26, 0.42000000000000004, 0.31999999999999995, 0.36, 0.36], "outside": [0.19999999999999996, 0.28, 0.19999999999999996, 0.19999999999999996, 0.4, 0.48, 0.33999999999999997, 0.38, 0.30000000000000004, 0.33999999999999997, 0.4, 0.28, 0.26, 0.36, 0.19999999999999996, 0.28, 0.33999999999999997, 0.30000000000000004]}, "centroidDeltaMs": 2246.066162109375, "insideScanCount": 9, "insideCentroidMs": 1778320227087.467, "outsideScanCount": 18, "clusterDurationMs": 3366, "outsideCentroidMs": 1778320224841.401}	f	2026-05-09 11:50:33.050905+02	\N
aa7f92ba-593a-4bac-9dd0-3df2dd899388	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3336799	0.6673598	1	0.5	\N	2026-05-09 11:50:24.829+02	2026-05-09 11:50:24.134+02	2026-05-09 11:50:27.5+02	{"centroidDeltaMs": 2246.333251953125, "insideScanCount": 9, "insideCentroidMs": 1778320227075.3333, "outsideScanCount": 18, "clusterDurationMs": 3366, "outsideCentroidMs": 1778320224829}	t	2026-05-09 11:50:33.050905+02	\N
7c8414e5-4ec4-4983-8cd6-1205e2ad9c46	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.02702305	0.540461	1	0.1	0.5	2026-05-09 11:51:29.022+02	2026-05-09 11:51:22.334+02	2026-05-09 11:51:37.129+02	{"rssiTrend": {"inside": {"r2": 0.8928571428571429, "slope": -0.015625}, "outside": {"r2": 0.01497028008748058, "slope": 0.00009981350969966008}}, "rssiWeights": {"inside": [0.43999999999999995, 0.45999999999999996, 0.4], "outside": [0.4, 0.43999999999999995, 0.54, 0.33999999999999997, 0.4, 0.42000000000000004, 0.38, 0.38, 0.43999999999999995, 0.4, 0.19999999999999996, 0.30000000000000004, 0.31999999999999995, 0.21999999999999997, 0.26, 0.31999999999999995, 0.48, 0.24, 0.4, 0.43999999999999995, 0.28, 0.28, 0.45999999999999996, 0.5800000000000001, 0.54, 0.52, 0.28, 0.38, 0.4, 0.33999999999999997, 0.38, 0.33999999999999997, 0.31999999999999995, 0.33999999999999997]}, "centroidDeltaMs": 7996.1201171875, "insideScanCount": 3, "insideCentroidMs": 1778320297018.2312, "outsideScanCount": 34, "clusterDurationMs": 14795, "outsideCentroidMs": 1778320289022.111}	f	2026-05-09 11:51:43.106019+02	\N
3e87204c-e249-4587-9383-66b90dd93b8f	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.055211682	0.5521168	1	0.1	\N	2026-05-09 11:51:28.853+02	2026-05-09 11:51:22.334+02	2026-05-09 11:51:37.129+02	{"centroidDeltaMs": 8168.568603515625, "insideScanCount": 3, "insideCentroidMs": 1778320297022.3333, "outsideScanCount": 34, "clusterDurationMs": 14795, "outsideCentroidMs": 1778320288853.7646}	t	2026-05-09 11:51:43.106019+02	\N
67044c7a-5acf-422c-b921-5209e83d4771	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.09495445	0.8071128	1	0.29411766	0.4	2026-05-09 11:53:03.403+02	2026-05-09 11:53:00.958+02	2026-05-09 11:53:14.984+02	{"rssiTrend": {"inside": {"r2": 0.28228816008183466, "slope": -0.0009413223737996697}, "outside": {"r2": 0.25064724743053146, "slope": -0.005100380034923586}}, "rssiWeights": {"inside": [0.5, 0.4, 0.28, 0.31999999999999995, 0.31999999999999995, 0.4, 0.43999999999999995, 0.54, 0.5, 0.45999999999999996, 0.54, 0.52, 0.6799999999999999, 0.5800000000000001, 0.64, 0.64, 0.62, 0.6799999999999999, 0.6799999999999999, 0.7, 0.64, 0.64, 0.4, 0.5800000000000001, 0.38, 0.5, 0.6, 0.52, 0.26, 0.28, 0.31999999999999995, 0.42000000000000004, 0.19999999999999996, 0.31999999999999995], "outside": [0.28, 0.33999999999999997, 0.38, 0.33999999999999997, 0.31999999999999995, 0.26, 0.21999999999999997, 0.30000000000000004, 0.21999999999999997, 0.30000000000000004]}, "centroidDeltaMs": 11320.564697265625, "insideScanCount": 34, "insideCentroidMs": 1778320383403.3818, "outsideScanCount": 10, "clusterDurationMs": 14026, "outsideCentroidMs": 1778320394723.9465}	f	2026-05-09 11:53:19.164567+02	\N
5eafa64e-669e-47e7-b519-23e09884ba1b	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.22486761	0.76454985	1	0.29411766	\N	2026-05-09 11:53:04.02+02	2026-05-09 11:53:00.958+02	2026-05-09 11:53:14.984+02	{"centroidDeltaMs": 10723.576416015625, "insideScanCount": 34, "insideCentroidMs": 1778320384020.8235, "outsideScanCount": 10, "clusterDurationMs": 14026, "outsideCentroidMs": 1778320394744.4}	t	2026-05-09 11:53:19.164567+02	\N
ba1cb3bc-f0eb-4d0c-b18f-4436b0234767	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.04678329	0.8732881	0.75	0.14285715	0.5	2026-05-09 11:53:48.509+02	2026-05-09 11:53:48.141+02	2026-05-09 11:53:51.052+02	{"rssiTrend": {"inside": {"r2": 0, "slope": 0}, "outside": {"r2": 0.07447440530255811, "slope": 0.002847969610040536}}, "rssiWeights": {"inside": [0.21999999999999997], "outside": [0.26, 0.21999999999999997, 0.38, 0.33999999999999997, 0.31999999999999995, 0.31999999999999995, 0.28]}, "centroidDeltaMs": 2542.1416015625, "insideScanCount": 1, "insideCentroidMs": 1778320431052, "outsideScanCount": 7, "clusterDurationMs": 2911, "outsideCentroidMs": 1778320428509.8584}	f	2026-05-09 11:53:55.180668+02	\N
687ba46a-9082-45dd-b387-a61064ba6452	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.093955725	0.8769201	0.75	0.14285715	\N	2026-05-09 11:53:48.499+02	2026-05-09 11:53:48.141+02	2026-05-09 11:53:51.052+02	{"centroidDeltaMs": 2552.71435546875, "insideScanCount": 1, "insideCentroidMs": 1778320431052, "outsideScanCount": 7, "clusterDurationMs": 2911, "outsideCentroidMs": 1778320428499.2856}	t	2026-05-09 11:53:55.180668+02	\N
51d318e6-b2cb-4f6d-9899-0cd2a79b90b6	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.2476966	0.86693805	1	0.5714286	0.5	2026-05-09 11:54:09.356+02	2026-05-09 11:54:09.2+02	2026-05-09 11:54:12.434+02	{"rssiTrend": {"inside": {"r2": 0.29138498873288365, "slope": 0.006396255850234009}, "outside": {"r2": 0.00008783181049898392, "slope": 0.00016144806784925043}}, "rssiWeights": {"inside": [0.33999999999999997, 0.4, 0.33999999999999997, 0.38], "outside": [0.28, 0.19999999999999996, 0.31999999999999995, 0.33999999999999997, 0.31999999999999995, 0.31999999999999995, 0.21999999999999997]}, "centroidDeltaMs": 2803.677734375, "insideScanCount": 4, "insideCentroidMs": 1778320449356.7122, "outsideScanCount": 7, "clusterDurationMs": 3234, "outsideCentroidMs": 1778320452160.39}	f	2026-05-09 11:54:17.195402+02	\N
4de3b292-c150-4d81-9e29-84da51e83a3d	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.49609378	0.8681641	1	0.5714286	\N	2026-05-09 11:54:09.352+02	2026-05-09 11:54:09.2+02	2026-05-09 11:54:12.434+02	{"centroidDeltaMs": 2807.642822265625, "insideScanCount": 4, "insideCentroidMs": 1778320449352.5, "outsideScanCount": 7, "clusterDurationMs": 3234, "outsideCentroidMs": 1778320452160.1428}	t	2026-05-09 11:54:17.195402+02	\N
\.


--
-- Data for Name: raw_scans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.raw_scans (id, lighthouse_id, epc, epc_length, rssi_dbm, antenna_id, frequency, sequence_number, detection_confidence, timestamp_ms, "timestamp", received_at, processed_at, orphaned_at, orphan_reason, source, time_basis, created_at) FROM stdin;
18567	9	E28011704000021D53DAB0CB	\N	-65	0	55	\N	\N	1778320380958	2026-05-09 11:53:00.958+02	2026-05-09 11:53:02.03106+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:02.03106+02
18571	9	E28011704000021D53DAB0CB	\N	-74	0	48	\N	\N	1778320381254	2026-05-09 11:53:01.254+02	2026-05-09 11:53:03.058841+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.058841+02
18572	9	E28011704000021D53DAB0CB	\N	-70	0	34	\N	\N	1778320381417	2026-05-09 11:53:01.417+02	2026-05-09 11:53:03.077131+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.077131+02
18573	9	E28011704000021D53DAB0CB	\N	-68	0	53	\N	\N	1778320381582	2026-05-09 11:53:01.582+02	2026-05-09 11:53:03.107663+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.107663+02
18577	9	E28011704000021D53DAB0CB	\N	-63	0	34	\N	\N	1778320381854	2026-05-09 11:53:01.854+02	2026-05-09 11:53:03.266054+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.266054+02
18578	9	E28011704000021D53DAB0CB	\N	-64	0	39	\N	\N	1778320382000	2026-05-09 11:53:02+02	2026-05-09 11:53:03.299252+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.299252+02
18498	10	E28011704000021D53DAB0CB	\N	-80	0	43	\N	\N	1778320224134	2026-05-09 11:50:24.134+02	2026-05-09 11:50:24.845602+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:24.845602+02
18499	10	E28011704000021D53DAB0CB	\N	-76	0	59	\N	\N	1778320224134	2026-05-09 11:50:24.134+02	2026-05-09 11:50:24.847707+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:24.847707+02
18500	10	E28011704000021D53DAB0CB	\N	-80	0	54	\N	\N	1778320224445	2026-05-09 11:50:24.445+02	2026-05-09 11:50:25.152578+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.152578+02
18501	10	E28011704000021D53DAB0CB	\N	-80	0	56	\N	\N	1778320224445	2026-05-09 11:50:24.445+02	2026-05-09 11:50:25.154761+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.154761+02
18502	10	E28011704000021D53DAB0CB	\N	-70	0	35	\N	\N	1778320224445	2026-05-09 11:50:24.445+02	2026-05-09 11:50:25.156561+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.156561+02
18503	10	E28011704000021D53DAB0CB	\N	-66	0	23	\N	\N	1778320224593	2026-05-09 11:50:24.593+02	2026-05-09 11:50:25.460294+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.460294+02
18504	10	E28011704000021D53DAB0CB	\N	-73	0	33	\N	\N	1778320224593	2026-05-09 11:50:24.593+02	2026-05-09 11:50:25.462878+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.462878+02
18505	10	E28011704000021D53DAB0CB	\N	-71	0	8	\N	\N	1778320224734	2026-05-09 11:50:24.734+02	2026-05-09 11:50:25.469675+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.469675+02
18506	10	E28011704000021D53DAB0CB	\N	-75	0	46	\N	\N	1778320224884	2026-05-09 11:50:24.884+02	2026-05-09 11:50:25.478628+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.478628+02
18507	10	E28011704000021D53DAB0CB	\N	-73	0	21	\N	\N	1778320224884	2026-05-09 11:50:24.884+02	2026-05-09 11:50:25.480675+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.480675+02
18508	10	E28011704000021D53DAB0CB	\N	-70	0	39	\N	\N	1778320225037	2026-05-09 11:50:25.037+02	2026-05-09 11:50:25.495127+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.495127+02
18509	10	E28011704000021D53DAB0CB	\N	-76	0	55	\N	\N	1778320225037	2026-05-09 11:50:25.037+02	2026-05-09 11:50:25.497264+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.497264+02
18510	10	E28011704000021D53DAB0CB	\N	-77	0	12	\N	\N	1778320225037	2026-05-09 11:50:25.037+02	2026-05-09 11:50:25.499036+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.499036+02
18511	10	E28011704000021D53DAB0CB	\N	-72	0	37	\N	\N	1778320225184	2026-05-09 11:50:25.184+02	2026-05-09 11:50:25.503779+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.503779+02
18512	10	E28011704000021D53DAB0CB	\N	-80	0	52	\N	\N	1778320225184	2026-05-09 11:50:25.184+02	2026-05-09 11:50:25.506113+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.506113+02
18513	10	E28011704000021D53DAB0CB	\N	-76	0	31	\N	\N	1778320225334	2026-05-09 11:50:25.334+02	2026-05-09 11:50:25.513627+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.513627+02
18514	10	E28011704000021D53DAB0CB	\N	-73	0	44	\N	\N	1778320225334	2026-05-09 11:50:25.334+02	2026-05-09 11:50:25.515416+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.515416+02
18515	10	E28011704000021D53DAB0CB	\N	-75	0	59	\N	\N	1778320225484	2026-05-09 11:50:25.484+02	2026-05-09 11:50:25.522971+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:25.522971+02
18516	9	E28011704000021D53DAB0CB	\N	-74	0	37	\N	\N	1778320226609	2026-05-09 11:50:26.609+02	2026-05-09 11:50:27.507903+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.507903+02
18517	9	E28011704000021D53DAB0CB	\N	-74	0	22	\N	\N	1778320226750	2026-05-09 11:50:26.75+02	2026-05-09 11:50:27.539376+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.539376+02
18518	9	E28011704000021D53DAB0CB	\N	-74	0	21	\N	\N	1778320226904	2026-05-09 11:50:26.904+02	2026-05-09 11:50:27.594267+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.594267+02
18519	9	E28011704000021D53DAB0CB	\N	-72	0	37	\N	\N	1778320226904	2026-05-09 11:50:26.904+02	2026-05-09 11:50:27.596463+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.596463+02
18520	9	E28011704000021D53DAB0CB	\N	-77	0	49	\N	\N	1778320227077	2026-05-09 11:50:27.077+02	2026-05-09 11:50:27.612583+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.612583+02
18521	9	E28011704000021D53DAB0CB	\N	-69	0	56	\N	\N	1778320227234	2026-05-09 11:50:27.234+02	2026-05-09 11:50:27.619543+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.619543+02
18522	9	E28011704000021D53DAB0CB	\N	-74	0	18	\N	\N	1778320227350	2026-05-09 11:50:27.35+02	2026-05-09 11:50:27.676805+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.676805+02
18523	9	E28011704000021D53DAB0CB	\N	-72	0	12	\N	\N	1778320227350	2026-05-09 11:50:27.35+02	2026-05-09 11:50:27.678807+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.678807+02
18524	9	E28011704000021D53DAB0CB	\N	-72	0	26	\N	\N	1778320227500	2026-05-09 11:50:27.5+02	2026-05-09 11:50:27.691846+02	2026-05-09 11:50:33.055+02	\N	\N	realtime	synced	2026-05-09 11:50:27.691846+02
18525	10	E28011704000021D53DAB0CB	\N	-76	0	14	\N	\N	1778320255634	2026-05-09 11:50:55.634+02	2026-05-09 11:50:56.697284+02	\N	2026-05-09 11:51:05.076+02	insufficient_data	realtime	synced	2026-05-09 11:50:56.697284+02
18526	10	E28011704000021D53DAB0CB	\N	-74	0	39	\N	\N	1778320255785	2026-05-09 11:50:55.785+02	2026-05-09 11:50:56.767372+02	\N	2026-05-09 11:51:05.076+02	insufficient_data	realtime	synced	2026-05-09 11:50:56.767372+02
18527	10	E28011704000021D53DAB0CB	\N	-68	0	38	\N	\N	1778320255934	2026-05-09 11:50:55.934+02	2026-05-09 11:50:56.776432+02	\N	2026-05-09 11:51:05.076+02	insufficient_data	realtime	synced	2026-05-09 11:50:56.776432+02
18528	10	E28011704000021D53DAB0CB	\N	-69	0	14	\N	\N	1778320255934	2026-05-09 11:50:55.934+02	2026-05-09 11:50:56.778203+02	\N	2026-05-09 11:51:05.076+02	insufficient_data	realtime	synced	2026-05-09 11:50:56.778203+02
18529	10	E28011704000021D53DAB0CB	\N	-76	0	52	\N	\N	1778320256085	2026-05-09 11:50:56.085+02	2026-05-09 11:50:56.787202+02	\N	2026-05-09 11:51:05.076+02	insufficient_data	realtime	synced	2026-05-09 11:50:56.787202+02
18556	10	E28011704000021D53DAB0CB	\N	-76	0	9	\N	\N	1778320294784	2026-05-09 11:51:34.784+02	2026-05-09 11:51:35.218516+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.218516+02
18558	10	E28011704000021D53DAB0CB	\N	-70	0	51	\N	\N	1778320294945	2026-05-09 11:51:34.945+02	2026-05-09 11:51:35.293239+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.293239+02
18560	10	E28011704000021D53DAB0CB	\N	-71	0	48	\N	\N	1778320295084	2026-05-09 11:51:35.084+02	2026-05-09 11:51:35.313059+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.313059+02
18562	10	E28011704000021D53DAB0CB	\N	-74	0	16	\N	\N	1778320295235	2026-05-09 11:51:35.235+02	2026-05-09 11:51:35.345418+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.345418+02
18565	9	E28011704000021D53DAB0CB	\N	-67	0	24	\N	\N	1778320296969	2026-05-09 11:51:36.969+02	2026-05-09 11:51:37.654522+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:37.654522+02
18568	9	E28011704000021D53DAB0CB	\N	-70	0	27	\N	\N	1778320380958	2026-05-09 11:53:00.958+02	2026-05-09 11:53:02.033092+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:02.033092+02
18569	9	E28011704000021D53DAB0CB	\N	-76	0	20	\N	\N	1778320381125	2026-05-09 11:53:01.125+02	2026-05-09 11:53:02.106694+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:02.106694+02
18570	9	E28011704000021D53DAB0CB	\N	-74	0	30	\N	\N	1778320381254	2026-05-09 11:53:01.254+02	2026-05-09 11:53:03.055339+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.055339+02
18574	9	E28011704000021D53DAB0CB	\N	-63	0	45	\N	\N	1778320381582	2026-05-09 11:53:01.582+02	2026-05-09 11:53:03.109532+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.109532+02
18575	9	E28011704000021D53DAB0CB	\N	-65	0	9	\N	\N	1778320381700	2026-05-09 11:53:01.7+02	2026-05-09 11:53:03.169547+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.169547+02
18576	9	E28011704000021D53DAB0CB	\N	-67	0	57	\N	\N	1778320381854	2026-05-09 11:53:01.854+02	2026-05-09 11:53:03.264222+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.264222+02
18580	9	E28011704000021D53DAB0CB	\N	-56	0	14	\N	\N	1778320382150	2026-05-09 11:53:02.15+02	2026-05-09 11:53:03.364644+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.364644+02
18581	9	E28011704000021D53DAB0CB	\N	-58	0	14	\N	\N	1778320382306	2026-05-09 11:53:02.306+02	2026-05-09 11:53:03.451084+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.451084+02
18584	9	E28011704000021D53DAB0CB	\N	-56	0	54	\N	\N	1778320382469	2026-05-09 11:53:02.469+02	2026-05-09 11:53:03.475903+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.475903+02
18585	9	E28011704000021D53DAB0CB	\N	-56	0	43	\N	\N	1778320382623	2026-05-09 11:53:02.623+02	2026-05-09 11:53:03.528489+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.528489+02
18586	9	E28011704000021D53DAB0CB	\N	-55	0	20	\N	\N	1778320382750	2026-05-09 11:53:02.75+02	2026-05-09 11:53:03.566154+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.566154+02
18590	9	E28011704000021D53DAB0CB	\N	-70	0	42	\N	\N	1778320383060	2026-05-09 11:53:03.06+02	2026-05-09 11:53:03.636667+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.636667+02
18591	9	E28011704000021D53DAB0CB	\N	-71	0	43	\N	\N	1778320383202	2026-05-09 11:53:03.202+02	2026-05-09 11:53:03.689674+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.689674+02
18594	9	E28011704000021D53DAB0CB	\N	-64	0	40	\N	\N	1778320383351	2026-05-09 11:53:03.351+02	2026-05-09 11:53:03.701446+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.701446+02
18595	9	E28011704000021D53DAB0CB	\N	-77	0	17	\N	\N	1778320392070	2026-05-09 11:53:12.07+02	2026-05-09 11:53:12.987452+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:12.987452+02
18596	9	E28011704000021D53DAB0CB	\N	-76	0	21	\N	\N	1778320392383	2026-05-09 11:53:12.383+02	2026-05-09 11:53:13.192057+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:13.192057+02
18597	9	E28011704000021D53DAB0CB	\N	-74	0	30	\N	\N	1778320392501	2026-05-09 11:53:12.501+02	2026-05-09 11:53:13.206503+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:13.206503+02
18598	9	E28011704000021D53DAB0CB	\N	-80	0	54	\N	\N	1778320392651	2026-05-09 11:53:12.651+02	2026-05-09 11:53:13.22223+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:13.22223+02
18603	10	E28011704000021D53DAB0CB	\N	-71	0	12	\N	\N	1778320394535	2026-05-09 11:53:14.535+02	2026-05-09 11:53:15.44679+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:15.44679+02
18604	10	E28011704000021D53DAB0CB	\N	-73	0	50	\N	\N	1778320394684	2026-05-09 11:53:14.684+02	2026-05-09 11:53:15.649794+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:15.649794+02
18606	10	E28011704000021D53DAB0CB	\N	-77	0	44	\N	\N	1778320394836	2026-05-09 11:53:14.836+02	2026-05-09 11:53:16.2644+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:16.2644+02
18607	10	E28011704000021D53DAB0CB	\N	-79	0	49	\N	\N	1778320394984	2026-05-09 11:53:14.984+02	2026-05-09 11:53:16.571451+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:16.571451+02
18610	10	E28011704000021D53DAB0CB	\N	-75	0	11	\N	\N	1778320394984	2026-05-09 11:53:14.984+02	2026-05-09 11:53:16.881766+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:16.881766+02
18614	10	E28011704000021D53DAB0CB	\N	-73	0	29	\N	\N	1778320428434	2026-05-09 11:53:48.434+02	2026-05-09 11:53:49.387145+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:49.387145+02
18615	10	E28011704000021D53DAB0CB	\N	-74	0	53	\N	\N	1778320428584	2026-05-09 11:53:48.584+02	2026-05-09 11:53:49.392459+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:49.392459+02
18616	10	E28011704000021D53DAB0CB	\N	-74	0	54	\N	\N	1778320428734	2026-05-09 11:53:48.734+02	2026-05-09 11:53:49.399472+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:49.399472+02
18617	10	E28011704000021D53DAB0CB	\N	-76	0	33	\N	\N	1778320428884	2026-05-09 11:53:48.884+02	2026-05-09 11:53:49.407058+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:49.407058+02
18620	9	E28011704000021D53DAB0CB	\N	-70	0	39	\N	\N	1778320449350	2026-05-09 11:54:09.35+02	2026-05-09 11:54:10.12803+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:10.12803+02
18622	9	E28011704000021D53DAB0CB	\N	-71	0	7	\N	\N	1778320449510	2026-05-09 11:54:09.51+02	2026-05-09 11:54:10.332007+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:10.332007+02
18624	10	E28011704000021D53DAB0CB	\N	-76	0	14	\N	\N	1778320451984	2026-05-09 11:54:11.984+02	2026-05-09 11:54:12.043064+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:12.043064+02
18627	10	E28011704000021D53DAB0CB	\N	-74	0	54	\N	\N	1778320452145	2026-05-09 11:54:12.145+02	2026-05-09 11:54:13.10147+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:13.10147+02
18629	10	E28011704000021D53DAB0CB	\N	-79	0	37	\N	\N	1778320452434	2026-05-09 11:54:12.434+02	2026-05-09 11:54:13.131767+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:13.131767+02
18632	9	E28011704000021D53DAB0CB	\N	-69	0	55	\N	\N	1778320476952	2026-05-09 11:54:36.952+02	2026-05-09 11:54:37.983177+02	\N	2026-05-09 11:54:45.208+02	insufficient_data	realtime	synced	2026-05-09 11:54:37.983177+02
18579	9	E28011704000021D53DAB0CB	\N	-61	0	13	\N	\N	1778320382150	2026-05-09 11:53:02.15+02	2026-05-09 11:53:03.362378+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.362378+02
18582	9	E28011704000021D53DAB0CB	\N	-58	0	47	\N	\N	1778320382306	2026-05-09 11:53:02.306+02	2026-05-09 11:53:03.452884+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.452884+02
18583	9	E28011704000021D53DAB0CB	\N	-59	0	30	\N	\N	1778320382469	2026-05-09 11:53:02.469+02	2026-05-09 11:53:03.47363+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.47363+02
18557	10	E28011704000021D53DAB0CB	\N	-73	0	44	\N	\N	1778320294945	2026-05-09 11:51:34.945+02	2026-05-09 11:51:35.290738+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.290738+02
18564	9	E28011704000021D53DAB0CB	\N	-68	0	55	\N	\N	1778320296969	2026-05-09 11:51:36.969+02	2026-05-09 11:51:37.652341+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:37.652341+02
18566	9	E28011704000021D53DAB0CB	\N	-70	0	27	\N	\N	1778320297129	2026-05-09 11:51:37.129+02	2026-05-09 11:51:37.665349+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:37.665349+02
18587	9	E28011704000021D53DAB0CB	\N	-58	0	42	\N	\N	1778320382750	2026-05-09 11:53:02.75+02	2026-05-09 11:53:03.568043+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.568043+02
18588	9	E28011704000021D53DAB0CB	\N	-58	0	47	\N	\N	1778320382900	2026-05-09 11:53:02.9+02	2026-05-09 11:53:03.618854+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.618854+02
18589	9	E28011704000021D53DAB0CB	\N	-61	0	9	\N	\N	1778320383060	2026-05-09 11:53:03.06+02	2026-05-09 11:53:03.632616+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.632616+02
18592	9	E28011704000021D53DAB0CB	\N	-65	0	10	\N	\N	1778320383202	2026-05-09 11:53:03.202+02	2026-05-09 11:53:03.692045+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.692045+02
18593	9	E28011704000021D53DAB0CB	\N	-60	0	24	\N	\N	1778320383351	2026-05-09 11:53:03.351+02	2026-05-09 11:53:03.699312+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:03.699312+02
18599	9	E28011704000021D53DAB0CB	\N	-69	0	56	\N	\N	1778320392651	2026-05-09 11:53:12.651+02	2026-05-09 11:53:13.224859+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:13.224859+02
18600	9	E28011704000021D53DAB0CB	\N	-74	0	45	\N	\N	1778320392815	2026-05-09 11:53:12.815+02	2026-05-09 11:53:13.24077+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:13.24077+02
18601	10	E28011704000021D53DAB0CB	\N	-76	0	57	\N	\N	1778320394234	2026-05-09 11:53:14.234+02	2026-05-09 11:53:14.31869+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:14.31869+02
18602	10	E28011704000021D53DAB0CB	\N	-73	0	30	\N	\N	1778320394535	2026-05-09 11:53:14.535+02	2026-05-09 11:53:15.444986+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:15.444986+02
18605	10	E28011704000021D53DAB0CB	\N	-74	0	55	\N	\N	1778320394684	2026-05-09 11:53:14.684+02	2026-05-09 11:53:15.651856+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:15.651856+02
18608	10	E28011704000021D53DAB0CB	\N	-75	0	11	\N	\N	1778320394984	2026-05-09 11:53:14.984+02	2026-05-09 11:53:16.573476+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:16.573476+02
18609	10	E28011704000021D53DAB0CB	\N	-79	0	49	\N	\N	1778320394984	2026-05-09 11:53:14.984+02	2026-05-09 11:53:16.878888+02	2026-05-09 11:53:19.17+02	\N	\N	realtime	synced	2026-05-09 11:53:16.878888+02
18613	10	E28011704000021D53DAB0CB	\N	-71	0	50	\N	\N	1778320428434	2026-05-09 11:53:48.434+02	2026-05-09 11:53:49.385462+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:49.385462+02
18618	9	E28011704000021D53DAB0CB	\N	-79	0	21	\N	\N	1778320431052	2026-05-09 11:53:51.052+02	2026-05-09 11:53:51.082659+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:51.082659+02
18621	9	E28011704000021D53DAB0CB	\N	-73	0	11	\N	\N	1778320449350	2026-05-09 11:54:09.35+02	2026-05-09 11:54:10.130052+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:10.130052+02
18625	10	E28011704000021D53DAB0CB	\N	-74	0	33	\N	\N	1778320452145	2026-05-09 11:54:12.145+02	2026-05-09 11:54:13.097647+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:13.097647+02
18628	10	E28011704000021D53DAB0CB	\N	-74	0	15	\N	\N	1778320452284	2026-05-09 11:54:12.284+02	2026-05-09 11:54:13.115728+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:13.115728+02
18630	9	E28011704000021D53DAB0CB	\N	-76	0	25	\N	\N	1778320476801	2026-05-09 11:54:36.801+02	2026-05-09 11:54:37.673045+02	\N	2026-05-09 11:54:45.208+02	insufficient_data	realtime	synced	2026-05-09 11:54:37.673045+02
18634	10	E28011704000021D53DAB0CB	\N	-73	0	43	\N	\N	1778320499834	2026-05-09 11:54:59.834+02	2026-05-09 11:55:00.014661+02	\N	2026-05-09 11:55:09.221+02	insufficient_data	realtime	synced	2026-05-09 11:55:00.014661+02
18611	10	E28011704000021D53DAB0CB	\N	-77	0	26	\N	\N	1778320428141	2026-05-09 11:53:48.141+02	2026-05-09 11:53:48.213353+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:48.213353+02
18530	10	E28011704000021D53DAB0CB	\N	-70	0	19	\N	\N	1778320282334	2026-05-09 11:51:22.334+02	2026-05-09 11:51:22.907242+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:22.907242+02
18531	10	E28011704000021D53DAB0CB	\N	-68	0	47	\N	\N	1778320282484	2026-05-09 11:51:22.484+02	2026-05-09 11:51:23.213692+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:23.213692+02
18532	10	E28011704000021D53DAB0CB	\N	-63	0	14	\N	\N	1778320282646	2026-05-09 11:51:22.646+02	2026-05-09 11:51:23.82782+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:23.82782+02
18533	10	E28011704000021D53DAB0CB	\N	-73	0	55	\N	\N	1778320282646	2026-05-09 11:51:22.646+02	2026-05-09 11:51:23.831052+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:23.831052+02
18534	10	E28011704000021D53DAB0CB	\N	-70	0	44	\N	\N	1778320282646	2026-05-09 11:51:22.646+02	2026-05-09 11:51:23.833411+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:23.833411+02
18535	10	E28011704000021D53DAB0CB	\N	-69	0	44	\N	\N	1778320282784	2026-05-09 11:51:22.784+02	2026-05-09 11:51:24.135865+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:24.135865+02
18536	10	E28011704000021D53DAB0CB	\N	-71	0	51	\N	\N	1778320282784	2026-05-09 11:51:22.784+02	2026-05-09 11:51:24.13783+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:24.13783+02
18537	10	E28011704000021D53DAB0CB	\N	-71	0	54	\N	\N	1778320282934	2026-05-09 11:51:22.934+02	2026-05-09 11:51:24.44238+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:24.44238+02
18538	10	E28011704000021D53DAB0CB	\N	-68	0	42	\N	\N	1778320283090	2026-05-09 11:51:23.09+02	2026-05-09 11:51:24.754909+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:24.754909+02
18539	10	E28011704000021D53DAB0CB	\N	-70	0	49	\N	\N	1778320283090	2026-05-09 11:51:23.09+02	2026-05-09 11:51:24.75737+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:24.75737+02
18540	10	E28011704000021D53DAB0CB	\N	-80	0	55	\N	\N	1778320283090	2026-05-09 11:51:23.09+02	2026-05-09 11:51:24.759836+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:24.759836+02
18541	10	E28011704000021D53DAB0CB	\N	-75	0	27	\N	\N	1778320283234	2026-05-09 11:51:23.234+02	2026-05-09 11:51:25.057062+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:25.057062+02
18542	10	E28011704000021D53DAB0CB	\N	-74	0	44	\N	\N	1778320283234	2026-05-09 11:51:23.234+02	2026-05-09 11:51:25.059538+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:25.059538+02
18543	10	E28011704000021D53DAB0CB	\N	-79	0	18	\N	\N	1778320284284	2026-05-09 11:51:24.284+02	2026-05-09 11:51:25.364984+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:25.364984+02
18544	10	E28011704000021D53DAB0CB	\N	-77	0	36	\N	\N	1778320285784	2026-05-09 11:51:25.784+02	2026-05-09 11:51:26.700791+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:26.700791+02
18545	10	E28011704000021D53DAB0CB	\N	-74	0	14	\N	\N	1778320285934	2026-05-09 11:51:25.934+02	2026-05-09 11:51:26.842612+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:26.842612+02
18546	10	E28011704000021D53DAB0CB	\N	-66	0	33	\N	\N	1778320286084	2026-05-09 11:51:26.084+02	2026-05-09 11:51:26.850133+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:26.850133+02
18547	10	E28011704000021D53DAB0CB	\N	-78	0	52	\N	\N	1778320286384	2026-05-09 11:51:26.384+02	2026-05-09 11:51:26.860743+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:26.860743+02
18548	10	E28011704000021D53DAB0CB	\N	-70	0	32	\N	\N	1778320294034	2026-05-09 11:51:34.034+02	2026-05-09 11:51:35.09259+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.09259+02
18549	10	E28011704000021D53DAB0CB	\N	-76	0	33	\N	\N	1778320294185	2026-05-09 11:51:34.185+02	2026-05-09 11:51:35.149868+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.149868+02
18550	10	E28011704000021D53DAB0CB	\N	-68	0	46	\N	\N	1778320294185	2026-05-09 11:51:34.185+02	2026-05-09 11:51:35.151921+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.151921+02
18551	10	E28011704000021D53DAB0CB	\N	-76	0	36	\N	\N	1778320294498	2026-05-09 11:51:34.498+02	2026-05-09 11:51:35.159596+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.159596+02
18552	10	E28011704000021D53DAB0CB	\N	-67	0	52	\N	\N	1778320294498	2026-05-09 11:51:34.498+02	2026-05-09 11:51:35.162064+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.162064+02
18553	10	E28011704000021D53DAB0CB	\N	-61	0	54	\N	\N	1778320294635	2026-05-09 11:51:34.635+02	2026-05-09 11:51:35.192539+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.192539+02
18554	10	E28011704000021D53DAB0CB	\N	-63	0	17	\N	\N	1778320294635	2026-05-09 11:51:34.635+02	2026-05-09 11:51:35.194894+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.194894+02
18555	10	E28011704000021D53DAB0CB	\N	-64	0	7	\N	\N	1778320294635	2026-05-09 11:51:34.635+02	2026-05-09 11:51:35.196647+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.196647+02
18559	10	E28011704000021D53DAB0CB	\N	-71	0	13	\N	\N	1778320294945	2026-05-09 11:51:34.945+02	2026-05-09 11:51:35.295954+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.295954+02
18561	10	E28011704000021D53DAB0CB	\N	-73	0	17	\N	\N	1778320295084	2026-05-09 11:51:35.084+02	2026-05-09 11:51:35.314823+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.314823+02
18563	10	E28011704000021D53DAB0CB	\N	-73	0	26	\N	\N	1778320295235	2026-05-09 11:51:35.235+02	2026-05-09 11:51:35.347153+02	2026-05-09 11:51:43.11+02	\N	\N	realtime	synced	2026-05-09 11:51:35.347153+02
18612	10	E28011704000021D53DAB0CB	\N	-79	0	58	\N	\N	1778320428284	2026-05-09 11:53:48.284+02	2026-05-09 11:53:49.339636+02	2026-05-09 11:53:55.183+02	\N	\N	realtime	synced	2026-05-09 11:53:49.339636+02
18619	9	E28011704000021D53DAB0CB	\N	-73	0	56	\N	\N	1778320449200	2026-05-09 11:54:09.2+02	2026-05-09 11:54:09.820077+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:09.820077+02
18623	10	E28011704000021D53DAB0CB	\N	-80	0	18	\N	\N	1778320451984	2026-05-09 11:54:11.984+02	2026-05-09 11:54:12.039886+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:12.039886+02
18626	10	E28011704000021D53DAB0CB	\N	-73	0	50	\N	\N	1778320452145	2026-05-09 11:54:12.145+02	2026-05-09 11:54:13.099483+02	2026-05-09 11:54:17.198+02	\N	\N	realtime	synced	2026-05-09 11:54:13.099483+02
18631	9	E28011704000021D53DAB0CB	\N	-80	0	46	\N	\N	1778320476952	2026-05-09 11:54:36.952+02	2026-05-09 11:54:37.980331+02	\N	2026-05-09 11:54:45.208+02	insufficient_data	realtime	synced	2026-05-09 11:54:37.980331+02
18633	10	E28011704000021D53DAB0CB	\N	-72	0	18	\N	\N	1778320499684	2026-05-09 11:54:59.684+02	2026-05-09 11:54:59.996702+02	\N	2026-05-09 11:55:09.221+02	insufficient_data	realtime	synced	2026-05-09 11:54:59.996702+02
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

SELECT pg_catalog.setval('public.lighthouse_connection_events_id_seq', 282, true);


--
-- Name: lighthouse_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_groups_id_seq', 5, true);


--
-- Name: lighthouse_health_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_health_snapshots_id_seq', 7286, true);


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

SELECT pg_catalog.setval('public.raw_scans_id_seq', 18634, true);


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

\unrestrict CLgOxfG230hwJ8GgMgUGSdCd4SLxhRT2wY4EuMrgPuoSb9vu7P4EyHE8pbzOk2c

