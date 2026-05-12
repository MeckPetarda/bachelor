--
-- PostgreSQL database dump
--

\restrict GxSEO7wh3gm8OYjUNM9ef4TBdneiWqsWkittRTfQvUNhawZIUBxuIKMvsjCgJgq

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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    offline_sync_pending boolean DEFAULT false NOT NULL
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
342	10	connected	\N	2026-05-09 19:29:17.539716+02
343	9	connected	\N	2026-05-09 19:29:18.041345+02
344	10	disconnected	t	2026-05-09 19:29:54.610093+02
345	10	connected	\N	2026-05-09 19:29:55.443119+02
346	9	disconnected	t	2026-05-09 19:30:38.325875+02
347	9	connected	\N	2026-05-09 19:30:43.322578+02
348	9	disconnected	t	2026-05-09 19:31:10.95663+02
349	9	connected	\N	2026-05-09 19:31:10.975275+02
350	9	disconnected	t	2026-05-09 19:33:29.024061+02
351	10	disconnected	t	2026-05-09 19:33:34.24946+02
352	9	connected	\N	2026-05-09 19:34:03.627155+02
353	10	connected	\N	2026-05-09 19:34:08.871029+02
354	10	disconnected	t	2026-05-09 19:34:16.504713+02
355	10	connected	\N	2026-05-09 19:34:20.679591+02
356	9	disconnected	t	2026-05-09 19:40:03.39725+02
357	9	connected	\N	2026-05-09 19:40:09.803941+02
358	9	disconnected	t	2026-05-09 19:40:15.926811+02
359	9	connected	\N	2026-05-09 19:40:20.254573+02
360	10	disconnected	t	2026-05-09 19:45:01.423185+02
361	10	connected	\N	2026-05-09 19:45:01.434921+02
362	9	disconnected	t	2026-05-09 19:45:02.895895+02
363	9	connected	\N	2026-05-09 19:45:44.951873+02
364	9	disconnected	t	2026-05-09 19:46:54.204628+02
365	10	disconnected	t	2026-05-09 19:46:54.61351+02
366	10	connected	\N	2026-05-09 19:47:35.890143+02
367	9	connected	\N	2026-05-09 19:47:35.948688+02
368	10	disconnected	t	2026-05-09 19:48:09.069635+02
369	10	connected	\N	2026-05-09 19:48:13.161065+02
370	10	disconnected	t	2026-05-09 19:48:58.237665+02
371	10	connected	\N	2026-05-09 19:49:02.554938+02
372	9	disconnected	t	2026-05-09 19:49:16.975916+02
373	9	connected	\N	2026-05-09 19:49:23.097947+02
374	10	connected	\N	2026-05-11 16:19:18.157783+02
375	10	disconnected	t	2026-05-11 16:21:17.491155+02
376	10	connected	\N	2026-05-11 17:04:02.44609+02
377	10	disconnected	t	2026-05-11 17:04:09.234407+02
378	10	connected	\N	2026-05-11 17:04:13.62876+02
379	10	disconnected	t	2026-05-11 17:05:16.785732+02
380	9	connected	\N	2026-05-11 17:10:46.680793+02
381	9	disconnected	t	2026-05-11 17:11:17.3094+02
382	9	connected	\N	2026-05-11 17:11:47.833373+02
383	9	disconnected	t	2026-05-11 17:13:20.634643+02
384	10	connected	\N	2026-05-11 17:22:25.570435+02
385	10	disconnected	t	2026-05-11 17:23:29.84396+02
386	10	connected	\N	2026-05-11 17:23:29.869931+02
387	10	disconnected	t	2026-05-11 17:24:05.703112+02
388	10	connected	\N	2026-05-11 17:24:05.71262+02
389	10	disconnected	t	2026-05-11 17:25:40.891852+02
390	10	connected	\N	2026-05-11 17:30:38.739061+02
391	10	disconnected	t	2026-05-11 17:30:46.309997+02
392	10	connected	\N	2026-05-11 17:30:50.743939+02
393	10	disconnected	t	2026-05-11 17:31:33.662186+02
394	9	connected	\N	2026-05-11 17:31:55.109596+02
395	9	connected	\N	2026-05-11 17:33:11.988103+02
396	9	disconnected	t	2026-05-11 17:33:20.908369+02
397	9	connected	\N	2026-05-11 17:33:25.310167+02
398	9	disconnected	t	2026-05-11 17:33:25.372615+02
399	9	connected	\N	2026-05-11 17:33:30.045983+02
400	9	disconnected	t	2026-05-11 17:33:30.104391+02
401	9	connected	\N	2026-05-11 17:33:36.523733+02
402	9	disconnected	t	2026-05-11 17:33:36.881339+02
403	9	connected	\N	2026-05-11 17:33:41.165925+02
404	9	disconnected	t	2026-05-11 17:33:41.248655+02
405	9	connected	\N	2026-05-11 17:33:45.310926+02
406	9	disconnected	t	2026-05-11 17:33:45.384251+02
407	9	connected	\N	2026-05-11 17:33:49.494312+02
408	9	disconnected	t	2026-05-11 17:33:50.088682+02
409	9	connected	\N	2026-05-11 17:33:55.614642+02
410	9	disconnected	t	2026-05-11 17:34:42.992275+02
411	9	connected	\N	2026-05-11 17:38:31.114279+02
412	9	disconnected	t	2026-05-11 17:39:01.707852+02
413	9	connected	\N	2026-05-11 17:39:41.800151+02
414	9	disconnected	t	2026-05-11 17:41:53.50828+02
415	9	connected	\N	2026-05-11 17:41:53.517351+02
416	9	disconnected	t	2026-05-11 17:45:22.047406+02
417	9	connected	\N	2026-05-11 17:45:22.058584+02
418	9	disconnected	t	2026-05-11 17:47:46.199843+02
419	9	connected	\N	2026-05-11 17:47:46.210602+02
420	9	disconnected	t	2026-05-11 17:48:01.959323+02
421	9	connected	\N	2026-05-11 17:48:06.304799+02
422	9	disconnected	t	2026-05-11 17:48:06.5592+02
423	9	connected	\N	2026-05-11 17:48:11.307893+02
424	9	disconnected	t	2026-05-11 17:48:11.366309+02
425	9	connected	\N	2026-05-11 17:48:17.604705+02
426	9	disconnected	t	2026-05-11 17:48:17.726689+02
427	9	connected	\N	2026-05-11 17:48:22.602277+02
428	9	disconnected	t	2026-05-11 17:48:22.753293+02
429	9	connected	\N	2026-05-11 17:48:27.456662+02
430	9	disconnected	t	2026-05-11 17:48:34.832561+02
431	9	connected	\N	2026-05-11 17:48:41.449984+02
432	9	disconnected	t	2026-05-11 17:48:57.848262+02
433	9	connected	\N	2026-05-11 17:48:57.857138+02
434	9	disconnected	t	2026-05-11 17:49:07.7036+02
435	9	connected	\N	2026-05-11 17:49:15.501763+02
436	9	disconnected	t	2026-05-11 17:49:15.995613+02
437	9	connected	\N	2026-05-11 17:49:22.264636+02
438	9	disconnected	t	2026-05-11 17:49:24.49682+02
439	9	connected	\N	2026-05-11 17:49:30.988669+02
440	9	disconnected	t	2026-05-11 17:49:31.059826+02
441	9	connected	\N	2026-05-11 17:49:37.171778+02
442	9	disconnected	t	2026-05-11 17:52:11.180514+02
443	9	connected	\N	2026-05-11 18:01:11.570645+02
444	9	disconnected	t	2026-05-11 18:02:27.839856+02
445	9	connected	\N	2026-05-11 18:03:01.723384+02
446	9	disconnected	t	2026-05-11 18:05:15.371587+02
447	9	connected	\N	2026-05-11 19:28:14.930977+02
448	9	disconnected	t	2026-05-11 19:30:23.298975+02
449	9	connected	\N	2026-05-11 19:35:12.28461+02
450	9	disconnected	t	2026-05-11 19:35:59.374335+02
451	9	connected	\N	2026-05-11 19:36:49.654995+02
452	9	disconnected	t	2026-05-11 19:40:50.86731+02
453	9	connected	\N	2026-05-11 19:53:11.618438+02
454	9	connected	\N	2026-05-11 19:54:17.554361+02
455	9	disconnected	t	2026-05-11 19:55:33.677973+02
456	9	connected	\N	2026-05-11 19:56:13.926104+02
457	9	disconnected	t	2026-05-11 20:00:10.636624+02
458	9	connected	\N	2026-05-11 20:37:59.444975+02
459	9	disconnected	t	2026-05-11 20:38:15.340762+02
460	9	connected	\N	2026-05-11 20:38:20.825443+02
461	9	connected	\N	2026-05-11 20:46:46.898354+02
462	9	connected	\N	2026-05-11 20:47:31.802706+02
463	9	disconnected	t	2026-05-11 20:50:10.329917+02
464	9	connected	\N	2026-05-11 20:50:10.471444+02
465	9	disconnected	t	2026-05-11 20:54:50.95573+02
466	9	connected	\N	2026-05-11 20:57:54.751468+02
467	9	disconnected	t	2026-05-11 20:58:27.466368+02
468	9	connected	\N	2026-05-11 20:58:27.476604+02
469	9	disconnected	t	2026-05-11 21:02:26.670352+02
470	9	connected	\N	2026-05-11 21:02:26.723506+02
471	9	disconnected	t	2026-05-11 21:05:45.401393+02
472	9	connected	\N	2026-05-11 21:06:24.767263+02
473	9	disconnected	t	2026-05-11 21:10:42.981313+02
474	9	connected	\N	2026-05-11 21:23:43.045793+02
475	9	disconnected	t	2026-05-11 21:26:34.978402+02
477	9	disconnected	t	2026-05-11 21:30:42.807681+02
478	9	connected	\N	2026-05-11 21:38:11.239948+02
480	9	connected	\N	2026-05-11 21:39:47.094206+02
481	9	disconnected	t	2026-05-11 21:41:40.734475+02
476	9	connected	\N	2026-05-11 21:27:42.392855+02
479	9	disconnected	t	2026-05-11 21:39:46.788428+02
482	9	connected	\N	2026-05-11 21:42:11.925023+02
483	9	disconnected	t	2026-05-11 21:45:17.791256+02
484	9	connected	\N	2026-05-11 21:51:40.045781+02
485	9	disconnected	t	2026-05-11 21:54:44.085043+02
486	9	connected	\N	2026-05-11 22:11:05.625257+02
487	9	disconnected	t	2026-05-11 22:13:21.396659+02
488	9	connected	\N	2026-05-11 22:14:01.777115+02
489	9	disconnected	t	2026-05-11 22:18:53.172426+02
490	9	connected	\N	2026-05-11 22:28:57.116493+02
491	9	disconnected	t	2026-05-11 22:31:45.382387+02
492	9	connected	\N	2026-05-11 22:32:22.971514+02
493	9	disconnected	t	2026-05-11 22:35:16.121785+02
494	9	connected	\N	2026-05-11 22:44:40.188082+02
495	9	disconnected	t	2026-05-11 22:46:10.570832+02
496	9	connected	\N	2026-05-11 22:47:31.401817+02
497	9	disconnected	t	2026-05-11 22:50:04.449827+02
498	9	connected	\N	2026-05-11 22:55:35.845679+02
499	10	connected	\N	2026-05-11 22:55:38.074344+02
500	9	disconnected	t	2026-05-11 22:57:05.831918+02
501	9	connected	\N	2026-05-11 22:57:11.928604+02
502	9	disconnected	t	2026-05-11 22:58:33.999368+02
503	10	disconnected	t	2026-05-11 22:58:40.551496+02
504	9	connected	\N	2026-05-11 22:58:58.249055+02
505	10	connected	\N	2026-05-11 22:59:03.136949+02
506	10	connected	\N	2026-05-11 23:04:39.597931+02
507	9	connected	\N	2026-05-11 23:04:40.942905+02
509	9	disconnected	t	2026-05-11 23:05:37.224323+02
508	10	disconnected	t	2026-05-11 23:05:37.224323+02
510	10	connected	\N	2026-05-11 23:11:00.90255+02
511	9	connected	\N	2026-05-11 23:11:02.306522+02
512	10	disconnected	t	2026-05-11 23:12:03.887833+02
513	9	disconnected	t	2026-05-11 23:12:06.241612+02
514	10	connected	\N	2026-05-11 23:12:20.694571+02
515	9	connected	\N	2026-05-11 23:12:28.464809+02
516	9	disconnected	t	2026-05-11 23:14:15.911182+02
517	10	disconnected	t	2026-05-11 23:14:18.908936+02
518	10	connected	\N	2026-05-11 23:37:48.976629+02
519	10	disconnected	t	2026-05-11 23:39:09.790333+02
520	10	connected	\N	2026-05-11 23:39:33.39903+02
521	10	disconnected	t	2026-05-11 23:40:19.885745+02
522	9	connected	\N	2026-05-11 23:41:43.249841+02
523	9	disconnected	t	2026-05-11 23:42:40.865894+02
524	9	connected	\N	2026-05-11 23:42:40.881994+02
525	10	connected	\N	2026-05-11 23:42:45.221096+02
526	9	disconnected	t	2026-05-11 23:43:11.582451+02
527	10	disconnected	t	2026-05-11 23:43:14.989677+02
528	10	connected	\N	2026-05-11 23:43:15.00092+02
529	10	disconnected	t	2026-05-11 23:43:45.676731+02
530	9	connected	\N	2026-05-11 23:46:05.973057+02
531	10	connected	\N	2026-05-11 23:46:10.91315+02
532	9	disconnected	t	2026-05-11 23:47:16.795703+02
533	9	connected	\N	2026-05-11 23:47:16.806072+02
534	10	disconnected	t	2026-05-11 23:47:20.390098+02
535	10	connected	\N	2026-05-11 23:47:20.401261+02
536	9	disconnected	t	2026-05-11 23:47:52.752329+02
537	9	connected	\N	2026-05-11 23:47:52.762429+02
538	10	disconnected	t	2026-05-11 23:48:09.084373+02
539	10	connected	\N	2026-05-11 23:48:09.121821+02
540	9	disconnected	t	2026-05-11 23:50:09.783108+02
541	10	disconnected	t	2026-05-11 23:50:12.444991+02
542	9	connected	\N	2026-05-11 23:51:21.259823+02
543	10	connected	\N	2026-05-11 23:51:25.203562+02
544	9	disconnected	t	2026-05-11 23:53:39.609127+02
545	10	disconnected	t	2026-05-11 23:53:43.903962+02
546	10	connected	\N	2026-05-11 23:54:44.529001+02
547	9	connected	\N	2026-05-11 23:54:46.736057+02
548	9	disconnected	t	2026-05-11 23:56:44.192656+02
549	9	connected	\N	2026-05-11 23:56:44.205346+02
550	10	disconnected	t	2026-05-11 23:56:59.228231+02
551	10	connected	\N	2026-05-11 23:56:59.250649+02
552	10	disconnected	t	2026-05-11 23:58:02.381896+02
553	9	disconnected	t	2026-05-11 23:58:03.946105+02
554	9	connected	\N	2026-05-11 23:58:36.849024+02
555	10	connected	\N	2026-05-11 23:58:36.959439+02
556	10	disconnected	t	2026-05-12 00:00:41.904554+02
557	9	disconnected	t	2026-05-12 00:00:41.978405+02
558	10	connected	\N	2026-05-12 00:05:08.994035+02
559	9	connected	\N	2026-05-12 00:05:11.390179+02
560	9	disconnected	t	2026-05-12 00:08:18.513474+02
561	10	disconnected	t	2026-05-12 00:08:19.021517+02
562	9	connected	\N	2026-05-12 00:33:55.412347+02
563	10	connected	\N	2026-05-12 00:33:58.767214+02
564	10	disconnected	t	2026-05-12 00:34:42.056315+02
565	10	connected	\N	2026-05-12 00:34:42.06588+02
566	9	disconnected	t	2026-05-12 00:35:03.316545+02
567	9	connected	\N	2026-05-12 00:35:03.327293+02
568	9	disconnected	t	2026-05-12 00:35:53.001399+02
569	10	disconnected	t	2026-05-12 00:35:53.516625+02
570	10	connected	\N	2026-05-12 00:36:28.886918+02
571	9	connected	\N	2026-05-12 00:36:30.125487+02
572	10	disconnected	t	2026-05-12 00:37:57.360684+02
573	9	disconnected	t	2026-05-12 00:38:03.08454+02
574	9	connected	\N	2026-05-12 01:09:50.604184+02
575	10	connected	\N	2026-05-12 01:09:53.226131+02
576	9	disconnected	t	2026-05-12 01:12:00.780278+02
577	10	disconnected	t	2026-05-12 01:12:02.336344+02
578	10	connected	\N	2026-05-12 01:12:14.798011+02
579	9	connected	\N	2026-05-12 01:12:15.653059+02
580	9	disconnected	t	2026-05-12 01:17:31.378806+02
581	10	disconnected	t	2026-05-12 01:17:37.26554+02
582	9	connected	\N	2026-05-12 01:20:25.704697+02
583	10	connected	\N	2026-05-12 01:20:25.777961+02
584	10	disconnected	t	2026-05-12 01:20:43.506325+02
585	10	connected	\N	2026-05-12 01:20:43.518286+02
586	9	disconnected	t	2026-05-12 01:20:46.353317+02
587	9	connected	\N	2026-05-12 01:20:46.363819+02
588	9	disconnected	t	2026-05-12 01:22:16.449935+02
589	10	disconnected	t	2026-05-12 01:22:18.854488+02
590	10	connected	\N	2026-05-12 01:30:56.803741+02
591	9	connected	\N	2026-05-12 01:31:08.688389+02
592	10	disconnected	t	2026-05-12 01:31:12.231258+02
593	10	connected	\N	2026-05-12 01:31:12.241728+02
594	10	disconnected	t	2026-05-12 01:32:17.351925+02
595	9	disconnected	t	2026-05-12 01:32:18.067082+02
596	10	connected	\N	2026-05-12 01:32:47.779951+02
597	9	connected	\N	2026-05-12 01:32:50.159121+02
598	9	connected	\N	2026-05-12 01:34:54.546483+02
599	10	connected	\N	2026-05-12 01:34:54.692377+02
600	10	connected	\N	2026-05-12 01:35:41.671753+02
601	9	connected	\N	2026-05-12 01:35:41.707604+02
602	10	disconnected	t	2026-05-12 01:36:46.772986+02
603	9	disconnected	t	2026-05-12 01:36:50.15055+02
604	10	connected	\N	2026-05-12 01:51:56.48941+02
605	9	connected	\N	2026-05-12 01:51:58.698453+02
606	10	connected	\N	2026-05-12 01:52:53.020425+02
607	9	connected	\N	2026-05-12 01:52:55.423797+02
608	9	connected	\N	2026-05-12 01:53:49.119245+02
609	10	connected	\N	2026-05-12 01:53:50.414213+02
610	9	connected	\N	2026-05-12 01:54:33.25157+02
611	10	connected	\N	2026-05-12 01:54:33.402067+02
612	9	connected	\N	2026-05-12 02:16:40.236767+02
613	10	connected	\N	2026-05-12 02:16:42.8845+02
614	10	connected	\N	2026-05-12 02:16:55.929344+02
615	9	connected	\N	2026-05-12 02:16:58.952381+02
616	10	connected	\N	2026-05-12 02:18:02.721801+02
617	9	connected	\N	2026-05-12 02:18:03.107515+02
618	9	connected	\N	2026-05-12 02:19:03.440922+02
619	10	connected	\N	2026-05-12 02:19:05.782452+02
620	9	connected	\N	2026-05-12 02:20:17.684695+02
621	10	connected	\N	2026-05-12 02:20:17.818677+02
622	9	disconnected	t	2026-05-12 02:21:54.050132+02
623	10	disconnected	t	2026-05-12 02:23:16.37955+02
624	9	connected	\N	2026-05-12 02:29:25.613832+02
625	10	connected	\N	2026-05-12 02:29:33.855846+02
626	9	connected	\N	2026-05-12 02:38:28.695175+02
627	10	connected	\N	2026-05-12 02:38:31.645308+02
628	9	disconnected	t	2026-05-12 02:38:36.172367+02
629	9	disconnected	f	2026-05-12 02:38:42.876648+02
630	9	connected	\N	2026-05-12 02:38:48.756787+02
631	9	disconnected	t	2026-05-12 02:39:53.66152+02
632	9	connected	\N	2026-05-12 02:39:53.676518+02
633	10	disconnected	t	2026-05-12 02:39:58.040904+02
634	10	connected	\N	2026-05-12 02:39:58.060035+02
635	9	connected	\N	2026-05-12 02:41:04.41291+02
636	10	connected	\N	2026-05-12 02:41:06.473508+02
637	9	connected	\N	2026-05-12 02:42:45.171626+02
638	10	disconnected	f	2026-05-12 02:42:45.592439+02
639	10	connected	\N	2026-05-12 02:42:51.610662+02
640	10	connected	\N	2026-05-12 02:44:04.350938+02
641	9	connected	\N	2026-05-12 02:44:07.958596+02
642	9	connected	\N	2026-05-12 02:44:53.745322+02
643	10	connected	\N	2026-05-12 02:44:55.499292+02
644	10	connected	\N	2026-05-12 02:46:24.624907+02
645	9	connected	\N	2026-05-12 02:46:24.900931+02
646	9	connected	\N	2026-05-12 02:47:05.074391+02
647	10	connected	\N	2026-05-12 02:47:08.790821+02
648	10	connected	\N	2026-05-12 02:48:09.206565+02
649	9	connected	\N	2026-05-12 02:48:11.661401+02
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
7734	9	90	165772	149684	-72	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:29.842314+02
7735	10	90	165708	152636	-82	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:30.354335+02
7736	10	96	165684	152636	-79	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:35.75997+02
7737	9	114	165664	149684	-71	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:52.984354+02
7738	10	6	189968	189836	-65	UNINITIALIZED	f	f	0.0	0	2026-05-09 19:29:55.6048+02
7739	9	121	165688	149684	-86	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:00.152755+02
7740	10	21	170640	166020	-73	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:11.416612+02
7741	10	27	170396	166020	-75	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:16.413613+02
7742	10	34	170396	166020	-79	UNKNOWN	t	t	129.3	0	2026-05-09 19:30:23.704592+02
7743	10	39	170396	166020	-78	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:28.824527+02
7744	10	44	170396	166020	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:33.842413+02
7745	10	49	170396	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:38.859721+02
7746	9	6	193320	191076	-72	UNINITIALIZED	f	f	0.0	0	2026-05-09 19:30:43.376867+02
7747	10	54	170396	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:43.980099+02
7748	10	59	170396	166020	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:48.998557+02
7749	10	64	170396	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:54.117989+02
7750	10	69	170396	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:30:59.093571+02
7751	10	74	170396	166020	-63	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:04.255475+02
7752	10	79	170396	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:09.273087+02
7753	9	6	193304	190908	-74	UNINITIALIZED	f	f	0.0	0	2026-05-09 19:31:11.024085+02
7754	10	84	170396	166020	-63	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:14.274225+02
7755	10	89	170396	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:19.33373+02
7756	10	94	170396	166020	-63	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:24.428431+02
7757	9	20	170636	165484	-74	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:25.05032+02
7758	10	100	170396	166020	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:29.547898+02
7759	9	25	170408	165484	-86	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:30.060062+02
7760	10	105	170396	166020	-63	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:34.565779+02
7761	9	30	170408	165484	-75	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:35.08018+02
7762	10	110	170396	166020	-63	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:39.584327+02
7763	9	35	170408	165484	-80	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:40.198329+02
7764	10	115	170396	166020	-63	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:44.624527+02
7766	10	120	170380	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:49.721696+02
7768	10	125	170416	166020	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:54.723919+02
7770	10	130	170416	166020	-64	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:59.784637+02
7771	10	135	170416	166020	-76	POWERED_OFF	t	t	129.3	0	2026-05-09 19:32:04.877061+02
7773	10	140	170416	166020	-72	POWERED_OFF	t	t	129.3	0	2026-05-09 19:32:09.997006+02
7776	9	74	170404	165484	-65	POWERED_OFF	f	t	129.3	263	2026-05-09 19:32:19.325626+02
7778	9	83	170404	165484	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:27.917405+02
7780	9	90	170404	165484	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:34.880543+02
7782	9	100	170396	165484	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:44.607784+02
7787	9	120	170404	163344	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:33:05.093653+02
7788	10	202	170276	163432	-43	RESPONSIVE	t	t	129.3	0	2026-05-09 19:33:11.744862+02
7852	10	521	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:30.834985+02
7861	10	556	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:05.836099+02
7865	9	498	165368	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:22.770216+02
7866	10	577	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:26.835396+02
7867	9	507	165700	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:32.471692+02
7870	9	517	165696	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:42.199618+02
7872	9	527	165692	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:51.927465+02
7878	10	626	170272	154060	-47	RESPONSIVE	t	t	129.3	0	2026-05-09 19:40:15.845994+02
7887	10	651	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:41.284987+02
7889	10	656	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:46.302523+02
7890	9	583	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:47.735518+02
7892	9	588	168732	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:52.790616+02
7913	10	717	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:47.026046+02
7915	10	722	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:52.043461+02
7916	9	648	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:53.433427+02
7918	9	653	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:58.597045+02
7926	9	674	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:18.769837+02
7930	9	684	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:28.908062+02
7945	10	798	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:07.923009+02
7946	9	724	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:09.356488+02
7948	9	729	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:14.381842+02
7951	10	813	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:23.186005+02
7953	10	818	168712	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:28.231872+02
7954	9	745	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:29.6319+02
7956	9	750	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:34.64996+02
7971	10	864	170272	154060	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:13.663953+02
7984	10	899	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:49.099428+02
7989	10	36	170380	166016	-40	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:30.874455+02
8009	9	56	170416	166036	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:31.701485+02
8012	10	173	162476	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:47:47.579843+02
8013	9	136	162492	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:47:51.778243+02
8014	10	181	165816	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:47:55.16255+02
8017	9	156	165836	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:11.697326+02
8018	10	204	165680	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:18.504583+02
8019	9	165	165836	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:21.576936+02
8023	9	185	165836	155600	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:41.556807+02
8032	10	270	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:24.901366+02
8039	10	298	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:52.919256+02
8043	9	273	165684	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:09.404407+02
8046	10	326	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:20.976955+02
8050	9	303	165668	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:38.794231+02
8054	10	361	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:55.997277+02
8055	9	322	165684	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:58.353167+02
8063	10	396	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:30.902019+02
8068	9	373	170288	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:49.348754+02
8074	9	394	170288	155600	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:10.340998+02
7765	9	40	170408	165484	-76	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:45.216092+02
7767	9	45	170408	165484	-70	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:50.335554+02
7769	9	54	170408	165484	-72	POWERED_OFF	t	t	129.3	0	2026-05-09 19:31:58.985884+02
7772	9	61	170404	165484	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:32:06.011021+02
7774	9	69	170404	165484	-67	POWERED_OFF	f	t	129.3	263	2026-05-09 19:32:14.297771+02
7775	10	149	170416	166020	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:18.496363+02
7777	10	156	170416	165220	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:25.459554+02
7779	10	163	170416	165220	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:32.550649+02
7781	10	171	168852	164608	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:40.819244+02
7783	10	178	170416	164608	-43	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:48.397558+02
7786	10	194	170276	163432	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:33:04.478022+02
7853	9	449	165700	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:34.204826+02
7854	10	528	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:37.835246+02
7855	9	459	165700	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:43.932639+02
7856	10	535	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:44.855071+02
7858	9	469	165700	153276	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:53.765833+02
7859	10	549	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:58.883463+02
7860	9	478	165700	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:03.492243+02
7862	10	563	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:12.91213+02
7863	9	488	165700	153276	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:12.934273+02
7864	10	570	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:19.87602+02
7869	10	591	170272	154060	-43	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:40.86795+02
7875	10	612	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:40:01.860789+02
7876	10	619	170028	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:40:08.838638+02
7877	9	550	158780	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:40:15.6857+02
7879	10	631	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:20.947217+02
7895	10	672	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:01.417626+02
7896	9	598	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:02.995864+02
7897	10	677	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:06.577932+02
7898	9	603	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:08.012055+02
7903	10	692	170272	154060	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:21.732997+02
7904	9	618	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:23.17187+02
7905	10	697	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:26.750948+02
7906	9	623	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:28.184614+02
7921	10	737	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:07.253027+02
7923	10	742	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:12.319387+02
7924	9	669	170292	153276	-69	STARTUP_PENDING	t	t	129.3	0	2026-05-09 19:42:13.752463+02
7933	10	768	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:37.612011+02
7934	9	694	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:39.046055+02
7935	10	773	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:42.629701+02
7936	9	699	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:44.06371+02
7959	10	833	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:43.460616+02
7961	10	838	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:48.371944+02
7962	9	765	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:49.805066+02
7964	9	770	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:54.924954+02
7969	10	859	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:08.646313+02
7970	9	785	170284	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:10.022063+02
7975	10	874	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:23.80185+02
7976	9	800	170284	153276	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:25.234989+02
7977	10	879	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:28.922533+02
7978	9	805	170284	153276	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:30.355456+02
7995	10	62	170380	165340	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:56.167807+02
8003	9	40	170416	166036	-65	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:16.474529+02
8010	10	165	162608	158192	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:47:39.999274+02
8011	9	126	162640	157392	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:47:42.152532+02
8020	10	212	165680	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:26.12304+02
8030	10	256	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:10.901416+02
8031	10	263	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:17.900571+02
8035	10	284	170248	155224	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:38.991952+02
8036	9	244	165684	155600	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:40.016817+02
8040	9	264	165684	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:59.77966+02
8047	10	333	170248	155224	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:27.939775+02
8052	9	312	165684	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:48.73243+02
8057	9	332	165684	155600	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:07.978164+02
8058	10	375	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:09.924379+02
8059	10	382	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:16.987895+02
8060	9	341	165684	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:17.603582+02
8070	9	380	170288	155600	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:56.531046+02
8071	10	424	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:58.974028+02
8080	9	415	170288	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:31.332849+02
8087	10	90	169160	156356	-47	UNKNOWN	t	t	129.3	0	2026-05-11 16:20:26.94835+02
8095	10	89	170300	157416	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:47.423674+02
8096	10	95	170300	157416	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:52.895272+02
8139	10	22	162644	154568	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:30:50.915924+02
8141	10	32	170388	154568	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:31:01.023379+02
8150	9	73	170232	150984	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:34:19.563797+02
8179	9	107	170248	156780	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:34.694371+02
8181	9	121	170264	156780	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:49.030323+02
8182	9	129	170276	156780	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:56.505655+02
8186	9	158	170144	156780	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:25.99763+02
8190	9	188	170144	156780	-63	STARTUP_PENDING	t	t	129.3	0	2026-05-11 17:44:55.489057+02
8196	9	38	165656	159064	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:45:52.940738+02
8199	9	61	165656	143288	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:16.382921+02
8203	9	91	165656	143288	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:46.284641+02
8204	9	98	165764	143288	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:53.974502+02
8206	9	113	170236	143288	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:47:08.09808+02
8210	9	8	191640	190892	-57	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:47:46.286751+02
8215	9	54	170204	154112	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 17:49:42.34495+02
7784	9	110	170404	163344	-65	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:54.643501+02
7785	10	186	170276	163432	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:32:56.38472+02
7857	10	542	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:51.920332+02
7868	10	584	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:33.905041+02
7871	10	598	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:47.934132+02
7873	10	605	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:39:54.897027+02
7874	9	536	161384	153276	-77	RESPONSIVE	t	t	129.3	0	2026-05-09 19:40:01.553478+02
7880	9	557	159632	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:40:22.443939+02
7883	10	641	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:31.401232+02
7885	10	646	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:36.164479+02
7886	9	573	170292	153276	-70	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:37.598625+02
7888	9	578	170292	153276	-70	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:42.717897+02
7911	10	712	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:41.905878+02
7912	9	638	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:43.339755+02
7914	9	643	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:48.46+02
7937	10	778	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:47.749998+02
7938	9	704	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:49.190242+02
7939	10	783	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:52.767698+02
7940	9	709	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:54.201291+02
7963	10	844	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:53.41907+02
7965	10	849	170272	154060	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:58.509035+02
7966	9	775	170292	153276	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:59.942497+02
7968	9	780	170284	153276	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:05.062108+02
7972	9	790	170284	153276	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:15.104792+02
7973	10	869	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:18.784343+02
7974	9	795	170284	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:20.142887+02
7980	9	810	170284	153276	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:35.373156+02
7988	10	31	170380	166016	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:25.754904+02
7994	10	56	168812	166016	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:51.090661+02
8000	10	77	170380	165340	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:11.323564+02
8016	10	189	165684	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:03.15015+02
8021	9	175	165836	155600	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:31.510022+02
8022	10	219	165680	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:34.070591+02
8027	10	242	160284	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:57.008527+02
8041	10	305	170248	155224	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:59.901807+02
8048	9	293	165664	155600	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:29.066485+02
8053	10	354	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:48.901871+02
8069	10	417	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:51.908135+02
8078	9	408	168728	155600	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:24.369763+02
8079	10	452	170248	155224	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:27.036653+02
8088	10	104	168660	156356	-49	UNKNOWN	t	t	129.3	0	2026-05-11 16:20:41.999414+02
8097	9	56	170656	166728	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:10:49.341584+02
8098	9	61	170408	166728	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:10:54.42035+02
8099	9	116	162616	160816	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:11:49.503598+02
8100	9	124	162644	159052	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:11:57.170968+02
8101	9	132	162360	158408	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:05.793293+02
8102	9	140	162512	152016	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:12.768904+02
8103	9	147	160868	152016	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:20.44885+02
8104	9	155	167100	152016	-52	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:27.844222+02
8105	9	162	170304	152016	-52	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:35.540452+02
8106	9	170	170304	152016	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:43.204683+02
8107	9	177	170304	152016	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:50.482818+02
8108	9	185	170300	152016	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:12:58.132738+02
8140	10	27	164680	154568	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 17:30:55.948095+02
8151	9	28	170664	166068	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:38:37.749463+02
8152	9	93	162640	158868	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:39:42.149589+02
8153	9	100	162520	158868	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:39:49.78231+02
8154	9	108	160168	158868	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:39:57.239+02
8155	9	115	162388	158868	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:04.415921+02
8157	9	131	170320	157496	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:20.133377+02
8158	9	138	170324	157496	-59	STARTUP_PENDING	t	t	129.3	0	2026-05-11 17:40:27.686895+02
8160	9	153	170320	157496	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:42.250918+02
8162	9	168	170320	157496	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:57.290073+02
8164	9	183	170188	157496	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:41:12.355068+02
8166	9	198	170320	157496	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:41:27.050062+02
8168	9	212	170320	157496	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 17:41:41.951012+02
8173	9	53	168036	156780	-70	UNKNOWN	t	t	129.3	0	2026-05-11 17:42:40.931205+02
8175	9	75	170128	156780	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:02.977517+02
8176	9	82	170088	156780	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:10.118179+02
8213	9	9	193296	191004	-67	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:48:57.933525+02
8222	9	89	170204	154112	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:17.744367+02
8227	9	114	170204	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:43.035041+02
8228	9	119	170204	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:48.05573+02
8235	9	155	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:23.383973+02
8236	9	160	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:28.501238+02
8245	9	60	170424	166716	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 18:01:40.450654+02
8246	9	65	170424	166716	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 18:01:45.467817+02
8249	9	145	162528	158944	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:04.864827+02
8251	9	160	165844	153748	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:20.764594+02
8252	9	168	163864	153748	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:28.483221+02
8253	9	175	165736	153748	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:35.548741+02
8254	9	183	165736	153748	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:43.331589+02
8255	9	191	165736	153748	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:50.992058+02
8256	9	199	165708	153748	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:58.69119+02
8257	9	206	165844	153748	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:07.192471+02
8258	9	214	165736	153748	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:14.563938+02
8259	9	222	170316	153748	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:22.346601+02
8260	9	230	170320	153748	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:30.130238+02
7789	9	183	161060	154072	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:08.180667+02
7790	10	262	162484	160684	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:11.854062+02
7792	10	276	166940	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:25.883563+02
7797	10	297	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:46.87509+02
7798	9	223	160936	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:48.00125+02
7800	9	233	165700	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:57.729892+02
7801	10	311	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:00.835676+02
7802	9	243	165700	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:07.673682+02
7803	10	318	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:07.833823+02
7808	10	339	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:28.859542+02
7813	10	360	170092	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:49.832521+02
7819	9	312	165700	153276	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:16.921213+02
7820	10	388	170272	154060	-43	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:17.909084+02
7822	9	322	165700	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:26.817645+02
7823	10	402	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:31.93872+02
7832	10	437	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:06.856628+02
7846	9	420	165700	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:04.634649+02
7849	10	507	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:16.835765+02
7881	10	636	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:26.02685+02
7882	9	562	170292	153276	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:27.460512+02
7884	9	567	170292	153276	-70	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:32.580286+02
7899	10	682	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:11.595876+02
7900	9	608	170292	153276	-69	STARTUP_PENDING	t	t	129.3	0	2026-05-09 19:41:13.02893+02
7907	10	702	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:31.768508+02
7908	9	628	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:33.201438+02
7909	10	707	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:36.81834+02
7910	9	633	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:38.322135+02
7941	10	788	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:57.785065+02
7942	9	714	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:59.218585+02
7943	10	793	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:02.905422+02
7944	9	719	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:04.338683+02
7949	10	808	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:18.060907+02
7950	9	734	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:19.494791+02
7952	9	739	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:24.512023+02
7967	10	854	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:03.629613+02
7979	10	884	170272	154060	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:33.939369+02
7981	10	889	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:38.957574+02
7982	9	815	170284	153276	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:40.391796+02
7986	10	19	170616	166016	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:13.46693+02
7987	10	26	170380	166016	-43	UNKNOWN	t	t	129.3	0	2026-05-09 19:45:20.634765+02
7990	10	41	170380	166016	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:35.892419+02
7996	9	23	170740	166036	-67	UNKNOWN	t	t	129.3	0	2026-05-09 19:45:59.141931+02
7997	10	67	170380	165340	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:01.190648+02
7998	9	28	170416	166036	-67	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:04.25749+02
7999	10	72	170380	165340	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:06.20286+02
8002	10	82	170380	165340	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:16.340636+02
8005	9	45	170416	166036	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:21.538619+02
8075	10	438	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:13.002724+02
8077	10	445	168680	155224	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:20.069029+02
8089	10	50	161040	160456	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:08.621607+02
8091	10	65	170300	157416	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:23.461464+02
8092	10	70	170216	157416	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:28.581735+02
8094	10	83	167736	157416	-42	UNKNOWN	t	t	129.3	0	2026-05-11 17:04:41.519161+02
8109	10	15	191528	189572	-48	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:22:25.59231+02
8110	10	27	170572	165972	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 17:22:37.51685+02
8111	10	32	170320	165972	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 17:22:42.640204+02
8112	10	37	170320	165972	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 17:22:47.610246+02
8113	10	43	170320	165972	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 17:22:52.671053+02
8114	10	48	170320	165972	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 17:22:57.79919+02
8115	10	53	170320	165972	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:02.810808+02
8116	10	58	170320	165972	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:07.826643+02
8117	10	63	170320	165972	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:12.863642+02
8118	10	68	170320	165972	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:17.964213+02
8120	10	20	170608	166020	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:41.926017+02
8122	10	30	170376	166020	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:51.96097+02
8125	10	16	170584	165984	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:17.76593+02
8127	10	26	170356	165984	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:27.804323+02
8129	10	36	170356	165984	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:37.939621+02
8131	10	46	170356	165984	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:48.076686+02
8133	10	56	170356	165984	-52	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:58.110292+02
8135	10	66	170356	165984	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 17:25:08.250182+02
8137	10	76	170356	165984	-52	POWERED_OFF	t	t	129.3	0	2026-05-11 17:25:18.388128+02
8142	10	37	170388	154568	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:31:06.041299+02
8144	9	7	193296	189820	-56	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:31:55.177859+02
8156	9	122	162524	158216	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:13.220298+02
8159	9	146	170320	157496	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:35.185761+02
8161	9	160	170320	157496	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:40:49.932599+02
8163	9	175	170320	157496	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:41:04.983823+02
8165	9	190	170320	157496	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:41:19.730114+02
8167	9	205	170320	157496	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:41:34.578185+02
8169	9	6	191616	190988	-58	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:41:53.6103+02
8170	9	22	168920	156780	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 17:42:09.604261+02
8171	9	31	167296	156780	-75	UNKNOWN	t	t	129.3	0	2026-05-11 17:42:19.468515+02
8172	9	40	170244	156780	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 17:42:28.131467+02
8174	9	68	169092	156780	-66	UNKNOWN	t	t	129.3	0	2026-05-11 17:42:55.344988+02
8214	9	48	158912	155264	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 17:49:37.603054+02
8225	9	104	170204	154112	-49	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:32.904345+02
8226	9	109	170204	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:37.917513+02
8239	9	175	170232	154112	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:43.656296+02
7791	9	193	160936	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:18.407622+02
7794	10	283	170296	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:32.921402+02
7796	10	290	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:39.833839+02
7805	9	252	165700	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:17.493521+02
7807	9	262	165700	153276	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:27.425584+02
7810	9	272	165420	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:37.358572+02
7816	10	374	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:03.88077+02
7821	10	395	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:24.833997+02
7824	9	332	165700	153276	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:36.649081+02
7825	10	409	170272	154060	-42	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:38.83413+02
7826	10	416	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:45.865339+02
7827	9	341	165700	153276	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:46.479414+02
7829	9	351	165700	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:56.207606+02
7830	10	430	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:59.894132+02
7831	9	361	165700	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:06.242772+02
7835	10	451	170272	154060	-42	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:20.833645+02
7837	10	458	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:27.849347+02
7840	10	472	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:41.878099+02
7845	10	493	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:02.835077+02
7848	9	430	165700	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:14.646374+02
7850	10	514	170272	154060	-42	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:23.86319+02
7851	9	439	165700	153276	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:24.477302+02
7891	10	661	170272	154060	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:51.320921+02
7893	10	666	170272	154060	-46	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:56.439615+02
7894	9	593	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:40:57.873545+02
7901	10	687	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:16.613087+02
7902	9	613	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:18.024022+02
7917	10	727	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:41:57.168975+02
7919	10	732	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:02.181645+02
7920	9	659	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:03.614625+02
7922	9	664	170292	153276	-69	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:08.684694+02
7925	10	747	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:17.337125+02
7927	10	752	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:22.35841+02
7928	9	679	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:23.890911+02
8007	9	50	170416	166036	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:26.5851+02
8015	9	146	162496	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:01.916698+02
8026	9	195	165836	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:51.080924+02
8028	9	205	165832	155600	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:00.797381+02
8033	9	234	165684	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:30.288204+02
8034	10	277	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:31.926102+02
8037	10	291	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:46.030432+02
8038	9	254	165684	155600	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:49.960471+02
8044	10	319	170248	155224	-47	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:13.910935+02
8045	9	283	165680	155600	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:19.440133+02
8051	10	347	170248	155224	-47	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:41.969062+02
8056	10	368	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:02.960932+02
8061	10	389	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:25.517781+02
8062	9	351	165668	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:27.502874+02
8065	10	403	170248	155224	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:37.982374+02
8072	9	387	170288	155600	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:03.377326+02
8081	10	459	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:33.995753+02
8083	10	39	168580	156356	-52	UNKNOWN	t	t	129.3	0	2026-05-11 16:19:36.56744+02
8090	10	60	165696	157416	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:18.671236+02
8119	10	8	193304	191064	-51	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:23:29.91988+02
8121	10	25	170376	166020	-51	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:46.948832+02
8123	10	35	170376	166020	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 17:23:57.081615+02
8124	10	4	193288	191008	-50	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:24:05.777765+02
8126	10	21	170356	165984	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:22.740194+02
8128	10	31	170356	165984	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:32.926663+02
8130	10	41	170356	165984	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:42.963869+02
8132	10	51	170356	165984	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 17:24:53.076869+02
8134	10	61	170356	165984	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 17:25:03.169858+02
8136	10	71	170356	165984	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 17:25:13.270707+02
8145	9	5	193296	190980	-57	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:33:12.037107+02
8147	9	58	167448	150984	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:34:04.52602+02
8148	9	63	170232	150984	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:34:09.541308+02
8177	9	90	170248	156780	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:17.491183+02
8183	9	136	170272	156780	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:03.923409+02
8187	9	166	170144	156780	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:33.472168+02
8191	9	195	170136	156780	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 17:45:03.115739+02
8193	9	7	193304	191056	-63	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:45:22.127208+02
8195	9	30	165764	159064	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:45:45.817191+02
8198	9	54	164904	143288	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:08.915005+02
8205	9	105	165656	143288	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 17:47:00.566814+02
8207	9	120	170264	143288	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:47:15.478285+02
8211	9	49	145404	137420	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 17:48:27.867096+02
8216	9	59	170204	154112	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:49:47.433788+02
8217	9	64	170204	154112	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 17:49:52.452039+02
8220	9	79	170204	154112	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:07.607297+02
8221	9	84	170204	154112	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:12.725138+02
8229	9	124	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:53.073054+02
8230	9	129	170232	154112	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:58.165159+02
8233	9	144	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:13.346267+02
8234	9	150	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:18.325239+02
8240	9	180	170232	154112	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:48.67629+02
8247	9	77	169984	161168	-68	RESPONSIVE	t	t	129.3	0	2026-05-11 18:01:57.039329+02
8248	9	85	170432	161168	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 18:02:05.333723+02
8250	9	153	162520	153748	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 18:03:12.713295+02
7793	9	203	160936	153276	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:28.274548+02
7795	9	213	160936	153276	-72	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:37.948055+02
7799	10	304	170272	154060	-47	RESPONSIVE	t	t	129.3	0	2026-05-09 19:34:53.941309+02
7804	10	325	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:14.833387+02
7806	10	332	170272	154060	-43	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:21.896671+02
7809	10	346	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:35.834011+02
7811	10	353	170296	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:42.834204+02
7812	9	282	165700	153276	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:47.289731+02
7814	10	367	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:56.917749+02
7815	9	292	165700	153276	-68	RESPONSIVE	t	t	129.3	0	2026-05-09 19:35:57.429665+02
7817	9	302	165700	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:07.162165+02
7818	10	381	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:10.834009+02
7828	10	423	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:36:52.930943+02
7833	10	444	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:13.922952+02
7834	9	371	165700	153276	-71	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:16.092079+02
7836	9	381	165700	153276	-70	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:25.69907+02
7838	10	465	170272	154060	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:34.915053+02
7839	9	390	165700	153276	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:35.427295+02
7841	9	400	165700	153276	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:45.241957+02
7842	10	479	170272	154060	-46	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:49.155851+02
7843	9	410	165700	153276	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:55.018733+02
7844	10	486	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:37:55.833788+02
7847	10	500	170272	154060	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:38:09.935706+02
7929	10	758	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:27.474468+02
7931	10	763	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:32.478712+02
7932	9	689	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:42:33.925981+02
7947	10	803	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:13.042287+02
7955	10	823	170272	154060	-45	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:33.217608+02
7957	10	828	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:38.335859+02
7958	9	755	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:39.769681+02
7960	9	760	170292	153276	-68	POWERED_OFF	t	t	129.3	0	2026-05-09 19:43:44.732679+02
7983	10	894	170272	154060	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:44:44.077219+02
7985	10	7	193312	190904	-43	UNINITIALIZED	f	f	0.0	0	2026-05-09 19:45:01.489608+02
7991	10	46	170380	166016	-44	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:40.891734+02
7992	9	9	191644	191392	-73	UNINITIALIZED	f	f	0.0	0	2026-05-09 19:45:44.998681+02
7993	10	51	170380	166016	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:45:46.030091+02
8001	9	35	170416	166036	-72	UNKNOWN	t	t	129.3	0	2026-05-09 19:46:11.374427+02
8004	10	87	170380	165340	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:21.460919+02
8006	10	92	170380	165340	-43	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:26.479062+02
8008	10	97	170380	165340	-42	POWERED_OFF	t	t	129.3	0	2026-05-09 19:46:31.496316+02
8024	10	227	165680	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:41.557615+02
8025	10	235	165804	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:48:49.225304+02
7731	10	79	165812	152636	-75	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:18.783123+02
7732	9	83	165924	149684	-72	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:22.67471+02
7733	10	85	165676	152636	-66	POWERED_OFF	t	t	129.3	0	2026-05-09 19:29:24.622432+02
8029	9	215	165688	155600	-69	RESPONSIVE	t	t	129.3	0	2026-05-09 19:49:10.795956+02
8042	10	312	170248	155224	-43	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:06.947987+02
8049	10	340	170248	155224	-44	RESPONSIVE	t	t	129.3	0	2026-05-09 19:50:35.007056+02
8064	9	359	165684	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:35.268007+02
8066	9	366	170288	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:42.28263+02
8067	10	410	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:51:44.945633+02
8073	10	431	170248	155224	-45	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:05.937637+02
8076	9	401	170288	155600	-67	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:17.30419+02
8082	9	422	170288	155600	-66	RESPONSIVE	t	t	129.3	0	2026-05-09 19:52:38.295938+02
8084	10	54	170512	156356	-49	UNKNOWN	t	t	129.3	0	2026-05-11 16:19:50.845342+02
8085	10	64	170516	156356	-49	UNKNOWN	t	t	129.3	0	2026-05-11 16:20:01.08303+02
8086	10	75	167704	156356	-51	UNKNOWN	t	t	129.3	0	2026-05-11 16:20:12.713441+02
8093	10	75	170216	157416	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 17:04:33.599379+02
8138	10	10	189536	189536	-58	UNINITIALIZED	f	f	0.0	0	2026-05-11 17:30:38.820356+02
8143	10	42	170388	154568	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:31:11.158875+02
8146	9	53	163544	150984	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:33:59.405835+02
8149	9	68	170232	150984	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:34:14.663747+02
8178	9	97	170220	156780	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:25.068484+02
8180	9	114	170240	156780	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 17:43:41.962457+02
8184	9	144	170276	156780	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:11.45717+02
8185	9	151	170144	156780	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:18.522761+02
8188	9	173	170144	156780	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:40.914015+02
8189	9	181	170144	156780	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 17:44:48.42305+02
8192	9	203	170144	156780	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 17:45:10.746639+02
8194	9	23	166032	159064	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 17:45:38.087965+02
8197	9	45	165652	159064	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:00.408653+02
8200	9	68	163792	143288	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:23.665919+02
8201	9	76	165656	143288	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:30.9292+02
8202	9	83	165764	143288	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 17:46:39.254815+02
8208	9	128	170264	143288	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 17:47:23.151+02
8209	9	135	170264	143288	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 17:47:30.317078+02
8212	9	67	165800	137420	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 17:48:44.968282+02
8218	9	69	170204	154112	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:49:57.56895+02
8219	9	74	168620	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:02.691651+02
8223	9	94	170204	154112	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:22.882854+02
8224	9	99	170204	154112	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 17:50:27.880278+02
8231	9	134	170232	154112	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:03.210249+02
8232	9	139	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:08.267849+02
8237	9	165	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:33.521172+02
8238	9	170	170232	154112	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 17:51:38.539263+02
8241	9	40	170752	166716	-72	UNKNOWN	t	t	129.3	0	2026-05-11 18:01:20.084894+02
8242	9	45	170424	166716	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 18:01:25.295456+02
8243	9	50	170424	166716	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 18:01:30.312639+02
8244	9	55	170424	166716	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 18:01:35.330483+02
8261	9	237	170320	153748	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:37.501728+02
8263	9	253	170328	153748	-52	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:52.866733+02
8977	10	113	159412	154412	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 23:39:34.870049+02
8986	9	32	167208	154384	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 23:42:10.469405+02
8987	9	37	167208	154384	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 23:42:15.487453+02
8990	10	6	190464	188020	-68	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:43:15.073122+02
8997	10	72	167396	163700	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:28.110573+02
8998	9	84	167428	162288	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:35.014004+02
9000	10	88	167396	162072	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:44.085056+02
9004	10	105	167264	160888	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:47:00.775824+02
9010	10	18	167468	157672	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:47:32.418187+02
9012	10	23	167236	157672	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 23:47:37.537878+02
9019	9	27	167384	161616	-51	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:14.91435+02
9020	9	32	167384	161616	-51	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:19.931887+02
9023	10	21	167384	163036	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:26.14499+02
9028	9	56	167384	160392	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:48:43.688822+02
9029	10	39	167384	163036	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:48:45.050329+02
9036	10	72	167252	156748	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:17.58552+02
9040	9	106	167252	160140	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:34.582722+02
9045	9	220	159324	155800	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:27.647638+02
9047	10	211	157700	152664	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:36.439306+02
9051	10	226	163780	150668	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:51.799594+02
9054	10	242	163804	150668	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:07.364214+02
9059	10	265	163672	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:30.404801+02
9062	9	294	167120	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:42.282859+02
9065	10	288	167000	150668	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:53.755651+02
9066	10	296	166872	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:53:01.227114+02
9077	9	450	159328	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:17.933735+02
9079	10	442	163804	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:27.05157+02
9092	9	502	167120	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:10.362089+02
9094	9	509	167120	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:17.325266+02
9096	10	505	167136	149888	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:30.1256+02
9100	10	6	190464	186920	-74	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:56:59.311708+02
9104	10	21	167728	163024	-71	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:14.772611+02
9106	10	28	167492	163024	-69	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:21.735661+02
9431	9	298	166996	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:35:59.690954+02
9441	9	1261	163656	150640	-45	POWERED_OFF	t	t	129.3	0	2026-05-12 01:52:02.641476+02
9516	10	3073	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:22:20.129427+02
9518	10	3087	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:22:34.212893+02
9612	10	191	167264	146900	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:01.603476+02
9617	9	212	166972	144824	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:18.179772+02
8262	9	245	170292	153748	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 18:04:45.079662+02
8264	9	5	191628	191168	-56	UNINITIALIZED	f	f	0.0	0	2026-05-11 19:28:14.983364+02
8265	9	19	170596	157776	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:29.074585+02
8266	9	24	170364	157776	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:34.09289+02
8267	9	29	168788	157776	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:39.297325+02
8268	9	34	170364	157776	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:44.230387+02
8269	9	39	170364	157776	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:49.247367+02
8270	9	44	170364	157776	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:54.368115+02
8271	9	49	170364	157776	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 19:28:59.385761+02
8272	9	54	170364	157776	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:04.403489+02
8273	9	59	170364	157776	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:09.523311+02
8274	9	64	170364	157776	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:14.541117+02
8275	9	69	170364	157776	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:19.559002+02
8276	9	74	170364	157776	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:24.678835+02
8277	9	79	170364	157776	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:29.696156+02
8278	9	84	170364	157776	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:34.713719+02
8279	9	89	170364	157776	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:39.910858+02
8280	9	94	170364	157776	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:44.851391+02
8281	9	99	170364	157776	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:49.909301+02
8282	9	104	170364	157776	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:29:54.995278+02
8283	9	110	170364	157776	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:30:00.006888+02
8284	9	7	193284	191252	-57	UNINITIALIZED	f	f	0.0	0	2026-05-11 19:35:12.342962+02
8285	9	20	170604	165996	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:35:26.253324+02
8286	9	26	170372	165996	-53	POWERED_OFF	t	t	129.3	0	2026-05-11 19:35:31.338052+02
8287	9	31	170372	165996	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:35:36.38489+02
8288	9	106	162584	159768	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 19:36:52.000706+02
8289	9	114	162460	158980	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:36:59.952725+02
8290	9	122	162356	158648	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:07.734601+02
8291	9	130	162456	158648	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:15.724368+02
8292	9	137	165688	158648	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:23.170619+02
8293	9	145	170268	158648	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:30.876692+02
8294	9	153	170268	158648	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:38.653332+02
8295	9	161	170268	158648	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:46.384864+02
8296	9	168	170268	158648	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 19:37:54.019607+02
8297	9	176	170268	158648	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:01.494548+02
8298	9	183	170136	158648	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:09.379642+02
8299	9	191	170268	158648	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:16.962271+02
8300	9	199	170268	158648	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:24.843789+02
8301	9	207	170268	158648	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:32.421929+02
8302	9	214	170268	158648	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:40.203554+02
8303	9	222	170268	158648	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:47.984704+02
8304	9	230	170264	158648	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 19:38:56.08501+02
8305	9	237	170268	158648	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:03.037673+02
8306	9	245	168708	158648	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:11.024649+02
8307	9	253	170268	158648	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:18.807475+02
8308	9	261	170292	158648	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:26.590439+02
8309	9	268	170268	158648	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:34.269725+02
8310	9	276	170268	158648	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:41.950176+02
8311	9	284	170240	158648	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:49.732097+02
8312	9	292	170268	158648	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 19:39:57.51455+02
8313	9	299	170240	158648	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 19:40:04.995205+02
8314	9	307	170268	158648	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 19:40:12.772566+02
8315	9	315	170400	158648	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 19:40:20.657555+02
8316	9	323	170400	158648	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 19:40:28.362837+02
8317	9	9	191624	191088	-60	UNINITIALIZED	f	f	0.0	0	2026-05-11 19:53:11.675478+02
8318	9	22	170452	157568	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 19:53:24.024612+02
8319	9	27	170224	157568	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:53:29.004821+02
8320	9	32	170224	157568	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 19:53:34.059591+02
8321	9	37	170224	157568	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 19:53:39.17958+02
8322	9	42	170224	157568	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 19:53:44.161709+02
8323	9	9	193288	189740	-58	UNINITIALIZED	f	f	0.0	0	2026-05-11 19:54:17.621649+02
8324	9	23	170596	165976	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 19:54:31.562118+02
8325	9	28	170360	165976	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 19:54:36.589886+02
8326	9	33	170360	165976	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:54:41.6184+02
8327	9	38	170360	165976	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:54:46.665695+02
8328	9	49	170360	165340	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 19:54:57.520525+02
8329	9	56	170360	165340	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:55:04.479712+02
8330	9	63	170328	163252	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:55:11.170563+02
8331	9	127	162600	157908	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:56:15.879544+02
8332	9	163	165644	153692	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:56:51.77462+02
8333	9	170	165676	153692	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 19:56:58.30726+02
8334	9	187	165676	153692	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 19:57:15.450843+02
8335	9	201	165676	153692	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 19:57:29.374162+02
8336	9	208	165676	153692	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:57:36.23801+02
8337	9	224	170120	153692	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 19:57:52.802931+02
8338	9	231	170252	153692	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 19:57:59.454199+02
8339	9	238	170252	153692	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:06.11203+02
8340	9	245	170252	153692	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:13.006403+02
8341	9	251	170252	153692	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:19.860213+02
8342	9	258	170252	153692	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:26.722006+02
8343	9	265	170156	153692	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:33.233215+02
8344	9	272	170252	153692	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:40.136457+02
8345	9	279	170252	153692	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:47.026197+02
8346	9	285	170220	153692	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 19:58:53.85816+02
8347	9	292	170120	153692	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 19:59:00.718815+02
8348	9	299	170088	153692	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 19:59:07.169524+02
8349	9	306	170088	153692	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 19:59:13.929325+02
8350	9	312	170120	153692	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 19:59:20.789157+02
8351	9	319	170120	153692	-72	POWERED_OFF	f	t	129.3	263	2026-05-11 19:59:27.752626+02
8353	9	333	170088	153692	-66	POWERED_OFF	f	t	129.3	263	2026-05-11 19:59:41.166627+02
8978	10	119	160848	154412	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 23:39:40.554258+02
8980	10	130	166968	154244	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 23:39:51.613879+02
8981	10	136	166968	154244	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 23:39:57.24566+02
8984	9	22	167208	154384	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 23:42:00.312447+02
8985	9	27	167208	154384	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 23:42:05.451335+02
8991	9	56	167680	162288	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 23:46:07.510427+02
8995	10	65	167408	163700	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:21.015907+02
8996	9	75	167428	162288	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:26.164377+02
9002	10	97	167396	160888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:53.101343+02
9007	9	6	190464	188216	-51	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:47:16.873732+02
9009	9	18	167488	160576	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 23:47:28.833954+02
9011	9	23	167252	160576	-49	POWERED_OFF	t	t	129.3	0	2026-05-11 23:47:33.857826+02
9015	9	5	190460	188088	-52	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:47:52.829671+02
9016	9	17	167620	163016	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:04.776922+02
9017	10	4	187020	186884	-63	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:48:09.495194+02
9018	9	22	167384	163016	-51	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:09.794108+02
9021	10	16	167624	163036	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:21.162943+02
9026	9	47	167384	161616	-51	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:35.092315+02
9030	9	64	167384	160392	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:48:52.393142+02
9031	10	48	167384	159932	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:48:53.096979+02
9032	10	56	167384	159932	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:00.994988+02
9038	10	80	167252	156748	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:25.058899+02
9046	10	203	159468	155664	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:28.533713+02
9048	9	230	157548	152756	-54	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:38.427528+02
9049	10	219	159476	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:44.017113+02
9050	9	241	163656	150540	-55	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:49.239089+02
9052	10	234	163804	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:59.581909+02
9053	9	252	163788	150540	-55	RESPONSIVE	t	t	129.3	0	2026-05-11 23:51:59.722537+02
9056	10	249	162244	150668	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:14.928689+02
9057	9	273	163788	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:21.090767+02
9060	9	284	163788	150540	-54	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:31.940772+02
9061	10	273	167004	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:37.982141+02
9067	9	315	166988	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:53:03.582635+02
9068	10	303	167004	150668	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:53:08.49848+02
9069	9	326	166988	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:53:14.027371+02
9071	10	404	159216	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:54:49.4655+02
9072	9	429	159328	150540	-54	RESPONSIVE	t	t	129.3	0	2026-05-11 23:54:56.71883+02
9073	10	412	159088	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:54:57.145134+02
9084	9	474	167120	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:42.406683+02
9088	9	488	167120	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:56.332973+02
9090	9	495	167120	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:03.398464+02
9098	9	8	190464	186916	-56	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:56:44.26992+02
9109	10	44	167360	162084	-71	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:37.608009+02
9445	10	1313	163904	150296	-68	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:00.118929+02
9447	10	1320	163904	150296	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:07.182173+02
9449	10	1327	163904	150296	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:14.145103+02
9451	10	1334	163904	150296	-66	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:21.118944+02
9520	10	3099	167128	142808	-64	POWERED_OFF	t	t	129.3	0	2026-05-12 02:22:46.296317+02
9525	9	24	167376	163020	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:44.706784+02
9527	9	29	167376	163020	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:49.71714+02
9528	10	26	167388	163024	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:50.893452+02
9530	10	31	167388	163024	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:55.970763+02
9535	10	48	167384	162468	-65	UNKNOWN	t	t	129.3	0	2026-05-12 02:30:13.686428+02
9536	9	54	167244	161092	-52	UNKNOWN	t	t	129.3	0	2026-05-12 02:30:14.864307+02
9613	9	198	166972	144824	-48	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:04.253142+02
9615	9	205	166972	144824	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:11.154126+02
8352	9	326	170088	153692	-70	POWERED_OFF	f	t	129.3	263	2026-05-11 19:59:34.51086+02
8354	9	340	170120	153692	-71	POWERED_OFF	f	t	129.3	263	2026-05-11 19:59:48.130409+02
8355	9	12	193288	189672	-67	UNINITIALIZED	f	f	0.0	0	2026-05-11 20:37:59.503972+02
8356	9	37	154232	134436	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 20:38:26.029697+02
8357	9	46	154788	134436	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 20:38:33.251757+02
8358	9	53	165892	134436	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 20:38:41.245987+02
8359	9	61	165776	134436	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 20:38:48.516093+02
8360	9	68	165792	134436	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 20:38:56.089735+02
8361	9	76	165860	134436	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 20:39:04.584813+02
8362	9	84	164080	134436	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 20:39:11.761561+02
8363	9	92	165792	134436	-83	POWERED_OFF	t	t	129.3	0	2026-05-11 20:39:19.236376+02
8364	9	99	165892	134436	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 20:39:27.428554+02
8365	9	107	170468	134436	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 20:39:35.010282+02
8366	9	115	170236	134436	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 20:39:42.38211+02
8367	9	56	166192	162644	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 20:46:49.509516+02
8368	9	61	159764	150216	-85	POWERED_OFF	t	t	129.3	0	2026-05-11 20:46:55.668884+02
8369	9	66	170280	150216	-85	POWERED_OFF	t	t	129.3	0	2026-05-11 20:46:59.732797+02
8370	9	71	170280	150216	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:04.750114+02
8371	9	76	170280	150216	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:09.768405+02
8372	9	81	170280	150216	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:14.863866+02
8373	9	86	170280	150216	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:19.905722+02
8374	9	91	170280	150216	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:24.897293+02
8375	9	101	170280	150216	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:35.062649+02
8376	9	107	170280	150216	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:40.079372+02
8377	9	114	170280	150216	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:47.658572+02
8378	9	121	170304	150216	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 20:47:54.994633+02
8379	9	129	170296	150216	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:02.607197+02
8380	9	137	170164	150216	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:10.50907+02
8381	9	144	170156	150216	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:17.788155+02
8382	9	152	170164	150216	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:25.342835+02
8383	9	159	170164	150216	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:32.814862+02
8384	9	166	170164	150216	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:39.982538+02
8385	9	174	170164	150216	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:47.652996+02
8386	9	180	170164	150216	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:53.511143+02
8387	9	185	170164	150216	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 20:48:58.210446+02
8388	9	193	170164	150216	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 20:49:06.812526+02
8389	9	201	170164	150216	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 20:49:14.208719+02
8390	9	209	170164	150216	-69	POWERED_OFF	f	t	129.3	263	2026-05-11 20:49:22.684211+02
8391	9	216	170304	150216	-62	POWERED_OFF	f	t	129.3	263	2026-05-11 20:49:29.647208+02
8392	9	221	170304	150216	-61	POWERED_OFF	f	t	129.3	263	2026-05-11 20:49:34.665132+02
8393	9	226	170304	150216	-64	POWERED_OFF	f	t	129.3	263	2026-05-11 20:49:39.785566+02
8394	9	235	170304	150216	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 20:49:48.285782+02
8395	9	242	170304	150216	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 20:49:55.244889+02
8396	9	9	189840	189692	-70	UNINITIALIZED	f	f	0.0	0	2026-05-11 20:50:10.634275+02
8397	9	23	170604	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:50:24.53485+02
8398	9	33	170368	158280	-65	UNKNOWN	t	t	129.3	0	2026-05-11 20:50:34.570269+02
8399	9	44	170240	158280	-65	UNKNOWN	t	t	129.3	0	2026-05-11 20:50:45.13685+02
8400	9	51	170240	158280	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 20:50:52.644481+02
8401	9	62	170264	158280	-64	UNKNOWN	t	t	129.3	0	2026-05-11 20:51:03.957996+02
8402	9	70	170240	158280	-64	STARTUP_PENDING	t	t	129.3	0	2026-05-11 20:51:11.638442+02
8403	9	78	170240	158280	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 20:51:19.523785+02
8404	9	88	170240	158280	-69	UNKNOWN	t	t	129.3	0	2026-05-11 20:51:29.86569+02
8405	9	96	170216	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:51:37.238701+02
8406	9	108	170240	158280	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 20:51:49.564458+02
8407	9	119	170240	158280	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 20:52:00.181092+02
8408	9	126	170268	158280	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:07.754708+02
8409	9	134	170268	158280	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:15.227826+02
8410	9	141	170268	158280	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:22.704593+02
8411	9	148	170268	158280	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:30.077848+02
8412	9	156	170244	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:37.246786+02
8413	9	163	170268	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:44.516079+02
8414	9	170	170264	158280	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:51.991411+02
8415	9	178	170268	158280	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 20:52:59.261791+02
8416	9	185	170268	158280	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:06.49827+02
8417	9	193	170268	158280	-68	STARTUP_PENDING	t	t	129.3	0	2026-05-11 20:53:14.1104+02
8418	9	200	170268	158280	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:21.585412+02
8419	9	207	168704	158280	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:29.11316+02
8420	9	215	170268	158280	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:36.433031+02
8421	9	222	170268	158280	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:43.601541+02
8422	9	230	170268	158280	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:51.076649+02
8423	9	237	170268	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:53:58.654874+02
8424	9	244	170268	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:54:05.924818+02
8425	9	252	170268	158280	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 20:54:13.330022+02
8426	9	259	170268	158280	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 20:54:20.983011+02
8427	9	267	170400	158280	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 20:54:28.452567+02
8428	9	476	162452	158128	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 20:57:57.089302+02
8429	9	481	153004	149240	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:02.26241+02
8430	9	486	167032	148640	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:07.284395+02
8431	9	491	167032	148640	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:12.301701+02
8432	9	8	193304	191056	-59	UNINITIALIZED	f	f	0.0	0	2026-05-11 20:58:27.544991+02
8433	9	22	170596	165996	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:41.793572+02
8434	9	27	170356	165996	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:46.811036+02
8435	9	32	170356	165996	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:51.931052+02
8436	9	37	170356	165996	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 20:58:56.869557+02
8437	9	42	170356	165996	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:01.965942+02
8438	9	47	170356	165996	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:06.984322+02
8439	9	53	170356	165996	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:12.103973+02
8440	9	58	170356	165996	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:17.121824+02
8441	9	66	170356	165996	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 20:59:25.731077+02
8442	9	73	170356	165996	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 20:59:32.686633+02
8443	9	78	170356	165996	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:37.806649+02
8452	9	127	170384	165996	-58	RESPONSIVE	t	t	129.3	0	2026-05-11 21:00:26.754408+02
8455	9	158	168632	159588	-60	RESPONSIVE	t	t	129.3	0	2026-05-11 21:00:57.988288+02
8472	9	90	170348	161556	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:48.791484+02
8477	9	131	170244	161392	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 21:04:30.468223+02
8481	9	164	170112	161256	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:05:03.036618+02
8484	9	246	162428	152468	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:06:25.084425+02
8488	9	276	165768	152468	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:06:55.329787+02
8490	9	291	165636	152468	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:10.316485+02
8494	9	321	165748	152468	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:41.65126+02
8495	9	330	165636	152468	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:48.613878+02
8979	10	125	167100	154244	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 23:39:46.073817+02
8982	9	5	190440	186896	-69	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:41:43.317362+02
8983	9	17	167452	154384	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 23:41:55.31399+02
8988	9	8	190464	188164	-73	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:42:40.945942+02
8989	10	8	188556	188224	-70	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:42:45.335825+02
8992	10	56	167660	163700	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 23:46:12.438183+02
8993	9	61	167428	162288	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 23:46:12.563006+02
8994	9	66	167428	162288	-49	POWERED_OFF	t	t	129.3	0	2026-05-11 23:46:17.618777+02
8999	10	80	166676	163280	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:36.591213+02
9001	9	94	167428	162288	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:45.870351+02
9003	9	105	167292	162288	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 23:46:56.680224+02
9005	9	116	167296	162288	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 23:47:07.512745+02
9006	10	112	167264	160888	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:47:08.558586+02
9008	10	6	190456	188036	-63	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:47:20.466972+02
9013	10	28	167236	157672	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 23:47:42.593886+02
9014	10	33	167236	157672	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 23:47:47.64355+02
9022	9	37	167384	161616	-50	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:24.937112+02
9024	9	42	167384	161616	-51	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:30.069477+02
9025	10	26	167384	163036	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:31.298315+02
9027	10	31	167384	163036	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:48:36.316532+02
9033	9	75	167384	160392	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:02.736053+02
9034	10	64	167384	159932	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:09.094844+02
9035	9	85	166972	160252	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:13.082975+02
9037	9	96	167252	160140	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:24.019179+02
9039	10	87	167252	156748	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:32.739387+02
9041	10	93	167252	156748	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 23:49:38.576059+02
9042	10	99	167252	156748	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:49:44.204827+02
9043	9	116	167384	160140	-51	RESPONSIVE	t	t	129.3	0	2026-05-11 23:49:44.231451+02
9044	10	104	167252	156748	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:49:49.942349+02
9055	9	262	163788	150540	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:10.334103+02
9058	10	257	163672	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:22.6078+02
9063	10	280	167004	150668	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:45.766467+02
9064	9	305	167120	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:52:53.040735+02
9070	10	310	167004	150668	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:53:15.563205+02
9074	10	420	163936	149888	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:05.035043+02
9075	9	439	159336	150540	-54	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:07.385486+02
9080	9	460	163788	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:28.377592+02
9082	9	467	167120	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:35.341061+02
9086	9	481	167120	150540	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:49.369547+02
9087	10	470	167136	149888	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:55.206569+02
9093	10	491	167136	149888	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:16.044055+02
9095	10	498	167136	149888	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:23.06459+02
9097	10	512	167136	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:37.093803+02
9099	9	20	167596	163004	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 23:56:56.238031+02
9101	9	25	167364	163004	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 23:57:01.255556+02
9103	9	35	167364	163004	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 23:57:11.392965+02
9105	9	44	167364	163004	-52	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:19.893209+02
9108	10	36	167492	162084	-71	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:30.029907+02
9446	9	1320	163788	150640	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:01.44733+02
9448	9	1327	163788	150640	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:08.513451+02
9450	9	1334	163788	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:15.476302+02
9452	9	1341	163788	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:22.439884+02
9521	10	3104	167128	142808	-65	POWERED_OFF	t	t	129.3	0	2026-05-12 02:22:51.314048+02
9523	10	9	190464	188216	-71	UNINITIALIZED	f	f	0.0	0	2026-05-12 02:29:33.922169+02
9529	9	34	167376	163020	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:54.844132+02
9531	9	39	167376	163020	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 02:30:00.06692+02
9532	10	36	167388	163024	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:30:01.020492+02
9533	10	41	167388	163024	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 02:30:06.108232+02
9534	9	47	167244	161092	-51	UNKNOWN	t	t	129.3	0	2026-05-12 02:30:07.84907+02
9537	10	54	167384	162468	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 02:30:18.806267+02
9538	9	61	167244	161092	-51	UNKNOWN	t	t	129.3	0	2026-05-12 02:30:21.864144+02
9621	10	262	165732	146900	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 02:44:12.608534+02
9624	9	277	167100	144824	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:44:22.781796+02
8444	9	83	168804	165996	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:42.926876+02
8460	9	211	170240	146764	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 21:01:50.313886+02
8471	9	82	170348	161556	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:41.417948+02
8473	9	97	170216	161556	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:56.024608+02
8487	9	269	164160	152468	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:06:48.504794+02
8496	9	337	165636	152468	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:55.782334+02
9076	10	427	163936	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:12.650738+02
9078	10	435	163804	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:20.08298+02
9081	10	449	167136	149888	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:34.112279+02
9083	10	456	167136	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:41.080666+02
9085	10	463	167136	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:55:48.141138+02
9089	10	477	167136	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:02.067415+02
9091	10	484	167136	149888	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:56:09.133571+02
9102	9	30	167364	163004	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 23:57:06.375548+02
9107	9	53	167364	161108	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:29.113354+02
9110	9	63	167356	161108	-53	RESPONSIVE	t	t	129.3	0	2026-05-11 23:57:39.450988+02
9453	10	1370	167108	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:56.848801+02
9456	9	1383	167124	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:54:04.880001+02
9522	9	5	190460	188220	-51	UNINITIALIZED	f	f	0.0	0	2026-05-12 02:29:25.679039+02
9526	10	21	167624	163024	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:45.925623+02
9622	9	270	167100	144824	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 02:44:15.611391+02
8445	9	88	170356	165996	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:47.838774+02
8446	9	93	170356	165996	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:53.224099+02
8454	9	148	170384	161484	-59	RESPONSIVE	t	t	129.3	0	2026-05-11 21:00:47.733346+02
8457	9	181	170240	146764	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 21:01:20.207542+02
8470	9	75	170348	161556	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:33.840275+02
9111	10	105	159452	155696	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:38.922452+02
9113	10	111	159332	152916	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:44.577731+02
9117	9	141	167240	156196	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:56.763792+02
9126	9	171	167240	156196	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:26.821585+02
9128	10	160	167120	152916	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:33.864287+02
9130	10	165	167120	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:38.953199+02
9137	10	185	167132	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:59.101541+02
9139	9	209	167124	156196	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:04.601969+02
9141	9	216	167124	156196	-56	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:11.82383+02
9145	10	498	159200	150356	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:11.902855+02
9147	10	504	159212	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:17.695116+02
9148	10	510	159212	150356	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:23.327174+02
9153	9	542	163756	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:38.461508+02
9159	10	541	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:55.27627+02
9161	9	565	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:01.523009+02
9163	9	571	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:06.788951+02
9169	9	586	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:21.950095+02
9171	9	591	163656	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:27.012807+02
9179	9	611	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:47.303488+02
9187	9	631	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:07.46884+02
9189	9	637	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:12.589174+02
9195	9	652	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:27.745736+02
9197	9	657	166988	150296	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:32.761864+02
9203	9	672	165428	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:47.897298+02
9205	9	677	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:52.938584+02
9454	9	1376	167124	150640	-48	RESPONSIVE	t	t	129.3	0	2026-05-12 01:53:57.972862+02
9455	10	1377	167108	148832	-66	RESPONSIVE	t	t	129.3	0	2026-05-12 01:54:04.864844+02
9539	9	553	162812	161028	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:33.403442+02
9540	10	549	162948	158240	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:34.426637+02
9542	10	559	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:44.446489+02
9543	10	564	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:49.602158+02
9549	10	580	167160	94560	-71	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:04.736621+02
9559	10	605	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:29.979691+02
9564	10	620	167160	94560	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:45.172376+02
9580	10	50	167384	163024	-74	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:40.443723+02
9623	10	269	167292	146900	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 02:44:19.517745+02
8447	9	98	170356	165996	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 20:59:57.937389+02
8448	9	103	170356	165996	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 21:00:03.099953+02
8449	9	109	170356	165996	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:00:08.142767+02
8450	9	114	170356	165996	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:00:13.115054+02
8453	9	138	170384	161484	-58	RESPONSIVE	t	t	129.3	0	2026-05-11 21:00:37.198709+02
8461	9	221	170240	146764	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 21:02:00.451397+02
8462	9	8	191600	190860	-65	UNINITIALIZED	f	f	0.0	0	2026-05-11 21:02:27.075247+02
8468	9	60	170348	161556	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:19.504148+02
8474	9	104	170200	161392	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:04:03.536808+02
8478	9	142	170244	161392	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 21:04:40.937394+02
8479	9	149	170216	161392	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 21:04:48.285737+02
8483	9	178	170216	161256	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 21:05:17.572763+02
8489	9	284	165880	152468	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:03.966937+02
8491	9	299	164064	152468	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:17.661724+02
8493	9	313	165748	152468	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:33.255903+02
9112	9	126	162908	157576	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:41.553192+02
9114	9	133	162784	156196	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:49.186412+02
9118	10	127	163788	152916	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:01.167054+02
9119	9	148	167240	156196	-56	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:04.034246+02
9121	9	156	167252	156196	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:11.612047+02
9123	10	144	163820	152916	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:17.858046+02
9125	10	150	167124	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:23.388352+02
9127	10	155	167120	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:28.815444+02
9129	9	178	167108	156196	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:34.24208+02
9131	9	186	167116	156196	-55	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:41.615629+02
9134	9	193	167124	156196	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:49.281714+02
9138	10	190	167132	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:04.245606+02
9144	9	223	167124	156196	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:19.472382+02
9146	9	520	159332	152228	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:15.885019+02
9150	10	515	163656	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:28.856782+02
9155	10	531	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:45.139584+02
9157	10	536	167180	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:50.679107+02
9165	9	576	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:11.84952+02
9167	9	581	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:16.984792+02
9173	9	596	163656	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:32.14076+02
9175	9	601	163656	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:37.158007+02
9177	9	606	162084	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:42.461737+02
9181	9	616	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:52.313543+02
9183	9	621	166988	150296	-56	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:57.345673+02
9185	9	626	166988	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:02.398035+02
9191	9	642	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:17.548207+02
9193	9	647	166988	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:22.620276+02
9199	9	662	166988	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:37.769042+02
9201	9	667	166988	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:42.899853+02
9457	10	1412	155672	148832	-68	RESPONSIVE	t	t	129.3	0	2026-05-12 01:54:39.309929+02
9458	9	1420	167120	148120	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:54:41.186133+02
9541	10	554	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:39.443871+02
9544	9	573	137572	77996	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:53.677086+02
9567	9	22	167580	162972	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:07.712988+02
9577	9	47	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:32.937352+02
9625	9	315	166968	139924	-49	RESPONSIVE	t	t	129.3	0	2026-05-12 02:45:00.653324+02
9626	10	312	167016	146900	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 02:45:02.21854+02
8451	9	119	170356	165996	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:00:18.152393+02
8456	9	170	170248	146764	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 21:01:10.069913+02
8459	9	201	170240	146764	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 21:01:40.278254+02
8465	9	35	170348	164216	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 21:02:54.276716+02
8469	9	68	170348	161556	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:26.774736+02
8476	9	119	170208	161392	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:04:18.38565+02
8482	9	171	170244	161256	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:05:10.304479+02
8492	9	306	165636	152468	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:07:25.065774+02
8497	9	344	165632	152468	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:03.155041+02
9115	10	116	159332	152916	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:50.165347+02
9116	10	122	163788	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:58:55.842418+02
9136	9	201	167124	156196	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:57.009912+02
9140	10	196	167132	152916	-71	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:09.263719+02
9142	10	201	167132	152916	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:14.281637+02
9149	9	527	157420	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:23.512419+02
9152	10	521	163656	150356	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:34.26065+02
9154	10	526	163656	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:39.926156+02
9156	9	550	163788	150296	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:46.16216+02
9166	10	562	167008	150356	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:15.449121+02
9168	10	567	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:20.454324+02
9174	10	582	167008	150356	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:35.614457+02
9176	10	587	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:40.668271+02
9182	10	602	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:55.814708+02
9184	10	607	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:00.914937+02
9190	10	622	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:16.063934+02
9192	10	627	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:21.092933+02
9198	10	643	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:36.224799+02
9200	10	648	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:41.3638+02
9459	10	1419	167112	148832	-66	RESPONSIVE	t	t	129.3	0	2026-05-12 01:54:46.408438+02
9460	9	1427	167120	148120	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:54:48.149027+02
9545	10	569	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:54.599504+02
9546	9	578	149388	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:58.695179+02
9553	10	590	167160	94560	-71	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:14.874771+02
9558	9	608	167148	77996	-52	STARTUP_PENDING	t	t	129.3	0	2026-05-12 02:39:28.991317+02
9574	10	35	167384	163024	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:25.223913+02
9579	9	52	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:37.99598+02
9627	9	322	166968	139924	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:45:07.749655+02
9629	9	329	166968	139924	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:45:14.71161+02
8458	9	191	170240	146764	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 21:01:30.242687+02
8463	9	22	170588	164216	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:02:40.796766+02
8464	9	27	170348	164216	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:02:45.814554+02
8466	9	46	170348	161556	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 21:03:04.861904+02
8467	9	53	170348	161556	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:03:12.233845+02
8475	9	112	170184	161392	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 21:04:10.909856+02
8480	9	157	170244	161392	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:04:55.761487+02
8485	9	254	164672	152468	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:06:33.961681+02
8486	9	262	165768	152468	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 21:06:40.824661+02
8498	9	351	165636	147912	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:10.220285+02
8499	9	359	162356	147912	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:17.798143+02
8500	9	366	165504	147912	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:25.068791+02
8501	9	373	165616	147912	-63	STARTUP_PENDING	t	t	129.3	0	2026-05-11 21:08:32.758774+02
8502	9	381	165504	147912	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:39.81487+02
8503	9	388	165492	147912	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:47.084701+02
8504	9	396	165504	147912	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:08:54.560126+02
8505	9	403	165504	147912	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:02.03549+02
8506	9	410	165504	147912	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:09.101103+02
8507	9	415	170076	147912	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:14.528116+02
8508	9	420	170076	147912	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:19.54602+02
8509	9	426	170076	147912	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:24.563614+02
8510	9	431	170076	147912	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:29.686557+02
8511	9	436	168516	147912	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:34.906012+02
8512	9	441	170076	147912	-57	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:39.718964+02
8513	9	446	170076	147912	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:44.838911+02
8514	9	451	170076	147912	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:49.856346+02
8515	9	456	170076	147912	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:54.874136+02
8516	9	461	170076	147912	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:09:59.994119+02
8517	9	466	170076	147912	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:10:05.008581+02
8518	9	471	170076	147912	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:10:10.029856+02
8519	9	476	170076	147912	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 21:10:15.149815+02
8520	9	481	170076	147912	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 21:10:20.477984+02
8521	9	36	170508	165920	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 21:23:53.931226+02
8522	9	41	170292	165920	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 21:23:58.984465+02
8523	9	46	170292	165920	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:24:04.083845+02
8524	9	51	170292	165920	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:24:09.101951+02
8525	9	56	170292	165920	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:24:14.221803+02
8526	9	61	170292	165920	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 21:24:19.239251+02
8527	9	71	167672	165040	-78	RESPONSIVE	t	t	129.3	0	2026-05-11 21:24:28.872935+02
8528	9	82	170292	164812	-69	RESPONSIVE	t	t	129.3	0	2026-05-11 21:24:39.238752+02
8529	9	89	170292	164812	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 21:24:46.785102+02
8530	9	97	170292	164812	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 21:24:54.567702+02
8531	9	105	170284	164812	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:02.349928+02
8532	9	112	170284	164812	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:09.953804+02
8533	9	120	170284	164812	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:17.252955+02
8534	9	127	170320	164812	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:24.985932+02
8535	9	135	170096	164812	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:32.763259+02
8536	9	143	170180	161280	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:40.412439+02
8537	9	150	170036	161280	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:47.983942+02
8538	9	158	170152	161280	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:25:55.481777+02
8539	9	166	170180	161280	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:26:03.483123+02
8540	9	173	170180	161280	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:26:11.179066+02
8541	9	265	161676	160180	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 21:27:42.48819+02
8542	9	273	159116	158672	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:27:50.799333+02
8543	9	280	165584	158672	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 21:27:58.06994+02
8544	9	288	165716	158420	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:05.749686+02
8545	9	295	165688	158420	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:13.02579+02
8546	9	303	165716	158420	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:20.863832+02
8547	9	311	165716	158420	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:28.790694+02
8548	9	319	165716	158420	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:36.470808+02
8549	9	326	160900	157388	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:43.996037+02
8550	9	331	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:48.967888+02
8551	9	336	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:53.980706+02
8552	9	341	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:28:59.00384+02
8553	9	346	170172	157388	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:04.118518+02
8554	9	351	170172	157388	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:09.136315+02
8555	9	356	170172	157388	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:14.1542+02
8556	9	362	170172	157388	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:19.273727+02
8557	9	367	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:24.29168+02
8558	9	372	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:29.411989+02
8559	9	377	170172	157388	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:34.429148+02
8560	9	382	170172	157388	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:39.43605+02
8561	9	387	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:44.567084+02
8562	9	392	170172	157388	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:49.791559+02
8563	9	397	170172	157388	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:54.595939+02
8564	9	402	170172	157388	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 21:29:59.721631+02
8565	9	407	170172	157388	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:30:04.739964+02
8566	9	412	170172	157388	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:30:09.859435+02
8567	9	417	170172	157388	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:30:14.877586+02
8568	9	422	170172	157388	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:30:19.895192+02
8569	9	46	166024	162456	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:15.211829+02
8570	9	51	170252	155892	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:20.265575+02
8571	9	56	170252	155892	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:25.313045+02
8572	9	61	170252	155892	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:30.396495+02
8573	9	66	170180	155892	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:35.516325+02
8574	9	71	170180	155892	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:40.533908+02
8575	9	76	170264	155892	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:45.551444+02
8576	9	82	170264	155892	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:50.670959+02
8577	9	87	170264	155892	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 21:38:55.68899+02
8590	9	60	170224	165868	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:39.423393+02
8601	9	201	165508	155036	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:00.22201+02
8603	9	216	165484	155036	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:15.582209+02
8605	9	231	165484	155036	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:30.634957+02
8610	9	269	169968	155036	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:09.137936+02
8615	9	308	170084	155036	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:47.539761+02
8620	9	51	170276	151216	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:00.182582+02
8623	9	66	170276	151216	-83	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:15.33752+02
8633	9	117	170276	151216	-80	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:05.787032+02
9120	10	133	163788	152916	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:06.59206+02
9122	10	138	163788	152916	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:12.328313+02
9124	9	163	167240	156196	-54	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:19.189302+02
9132	10	170	167120	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:43.95146+02
9133	10	175	167120	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:49.09743+02
9135	10	180	167120	152916	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 23:59:54.108041+02
9143	10	206	167132	152916	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:00:19.401516+02
9151	9	535	159196	150296	-55	POWERED_OFF	t	t	129.3	0	2026-05-12 00:05:31.212075+02
9158	9	558	163788	150296	-53	STARTUP_PENDING	t	t	129.3	0	2026-05-12 00:05:53.945176+02
9160	10	547	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:00.294101+02
9162	10	552	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:05.311737+02
9164	10	557	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:10.344082+02
9170	10	572	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:25.514762+02
9172	10	577	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:30.583254+02
9178	10	592	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:45.715746+02
9180	10	597	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:06:50.77743+02
9186	10	612	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:05.933118+02
9188	10	617	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:10.964707+02
9194	10	632	167008	150356	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:26.208197+02
9196	10	637	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:31.164962+02
9202	10	653	167008	150356	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:46.324996+02
9204	10	658	167008	150356	-66	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:51.384598+02
9206	10	663	167008	150356	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 00:07:56.51863+02
9461	9	2741	167112	148120	-44	POWERED_OFF	t	t	129.3	0	2026-05-12 02:16:42.870213+02
9462	10	2737	167116	148832	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 02:16:44.179087+02
9547	10	574	167160	94560	-71	POWERED_OFF	t	t	129.3	0	2026-05-12 02:38:59.616755+02
9548	9	583	156492	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:03.712889+02
9552	9	593	167148	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:13.850361+02
9557	10	600	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:24.908532+02
9562	9	618	167148	77996	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:39.148409+02
9569	9	27	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:12.731081+02
9584	10	60	167384	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:50.494069+02
9628	10	319	167016	146900	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 02:45:09.284519+02
9630	10	326	167016	146900	-73	RESPONSIVE	t	t	129.3	0	2026-05-12 02:45:16.247795+02
8578	9	92	170264	155892	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:39:00.706633+02
8581	9	7	189844	189708	-71	UNINITIALIZED	f	f	0.0	0	2026-05-11 21:39:47.383141+02
8582	9	19	170460	165868	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 21:39:58.984551+02
8585	9	35	170224	165868	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:14.230684+02
8591	9	68	170224	165868	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 21:40:47.995307+02
8597	9	170	165376	155036	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:42:29.70684+02
8602	9	208	165508	155036	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:08.005053+02
8604	9	224	165504	155036	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:23.262596+02
8609	9	262	170104	155036	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:01.306049+02
9207	9	7	190456	188208	-60	UNINITIALIZED	f	f	0.0	0	2026-05-12 00:33:55.471024+02
9209	9	19	167584	162996	-60	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:07.451797+02
9211	9	24	167356	162996	-60	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:12.437951+02
9218	9	49	167356	161600	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:37.762461+02
9220	9	54	167356	161600	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:42.78187+02
9226	10	35	167364	162992	-77	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:14.318975+02
9228	10	40	167364	162992	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:19.330354+02
9230	10	45	167364	162992	-73	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:24.380006+02
9231	9	28	167380	163016	-56	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:25.424562+02
9233	9	33	167380	163016	-58	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:30.498248+02
9234	9	99	159464	155620	-57	RESPONSIVE	t	t	129.3	0	2026-05-12 00:36:36.261031+02
9236	10	127	163792	152888	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 00:36:46.37767+02
9238	10	135	163792	152888	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 00:36:54.364877+02
9244	9	142	167140	152896	-57	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:19.247927+02
9245	10	166	166992	152888	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:26.007484+02
9463	10	2752	167116	148832	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 02:16:59.330225+02
9464	9	2762	167112	148120	-45	POWERED_OFF	t	t	129.3	0	2026-05-12 02:17:03.155677+02
9465	10	2757	167116	148832	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 02:17:04.482295+02
9466	9	2767	167112	148120	-45	POWERED_OFF	t	t	129.3	0	2026-05-12 02:17:08.168781+02
9467	10	2762	167116	148832	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 02:17:09.499681+02
9468	9	2772	167112	148120	-45	POWERED_OFF	t	t	129.3	0	2026-05-12 02:17:13.227947+02
9550	9	588	167148	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:08.833036+02
9568	10	20	167612	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:10.023654+02
9578	10	45	167384	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:35.313512+02
9583	9	62	167344	162972	-54	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:48.161715+02
9631	10	397	162692	146900	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 02:46:27.787197+02
9632	9	403	162640	139924	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 02:46:28.86419+02
8579	9	97	170264	155892	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 21:39:05.824637+02
8584	9	30	170224	165868	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:09.110712+02
8587	9	45	170224	165868	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:24.367775+02
8592	9	77	170224	164536	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 21:40:57.039309+02
8593	9	88	170204	163732	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 21:41:07.643404+02
8595	9	155	162312	155036	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:42:14.569561+02
8599	9	186	163944	155036	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 21:42:48.343576+02
8608	9	254	170104	155036	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:53.865266+02
8612	9	285	169952	155036	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:24.70288+02
8614	9	300	170084	155036	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:39.653882+02
9208	10	8	190464	188224	-75	UNINITIALIZED	f	f	0.0	0	2026-05-12 00:33:58.834144+02
9210	10	20	167624	163024	-73	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:10.848448+02
9213	9	29	167348	161600	-60	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:17.5893+02
9215	9	34	167356	161600	-58	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:22.607198+02
9219	10	3	190452	188204	-72	UNINITIALIZED	f	f	0.0	0	2026-05-12 00:34:42.138334+02
9221	10	14	167600	162992	-83	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:54.145991+02
9222	10	20	167364	162992	-74	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:59.163645+02
9232	10	50	167364	162992	-79	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:29.474508+02
9235	10	119	159296	152888	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 00:36:38.520643+02
9240	10	143	163652	152888	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:02.454564+02
9243	10	158	166992	152888	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:18.019313+02
9246	9	152	167140	152896	-60	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:29.820214+02
9248	9	163	167140	152896	-60	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:40.581563+02
9469	9	2824	162524	148120	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:05.5139+02
9470	10	2819	162524	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:06.592397+02
9472	10	2826	166984	148832	-68	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:13.603299+02
9474	10	2833	166980	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:20.668157+02
9476	10	2840	166984	148832	-69	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:27.587967+02
9477	9	2852	167112	148120	-44	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:33.468979+02
9479	9	2859	167112	148120	-44	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:40.534175+02
9551	10	585	167160	94560	-72	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:09.75433+02
9556	9	603	167148	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:23.931152+02
9561	10	610	167160	94560	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:35.047672+02
9572	10	30	167384	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:20.206559+02
9582	10	55	167384	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:45.433588+02
9587	9	73	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:58.459303+02
9633	10	404	167028	145056	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 02:46:34.86431+02
8580	9	112	170264	155892	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 21:39:20.98694+02
8583	9	24	170224	165868	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:04.036505+02
8586	9	40	170224	165868	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:19.277778+02
8589	9	55	170224	165868	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:34.384936+02
8594	9	96	170224	163732	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:41:15.46645+02
8596	9	162	162172	155036	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:42:21.924104+02
9212	10	25	167388	163024	-74	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:15.848792+02
9214	10	30	167388	163024	-74	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:20.9679+02
9216	9	39	167356	161600	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:27.624378+02
9217	9	44	167356	161600	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 00:34:32.744549+02
9223	9	6	190464	188224	-56	UNINITIALIZED	f	f	0.0	0	2026-05-12 00:35:03.390625+02
9224	10	25	167364	162992	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:04.181295+02
9225	10	30	167364	162992	-78	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:09.30157+02
9227	9	18	167616	163016	-57	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:15.342997+02
9229	9	23	167380	163016	-57	POWERED_OFF	t	t	129.3	0	2026-05-12 00:35:20.364837+02
9237	9	109	167376	152896	-57	RESPONSIVE	t	t	129.3	0	2026-05-12 00:36:47.196984+02
9239	9	120	167248	152896	-56	RESPONSIVE	t	t	129.3	0	2026-05-12 00:36:57.612025+02
9241	9	131	167140	152896	-57	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:08.393854+02
9242	10	151	166992	152888	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:10.134956+02
9247	10	174	166992	152888	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 00:37:33.774311+02
9471	9	2831	167112	148120	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:12.476308+02
9473	9	2838	167112	148120	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:19.455731+02
9475	9	2845	167112	148120	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:26.505106+02
9554	9	598	167148	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:18.870932+02
9570	10	25	167384	163024	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:15.188295+02
9575	9	42	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:27.988795+02
9585	9	68	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:53.281638+02
9634	9	410	167096	139924	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:46:35.899795+02
8588	9	50	170224	165868	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 21:40:29.38573+02
8598	9	178	165508	155036	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 21:42:37.48929+02
8600	9	193	165504	155036	-80	POWERED_OFF	t	t	129.3	0	2026-05-11 21:42:52.64408+02
8606	9	239	163624	155036	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:38.885905+02
8607	9	247	170104	155036	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 21:43:46.200601+02
8611	9	277	169952	155036	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:17.033972+02
8613	9	293	170084	155036	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:32.280648+02
8616	9	316	170084	155036	-79	POWERED_OFF	t	t	129.3	0	2026-05-11 21:44:55.285733+02
8617	9	36	166052	160804	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:51:45.032063+02
8618	9	41	170276	151216	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 21:51:49.984651+02
8619	9	46	170276	151216	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:51:55.030497+02
8621	9	56	170276	151216	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:05.139725+02
8622	9	61	170276	151216	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:10.217526+02
8624	9	71	170276	151216	-83	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:20.355721+02
8625	9	76	170276	151216	-90	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:25.373651+02
8626	9	81	170276	151216	-83	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:30.493379+02
8627	9	86	170276	151216	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:35.624102+02
8628	9	91	170276	151216	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:40.528599+02
8629	9	96	170276	151216	-93	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:45.648884+02
8630	9	101	170276	151216	-87	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:50.66651+02
8631	9	107	170276	151216	-86	POWERED_OFF	t	t	129.3	0	2026-05-11 21:52:55.683862+02
8632	9	112	170276	151216	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:00.701699+02
8634	9	122	170304	151216	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:10.839277+02
8635	9	127	170296	151216	-79	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:15.95894+02
8636	9	132	170296	151216	-84	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:20.92106+02
8637	9	137	170296	151216	-83	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:25.9944+02
8638	9	142	170296	151216	-84	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:31.114155+02
8639	9	147	170296	151216	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:36.131965+02
8640	9	152	170296	151216	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:41.149348+02
8641	9	157	170296	151216	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:46.272853+02
8642	9	162	170296	151216	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:51.287158+02
8643	9	167	170296	151216	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 21:53:56.407305+02
8644	9	172	170296	151216	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 21:54:01.425023+02
8645	9	177	170296	151216	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 21:54:06.400803+02
8646	9	182	170296	151216	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 21:54:11.473019+02
8647	9	187	170296	151216	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:54:16.580648+02
8648	9	192	170296	151216	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 21:54:21.582481+02
8649	9	12	191636	191052	-71	UNINITIALIZED	f	f	0.0	0	2026-05-11 22:11:05.713555+02
8650	9	24	170460	165860	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:17.627695+02
8651	9	29	170228	165860	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:22.739686+02
8652	9	34	170228	165860	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:27.757902+02
8653	9	39	170228	165072	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:32.774851+02
8654	9	44	170228	165072	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:37.895121+02
8655	9	49	170228	165072	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:42.879187+02
8656	9	54	170228	165072	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:47.924683+02
8657	9	59	170228	165072	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:53.055384+02
8658	9	64	170228	165072	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:11:58.067908+02
8659	9	69	170228	165072	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:03.085275+02
8660	9	74	170228	165072	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:08.2064+02
8661	9	79	170228	165072	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:13.172861+02
8662	9	84	170228	165072	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:18.241027+02
8663	9	94	167456	165072	-67	RESPONSIVE	t	t	129.3	0	2026-05-11 22:12:28.481194+02
8664	9	102	170228	164232	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:35.57272+02
8665	9	109	170228	159772	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:43.227155+02
8666	9	117	170228	159772	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:51.047836+02
8667	9	125	170248	159772	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 22:12:58.894348+02
8668	9	194	163788	157020	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:08.610987+02
8669	9	202	165512	157020	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:16.002172+02
8670	9	210	165216	157020	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:23.47768+02
8671	9	217	165536	157020	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:31.259697+02
8672	9	225	165512	157020	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:38.939575+02
8673	9	233	165536	157020	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:46.72197+02
8674	9	241	165536	157020	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:14:54.504808+02
8675	9	248	165216	157020	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:01.672526+02
8676	9	256	165536	156388	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:09.455996+02
8677	9	263	165536	156388	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:17.237863+02
8678	9	270	168008	156388	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:23.996102+02
8679	9	275	170116	156388	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:28.80924+02
8680	9	280	170116	156388	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:33.758234+02
8681	9	285	170116	156388	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:38.844195+02
8682	9	290	170116	156388	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:43.964471+02
8683	9	295	170116	156388	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:48.987177+02
8684	9	300	170116	156388	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:53.999526+02
8685	9	305	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:15:59.120125+02
8686	9	310	170116	156388	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:04.094294+02
8687	9	315	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:09.155125+02
8688	9	320	170116	156388	-82	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:14.275033+02
8689	9	326	170116	156388	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:19.292965+02
8690	9	331	170116	156388	-85	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:24.4126+02
8691	9	336	170116	156388	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:29.430947+02
8692	9	341	170116	156388	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:34.448021+02
8693	9	346	170116	156388	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:39.567551+02
8694	9	351	170116	156388	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:44.585331+02
8695	9	356	170116	156388	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:49.603747+02
8696	9	361	170116	156388	-79	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:54.723522+02
8697	9	366	170116	156388	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 22:16:59.741508+02
8698	9	371	170116	156388	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:04.861486+02
8699	9	376	170116	156388	-76	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:09.878415+02
8700	9	381	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:14.896306+02
8706	9	411	170116	156388	-81	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:45.207125+02
8707	9	417	170116	156388	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:50.327275+02
8712	9	442	170116	156388	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:15.517694+02
8713	9	447	170116	156388	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:20.637514+02
8716	9	47	166004	162396	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:01.007087+02
8717	9	52	168596	156336	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:06.056683+02
8723	9	82	169956	156336	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:36.398412+02
8726	9	97	169956	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:51.639355+02
8736	9	148	169988	156336	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:42.12307+02
8745	9	277	163528	156336	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:32:51.981262+02
8760	9	391	169948	156336	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:45.837071+02
9249	9	6	190444	188204	-60	UNINITIALIZED	f	f	0.0	0	2026-05-12 01:09:50.661914+02
9250	10	6	190468	186924	-70	UNINITIALIZED	f	f	0.0	0	2026-05-12 01:09:53.294147+02
9251	9	18	167456	154112	-60	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:02.683857+02
9253	9	28	167228	154112	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:12.821536+02
9255	10	36	167488	148324	-80	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:23.317095+02
9257	10	41	167228	148324	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:28.394069+02
9259	10	46	167228	148324	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:33.404472+02
9261	10	53	167228	148324	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:40.432621+02
9263	10	60	167228	148324	-71	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:47.082737+02
9265	9	68	167228	154112	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:52.348368+02
9267	9	73	167228	154112	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:57.3253+02
9269	10	78	167228	148324	-68	POWERED_OFF	f	t	129.3	263	2026-05-12 01:11:04.952433+02
9271	10	86	167228	148324	-74	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:13.532798+02
9273	10	93	167228	148324	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:20.482779+02
9275	10	102	167228	148324	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:29.212875+02
9276	9	111	167228	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:36.175958+02
9282	10	173	167116	144804	-80	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:40.502638+02
9285	9	187	167120	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:51.542958+02
9287	9	197	167120	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:02.040174+02
9290	9	208	166988	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:12.84213+02
9292	9	219	166988	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:23.49187+02
9294	9	229	166988	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:34.141842+02
9296	10	235	167096	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:42.753379+02
9298	10	243	167096	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:50.540792+02
9300	10	251	167104	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:58.308333+02
9302	10	259	167104	144804	-80	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:05.900253+02
9478	10	2847	166984	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:18:34.587655+02
9555	10	595	167160	94560	-70	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:19.892035+02
9560	9	613	167148	77996	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:34.075599+02
9566	10	8	188800	186856	-75	UNINITIALIZED	f	f	0.0	0	2026-05-12 02:39:58.120586+02
9576	10	40	167384	163024	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:30.344253+02
9586	10	65	167384	163024	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:55.61184+02
9635	10	411	167028	145056	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 02:46:41.854779+02
8701	9	386	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:20.016397+02
8702	9	391	170116	156388	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:25.039153+02
8708	9	422	170116	156388	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:55.344577+02
8709	9	427	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:00.370655+02
8714	9	452	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:25.655662+02
8715	9	457	170116	156388	-87	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:30.669325+02
8718	9	57	169960	156336	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:11.116891+02
8725	9	92	169956	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:46.519336+02
8728	9	107	169956	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:01.890591+02
8731	9	122	169984	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:16.932311+02
9252	9	23	167228	154112	-60	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:07.701542+02
9254	9	33	167228	154112	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:17.775348+02
9256	9	40	167228	154112	-58	UNKNOWN	t	t	129.3	0	2026-05-12 01:10:24.992273+02
9258	9	47	165660	154112	-49	UNKNOWN	t	t	129.3	0	2026-05-12 01:10:32.072573+02
9260	9	52	167228	154112	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:37.192791+02
9262	9	57	167228	154112	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:42.210288+02
9264	9	62	167228	154112	-49	POWERED_OFF	t	t	129.3	0	2026-05-12 01:10:47.214708+02
9266	10	69	167228	148324	-66	POWERED_OFF	f	t	129.3	263	2026-05-12 01:10:56.804658+02
9268	9	78	167228	154112	-49	POWERED_OFF	t	t	129.3	0	2026-05-12 01:11:02.486016+02
9270	9	83	167228	154112	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:11:07.503326+02
9272	9	91	167228	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:16.002807+02
9274	9	101	167228	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:25.730776+02
9277	10	110	167096	148324	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:11:37.102179+02
9278	9	155	162660	154112	-49	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:19.624948+02
9279	10	158	157520	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:24.849836+02
9280	9	165	162536	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:30.011829+02
9281	10	165	167248	144804	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:32.833444+02
9283	9	176	167120	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:40.664375+02
9284	10	181	167104	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:48.266113+02
9286	10	189	167104	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:12:56.21234+02
9288	10	197	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:04.035639+02
9289	10	204	167104	144804	-80	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:11.613493+02
9291	10	212	167096	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:19.500559+02
9293	10	220	167096	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:27.384716+02
9295	10	228	167096	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:34.96091+02
9297	9	240	166988	154112	-52	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:44.483887+02
9299	9	250	166988	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:13:55.173144+02
9301	9	261	166988	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:05.885406+02
9480	9	2888	167132	148120	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 02:19:09.821205+02
9481	10	2883	162524	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:19:10.12931+02
9483	10	2890	166980	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:19:17.096024+02
9563	10	615	167160	94560	-69	POWERED_OFF	t	t	129.3	0	2026-05-12 02:39:40.167517+02
9571	9	32	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:17.851081+02
9581	9	57	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:43.149099+02
9636	9	417	167096	139924	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:46:42.878834+02
8703	9	396	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:30.051962+02
8704	9	401	170116	156388	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:35.171832+02
8705	9	406	168556	156388	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 22:17:40.308831+02
8710	9	432	170116	156388	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:05.48258+02
8711	9	437	170116	156388	-72	POWERED_OFF	t	t	129.3	0	2026-05-11 22:18:10.492803+02
8719	9	62	169960	156336	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:16.21631+02
8720	9	67	169960	156336	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:21.226096+02
8721	9	72	169952	156336	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:26.346248+02
8722	9	77	169952	156336	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:31.32654+02
8724	9	87	169956	156336	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:41.501748+02
8727	9	102	169956	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:29:56.656825+02
8729	9	112	169956	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:06.729193+02
8730	9	117	169956	156336	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:11.775788+02
8732	9	127	169984	156336	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:21.949937+02
8733	9	133	169984	156336	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:26.972542+02
8734	9	138	169984	156336	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:32.08777+02
8735	9	143	169984	156336	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:37.212013+02
8737	9	153	169988	156336	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 22:30:47.243057+02
8738	9	165	169988	156336	-67	RESPONSIVE	t	t	129.3	0	2026-05-11 22:30:59.184094+02
8739	9	172	169988	156336	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:31:06.593315+02
8740	9	180	169660	156336	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:31:14.482303+02
8741	9	188	169980	156336	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 22:31:22.366395+02
8742	9	254	161928	156336	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 22:32:28.878777+02
8743	9	262	165056	156336	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:32:36.541174+02
8744	9	270	165408	156336	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 22:32:44.287676+02
8746	9	285	165404	156336	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:32:59.340081+02
8747	9	293	165404	156336	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:07.025508+02
8748	9	300	165404	156336	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:14.59759+02
8749	9	308	165404	156336	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:22.278335+02
8750	9	315	165088	156336	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:29.650882+02
8751	9	323	165400	156336	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:37.331058+02
8752	9	331	165536	156336	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:45.113017+02
8753	9	338	163844	156336	-67	POWERED_OFF	t	t	129.3	0	2026-05-11 22:33:52.793446+02
8754	9	346	165536	156336	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:00.063976+02
8755	9	353	170112	156336	-68	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:07.64161+02
8756	9	361	170112	156336	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:15.424174+02
8757	9	369	169980	156336	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:23.104358+02
8758	9	376	169968	156336	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:30.682299+02
8759	9	384	169980	156336	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:38.157246+02
8761	9	399	169968	156336	-75	POWERED_OFF	t	t	129.3	0	2026-05-11 22:34:53.619608+02
8762	9	34	166924	150640	-66	POWERED_OFF	t	t	129.3	0	2026-05-11 22:44:49.091807+02
8763	9	39	169932	150640	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:44:54.201191+02
8764	9	44	169932	150640	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:44:59.159191+02
8765	9	49	169932	150640	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:04.236429+02
8766	9	54	169932	150640	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:09.260063+02
8767	9	59	169932	150640	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:14.315839+02
8768	9	64	169932	150640	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:19.391359+02
8769	9	69	169932	150640	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:24.511853+02
8770	9	74	169932	150640	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:29.529678+02
8771	9	84	169932	150640	-73	RESPONSIVE	t	t	129.3	0	2026-05-11 22:45:39.768957+02
8772	9	92	169932	150640	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:45:47.643334+02
8773	9	196	162316	150640	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:47:31.886977+02
8774	9	204	162188	150640	-77	STARTUP_PENDING	t	t	129.3	0	2026-05-11 22:47:39.78295+02
8775	9	212	158624	150640	-73	POWERED_OFF	t	t	129.3	0	2026-05-11 22:47:47.770365+02
8776	9	220	162188	150640	-78	POWERED_OFF	t	t	129.3	0	2026-05-11 22:47:55.143234+02
8777	9	227	162188	150640	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:02.685643+02
8778	9	235	165388	150640	-77	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:10.321703+02
8779	9	243	162260	150640	-79	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:18.183487+02
8780	9	250	163828	150640	-74	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:26.068366+02
8781	9	258	165388	150640	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:33.217512+02
8782	9	265	165388	150640	-73	STARTUP_PENDING	t	t	129.3	0	2026-05-11 22:48:40.506837+02
8783	9	273	165388	150640	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:48.288775+02
8784	9	280	162128	150640	-71	POWERED_OFF	t	t	129.3	0	2026-05-11 22:48:56.276781+02
8785	9	288	165388	150640	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:49:03.547056+02
8786	9	296	165392	150640	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:49:12.802527+02
8787	9	303	163488	150640	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:49:18.918985+02
8788	9	311	169980	150640	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:49:26.436434+02
8789	9	316	168296	150640	-70	POWERED_OFF	t	t	129.3	0	2026-05-11 22:49:31.817529+02
8790	9	321	169980	150640	-69	POWERED_OFF	t	t	129.3	0	2026-05-11 22:49:37.106746+02
8791	9	327	169980	150640	-83	STARTUP_PENDING	t	t	129.3	0	2026-05-11 22:49:41.947188+02
8792	9	10	189832	189688	-63	UNINITIALIZED	f	f	0.0	0	2026-05-11 22:55:36.130947+02
8793	10	11	193300	191052	-61	UNINITIALIZED	f	f	0.0	0	2026-05-11 22:55:38.140303+02
8794	10	23	170448	165848	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:55:50.079112+02
8795	10	28	168644	165848	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:55:55.199306+02
8796	10	33	170212	165172	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:56:00.216084+02
8797	10	39	170212	165172	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:56:05.234674+02
8798	10	44	170212	165172	-65	POWERED_OFF	t	t	129.3	0	2026-05-11 22:56:10.31875+02
8799	10	49	170212	165172	-64	POWERED_OFF	t	t	129.3	0	2026-05-11 22:56:15.37232+02
8800	10	54	170212	165172	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:56:20.370127+02
8801	10	59	170212	165172	-63	POWERED_OFF	t	t	129.3	0	2026-05-11 22:56:25.509782+02
8802	10	67	170212	165172	-60	RESPONSIVE	t	t	129.3	0	2026-05-11 22:56:34.009269+02
8803	10	74	170212	165172	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 22:56:41.074857+02
8804	10	81	170212	165172	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 22:56:48.037837+02
8805	10	88	170212	165172	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 22:56:55.112798+02
8806	10	95	170212	164988	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:02.066784+02
8807	10	102	170212	164988	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:09.03508+02
8808	10	109	170212	164988	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:16.0959+02
8809	9	29	170452	165864	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 22:57:20.805903+02
8810	10	116	170212	164988	-60	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:23.020739+02
8823	9	132	161892	158496	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:03.960113+02
8825	10	227	165492	155004	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:13.549876+02
8827	10	235	165496	155004	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:21.434956+02
8833	9	174	165680	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:46.010807+02
8836	10	273	165508	155004	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:00.361062+02
8880	10	447	170100	154676	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:53.193514+02
8886	10	462	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:08.355193+02
8893	9	394	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:25.699275+02
8903	9	419	169864	153432	-46	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:50.953855+02
8909	9	435	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:06.109825+02
8919	9	460	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:31.40215+02
9303	10	266	167104	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:13.463495+02
9305	10	273	167104	144804	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:21.928075+02
9307	10	280	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:27.392725+02
9309	9	293	166988	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:38.039617+02
9311	9	304	166988	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:48.382209+02
9313	10	308	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:55.44813+02
9315	10	315	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:02.411351+02
9317	9	325	166988	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:09.784403+02
9319	9	335	166988	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:20.229152+02
9321	10	343	167104	144804	-80	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:30.393461+02
9323	10	350	167104	144804	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:37.393341+02
9325	10	357	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:44.498191+02
9327	10	364	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:51.461286+02
9329	10	371	167104	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:58.426865+02
9331	10	378	167104	144804	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:05.490199+02
9333	10	385	167104	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:12.453838+02
9335	10	392	167276	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:19.416872+02
9337	10	399	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:26.467727+02
9339	10	406	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:33.446032+02
9341	10	413	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:40.408766+02
9343	10	420	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:47.474399+02
9345	10	427	167104	144804	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:54.437749+02
9347	10	434	167104	144804	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 01:17:01.403865+02
9349	10	441	167104	144804	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:17:08.466767+02
9353	9	14	190448	187296	-51	UNINITIALIZED	f	f	0.0	0	2026-05-12 01:20:46.43184+02
9354	10	19	167584	162996	-81	POWERED_OFF	t	t	129.3	0	2026-05-12 01:20:55.570077+02
9356	10	25	167352	162996	-82	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:00.610077+02
9358	10	30	167352	162996	-82	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:05.627765+02
9360	10	35	167352	162996	-81	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:10.678174+02
9362	10	40	167352	162996	-79	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:15.751089+02
9364	10	45	167352	162996	-81	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:20.885243+02
9366	10	50	167352	162996	-79	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:25.903204+02
9368	10	55	167352	162996	-81	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:30.920868+02
9370	10	60	167352	162996	-79	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:36.04089+02
9372	10	65	165788	162996	-81	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:41.16085+02
9374	10	70	167352	162304	-79	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:46.075937+02
9376	10	75	167352	162304	-81	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:51.195919+02
9378	10	80	167352	162304	-82	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:56.352917+02
9379	10	48	167676	161928	-65	POWERED_OFF	t	t	129.3	0	2026-05-12 01:30:57.011309+02
9383	10	17	167600	163008	-63	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:24.231955+02
9385	10	22	167360	163008	-66	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:29.301401+02
9387	10	27	167360	163008	-65	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:34.677075+02
9389	10	32	167360	163008	-68	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:39.694858+02
9392	9	44	167372	162420	-47	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:45.126472+02
9394	9	49	167372	162420	-47	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:50.242382+02
9396	9	54	167372	162420	-46	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:55.564581+02
9397	10	106	155944	154160	-67	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:32:53.618832+02
9398	9	114	163776	152240	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:32:55.84964+02
9400	9	121	167164	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:02.864493+02
9402	9	128	167140	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:09.864309+02
9404	9	135	167140	152240	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:16.853699+02
9406	9	142	167140	152240	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:23.938658+02
9408	9	149	167140	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:30.901869+02
9410	9	156	167140	152240	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:37.848919+02
9412	9	163	167140	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:44.930662+02
9414	9	170	167140	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:51.894227+02
9416	9	177	167140	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:33:58.856403+02
9418	9	184	167140	152240	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:34:05.922809+02
9482	9	2895	167132	148120	-44	RESPONSIVE	t	t	129.3	0	2026-05-12 02:19:16.753591+02
9484	9	2902	167132	148120	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 02:19:23.849388+02
9565	9	8	190440	188192	-53	UNINITIALIZED	f	f	0.0	0	2026-05-12 02:39:53.746727+02
9573	9	37	167344	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:40:22.826364+02
9637	9	446	166964	139924	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:47:11.449766+02
9639	9	453	166964	139924	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 02:47:18.516646+02
8811	9	38	170224	165864	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:29.305589+02
8826	9	143	160656	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:15.497036+02
8830	9	164	165680	153432	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:35.169475+02
8832	10	258	165508	155004	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:44.885296+02
8834	10	266	165508	155004	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:52.667548+02
8838	10	281	163944	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:08.571849+02
8840	9	206	165548	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:17.140854+02
8843	10	305	165204	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:31.476605+02
8846	10	320	168536	154676	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:47.349019+02
8852	9	258	169864	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:09.672862+02
8854	9	268	169864	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:20.117618+02
8856	10	363	170100	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:29.948071+02
8862	9	300	169864	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:51.349643+02
8864	9	310	169864	153432	-47	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:01.999682+02
8866	10	405	170100	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:11.946616+02
8872	10	426	170100	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:33.031769+02
8878	10	441	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:48.143628+02
8888	10	467	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:13.475111+02
8898	10	492	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:38.665926+02
8904	10	507	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:53.934768+02
8914	10	532	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:19.114414+02
9304	9	272	166988	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:16.433466+02
9306	9	283	166988	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:27.243128+02
9308	10	287	167104	144804	-80	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:34.4558+02
9310	10	294	167104	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:41.419133+02
9312	10	301	167104	144804	-78	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:48.39193+02
9314	9	314	166988	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:14:59.139407+02
9316	10	322	167104	144804	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:09.392833+02
9318	10	329	167104	144804	-79	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:16.440327+02
9320	10	336	167104	144804	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:23.580649+02
9322	9	346	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:30.841534+02
9324	9	353	165296	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:37.846161+02
9326	9	360	166856	154112	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:44.841068+02
9328	9	367	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:51.865362+02
9330	9	374	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:15:58.864736+02
9332	9	381	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:05.864684+02
9334	9	388	166884	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:12.874833+02
9336	9	395	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:19.928921+02
9338	9	402	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:26.892305+02
9340	9	409	166856	154112	-49	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:33.956951+02
9342	9	416	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:40.864776+02
9344	9	423	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:47.884181+02
9346	9	430	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:16:54.950144+02
9348	9	437	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:17:01.913652+02
9350	9	444	166856	154112	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 01:17:08.876417+02
9351	10	644	149964	144804	-74	RESPONSIVE	t	t	129.3	0	2026-05-12 01:20:31.395673+02
9352	10	8	190444	186904	-81	UNINITIALIZED	f	f	0.0	0	2026-05-12 01:20:43.587188+02
9355	9	26	167468	151876	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 01:20:58.45987+02
9357	9	31	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:03.47755+02
9359	9	36	167220	151876	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:08.468056+02
9361	9	41	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:13.517967+02
9363	9	46	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:18.567647+02
9365	9	51	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:23.650029+02
9367	9	57	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:28.667702+02
9369	9	62	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:33.788114+02
9371	9	67	167220	151876	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:38.80583+02
9373	9	72	167220	151876	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:43.864396+02
9375	9	77	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:48.943364+02
9377	9	82	167220	151876	-50	POWERED_OFF	t	t	129.3	0	2026-05-12 01:21:53.947704+02
9380	10	53	167420	161928	-63	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:02.071345+02
9381	9	7	190456	188208	-47	UNINITIALIZED	f	f	0.0	0	2026-05-12 01:31:08.76025+02
9382	10	5	190448	188208	-66	UNINITIALIZED	f	f	0.0	0	2026-05-12 01:31:12.306468+02
9384	9	23	167696	163004	-46	UNKNOWN	t	t	129.3	0	2026-05-12 01:31:24.845727+02
9386	9	28	167372	162420	-47	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:30.079427+02
9388	9	34	167372	162420	-46	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:35.091002+02
9390	9	39	167372	162420	-45	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:40.1039+02
9391	10	37	167360	163008	-66	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:44.712687+02
9393	10	43	167360	163008	-66	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:49.832179+02
9395	10	48	167360	163008	-66	POWERED_OFF	t	t	129.3	0	2026-05-12 01:31:54.849291+02
9399	10	113	163892	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:00.620012+02
9401	10	120	167248	150920	-67	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:07.657607+02
9403	10	127	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:14.722418+02
9405	10	134	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:21.685807+02
9407	10	141	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:28.649526+02
9409	10	148	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:35.71492+02
9411	10	155	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:42.678195+02
9413	10	162	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:49.641181+02
9415	10	169	167248	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:33:56.707112+02
9417	10	176	167248	150920	-67	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:34:03.670348+02
9419	10	183	167248	150920	-67	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:34:10.62+02
9485	10	2897	166980	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:19:24.029145+02
9588	9	83	167332	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:08.438702+02
9589	10	80	167384	163024	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:10.793+02
9590	9	88	167332	162972	-52	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:13.455379+02
9591	10	85	167384	163024	-76	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:15.810758+02
9592	9	93	167332	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:18.473047+02
9593	10	90	167384	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:20.834467+02
9594	9	98	167332	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:23.550179+02
8812	10	123	170240	164988	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:30.124872+02
8816	9	59	170092	164824	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:50.334822+02
8820	10	163	168540	161448	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 22:58:10.266358+02
8839	10	289	165508	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:15.955179+02
8867	9	321	169864	153432	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:12.422558+02
8869	9	330	169864	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:21.148033+02
8877	9	354	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:45.398689+02
8883	9	369	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:00.470261+02
8887	9	379	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:10.543485+02
8894	10	482	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:28.553923+02
8900	10	497	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:43.695464+02
8910	10	522	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:08.981275+02
8916	10	537	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:24.131929+02
9420	10	233	160368	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:34:59.742091+02
9424	10	247	167116	150920	-65	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:35:13.815558+02
9486	9	2960	162532	148120	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:21.098203+02
9487	10	2954	162528	148832	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:21.129057+02
9498	9	3000	167112	147160	-79	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:01.179931+02
9499	10	2996	167128	142808	-69	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:03.287199+02
9508	10	3024	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:31.138966+02
9514	10	3059	167128	142808	-71	RESPONSIVE	t	t	129.3	0	2026-05-12 02:22:06.139433+02
9595	10	95	167384	163024	-75	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:25.884151+02
9597	10	101	167384	163024	-73	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:30.965782+02
9599	10	106	167384	163024	-77	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:35.995348+02
9601	9	119	167332	162972	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 02:41:44.482643+02
9603	9	126	167352	162972	-49	RESPONSIVE	t	t	129.3	0	2026-05-12 02:41:51.445823+02
9604	10	127	167272	161576	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 02:41:57.436924+02
9638	10	447	167148	145056	-73	RESPONSIVE	t	t	129.3	0	2026-05-12 02:47:17.592948+02
8813	10	132	170240	161476	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:38.317015+02
8817	10	147	170240	161448	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:54.013098+02
8819	10	156	170108	161448	-66	RESPONSIVE	t	t	129.3	0	2026-05-11 22:58:02.512493+02
8821	9	80	170092	161308	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 22:58:11.494745+02
8831	10	250	165204	155004	-65	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:36.913005+02
8841	10	297	165508	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:23.592124+02
8848	10	328	170100	154676	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:54.619744+02
8858	10	370	168536	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:37.016828+02
8868	10	412	170100	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:18.942544+02
8876	10	436	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:43.094401+02
8882	10	452	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:58.290637+02
8892	10	477	170100	154676	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:23.510571+02
8902	10	502	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:48.743685+02
8908	10	517	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:03.959179+02
8918	10	542	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:29.252424+02
9421	9	241	167136	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:35:02.419124+02
9422	10	240	167116	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:35:06.751738+02
9423	9	248	167136	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:35:09.514571+02
9425	9	255	167136	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:35:16.477849+02
9488	9	2967	167112	147160	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:28.055379+02
9492	9	2981	167112	147160	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:42.083899+02
9493	10	2975	165568	142808	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:42.226194+02
9494	9	2988	167112	147160	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:49.15474+02
9500	9	3005	165564	147160	-60	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:06.557775+02
9501	10	3003	167128	142808	-68	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:10.14177+02
9502	9	3010	167112	147160	-64	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:11.370141+02
9510	10	3031	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:38.200028+02
9512	10	3045	167128	142808	-69	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:52.228046+02
9596	9	103	167332	162972	-53	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:28.71329+02
9598	9	110	167332	162972	-50	UNKNOWN	t	t	129.3	0	2026-05-12 02:41:35.881413+02
9600	10	111	167384	163024	-80	POWERED_OFF	t	t	129.3	0	2026-05-12 02:41:41.108342+02
9602	10	118	167384	163024	-66	UNKNOWN	t	t	129.3	0	2026-05-12 02:41:48.271458+02
9605	9	133	167220	162788	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:41:59.130833+02
9607	9	140	167220	162788	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 02:42:06.089271+02
9608	10	141	167272	161576	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 02:42:11.51607+02
9640	10	504	153536	145056	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 02:48:14.357049+02
9641	9	512	160264	139924	-51	RESPONSIVE	t	t	129.3	0	2026-05-12 02:48:17.281419+02
8814	9	49	170224	164824	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:40.262551+02
8822	10	171	170108	161448	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 22:58:18.048436+02
8824	10	219	163864	160056	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:05.566233+02
8835	9	185	165680	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:56.353129+02
8837	9	195	162108	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:06.798097+02
8844	9	227	169996	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:38.150178+02
8853	10	349	170100	154676	-59	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:16.021505+02
8863	10	391	170100	154676	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:58.00582+02
8881	9	364	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:55.384444+02
8891	9	389	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:20.718077+02
8897	9	404	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:35.901247+02
8907	9	429	169864	153432	-49	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:01.091777+02
8913	9	445	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:16.247219+02
8920	10	548	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:34.269549+02
9426	10	254	167116	150920	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:35:20.778734+02
9489	10	2961	167128	142808	-66	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:28.128764+02
9497	10	2989	167128	142808	-64	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:56.128943+02
9503	9	3015	167112	147160	-66	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:16.387807+02
9505	9	3020	167112	147160	-65	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:21.405463+02
9506	10	3017	167128	142808	-71	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:24.170868+02
9513	10	3052	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:59.163604+02
9606	10	134	167272	161576	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 02:42:04.450748+02
9642	10	511	167148	144244	-76	RESPONSIVE	t	t	129.3	0	2026-05-12 02:48:21.371816+02
8815	10	139	170232	161448	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 22:57:46.201899+02
8828	9	154	165548	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:25.219911+02
8847	9	237	169996	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:48.577504+02
8849	9	248	169996	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:59.227343+02
8851	10	342	170100	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:08.955553+02
8857	9	279	169864	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:30.562011+02
8859	9	289	169864	153432	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:41.012112+02
8861	10	384	170100	154676	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:50.940342+02
8873	9	344	169864	153432	-48	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:35.176916+02
8879	9	359	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:50.33321+02
8889	9	384	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:15.6256+02
8899	9	409	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:40.845108+02
8905	9	424	169864	153432	-45	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:56.076029+02
8915	9	450	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:21.367033+02
9427	9	284	162540	152240	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:35:45.662905+02
9436	10	310	167116	150296	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:36:17.201529+02
9438	10	317	167116	150296	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:36:24.2671+02
9444	10	1261	163772	150296	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 01:52:08.149225+02
9490	9	2974	167112	147160	-45	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:35.125284+02
9495	10	2982	167128	142808	-65	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:49.155097+02
9496	9	2995	167112	147160	-64	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:56.060602+02
9507	9	3025	167112	147160	-64	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:26.525533+02
9509	9	3030	167112	147160	-59	POWERED_OFF	t	t	129.3	0	2026-05-12 02:21:31.542993+02
9511	10	3038	167128	142808	-69	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:45.173019+02
9609	9	184	162764	158896	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:42:50.225372+02
9616	10	205	165704	146900	-74	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:15.752302+02
9618	10	212	167264	146900	-77	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:22.685453+02
8818	9	69	167692	164432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 22:58:01.640415+02
8829	10	242	162080	155004	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 22:59:30.822128+02
8842	9	216	169996	153432	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:27.791017+02
8855	10	356	170100	154676	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:22.989456+02
8865	10	398	170100	154676	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:04.9741+02
8871	9	337	169864	153432	-47	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:28.132419+02
8875	9	349	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:40.297347+02
8885	9	374	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:05.590105+02
8895	9	399	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:30.780915+02
8901	9	414	169864	153432	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:45.936568+02
8911	9	440	169864	153432	-47	STARTUP_PENDING	t	t	129.3	0	2026-05-11 23:04:11.229424+02
8917	9	455	169864	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:26.4853+02
9428	10	282	167116	150296	-67	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:35:49.246076+02
9433	9	305	166996	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:36:06.628327+02
9435	9	312	166996	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:36:13.719307+02
9442	10	1256	163772	150296	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 01:52:03.089652+02
9491	10	2968	167128	142808	-67	RESPONSIVE	t	t	129.3	0	2026-05-12 02:20:35.128726+02
9504	10	3010	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:21:17.129182+02
9610	10	184	162812	161024	-74	RESPONSIVE	t	t	129.3	0	2026-05-12 02:42:54.627546+02
9614	10	198	167264	146900	-74	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:08.656187+02
9619	9	219	166972	144824	-50	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:25.244936+02
8845	10	313	170100	154676	-64	RESPONSIVE	t	t	129.3	0	2026-05-11 23:00:39.327375+02
8850	10	335	170096	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:01.992887+02
8860	10	377	170100	154676	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:01:43.977079+02
8870	10	419	170100	154676	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:02:25.961564+02
8874	10	431	170100	154676	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 23:02:38.049746+02
8884	10	457	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:03.33728+02
8890	10	472	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:18.493073+02
8896	10	487	170100	154676	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:33.647791+02
8906	10	512	170100	154676	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 23:03:58.864279+02
8912	10	527	170100	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:14.022201+02
8921	9	470	165380	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:41.542008+02
8922	10	558	165620	154676	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:44.407718+02
8923	9	475	155716	153432	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:46.579942+02
8924	10	563	169944	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:49.405092+02
8925	9	480	169836	147964	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:51.678248+02
8926	10	568	169944	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:54.537674+02
8927	9	485	169836	147964	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:56.636146+02
8928	10	573	169944	147632	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 23:04:59.562987+02
8929	9	490	169836	147964	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:05:01.682661+02
8930	10	578	169944	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:05:04.683177+02
8931	9	495	169836	147964	-48	POWERED_OFF	t	t	129.3	0	2026-05-11 23:05:06.732864+02
8932	10	583	169944	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:05:09.700717+02
8933	9	500	169836	147964	-49	STARTUP_PENDING	t	t	129.3	0	2026-05-11 23:05:11.850941+02
8934	10	588	169944	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:05:14.718155+02
8935	10	936	166608	147632	-62	POWERED_OFF	t	t	129.3	0	2026-05-11 23:11:03.137246+02
8936	9	854	166484	147964	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:11:05.289468+02
8937	10	942	166608	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:11:08.206506+02
8938	9	859	166484	147964	-47	POWERED_OFF	t	t	129.3	0	2026-05-11 23:11:10.35722+02
8939	10	947	166608	147632	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:11:13.325684+02
8940	9	867	166484	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:11:18.958305+02
8941	10	955	166616	147632	-60	RESPONSIVE	t	t	129.3	0	2026-05-11 23:11:21.826066+02
8942	9	874	164640	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:11:26.433691+02
8943	10	963	164600	147632	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:11:29.245008+02
8944	9	885	166616	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:11:36.469538+02
8945	10	971	166476	147632	-63	RESPONSIVE	t	t	129.3	0	2026-05-11 23:11:37.595554+02
8946	10	1018	162032	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:25.146135+02
8947	10	1026	165380	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:33.173358+02
8948	9	948	162184	147964	-50	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:39.978805+02
8949	10	1034	165388	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:40.851852+02
8950	10	1042	165388	147632	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:48.586721+02
8951	9	959	162052	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:51.067412+02
8952	10	1050	165512	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:12:56.528354+02
8953	9	970	161720	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:01.207353+02
8954	10	1058	165512	147632	-60	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:04.329195+02
8955	9	980	162028	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:11.394558+02
8956	10	1065	165512	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:12.009009+02
8957	10	1073	169952	147632	-60	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:19.867681+02
8958	9	990	162052	147964	-47	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:22.146332+02
8959	10	1081	169952	147632	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:27.64873+02
8960	9	1001	161920	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:32.694033+02
8961	10	1089	169952	147632	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:35.356817+02
8962	10	1096	169952	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:42.404651+02
8963	9	1011	166612	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:42.616367+02
8964	10	1103	169952	147632	-61	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:49.406882+02
8965	9	1022	166632	147964	-49	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:53.407062+02
8966	10	1110	169952	147632	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:13:56.407045+02
8967	10	8	190472	186572	-61	UNINITIALIZED	f	f	0.0	0	2026-05-11 23:37:49.039044+02
8968	10	19	167596	154412	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:01.02137+02
8969	10	25	167364	154412	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:06.001984+02
8970	10	30	167364	154412	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:11.157969+02
8971	10	35	167364	154412	-61	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:16.17634+02
8972	10	40	167364	154412	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:21.297595+02
8973	10	45	167364	154412	-59	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:26.313767+02
8974	10	50	167364	154412	-60	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:31.33143+02
8975	10	55	167364	154412	-58	POWERED_OFF	t	t	129.3	0	2026-05-11 23:38:36.349088+02
8976	10	64	167364	154412	-62	RESPONSIVE	t	t	129.3	0	2026-05-11 23:38:45.742982+02
9429	9	291	166996	150640	-47	RESPONSIVE	t	t	129.3	0	2026-05-12 01:35:52.728343+02
9430	10	289	167116	150296	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:35:56.170832+02
9432	10	296	167116	150296	-66	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:36:03.259544+02
9434	10	303	167116	150296	-67	UNRESPONSIVE	f	t	129.3	263	2026-05-12 01:36:10.238123+02
9437	9	319	166996	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:36:20.667785+02
9439	9	326	166996	150640	-46	RESPONSIVE	t	t	129.3	0	2026-05-12 01:36:27.646846+02
9440	10	1251	163772	150296	-67	POWERED_OFF	t	t	129.3	0	2026-05-12 01:51:58.028879+02
9443	9	1266	163656	150640	-46	POWERED_OFF	t	t	129.3	0	2026-05-12 01:52:07.789526+02
9515	10	3066	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:22:13.128824+02
9517	10	3080	167128	142808	-70	RESPONSIVE	t	t	129.3	0	2026-05-12 02:22:27.15216+02
9519	10	3094	167128	142808	-60	RESPONSIVE	t	t	129.3	0	2026-05-12 02:22:41.176515+02
9524	9	19	167608	163020	-51	POWERED_OFF	t	t	129.3	0	2026-05-12 02:29:39.688828+02
9611	9	191	166972	144824	-53	RESPONSIVE	t	t	129.3	0	2026-05-12 02:42:57.153511+02
9620	10	219	167264	146900	-75	RESPONSIVE	t	t	129.3	0	2026-05-12 02:43:29.603867+02
\.


--
-- Data for Name: lighthouses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lighthouses (id, name, device_id, placement, comment, firmware_version, last_seen_at, is_active, config, group_id, created_at, canged_at) FROM stdin;
9	Yellow	00:70:07:25:15:00	INSIDE	\N	\N	2026-05-12 02:48:17.284+02	t	{}	5	2026-05-08 22:51:30.087+02	2026-05-08 22:51:30.088128+02
10	Red	68:FE:71:0D:D0:74	OUTSIDE	\N	\N	2026-05-12 02:48:21.374+02	t	{}	5	2026-05-08 22:52:09.26+02	2026-05-08 22:52:09.261586+02
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
0f383922-4cda-400f-8e86-541496d5f5dd	27211
348c095d-ff04-4765-9b96-a5f365be1def	27211
0f383922-4cda-400f-8e86-541496d5f5dd	27212
348c095d-ff04-4765-9b96-a5f365be1def	27212
0f383922-4cda-400f-8e86-541496d5f5dd	27213
348c095d-ff04-4765-9b96-a5f365be1def	27213
0f383922-4cda-400f-8e86-541496d5f5dd	27214
348c095d-ff04-4765-9b96-a5f365be1def	27214
0f383922-4cda-400f-8e86-541496d5f5dd	27215
348c095d-ff04-4765-9b96-a5f365be1def	27215
0f383922-4cda-400f-8e86-541496d5f5dd	27216
348c095d-ff04-4765-9b96-a5f365be1def	27216
0f383922-4cda-400f-8e86-541496d5f5dd	27217
348c095d-ff04-4765-9b96-a5f365be1def	27217
0f383922-4cda-400f-8e86-541496d5f5dd	27218
348c095d-ff04-4765-9b96-a5f365be1def	27218
0f383922-4cda-400f-8e86-541496d5f5dd	27219
348c095d-ff04-4765-9b96-a5f365be1def	27219
0f383922-4cda-400f-8e86-541496d5f5dd	27220
348c095d-ff04-4765-9b96-a5f365be1def	27220
0f383922-4cda-400f-8e86-541496d5f5dd	27221
348c095d-ff04-4765-9b96-a5f365be1def	27221
0f383922-4cda-400f-8e86-541496d5f5dd	27222
348c095d-ff04-4765-9b96-a5f365be1def	27222
0f383922-4cda-400f-8e86-541496d5f5dd	27223
348c095d-ff04-4765-9b96-a5f365be1def	27223
0f383922-4cda-400f-8e86-541496d5f5dd	27224
348c095d-ff04-4765-9b96-a5f365be1def	27224
0f383922-4cda-400f-8e86-541496d5f5dd	27225
348c095d-ff04-4765-9b96-a5f365be1def	27225
0f383922-4cda-400f-8e86-541496d5f5dd	27226
348c095d-ff04-4765-9b96-a5f365be1def	27226
0f383922-4cda-400f-8e86-541496d5f5dd	27227
348c095d-ff04-4765-9b96-a5f365be1def	27227
0f383922-4cda-400f-8e86-541496d5f5dd	27228
348c095d-ff04-4765-9b96-a5f365be1def	27228
0f383922-4cda-400f-8e86-541496d5f5dd	27229
348c095d-ff04-4765-9b96-a5f365be1def	27229
0f383922-4cda-400f-8e86-541496d5f5dd	27230
348c095d-ff04-4765-9b96-a5f365be1def	27230
0f383922-4cda-400f-8e86-541496d5f5dd	27259
348c095d-ff04-4765-9b96-a5f365be1def	27259
0f383922-4cda-400f-8e86-541496d5f5dd	27260
348c095d-ff04-4765-9b96-a5f365be1def	27260
0f383922-4cda-400f-8e86-541496d5f5dd	27261
348c095d-ff04-4765-9b96-a5f365be1def	27261
0f383922-4cda-400f-8e86-541496d5f5dd	27262
348c095d-ff04-4765-9b96-a5f365be1def	27262
0f383922-4cda-400f-8e86-541496d5f5dd	27263
348c095d-ff04-4765-9b96-a5f365be1def	27263
0f383922-4cda-400f-8e86-541496d5f5dd	27264
348c095d-ff04-4765-9b96-a5f365be1def	27264
0f383922-4cda-400f-8e86-541496d5f5dd	27265
348c095d-ff04-4765-9b96-a5f365be1def	27265
0f383922-4cda-400f-8e86-541496d5f5dd	27266
348c095d-ff04-4765-9b96-a5f365be1def	27266
0f383922-4cda-400f-8e86-541496d5f5dd	27267
348c095d-ff04-4765-9b96-a5f365be1def	27267
0f383922-4cda-400f-8e86-541496d5f5dd	27268
348c095d-ff04-4765-9b96-a5f365be1def	27268
0f383922-4cda-400f-8e86-541496d5f5dd	27269
348c095d-ff04-4765-9b96-a5f365be1def	27269
0f383922-4cda-400f-8e86-541496d5f5dd	27270
348c095d-ff04-4765-9b96-a5f365be1def	27270
0f383922-4cda-400f-8e86-541496d5f5dd	27271
348c095d-ff04-4765-9b96-a5f365be1def	27271
0f383922-4cda-400f-8e86-541496d5f5dd	27272
348c095d-ff04-4765-9b96-a5f365be1def	27272
0f383922-4cda-400f-8e86-541496d5f5dd	27273
348c095d-ff04-4765-9b96-a5f365be1def	27273
0f383922-4cda-400f-8e86-541496d5f5dd	27274
348c095d-ff04-4765-9b96-a5f365be1def	27274
b0f811a9-5572-4f23-895f-17919288b96b	27231
1a6dab08-758e-434f-ad17-709a62cc09cb	27231
b0f811a9-5572-4f23-895f-17919288b96b	27233
1a6dab08-758e-434f-ad17-709a62cc09cb	27233
b0f811a9-5572-4f23-895f-17919288b96b	27235
1a6dab08-758e-434f-ad17-709a62cc09cb	27235
b0f811a9-5572-4f23-895f-17919288b96b	27237
1a6dab08-758e-434f-ad17-709a62cc09cb	27237
b0f811a9-5572-4f23-895f-17919288b96b	27232
1a6dab08-758e-434f-ad17-709a62cc09cb	27232
b0f811a9-5572-4f23-895f-17919288b96b	27251
1a6dab08-758e-434f-ad17-709a62cc09cb	27251
b0f811a9-5572-4f23-895f-17919288b96b	27234
1a6dab08-758e-434f-ad17-709a62cc09cb	27234
b0f811a9-5572-4f23-895f-17919288b96b	27252
1a6dab08-758e-434f-ad17-709a62cc09cb	27252
b0f811a9-5572-4f23-895f-17919288b96b	27253
1a6dab08-758e-434f-ad17-709a62cc09cb	27253
b0f811a9-5572-4f23-895f-17919288b96b	27236
1a6dab08-758e-434f-ad17-709a62cc09cb	27236
b0f811a9-5572-4f23-895f-17919288b96b	27254
1a6dab08-758e-434f-ad17-709a62cc09cb	27254
b0f811a9-5572-4f23-895f-17919288b96b	27238
1a6dab08-758e-434f-ad17-709a62cc09cb	27238
b0f811a9-5572-4f23-895f-17919288b96b	27255
1a6dab08-758e-434f-ad17-709a62cc09cb	27255
b0f811a9-5572-4f23-895f-17919288b96b	27239
1a6dab08-758e-434f-ad17-709a62cc09cb	27239
b0f811a9-5572-4f23-895f-17919288b96b	27256
1a6dab08-758e-434f-ad17-709a62cc09cb	27256
b0f811a9-5572-4f23-895f-17919288b96b	27240
1a6dab08-758e-434f-ad17-709a62cc09cb	27240
b0f811a9-5572-4f23-895f-17919288b96b	27241
1a6dab08-758e-434f-ad17-709a62cc09cb	27241
b0f811a9-5572-4f23-895f-17919288b96b	27257
1a6dab08-758e-434f-ad17-709a62cc09cb	27257
b0f811a9-5572-4f23-895f-17919288b96b	27258
1a6dab08-758e-434f-ad17-709a62cc09cb	27258
b0f811a9-5572-4f23-895f-17919288b96b	27242
1a6dab08-758e-434f-ad17-709a62cc09cb	27242
b0f811a9-5572-4f23-895f-17919288b96b	27243
1a6dab08-758e-434f-ad17-709a62cc09cb	27243
b0f811a9-5572-4f23-895f-17919288b96b	27244
1a6dab08-758e-434f-ad17-709a62cc09cb	27244
b0f811a9-5572-4f23-895f-17919288b96b	27245
1a6dab08-758e-434f-ad17-709a62cc09cb	27245
b0f811a9-5572-4f23-895f-17919288b96b	27246
1a6dab08-758e-434f-ad17-709a62cc09cb	27246
b0f811a9-5572-4f23-895f-17919288b96b	27247
1a6dab08-758e-434f-ad17-709a62cc09cb	27247
b0f811a9-5572-4f23-895f-17919288b96b	27248
1a6dab08-758e-434f-ad17-709a62cc09cb	27248
b0f811a9-5572-4f23-895f-17919288b96b	27249
1a6dab08-758e-434f-ad17-709a62cc09cb	27249
b0f811a9-5572-4f23-895f-17919288b96b	27250
1a6dab08-758e-434f-ad17-709a62cc09cb	27250
b0f811a9-5572-4f23-895f-17919288b96b	27275
1a6dab08-758e-434f-ad17-709a62cc09cb	27275
b0f811a9-5572-4f23-895f-17919288b96b	27276
1a6dab08-758e-434f-ad17-709a62cc09cb	27276
b0f811a9-5572-4f23-895f-17919288b96b	27277
1a6dab08-758e-434f-ad17-709a62cc09cb	27277
b0f811a9-5572-4f23-895f-17919288b96b	27278
1a6dab08-758e-434f-ad17-709a62cc09cb	27278
b0f811a9-5572-4f23-895f-17919288b96b	27279
1a6dab08-758e-434f-ad17-709a62cc09cb	27279
b0f811a9-5572-4f23-895f-17919288b96b	27280
1a6dab08-758e-434f-ad17-709a62cc09cb	27280
b0f811a9-5572-4f23-895f-17919288b96b	27281
1a6dab08-758e-434f-ad17-709a62cc09cb	27281
b0f811a9-5572-4f23-895f-17919288b96b	27282
1a6dab08-758e-434f-ad17-709a62cc09cb	27282
b0f811a9-5572-4f23-895f-17919288b96b	27283
1a6dab08-758e-434f-ad17-709a62cc09cb	27283
b0f811a9-5572-4f23-895f-17919288b96b	27284
1a6dab08-758e-434f-ad17-709a62cc09cb	27284
b0f811a9-5572-4f23-895f-17919288b96b	27285
1a6dab08-758e-434f-ad17-709a62cc09cb	27285
b0f811a9-5572-4f23-895f-17919288b96b	27286
1a6dab08-758e-434f-ad17-709a62cc09cb	27286
b0f811a9-5572-4f23-895f-17919288b96b	27287
1a6dab08-758e-434f-ad17-709a62cc09cb	27287
b0f811a9-5572-4f23-895f-17919288b96b	27289
1a6dab08-758e-434f-ad17-709a62cc09cb	27289
b0f811a9-5572-4f23-895f-17919288b96b	27291
1a6dab08-758e-434f-ad17-709a62cc09cb	27291
b0f811a9-5572-4f23-895f-17919288b96b	27293
1a6dab08-758e-434f-ad17-709a62cc09cb	27293
b0f811a9-5572-4f23-895f-17919288b96b	27288
1a6dab08-758e-434f-ad17-709a62cc09cb	27288
b0f811a9-5572-4f23-895f-17919288b96b	27290
1a6dab08-758e-434f-ad17-709a62cc09cb	27290
b0f811a9-5572-4f23-895f-17919288b96b	27292
1a6dab08-758e-434f-ad17-709a62cc09cb	27292
b0f811a9-5572-4f23-895f-17919288b96b	27294
1a6dab08-758e-434f-ad17-709a62cc09cb	27294
b0f811a9-5572-4f23-895f-17919288b96b	27296
1a6dab08-758e-434f-ad17-709a62cc09cb	27296
b0f811a9-5572-4f23-895f-17919288b96b	27297
1a6dab08-758e-434f-ad17-709a62cc09cb	27297
b0f811a9-5572-4f23-895f-17919288b96b	27298
1a6dab08-758e-434f-ad17-709a62cc09cb	27298
b0f811a9-5572-4f23-895f-17919288b96b	27299
1a6dab08-758e-434f-ad17-709a62cc09cb	27299
b0f811a9-5572-4f23-895f-17919288b96b	27295
1a6dab08-758e-434f-ad17-709a62cc09cb	27295
1fcf0857-c5d9-4683-8231-80dc1740bb83	27384
0665909d-4935-4111-b094-af33ce372e96	27384
1fcf0857-c5d9-4683-8231-80dc1740bb83	27385
0665909d-4935-4111-b094-af33ce372e96	27385
1fcf0857-c5d9-4683-8231-80dc1740bb83	27386
0665909d-4935-4111-b094-af33ce372e96	27386
1fcf0857-c5d9-4683-8231-80dc1740bb83	27387
0665909d-4935-4111-b094-af33ce372e96	27387
1fcf0857-c5d9-4683-8231-80dc1740bb83	27388
0665909d-4935-4111-b094-af33ce372e96	27388
1fcf0857-c5d9-4683-8231-80dc1740bb83	27389
0665909d-4935-4111-b094-af33ce372e96	27389
1fcf0857-c5d9-4683-8231-80dc1740bb83	27390
0665909d-4935-4111-b094-af33ce372e96	27390
1fcf0857-c5d9-4683-8231-80dc1740bb83	27391
0665909d-4935-4111-b094-af33ce372e96	27391
1fcf0857-c5d9-4683-8231-80dc1740bb83	27392
0665909d-4935-4111-b094-af33ce372e96	27392
1fcf0857-c5d9-4683-8231-80dc1740bb83	27393
0665909d-4935-4111-b094-af33ce372e96	27393
1fcf0857-c5d9-4683-8231-80dc1740bb83	27394
0665909d-4935-4111-b094-af33ce372e96	27394
1fcf0857-c5d9-4683-8231-80dc1740bb83	27395
0665909d-4935-4111-b094-af33ce372e96	27395
1fcf0857-c5d9-4683-8231-80dc1740bb83	27396
0665909d-4935-4111-b094-af33ce372e96	27396
1fcf0857-c5d9-4683-8231-80dc1740bb83	27397
0665909d-4935-4111-b094-af33ce372e96	27397
1fcf0857-c5d9-4683-8231-80dc1740bb83	27398
0665909d-4935-4111-b094-af33ce372e96	27398
1fcf0857-c5d9-4683-8231-80dc1740bb83	27399
0665909d-4935-4111-b094-af33ce372e96	27399
1fcf0857-c5d9-4683-8231-80dc1740bb83	27400
0665909d-4935-4111-b094-af33ce372e96	27400
1fcf0857-c5d9-4683-8231-80dc1740bb83	27401
0665909d-4935-4111-b094-af33ce372e96	27401
1fcf0857-c5d9-4683-8231-80dc1740bb83	27402
0665909d-4935-4111-b094-af33ce372e96	27402
1fcf0857-c5d9-4683-8231-80dc1740bb83	27403
0665909d-4935-4111-b094-af33ce372e96	27403
1fcf0857-c5d9-4683-8231-80dc1740bb83	27404
0665909d-4935-4111-b094-af33ce372e96	27404
1fcf0857-c5d9-4683-8231-80dc1740bb83	27405
0665909d-4935-4111-b094-af33ce372e96	27405
1fcf0857-c5d9-4683-8231-80dc1740bb83	27406
0665909d-4935-4111-b094-af33ce372e96	27406
1fcf0857-c5d9-4683-8231-80dc1740bb83	27407
0665909d-4935-4111-b094-af33ce372e96	27407
1fcf0857-c5d9-4683-8231-80dc1740bb83	27408
0665909d-4935-4111-b094-af33ce372e96	27408
1fcf0857-c5d9-4683-8231-80dc1740bb83	27409
0665909d-4935-4111-b094-af33ce372e96	27409
1fcf0857-c5d9-4683-8231-80dc1740bb83	27410
0665909d-4935-4111-b094-af33ce372e96	27410
1fcf0857-c5d9-4683-8231-80dc1740bb83	27300
0665909d-4935-4111-b094-af33ce372e96	27300
1fcf0857-c5d9-4683-8231-80dc1740bb83	27301
0665909d-4935-4111-b094-af33ce372e96	27301
1fcf0857-c5d9-4683-8231-80dc1740bb83	27302
0665909d-4935-4111-b094-af33ce372e96	27302
1fcf0857-c5d9-4683-8231-80dc1740bb83	27303
0665909d-4935-4111-b094-af33ce372e96	27303
1fcf0857-c5d9-4683-8231-80dc1740bb83	27304
0665909d-4935-4111-b094-af33ce372e96	27304
1fcf0857-c5d9-4683-8231-80dc1740bb83	27305
0665909d-4935-4111-b094-af33ce372e96	27305
1fcf0857-c5d9-4683-8231-80dc1740bb83	27306
0665909d-4935-4111-b094-af33ce372e96	27306
1fcf0857-c5d9-4683-8231-80dc1740bb83	27307
0665909d-4935-4111-b094-af33ce372e96	27307
1fcf0857-c5d9-4683-8231-80dc1740bb83	27308
0665909d-4935-4111-b094-af33ce372e96	27308
1fcf0857-c5d9-4683-8231-80dc1740bb83	27309
0665909d-4935-4111-b094-af33ce372e96	27309
1fcf0857-c5d9-4683-8231-80dc1740bb83	27310
0665909d-4935-4111-b094-af33ce372e96	27310
1fcf0857-c5d9-4683-8231-80dc1740bb83	27311
0665909d-4935-4111-b094-af33ce372e96	27311
1fcf0857-c5d9-4683-8231-80dc1740bb83	27312
0665909d-4935-4111-b094-af33ce372e96	27312
1fcf0857-c5d9-4683-8231-80dc1740bb83	27313
0665909d-4935-4111-b094-af33ce372e96	27313
1fcf0857-c5d9-4683-8231-80dc1740bb83	27314
0665909d-4935-4111-b094-af33ce372e96	27314
1fcf0857-c5d9-4683-8231-80dc1740bb83	27315
0665909d-4935-4111-b094-af33ce372e96	27315
1fcf0857-c5d9-4683-8231-80dc1740bb83	27316
0665909d-4935-4111-b094-af33ce372e96	27316
1fcf0857-c5d9-4683-8231-80dc1740bb83	27317
0665909d-4935-4111-b094-af33ce372e96	27317
1fcf0857-c5d9-4683-8231-80dc1740bb83	27318
0665909d-4935-4111-b094-af33ce372e96	27318
1fcf0857-c5d9-4683-8231-80dc1740bb83	27319
0665909d-4935-4111-b094-af33ce372e96	27319
1fcf0857-c5d9-4683-8231-80dc1740bb83	27321
0665909d-4935-4111-b094-af33ce372e96	27321
1fcf0857-c5d9-4683-8231-80dc1740bb83	27323
0665909d-4935-4111-b094-af33ce372e96	27323
1fcf0857-c5d9-4683-8231-80dc1740bb83	27325
0665909d-4935-4111-b094-af33ce372e96	27325
1fcf0857-c5d9-4683-8231-80dc1740bb83	27327
0665909d-4935-4111-b094-af33ce372e96	27327
1fcf0857-c5d9-4683-8231-80dc1740bb83	27320
0665909d-4935-4111-b094-af33ce372e96	27320
1fcf0857-c5d9-4683-8231-80dc1740bb83	27322
0665909d-4935-4111-b094-af33ce372e96	27322
1fcf0857-c5d9-4683-8231-80dc1740bb83	27324
0665909d-4935-4111-b094-af33ce372e96	27324
1fcf0857-c5d9-4683-8231-80dc1740bb83	27326
0665909d-4935-4111-b094-af33ce372e96	27326
1fcf0857-c5d9-4683-8231-80dc1740bb83	27328
0665909d-4935-4111-b094-af33ce372e96	27328
1fcf0857-c5d9-4683-8231-80dc1740bb83	27329
0665909d-4935-4111-b094-af33ce372e96	27329
1fcf0857-c5d9-4683-8231-80dc1740bb83	27331
0665909d-4935-4111-b094-af33ce372e96	27331
1fcf0857-c5d9-4683-8231-80dc1740bb83	27333
0665909d-4935-4111-b094-af33ce372e96	27333
1fcf0857-c5d9-4683-8231-80dc1740bb83	27330
0665909d-4935-4111-b094-af33ce372e96	27330
1fcf0857-c5d9-4683-8231-80dc1740bb83	27332
0665909d-4935-4111-b094-af33ce372e96	27332
1fcf0857-c5d9-4683-8231-80dc1740bb83	27334
0665909d-4935-4111-b094-af33ce372e96	27334
1fcf0857-c5d9-4683-8231-80dc1740bb83	27335
0665909d-4935-4111-b094-af33ce372e96	27335
1fcf0857-c5d9-4683-8231-80dc1740bb83	27336
0665909d-4935-4111-b094-af33ce372e96	27336
1fcf0857-c5d9-4683-8231-80dc1740bb83	27337
0665909d-4935-4111-b094-af33ce372e96	27337
1fcf0857-c5d9-4683-8231-80dc1740bb83	27338
0665909d-4935-4111-b094-af33ce372e96	27338
1fcf0857-c5d9-4683-8231-80dc1740bb83	27339
0665909d-4935-4111-b094-af33ce372e96	27339
1fcf0857-c5d9-4683-8231-80dc1740bb83	27340
0665909d-4935-4111-b094-af33ce372e96	27340
1fcf0857-c5d9-4683-8231-80dc1740bb83	27341
0665909d-4935-4111-b094-af33ce372e96	27341
1fcf0857-c5d9-4683-8231-80dc1740bb83	27342
0665909d-4935-4111-b094-af33ce372e96	27342
1fcf0857-c5d9-4683-8231-80dc1740bb83	27343
0665909d-4935-4111-b094-af33ce372e96	27343
1fcf0857-c5d9-4683-8231-80dc1740bb83	27344
0665909d-4935-4111-b094-af33ce372e96	27344
1fcf0857-c5d9-4683-8231-80dc1740bb83	27345
0665909d-4935-4111-b094-af33ce372e96	27345
1fcf0857-c5d9-4683-8231-80dc1740bb83	27346
0665909d-4935-4111-b094-af33ce372e96	27346
1fcf0857-c5d9-4683-8231-80dc1740bb83	27348
0665909d-4935-4111-b094-af33ce372e96	27348
ca2aa626-ad16-431b-8220-a29b9baf86d5	27412
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27412
ca2aa626-ad16-431b-8220-a29b9baf86d5	27414
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27414
ca2aa626-ad16-431b-8220-a29b9baf86d5	27416
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27416
ca2aa626-ad16-431b-8220-a29b9baf86d5	27418
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27418
ca2aa626-ad16-431b-8220-a29b9baf86d5	27420
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27420
ca2aa626-ad16-431b-8220-a29b9baf86d5	27411
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27411
ca2aa626-ad16-431b-8220-a29b9baf86d5	27413
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27413
ca2aa626-ad16-431b-8220-a29b9baf86d5	27415
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27415
ca2aa626-ad16-431b-8220-a29b9baf86d5	27417
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27417
ca2aa626-ad16-431b-8220-a29b9baf86d5	27419
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27419
ca2aa626-ad16-431b-8220-a29b9baf86d5	27421
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27421
ca2aa626-ad16-431b-8220-a29b9baf86d5	27422
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27422
ca2aa626-ad16-431b-8220-a29b9baf86d5	27423
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27423
ca2aa626-ad16-431b-8220-a29b9baf86d5	27424
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27424
ca2aa626-ad16-431b-8220-a29b9baf86d5	27425
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27425
ca2aa626-ad16-431b-8220-a29b9baf86d5	27426
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27426
ca2aa626-ad16-431b-8220-a29b9baf86d5	27427
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27427
ca2aa626-ad16-431b-8220-a29b9baf86d5	27428
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27428
ca2aa626-ad16-431b-8220-a29b9baf86d5	27429
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27429
ca2aa626-ad16-431b-8220-a29b9baf86d5	27430
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27430
ca2aa626-ad16-431b-8220-a29b9baf86d5	27347
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27347
ca2aa626-ad16-431b-8220-a29b9baf86d5	27349
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27349
ca2aa626-ad16-431b-8220-a29b9baf86d5	27351
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27351
ca2aa626-ad16-431b-8220-a29b9baf86d5	27353
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27353
ca2aa626-ad16-431b-8220-a29b9baf86d5	27355
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27355
ca2aa626-ad16-431b-8220-a29b9baf86d5	27357
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27357
ca2aa626-ad16-431b-8220-a29b9baf86d5	27359
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27359
ca2aa626-ad16-431b-8220-a29b9baf86d5	27362
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27362
ca2aa626-ad16-431b-8220-a29b9baf86d5	27350
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27350
ca2aa626-ad16-431b-8220-a29b9baf86d5	27352
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27352
ca2aa626-ad16-431b-8220-a29b9baf86d5	27354
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27354
ca2aa626-ad16-431b-8220-a29b9baf86d5	27356
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27356
ca2aa626-ad16-431b-8220-a29b9baf86d5	27358
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27358
ca2aa626-ad16-431b-8220-a29b9baf86d5	27360
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27360
ca2aa626-ad16-431b-8220-a29b9baf86d5	27363
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27363
ca2aa626-ad16-431b-8220-a29b9baf86d5	27365
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27365
ca2aa626-ad16-431b-8220-a29b9baf86d5	27361
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27361
ca2aa626-ad16-431b-8220-a29b9baf86d5	27364
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27364
ca2aa626-ad16-431b-8220-a29b9baf86d5	27366
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27366
ca2aa626-ad16-431b-8220-a29b9baf86d5	27367
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27367
ca2aa626-ad16-431b-8220-a29b9baf86d5	27368
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27368
ca2aa626-ad16-431b-8220-a29b9baf86d5	27369
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27369
ca2aa626-ad16-431b-8220-a29b9baf86d5	27370
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27370
ca2aa626-ad16-431b-8220-a29b9baf86d5	27371
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27371
ca2aa626-ad16-431b-8220-a29b9baf86d5	27372
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27372
ca2aa626-ad16-431b-8220-a29b9baf86d5	27374
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27374
ca2aa626-ad16-431b-8220-a29b9baf86d5	27376
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27376
ca2aa626-ad16-431b-8220-a29b9baf86d5	27378
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27378
ca2aa626-ad16-431b-8220-a29b9baf86d5	27380
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27380
ca2aa626-ad16-431b-8220-a29b9baf86d5	27381
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27381
ca2aa626-ad16-431b-8220-a29b9baf86d5	27382
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27382
ca2aa626-ad16-431b-8220-a29b9baf86d5	27383
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27383
ca2aa626-ad16-431b-8220-a29b9baf86d5	27373
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27373
ca2aa626-ad16-431b-8220-a29b9baf86d5	27375
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27375
ca2aa626-ad16-431b-8220-a29b9baf86d5	27377
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27377
ca2aa626-ad16-431b-8220-a29b9baf86d5	27379
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	27379
6d2808e6-7590-4859-86e8-96b8be78663c	27431
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27431
6d2808e6-7590-4859-86e8-96b8be78663c	27432
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27432
6d2808e6-7590-4859-86e8-96b8be78663c	27433
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27433
6d2808e6-7590-4859-86e8-96b8be78663c	27434
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27434
6d2808e6-7590-4859-86e8-96b8be78663c	27435
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27435
6d2808e6-7590-4859-86e8-96b8be78663c	27436
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27436
6d2808e6-7590-4859-86e8-96b8be78663c	27438
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27438
6d2808e6-7590-4859-86e8-96b8be78663c	27439
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27439
6d2808e6-7590-4859-86e8-96b8be78663c	27437
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27437
6d2808e6-7590-4859-86e8-96b8be78663c	27440
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27440
6d2808e6-7590-4859-86e8-96b8be78663c	27442
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27442
6d2808e6-7590-4859-86e8-96b8be78663c	27445
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27445
6d2808e6-7590-4859-86e8-96b8be78663c	27449
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27449
6d2808e6-7590-4859-86e8-96b8be78663c	27455
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27455
6d2808e6-7590-4859-86e8-96b8be78663c	27460
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27460
6d2808e6-7590-4859-86e8-96b8be78663c	27463
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27463
6d2808e6-7590-4859-86e8-96b8be78663c	27441
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27441
6d2808e6-7590-4859-86e8-96b8be78663c	27443
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27443
6d2808e6-7590-4859-86e8-96b8be78663c	27448
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27448
6d2808e6-7590-4859-86e8-96b8be78663c	27452
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27452
6d2808e6-7590-4859-86e8-96b8be78663c	27519
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27519
6d2808e6-7590-4859-86e8-96b8be78663c	27520
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27520
6d2808e6-7590-4859-86e8-96b8be78663c	27521
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27521
6d2808e6-7590-4859-86e8-96b8be78663c	27522
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27522
6d2808e6-7590-4859-86e8-96b8be78663c	27523
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27523
6d2808e6-7590-4859-86e8-96b8be78663c	27524
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27524
6d2808e6-7590-4859-86e8-96b8be78663c	27525
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27525
6d2808e6-7590-4859-86e8-96b8be78663c	27526
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27526
6d2808e6-7590-4859-86e8-96b8be78663c	27527
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27527
6d2808e6-7590-4859-86e8-96b8be78663c	27528
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27528
6d2808e6-7590-4859-86e8-96b8be78663c	27529
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27529
6d2808e6-7590-4859-86e8-96b8be78663c	27530
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27530
6d2808e6-7590-4859-86e8-96b8be78663c	27531
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27531
6d2808e6-7590-4859-86e8-96b8be78663c	27532
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27532
6d2808e6-7590-4859-86e8-96b8be78663c	27533
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27533
6d2808e6-7590-4859-86e8-96b8be78663c	27534
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27534
6d2808e6-7590-4859-86e8-96b8be78663c	27535
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27535
6d2808e6-7590-4859-86e8-96b8be78663c	27536
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27536
6d2808e6-7590-4859-86e8-96b8be78663c	27537
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27537
6d2808e6-7590-4859-86e8-96b8be78663c	27539
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27539
6d2808e6-7590-4859-86e8-96b8be78663c	27541
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27541
6d2808e6-7590-4859-86e8-96b8be78663c	27543
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27543
6d2808e6-7590-4859-86e8-96b8be78663c	27545
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27545
6d2808e6-7590-4859-86e8-96b8be78663c	27547
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27547
6d2808e6-7590-4859-86e8-96b8be78663c	27538
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27538
6d2808e6-7590-4859-86e8-96b8be78663c	27540
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27540
6d2808e6-7590-4859-86e8-96b8be78663c	27542
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27542
6d2808e6-7590-4859-86e8-96b8be78663c	27544
af534296-abaa-4e8d-9d8f-65fb4c6b3344	27544
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27456
befff389-aa8a-4411-94de-4e57b9de2cc3	27456
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27458
befff389-aa8a-4411-94de-4e57b9de2cc3	27458
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27467
befff389-aa8a-4411-94de-4e57b9de2cc3	27467
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27473
befff389-aa8a-4411-94de-4e57b9de2cc3	27473
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27447
befff389-aa8a-4411-94de-4e57b9de2cc3	27447
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27451
befff389-aa8a-4411-94de-4e57b9de2cc3	27451
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27453
befff389-aa8a-4411-94de-4e57b9de2cc3	27453
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27457
befff389-aa8a-4411-94de-4e57b9de2cc3	27457
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27461
befff389-aa8a-4411-94de-4e57b9de2cc3	27461
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27465
befff389-aa8a-4411-94de-4e57b9de2cc3	27465
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27470
befff389-aa8a-4411-94de-4e57b9de2cc3	27470
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27476
befff389-aa8a-4411-94de-4e57b9de2cc3	27476
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27444
befff389-aa8a-4411-94de-4e57b9de2cc3	27444
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27446
befff389-aa8a-4411-94de-4e57b9de2cc3	27446
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27450
befff389-aa8a-4411-94de-4e57b9de2cc3	27450
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27454
befff389-aa8a-4411-94de-4e57b9de2cc3	27454
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27459
befff389-aa8a-4411-94de-4e57b9de2cc3	27459
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27466
befff389-aa8a-4411-94de-4e57b9de2cc3	27466
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27469
befff389-aa8a-4411-94de-4e57b9de2cc3	27469
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27474
befff389-aa8a-4411-94de-4e57b9de2cc3	27474
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27462
befff389-aa8a-4411-94de-4e57b9de2cc3	27462
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27464
befff389-aa8a-4411-94de-4e57b9de2cc3	27464
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27472
befff389-aa8a-4411-94de-4e57b9de2cc3	27472
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27546
befff389-aa8a-4411-94de-4e57b9de2cc3	27546
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27548
befff389-aa8a-4411-94de-4e57b9de2cc3	27548
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27549
befff389-aa8a-4411-94de-4e57b9de2cc3	27549
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27550
befff389-aa8a-4411-94de-4e57b9de2cc3	27550
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27551
befff389-aa8a-4411-94de-4e57b9de2cc3	27551
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27552
befff389-aa8a-4411-94de-4e57b9de2cc3	27552
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27554
befff389-aa8a-4411-94de-4e57b9de2cc3	27554
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27556
befff389-aa8a-4411-94de-4e57b9de2cc3	27556
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27558
befff389-aa8a-4411-94de-4e57b9de2cc3	27558
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27560
befff389-aa8a-4411-94de-4e57b9de2cc3	27560
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27562
befff389-aa8a-4411-94de-4e57b9de2cc3	27562
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27564
befff389-aa8a-4411-94de-4e57b9de2cc3	27564
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27553
befff389-aa8a-4411-94de-4e57b9de2cc3	27553
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27555
befff389-aa8a-4411-94de-4e57b9de2cc3	27555
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27557
befff389-aa8a-4411-94de-4e57b9de2cc3	27557
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27559
befff389-aa8a-4411-94de-4e57b9de2cc3	27559
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27561
befff389-aa8a-4411-94de-4e57b9de2cc3	27561
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27563
befff389-aa8a-4411-94de-4e57b9de2cc3	27563
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27565
befff389-aa8a-4411-94de-4e57b9de2cc3	27565
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27566
befff389-aa8a-4411-94de-4e57b9de2cc3	27566
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27567
befff389-aa8a-4411-94de-4e57b9de2cc3	27567
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27568
befff389-aa8a-4411-94de-4e57b9de2cc3	27568
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27569
befff389-aa8a-4411-94de-4e57b9de2cc3	27569
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27570
befff389-aa8a-4411-94de-4e57b9de2cc3	27570
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27571
befff389-aa8a-4411-94de-4e57b9de2cc3	27571
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27572
befff389-aa8a-4411-94de-4e57b9de2cc3	27572
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27573
befff389-aa8a-4411-94de-4e57b9de2cc3	27573
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27574
befff389-aa8a-4411-94de-4e57b9de2cc3	27574
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	27575
befff389-aa8a-4411-94de-4e57b9de2cc3	27575
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27477
67c9e66f-06be-4a11-8269-94cf0eb20889	27477
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27484
67c9e66f-06be-4a11-8269-94cf0eb20889	27484
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27487
67c9e66f-06be-4a11-8269-94cf0eb20889	27487
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27491
67c9e66f-06be-4a11-8269-94cf0eb20889	27491
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27497
67c9e66f-06be-4a11-8269-94cf0eb20889	27497
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27468
67c9e66f-06be-4a11-8269-94cf0eb20889	27468
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27471
67c9e66f-06be-4a11-8269-94cf0eb20889	27471
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27478
67c9e66f-06be-4a11-8269-94cf0eb20889	27478
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27481
67c9e66f-06be-4a11-8269-94cf0eb20889	27481
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27485
67c9e66f-06be-4a11-8269-94cf0eb20889	27485
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27489
67c9e66f-06be-4a11-8269-94cf0eb20889	27489
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27493
67c9e66f-06be-4a11-8269-94cf0eb20889	27493
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27496
67c9e66f-06be-4a11-8269-94cf0eb20889	27496
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27480
67c9e66f-06be-4a11-8269-94cf0eb20889	27480
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27483
67c9e66f-06be-4a11-8269-94cf0eb20889	27483
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27488
67c9e66f-06be-4a11-8269-94cf0eb20889	27488
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27490
67c9e66f-06be-4a11-8269-94cf0eb20889	27490
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27495
67c9e66f-06be-4a11-8269-94cf0eb20889	27495
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27501
67c9e66f-06be-4a11-8269-94cf0eb20889	27501
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27505
67c9e66f-06be-4a11-8269-94cf0eb20889	27505
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27507
67c9e66f-06be-4a11-8269-94cf0eb20889	27507
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27475
67c9e66f-06be-4a11-8269-94cf0eb20889	27475
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27479
67c9e66f-06be-4a11-8269-94cf0eb20889	27479
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27482
67c9e66f-06be-4a11-8269-94cf0eb20889	27482
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27486
67c9e66f-06be-4a11-8269-94cf0eb20889	27486
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27492
67c9e66f-06be-4a11-8269-94cf0eb20889	27492
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27494
67c9e66f-06be-4a11-8269-94cf0eb20889	27494
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27499
67c9e66f-06be-4a11-8269-94cf0eb20889	27499
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27502
67c9e66f-06be-4a11-8269-94cf0eb20889	27502
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27498
67c9e66f-06be-4a11-8269-94cf0eb20889	27498
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27500
67c9e66f-06be-4a11-8269-94cf0eb20889	27500
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27576
67c9e66f-06be-4a11-8269-94cf0eb20889	27576
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27578
67c9e66f-06be-4a11-8269-94cf0eb20889	27578
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27580
67c9e66f-06be-4a11-8269-94cf0eb20889	27580
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27582
67c9e66f-06be-4a11-8269-94cf0eb20889	27582
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27584
67c9e66f-06be-4a11-8269-94cf0eb20889	27584
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27586
67c9e66f-06be-4a11-8269-94cf0eb20889	27586
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27588
67c9e66f-06be-4a11-8269-94cf0eb20889	27588
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27577
67c9e66f-06be-4a11-8269-94cf0eb20889	27577
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27579
67c9e66f-06be-4a11-8269-94cf0eb20889	27579
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27581
67c9e66f-06be-4a11-8269-94cf0eb20889	27581
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27583
67c9e66f-06be-4a11-8269-94cf0eb20889	27583
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27585
67c9e66f-06be-4a11-8269-94cf0eb20889	27585
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27587
67c9e66f-06be-4a11-8269-94cf0eb20889	27587
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27589
67c9e66f-06be-4a11-8269-94cf0eb20889	27589
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27590
67c9e66f-06be-4a11-8269-94cf0eb20889	27590
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27592
67c9e66f-06be-4a11-8269-94cf0eb20889	27592
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27593
67c9e66f-06be-4a11-8269-94cf0eb20889	27593
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27594
67c9e66f-06be-4a11-8269-94cf0eb20889	27594
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27595
67c9e66f-06be-4a11-8269-94cf0eb20889	27595
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27596
67c9e66f-06be-4a11-8269-94cf0eb20889	27596
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27597
67c9e66f-06be-4a11-8269-94cf0eb20889	27597
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27598
67c9e66f-06be-4a11-8269-94cf0eb20889	27598
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27599
67c9e66f-06be-4a11-8269-94cf0eb20889	27599
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27600
67c9e66f-06be-4a11-8269-94cf0eb20889	27600
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27601
67c9e66f-06be-4a11-8269-94cf0eb20889	27601
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27602
67c9e66f-06be-4a11-8269-94cf0eb20889	27602
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27603
67c9e66f-06be-4a11-8269-94cf0eb20889	27603
1e95f7ca-20ba-4d1e-ab92-180975f4322f	27604
67c9e66f-06be-4a11-8269-94cf0eb20889	27604
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27504
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27504
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27506
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27506
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27510
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27510
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27512
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27512
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27514
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27514
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27516
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27516
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27503
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27503
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27508
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27508
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27509
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27509
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27511
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27511
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27513
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27513
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27515
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27515
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27517
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27517
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27518
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27518
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27591
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27591
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27605
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27605
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27606
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27606
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27607
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27607
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27608
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27608
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27609
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27609
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27610
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27610
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27611
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27611
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27612
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27612
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27613
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27613
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27614
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27614
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27615
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27615
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27616
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27616
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27617
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27617
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27618
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27618
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27619
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27619
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27620
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27620
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	27621
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	27621
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27641
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27641
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27642
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27642
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27643
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27643
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27644
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27644
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27645
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27645
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27646
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27646
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27647
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27647
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27648
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27648
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27649
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27649
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27650
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27650
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27651
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27651
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27652
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27652
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27653
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27653
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27654
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27654
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27655
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27655
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27656
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27656
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27657
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27657
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27658
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27658
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27659
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27659
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27660
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27660
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27661
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27661
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27662
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27662
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27663
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27663
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27664
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27664
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27672
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27672
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27666
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27666
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27668
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27668
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27674
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27674
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27670
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27670
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27676
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27676
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27678
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27678
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27671
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27671
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27680
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27680
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27673
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27673
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27681
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27681
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27675
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27675
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27677
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27677
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27682
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27682
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27683
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27683
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27679
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27679
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27665
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27665
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27667
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27667
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27669
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27669
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27622
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27622
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27623
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27623
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27624
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27624
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27625
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27625
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27626
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27626
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27627
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27627
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27628
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27628
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27629
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27629
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27630
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27630
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27631
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27631
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27632
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27632
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27633
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27633
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27634
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27634
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27635
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27635
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27637
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27637
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27639
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27639
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27636
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27636
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27638
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27638
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	27640
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	27640
28f89919-4d4e-45fd-82a6-99e7b87148e0	27684
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27684
28f89919-4d4e-45fd-82a6-99e7b87148e0	27685
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27685
28f89919-4d4e-45fd-82a6-99e7b87148e0	27686
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27686
28f89919-4d4e-45fd-82a6-99e7b87148e0	27687
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27687
28f89919-4d4e-45fd-82a6-99e7b87148e0	27688
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27688
28f89919-4d4e-45fd-82a6-99e7b87148e0	27689
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27689
28f89919-4d4e-45fd-82a6-99e7b87148e0	27690
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27690
28f89919-4d4e-45fd-82a6-99e7b87148e0	27691
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27691
28f89919-4d4e-45fd-82a6-99e7b87148e0	27692
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27692
28f89919-4d4e-45fd-82a6-99e7b87148e0	27693
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27693
28f89919-4d4e-45fd-82a6-99e7b87148e0	27694
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27694
28f89919-4d4e-45fd-82a6-99e7b87148e0	27695
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27695
28f89919-4d4e-45fd-82a6-99e7b87148e0	27746
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27746
28f89919-4d4e-45fd-82a6-99e7b87148e0	27747
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27747
28f89919-4d4e-45fd-82a6-99e7b87148e0	27748
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27748
28f89919-4d4e-45fd-82a6-99e7b87148e0	27749
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27749
28f89919-4d4e-45fd-82a6-99e7b87148e0	27750
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27750
28f89919-4d4e-45fd-82a6-99e7b87148e0	27751
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27751
28f89919-4d4e-45fd-82a6-99e7b87148e0	27752
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27752
28f89919-4d4e-45fd-82a6-99e7b87148e0	27753
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27753
28f89919-4d4e-45fd-82a6-99e7b87148e0	27754
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27754
28f89919-4d4e-45fd-82a6-99e7b87148e0	27755
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27755
28f89919-4d4e-45fd-82a6-99e7b87148e0	27756
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27756
28f89919-4d4e-45fd-82a6-99e7b87148e0	27757
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27757
28f89919-4d4e-45fd-82a6-99e7b87148e0	27758
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27758
28f89919-4d4e-45fd-82a6-99e7b87148e0	27759
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27759
28f89919-4d4e-45fd-82a6-99e7b87148e0	27760
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27760
28f89919-4d4e-45fd-82a6-99e7b87148e0	27761
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27761
28f89919-4d4e-45fd-82a6-99e7b87148e0	27762
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27762
28f89919-4d4e-45fd-82a6-99e7b87148e0	27763
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27763
28f89919-4d4e-45fd-82a6-99e7b87148e0	27764
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27764
28f89919-4d4e-45fd-82a6-99e7b87148e0	27766
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27766
28f89919-4d4e-45fd-82a6-99e7b87148e0	27768
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27768
28f89919-4d4e-45fd-82a6-99e7b87148e0	27770
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27770
28f89919-4d4e-45fd-82a6-99e7b87148e0	27772
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27772
28f89919-4d4e-45fd-82a6-99e7b87148e0	27774
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27774
28f89919-4d4e-45fd-82a6-99e7b87148e0	27765
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27765
28f89919-4d4e-45fd-82a6-99e7b87148e0	27767
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27767
28f89919-4d4e-45fd-82a6-99e7b87148e0	27769
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27769
28f89919-4d4e-45fd-82a6-99e7b87148e0	27771
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27771
28f89919-4d4e-45fd-82a6-99e7b87148e0	27773
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27773
28f89919-4d4e-45fd-82a6-99e7b87148e0	27775
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27775
28f89919-4d4e-45fd-82a6-99e7b87148e0	27776
b7adec69-be7c-4df6-ab05-bf27091b7cd1	27776
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27696
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27696
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27697
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27697
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27698
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27698
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27699
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27699
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27700
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27700
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27701
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27701
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27702
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27702
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27703
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27703
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27704
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27704
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27705
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27705
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27706
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27706
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27707
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27707
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27708
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27708
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27709
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27709
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27710
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27710
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27711
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27711
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27712
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27712
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27713
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27713
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27777
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27777
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27778
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27778
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27779
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27779
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27781
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27781
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27783
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27783
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27785
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27785
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27787
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27787
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27789
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27789
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27791
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27791
bf556d10-db9d-41b8-a0f5-dfd606f6f050	27780
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	27780
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27714
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27714
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27716
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27716
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27715
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27715
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27735
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27735
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27717
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27717
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27737
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27737
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27718
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27718
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27739
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27739
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27719
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27719
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27741
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27741
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27720
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27720
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27742
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27742
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27722
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27722
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27743
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27743
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27744
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27744
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27724
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27724
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27726
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27726
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27745
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27745
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27721
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27721
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27723
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27723
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27725
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27725
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27727
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27727
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27728
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27728
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27729
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27729
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27730
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27730
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27731
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27731
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27732
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27732
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27733
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27733
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27734
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27734
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27736
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27736
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27738
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27738
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27740
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27740
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27782
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27782
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27784
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27784
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27786
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27786
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27788
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27788
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27790
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27790
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27792
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27792
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27793
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27793
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27794
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27794
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27795
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27795
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27797
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27797
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27799
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27799
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27801
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27801
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27803
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27803
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27806
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27806
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27808
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27808
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27796
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27796
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27798
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27798
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27800
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27800
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27802
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27802
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27804
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27804
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27805
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27805
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27807
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27807
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27809
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27809
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27810
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27810
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27811
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27811
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27812
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27812
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27813
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27813
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27814
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27814
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27815
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27815
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	27816
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	27816
\.


--
-- Data for Name: processed_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.processed_events (id, algorithm_id, direction, tag_epc, user_id, group_id, confidence, centroid_separation_factor, cluster_size_factor, bilateral_coverage_factor, rssi_trend_consistency_factor, "timestamp", cluster_started_at, cluster_ended_at, metadata, synced_to_integration, created_at, navigo3_record_id) FROM stdin;
0f383922-4cda-400f-8e86-541496d5f5dd	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.4007378	0.5009222	1	0.8	\N	2026-05-12 02:43:39.342+02	2026-05-12 02:43:38.437+02	2026-05-12 02:43:41.663+02	{"centroidDeltaMs": 1615.97509765625, "insideScanCount": 16, "insideCentroidMs": 1778546619342.625, "outsideScanCount": 20, "clusterDurationMs": 3226, "outsideCentroidMs": 1778546620958.6}	f	2026-05-12 02:44:13.570702+02	\N
348c095d-ff04-4765-9b96-a5f365be1def	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.29876298	0.5335053	1	0.8	0.7	2026-05-12 02:43:39.307+02	2026-05-12 02:43:38.437+02	2026-05-12 02:43:41.663+02	{"rssiTrend": {"inside": {"r2": 0.08924473608995254, "slope": -0.00657294324180256}, "outside": {"r2": 0.7333622477409976, "slope": 0.013709510908470638}}, "rssiWeights": {"inside": [0.52, 0.62, 0.98, 1, 1, 1, 1, 1, 0.88, 0.94, 0.8200000000000001, 0.6799999999999999, 0.6799999999999999, 0.56, 0.54, 0.43999999999999995], "outside": [0.4, 0.5800000000000001, 0.56, 0.52, 0.64, 0.64, 0.64, 0.76, 0.76, 0.74, 0.9, 0.84, 0.8, 0.86, 0.88, 0.88, 0.88, 0.86, 0.76, 0.8200000000000001]}, "centroidDeltaMs": 1721.088134765625, "insideScanCount": 16, "insideCentroidMs": 1778546619307.6633, "outsideScanCount": 20, "clusterDurationMs": 3226, "outsideCentroidMs": 1778546621028.7515}	f	2026-05-12 02:44:13.570702+02	\N
b0f811a9-5572-4f23-895f-17919288b96b	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.46130183	0.51665807	1	0.89285713	\N	2026-05-12 02:43:54.149+02	2026-05-12 02:43:53.399+02	2026-05-12 02:43:57.012+02	{"centroidDeltaMs": 1866.685546875, "insideScanCount": 25, "insideCentroidMs": 1778546636016.4, "outsideScanCount": 28, "clusterDurationMs": 3613, "outsideCentroidMs": 1778546634149.7144}	f	2026-05-12 02:44:13.596281+02	\N
1a6dab08-758e-434f-ad17-709a62cc09cb	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.3412245	0.5459592	1	0.89285713	0.7	2026-05-12 02:43:54.148+02	2026-05-12 02:43:53.399+02	2026-05-12 02:43:57.012+02	{"rssiTrend": {"inside": {"r2": 0.6252504203008326, "slope": 0.008495687488530555}, "outside": {"r2": 0.0011450875207223987, "slope": -0.000301041502044102}}, "rssiWeights": {"inside": [0.5, 0.43999999999999995, 0.38, 0.5, 0.5, 0.38, 0.5800000000000001, 0.5800000000000001, 0.6799999999999999, 0.72, 0.78, 0.6799999999999999, 0.74, 0.7, 0.6799999999999999, 0.7, 0.76, 0.8, 0.76, 0.76, 0.84, 0.7, 0.84, 0.56, 0.78], "outside": [0.45999999999999996, 0.52, 0.56, 0.52, 0.62, 0.62, 0.5800000000000001, 0.5800000000000001, 0.72, 0.72, 0.52, 0.52, 0.62, 0.62, 0.62, 0.62, 0.5800000000000001, 0.5800000000000001, 0.6599999999999999, 0.6599999999999999, 0.52, 0.4, 0.52, 0.56, 0.62, 0.5800000000000001, 0.56, 0.52]}, "centroidDeltaMs": 1972.550537109375, "insideScanCount": 25, "insideCentroidMs": 1778546636120.6633, "outsideScanCount": 28, "clusterDurationMs": 3613, "outsideCentroidMs": 1778546634148.1128}	f	2026-05-12 02:44:13.596281+02	\N
1fcf0857-c5d9-4683-8231-80dc1740bb83	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23566814	0.41896558	1	0.5625	\N	2026-05-12 02:44:29.902+02	2026-05-12 02:44:27.807+02	2026-05-12 02:44:33.035+02	{"centroidDeltaMs": 2190.35205078125, "insideScanCount": 48, "insideCentroidMs": 1778546669902.8333, "outsideScanCount": 27, "clusterDurationMs": 5228, "outsideCentroidMs": 1778546672093.1853}	f	2026-05-12 02:45:00.99576+02	\N
0665909d-4935-4111-b094-af33ce372e96	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.021079475	0.37474623	1	0.5625	0.1	2026-05-12 02:44:30.098+02	2026-05-12 02:44:27.807+02	2026-05-12 02:44:33.035+02	{"rssiTrend": {"inside": {"r2": 0.3513547132858901, "slope": 0.0051227793446719}, "outside": {"r2": 0.10934611547150574, "slope": -0.003662695937264282}}, "rssiWeights": {"inside": [0.21999999999999997, 0.19999999999999996, 0.4, 0.52, 0.45999999999999996, 0.38, 0.45999999999999996, 0.48, 0.33999999999999997, 0.52, 0.56, 0.62, 0.43999999999999995, 0.43999999999999995, 0.5, 0.43999999999999995, 0.5800000000000001, 0.72, 0.6799999999999999, 0.5800000000000001, 0.7, 0.7, 0.6799999999999999, 0.72, 0.84, 0.8200000000000001, 0.8200000000000001, 0.76, 0.88, 0.86, 0.84, 0.84, 0.92, 0.94, 0.8200000000000001, 0.88, 0.86, 0.74, 0.9, 0.74, 0.76, 0.76, 0.6799999999999999, 0.62, 0.6, 0.62, 0.56, 0.28], "outside": [0.5, 0.5800000000000001, 0.62, 0.7, 0.76, 0.8, 0.8200000000000001, 0.8, 0.88, 0.92, 0.88, 0.9, 0.88, 0.76, 0.76, 0.7, 0.6799999999999999, 0.7, 0.78, 0.7, 0.7, 0.6799999999999999, 0.5800000000000001, 0.5, 0.5, 0.52, 0.52]}, "centroidDeltaMs": 1959.17333984375, "insideScanCount": 48, "insideCentroidMs": 1778546670098.3958, "outsideScanCount": 27, "clusterDurationMs": 5228, "outsideCentroidMs": 1778546672057.569}	f	2026-05-12 02:45:00.99576+02	\N
ca2aa626-ad16-431b-8220-a29b9baf86d5	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.26996753	0.48594153	1	0.5555556	\N	2026-05-12 02:44:45.219+02	2026-05-12 02:44:44.499+02	2026-05-12 02:44:48.857+02	{"centroidDeltaMs": 2117.733154296875, "insideScanCount": 36, "insideCentroidMs": 1778546687337.3333, "outsideScanCount": 20, "clusterDurationMs": 4358, "outsideCentroidMs": 1778546685219.6}	f	2026-05-12 02:45:01.014526+02	\N
dd667648-1c77-4d97-b915-d2c8e0bfd3cc	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.11134939	0.5010722	1	0.5555556	0.4	2026-05-12 02:44:45.234+02	2026-05-12 02:44:44.499+02	2026-05-12 02:44:48.857+02	{"rssiTrend": {"inside": {"r2": 0.20960094123797623, "slope": 0.0027056031627694264}, "outside": {"r2": 0.13544937855231565, "slope": 0.0025749300465732292}}, "rssiWeights": {"inside": [0.28, 0.33999999999999997, 0.31999999999999995, 0.38, 0.31999999999999995, 0.52, 0.52, 0.45999999999999996, 0.56, 0.45999999999999996, 0.45999999999999996, 0.5, 0.56, 0.64, 0.56, 0.5800000000000001, 0.56, 0.5800000000000001, 0.5800000000000001, 0.56, 0.74, 0.5800000000000001, 0.64, 0.6799999999999999, 0.64, 0.56, 0.6, 0.56, 0.5800000000000001, 0.64, 0.52, 0.43999999999999995, 0.5, 0.43999999999999995, 0.5800000000000001, 0.42000000000000004], "outside": [0.64, 0.5, 0.56, 0.64, 0.56, 0.5800000000000001, 0.6, 0.64, 0.64, 0.6599999999999999, 0.64, 0.5800000000000001, 0.5800000000000001, 0.62, 0.56, 0.64, 0.72, 0.72, 0.7, 0.52]}, "centroidDeltaMs": 2183.6728515625, "insideScanCount": 36, "insideCentroidMs": 1778546687418.305, "outsideScanCount": 20, "clusterDurationMs": 4358, "outsideCentroidMs": 1778546685234.632}	f	2026-05-12 02:45:01.014526+02	\N
6d2808e6-7590-4859-86e8-96b8be78663c	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.33664328	0.4713006	1	0.71428573	\N	2026-05-12 02:45:29.065+02	2026-05-12 02:45:27.674+02	2026-05-12 02:45:31.582+02	{"centroidDeltaMs": 1841.8427734375, "insideScanCount": 28, "insideCentroidMs": 1778546729065.1072, "outsideScanCount": 20, "clusterDurationMs": 3908, "outsideCentroidMs": 1778546730906.95}	f	2026-05-12 02:46:31.8735+02	\N
af534296-abaa-4e8d-9d8f-65fb4c6b3344	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.15722218	0.44022208	1	0.71428573	0.5	2026-05-12 02:45:29.087+02	2026-05-12 02:45:27.674+02	2026-05-12 02:45:31.582+02	{"rssiTrend": {"inside": {"r2": 0.012864971297279926, "slope": 0.0016064924952732865}, "outside": {"r2": 0.7042920427192805, "slope": -0.019381742339662892}}, "rssiWeights": {"inside": [0.43999999999999995, 0.54, 0.5, 0.52, 0.5800000000000001, 0.7, 0.7, 0.74, 0.76, 0.88, 0.94, 1, 1, 1, 1, 1, 1, 1, 1, 0.98, 0.8, 0.8, 0.76, 0.6799999999999999, 0.56, 0.45999999999999996, 0.52, 0.36], "outside": [0.9, 0.88, 0.86, 0.94, 0.94, 0.98, 0.92, 0.86, 0.9, 0.8200000000000001, 0.76, 0.9, 0.78, 0.78, 0.54, 0.5, 0.38, 0.43999999999999995, 0.4, 0.45999999999999996]}, "centroidDeltaMs": 1720.387939453125, "insideScanCount": 28, "insideCentroidMs": 1778546729087.397, "outsideScanCount": 20, "clusterDurationMs": 3908, "outsideCentroidMs": 1778546730807.785}	f	2026-05-12 02:46:31.8735+02	\N
a35ffbf5-59b4-4b8c-b162-cca9a914dfec	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.39125347	0.4933196	1	0.79310346	\N	2026-05-12 02:45:43.366+02	2026-05-12 02:45:42.509+02	2026-05-12 02:45:46.609+02	{"centroidDeltaMs": 2022.6103515625, "insideScanCount": 29, "insideCentroidMs": 1778546745388.8276, "outsideScanCount": 23, "clusterDurationMs": 4100, "outsideCentroidMs": 1778546743366.2173}	f	2026-05-12 02:46:31.890009+02	\N
befff389-aa8a-4411-94de-4e57b9de2cc3	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.28276077	0.5093206	1	0.79310346	0.7	2026-05-12 02:45:43.381+02	2026-05-12 02:45:42.509+02	2026-05-12 02:45:46.609+02	{"rssiTrend": {"inside": {"r2": 0.3610419243911227, "slope": 0.004088064609466293}, "outside": {"r2": 0.01874335688178741, "slope": 0.0019474494567963503}}, "rssiWeights": {"inside": [0.38, 0.43999999999999995, 0.5, 0.43999999999999995, 0.48, 0.52, 0.43999999999999995, 0.43999999999999995, 0.56, 0.62, 0.43999999999999995, 0.52, 0.5800000000000001, 0.72, 0.5800000000000001, 0.64, 0.5800000000000001, 0.7, 0.76, 0.76, 0.64, 0.52, 0.56, 0.56, 0.72, 0.6599999999999999, 0.62, 0.5800000000000001, 0.52], "outside": [0.42000000000000004, 0.45999999999999996, 0.54, 0.5, 0.64, 0.64, 0.5800000000000001, 0.56, 0.6799999999999999, 0.78, 0.6799999999999999, 0.76, 0.74, 0.84, 0.74, 0.6599999999999999, 0.78, 0.76, 0.7, 0.72, 0.52, 0.33999999999999997, 0.33999999999999997]}, "centroidDeltaMs": 2088.214599609375, "insideScanCount": 29, "insideCentroidMs": 1778546745469.5374, "outsideScanCount": 23, "clusterDurationMs": 4100, "outsideCentroidMs": 1778546743381.3228}	f	2026-05-12 02:46:31.890009+02	\N
1e95f7ca-20ba-4d1e-ab92-180975f4322f	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.41439652	0.45879614	1	0.9032258	\N	2026-05-12 02:45:59.028+02	2026-05-12 02:45:57.497+02	2026-05-12 02:46:02.339+02	{"centroidDeltaMs": 2221.490966796875, "insideScanCount": 28, "insideCentroidMs": 1778546759028.9285, "outsideScanCount": 31, "clusterDurationMs": 4842, "outsideCentroidMs": 1778546761250.4194}	f	2026-05-12 02:46:31.913206+02	\N
67c9e66f-06be-4a11-8269-94cf0eb20889	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.19566433	0.43325675	1	0.9032258	0.5	2026-05-12 02:45:59.121+02	2026-05-12 02:45:57.497+02	2026-05-12 02:46:02.339+02	{"rssiTrend": {"inside": {"r2": 0.19101059458729308, "slope": 0.0052190951617564285}, "outside": {"r2": 0.05406562650894975, "slope": -0.002515138386660698}}, "rssiWeights": {"inside": [0.33999999999999997, 0.52, 0.48, 0.43999999999999995, 0.52, 0.5800000000000001, 0.6799999999999999, 0.78, 0.78, 0.76, 0.8, 0.8200000000000001, 0.8, 0.9, 0.86, 0.9, 0.86, 0.92, 0.94, 0.98, 0.94, 1, 0.92, 0.8, 0.8200000000000001, 0.5800000000000001, 0.45999999999999996, 0.4], "outside": [0.45999999999999996, 0.56, 0.64, 0.56, 0.62, 0.6799999999999999, 0.7, 0.84, 0.9, 0.96, 0.88, 1, 0.86, 0.88, 0.88, 0.8200000000000001, 0.8, 0.78, 0.6799999999999999, 0.74, 0.7, 0.6799999999999999, 0.7, 0.64, 0.64, 0.6799999999999999, 0.6, 0.6, 0.56, 0.43999999999999995, 0.5]}, "centroidDeltaMs": 2097.8291015625, "insideScanCount": 28, "insideCentroidMs": 1778546759121.6528, "outsideScanCount": 31, "clusterDurationMs": 4842, "outsideCentroidMs": 1778546761219.482}	f	2026-05-12 02:46:31.913206+02	\N
b5dd7436-a2eb-4d6d-b5bb-e0df07f9be26	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.5438165	0.6163254	1	0.88235295	\N	2026-05-12 02:46:14.033+02	2026-05-12 02:46:13.439+02	2026-05-12 02:46:16.998+02	{"centroidDeltaMs": 2193.501953125, "insideScanCount": 17, "insideCentroidMs": 1778546776227.2354, "outsideScanCount": 15, "clusterDurationMs": 3559, "outsideCentroidMs": 1778546774033.7334}	f	2026-05-12 02:46:31.932017+02	\N
dbc00dd1-4f7a-4d95-bc2a-a6984ea86799	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.21914135	0.6209005	1	0.88235295	0.4	2026-05-12 02:46:14.058+02	2026-05-12 02:46:13.439+02	2026-05-12 02:46:16.998+02	{"rssiTrend": {"inside": {"r2": 0.22569828880846554, "slope": 0.003560240495438017}, "outside": {"r2": 0.30292377693967254, "slope": 0.006719994237595253}}, "rssiWeights": {"inside": [0.43999999999999995, 0.4, 0.45999999999999996, 0.5, 0.5800000000000001, 0.56, 0.64, 0.78, 0.62, 0.52, 0.56, 0.56, 0.5800000000000001, 0.6, 0.56, 0.62, 0.5], "outside": [0.45999999999999996, 0.43999999999999995, 0.6799999999999999, 0.5800000000000001, 0.72, 0.6799999999999999, 0.6799999999999999, 0.6599999999999999, 0.56, 0.6799999999999999, 0.62, 0.72, 0.6799999999999999, 0.6799999999999999, 0.64]}, "centroidDeltaMs": 2209.784912109375, "insideScanCount": 17, "insideCentroidMs": 1778546776268.3967, "outsideScanCount": 15, "clusterDurationMs": 3559, "outsideCentroidMs": 1778546774058.6118}	f	2026-05-12 02:46:31.932017+02	\N
58f31fbd-0182-4fc3-9a5a-a2e1a5c8e6da	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23731571	0.5370829	1	0.44186047	\N	2026-05-12 02:46:51.47+02	2026-05-12 02:46:50.557+02	2026-05-12 02:46:54.729+02	{"centroidDeltaMs": 2240.7099609375, "insideScanCount": 19, "insideCentroidMs": 1778546811470.8948, "outsideScanCount": 43, "clusterDurationMs": 4172, "outsideCentroidMs": 1778546813711.6047}	f	2026-05-12 02:47:16.488149+02	\N
9d5ae2ae-bb81-45d2-9e10-3a90486f2eb4	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.11502955	0.5206601	1	0.44186047	0.5	2026-05-12 02:46:51.54+02	2026-05-12 02:46:50.557+02	2026-05-12 02:46:54.729+02	{"rssiTrend": {"inside": {"r2": 0.4211750569367071, "slope": 0.01106151118500641}, "outside": {"r2": 0.00005464110940633926, "slope": 0.00008336237772002212}}, "rssiWeights": {"inside": [0.43999999999999995, 0.45999999999999996, 0.62, 0.62, 0.72, 0.74, 0.8200000000000001, 0.8200000000000001, 0.96, 0.98, 1, 0.9, 1, 1, 0.86, 0.92, 0.76, 0.8, 0.74], "outside": [0.38, 0.52, 0.31999999999999995, 0.45999999999999996, 0.5800000000000001, 0.56, 0.52, 0.56, 0.7, 0.62, 0.72, 0.6799999999999999, 0.8, 0.76, 0.84, 0.8200000000000001, 0.8, 0.8200000000000001, 0.8200000000000001, 0.9, 0.84, 0.8200000000000001, 0.8200000000000001, 0.8, 0.76, 0.76, 0.76, 0.76, 0.72, 0.72, 0.6799999999999999, 0.6799999999999999, 0.5800000000000001, 0.5800000000000001, 0.5, 0.5, 0.4, 0.4, 0.52, 0.52, 0.38, 0.43999999999999995, 0.42000000000000004]}, "centroidDeltaMs": 2172.19384765625, "insideScanCount": 19, "insideCentroidMs": 1778546811540.6963, "outsideScanCount": 43, "clusterDurationMs": 4172, "outsideCentroidMs": 1778546813712.8901}	f	2026-05-12 02:47:16.488149+02	\N
28f89919-4d4e-45fd-82a6-99e7b87148e0	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.23898312	0.61737305	1	0.38709676	\N	2026-05-12 02:47:30.845+02	2026-05-12 02:47:30.359+02	2026-05-12 02:47:34.81+02	{"centroidDeltaMs": 2747.927490234375, "insideScanCount": 31, "insideCentroidMs": 1778546853593.6775, "outsideScanCount": 12, "clusterDurationMs": 4451, "outsideCentroidMs": 1778546850845.75}	f	2026-05-12 02:48:18.264147+02	\N
b7adec69-be7c-4df6-ab05-bf27091b7cd1	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.09582171	0.61884856	1	0.38709676	0.4	2026-05-12 02:47:30.885+02	2026-05-12 02:47:30.359+02	2026-05-12 02:47:34.81+02	{"rssiTrend": {"inside": {"r2": 0.19546370021276793, "slope": 0.002569710650529164}, "outside": {"r2": 0.4878637610310651, "slope": 0.01095209418333744}}, "rssiWeights": {"inside": [0.54, 0.43999999999999995, 0.43999999999999995, 0.52, 0.5, 0.43999999999999995, 0.5800000000000001, 0.64, 0.62, 0.64, 0.7, 0.6799999999999999, 0.6799999999999999, 0.62, 0.7, 0.7, 0.62, 0.64, 0.64, 0.6799999999999999, 0.7, 0.7, 0.7, 0.6799999999999999, 0.72, 0.62, 0.6799999999999999, 0.7, 0.52, 0.5, 0.56], "outside": [0.31999999999999995, 0.45999999999999996, 0.54, 0.52, 0.43999999999999995, 0.6599999999999999, 0.6599999999999999, 0.62, 0.62, 0.64, 0.5800000000000001, 0.5800000000000001]}, "centroidDeltaMs": 2754.494873046875, "insideScanCount": 31, "insideCentroidMs": 1778546853639.7812, "outsideScanCount": 12, "clusterDurationMs": 4451, "outsideCentroidMs": 1778546850885.2864}	f	2026-05-12 02:48:18.264147+02	\N
bf556d10-db9d-41b8-a0f5-dfd606f6f050	temporal_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.36096242	0.64973235	1	0.5555556	\N	2026-05-12 02:47:45.273+02	2026-05-12 02:47:44.687+02	2026-05-12 02:47:48.133+02	{"centroidDeltaMs": 2238.977783203125, "insideScanCount": 10, "insideCentroidMs": 1778546865273.8, "outsideScanCount": 18, "clusterDurationMs": 3446, "outsideCentroidMs": 1778546867512.7778}	f	2026-05-12 02:48:18.281107+02	\N
fa2f7fbc-e8b9-4ab5-bc64-11f16c88497c	rssi_weighted_centroid	out	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.14283302	0.6427486	1	0.5555556	0.4	2026-05-12 02:47:45.344+02	2026-05-12 02:47:44.687+02	2026-05-12 02:47:48.133+02	{"rssiTrend": {"inside": {"r2": 0.43849698503276957, "slope": 0.011836595187858316}, "outside": {"r2": 0.29390323745725744, "slope": 0.0053589698179358465}}, "rssiWeights": {"inside": [0.31999999999999995, 0.38, 0.19999999999999996, 0.54, 0.45999999999999996, 0.45999999999999996, 0.72, 0.5, 0.5, 0.52], "outside": [0.31999999999999995, 0.45999999999999996, 0.43999999999999995, 0.52, 0.45999999999999996, 0.52, 0.7, 0.54, 0.56, 0.62, 0.5, 0.64, 0.56, 0.62, 0.7, 0.48, 0.43999999999999995, 0.52]}, "centroidDeltaMs": 2214.91162109375, "insideScanCount": 10, "insideCentroidMs": 1778546865344.0261, "outsideScanCount": 18, "clusterDurationMs": 3446, "outsideCentroidMs": 1778546867558.9377}	f	2026-05-12 02:48:18.281107+02	\N
c7c1ce8c-b85b-4da1-9101-d90b6d55669f	temporal_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.52268654	0.5575323	1	0.9375	\N	2026-05-12 02:47:59.991+02	2026-05-12 02:47:59.239+02	2026-05-12 02:48:03.788+02	{"centroidDeltaMs": 2536.214599609375, "insideScanCount": 30, "insideCentroidMs": 1778546882527.4333, "outsideScanCount": 32, "clusterDurationMs": 4549, "outsideCentroidMs": 1778546879991.2188}	f	2026-05-12 02:48:18.302975+02	\N
28c3cb9c-56ff-4ddc-ad7a-85e42aac71c7	rssi_weighted_centroid	in	E28011704000021D53DAB0CB	f908224d-2e38-409a-bc7f-81902406f95b	5	0.2628549	0.56075716	1	0.9375	0.5	2026-05-12 02:47:59.999+02	2026-05-12 02:47:59.239+02	2026-05-12 02:48:03.788+02	{"rssiTrend": {"inside": {"r2": 0.030613359714054766, "slope": 0.0011478015977608345}, "outside": {"r2": 0.015319710097425054, "slope": 0.0014336808549057563}}, "rssiWeights": {"inside": [0.45999999999999996, 0.56, 0.62, 0.45999999999999996, 0.56, 0.6599999999999999, 0.6599999999999999, 0.56, 0.52, 0.5800000000000001, 0.6599999999999999, 0.5800000000000001, 0.64, 0.78, 0.74, 0.7, 0.64, 0.8200000000000001, 0.9, 0.6799999999999999, 0.8200000000000001, 0.64, 0.5800000000000001, 0.6799999999999999, 0.56, 0.62, 0.52, 0.62, 0.62, 0.45999999999999996], "outside": [0.31999999999999995, 0.5800000000000001, 0.6799999999999999, 0.6799999999999999, 0.78, 0.78, 0.74, 0.74, 0.8, 0.8, 0.74, 0.74, 0.76, 0.76, 0.76, 0.76, 0.88, 0.88, 0.8, 0.88, 0.76, 0.8200000000000001, 0.8, 0.84, 0.72, 0.8200000000000001, 0.8, 0.6799999999999999, 0.74, 0.74, 0.64, 0.5]}, "centroidDeltaMs": 2550.88427734375, "insideScanCount": 30, "insideCentroidMs": 1778546882550.7878, "outsideScanCount": 32, "clusterDurationMs": 4549, "outsideCentroidMs": 1778546879999.9036}	f	2026-05-12 02:48:18.302975+02	\N
\.


--
-- Data for Name: raw_scans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.raw_scans (id, lighthouse_id, epc, epc_length, rssi_dbm, antenna_id, frequency, sequence_number, detection_confidence, timestamp_ms, "timestamp", received_at, processed_at, orphaned_at, orphan_reason, source, time_basis, created_at, offline_sync_pending) FROM stdin;
27275	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546634887	2026-05-12 02:43:54.887+02	2026-05-12 02:44:13.21234+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.21234+02	f
27277	9	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546635117	2026-05-12 02:43:55.117+02	2026-05-12 02:44:13.21666+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.21666+02	f
27279	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546635271	2026-05-12 02:43:55.271+02	2026-05-12 02:44:13.223191+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.223191+02	f
27281	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546635517	2026-05-12 02:43:55.517+02	2026-05-12 02:44:13.226916+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.226916+02	f
27284	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546635834	2026-05-12 02:43:55.834+02	2026-05-12 02:44:13.239935+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.239935+02	f
27286	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546635973	2026-05-12 02:43:55.973+02	2026-05-12 02:44:13.243507+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.243507+02	f
27287	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546636047	2026-05-12 02:43:56.047+02	2026-05-12 02:44:13.245186+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.245186+02	f
27289	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546636122	2026-05-12 02:43:56.122+02	2026-05-12 02:44:13.2474+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.2474+02	f
27291	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546636198	2026-05-12 02:43:56.198+02	2026-05-12 02:44:13.250929+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.250929+02	f
27293	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546636276	2026-05-12 02:43:56.276+02	2026-05-12 02:44:13.256178+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.256178+02	f
27296	9	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546636704	2026-05-12 02:43:56.704+02	2026-05-12 02:44:13.260616+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.260616+02	f
27299	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546636937	2026-05-12 02:43:56.937+02	2026-05-12 02:44:13.266942+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.266942+02	f
27641	10	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546812199	2026-05-12 02:46:52.199+02	2026-05-12 02:47:15.063448+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.063448+02	f
27605	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546775107	2026-05-12 02:46:15.107+02	2026-05-12 02:46:30.311657+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.311657+02	f
27608	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546775624	2026-05-12 02:46:15.624+02	2026-05-12 02:46:30.345689+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.345689+02	f
27612	9	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546776250	2026-05-12 02:46:16.25+02	2026-05-12 02:46:30.355854+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.355854+02	f
27698	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546867005	2026-05-12 02:47:47.005+02	2026-05-12 02:48:15.347025+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.347025+02	f
27211	10	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546620139	2026-05-12 02:43:40.139+02	2026-05-12 02:44:09.833133+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.833133+02	f
27212	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546620359	2026-05-12 02:43:40.359+02	2026-05-12 02:44:09.83648+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.83648+02	f
27213	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546620423	2026-05-12 02:43:40.423+02	2026-05-12 02:44:09.83889+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.83889+02	f
27214	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546620489	2026-05-12 02:43:40.489+02	2026-05-12 02:44:09.841293+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.841293+02	f
27215	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546620553	2026-05-12 02:43:40.553+02	2026-05-12 02:44:09.843743+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.843743+02	f
27431	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546730109	2026-05-12 02:45:30.109+02	2026-05-12 02:46:29.765064+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.765064+02	f
27432	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546730249	2026-05-12 02:45:30.249+02	2026-05-12 02:46:29.770922+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.770922+02	f
27433	10	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546730323	2026-05-12 02:45:30.323+02	2026-05-12 02:46:29.781077+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.781077+02	f
27434	10	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546730385	2026-05-12 02:45:30.385+02	2026-05-12 02:46:29.786213+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.786213+02	f
27525	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546728389	2026-05-12 02:45:28.389+02	2026-05-12 02:46:30.052884+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.052884+02	f
27532	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546729042	2026-05-12 02:45:29.042+02	2026-05-12 02:46:30.076231+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.076231+02	f
27538	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546729971	2026-05-12 02:45:29.971+02	2026-05-12 02:46:30.111233+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.111233+02	f
27546	9	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546743977	2026-05-12 02:45:43.977+02	2026-05-12 02:46:30.11914+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.11914+02	f
27559	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546745477	2026-05-12 02:45:45.477+02	2026-05-12 02:46:30.140815+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.140815+02	f
27574	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546746533	2026-05-12 02:45:46.533+02	2026-05-12 02:46:30.167828+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.167828+02	f
27580	9	E28011704000021D53DAB0CB	\N	-66	1	0	\N	\N	1778546757721	2026-05-12 02:45:57.721+02	2026-05-12 02:46:30.197011+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.197011+02	f
27588	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546758378	2026-05-12 02:45:58.378+02	2026-05-12 02:46:30.207981+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.207981+02	f
27594	9	E28011704000021D53DAB0CB	\N	-44	1	0	\N	\N	1778546759384	2026-05-12 02:45:59.384+02	2026-05-12 02:46:30.272318+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.272318+02	f
27598	9	E28011704000021D53DAB0CB	\N	-39	1	0	\N	\N	1778546759749	2026-05-12 02:45:59.749+02	2026-05-12 02:46:30.279983+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.279983+02	f
27601	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546760033	2026-05-12 02:46:00.033+02	2026-05-12 02:46:30.303971+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.303971+02	f
27231	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546633399	2026-05-12 02:43:53.399+02	2026-05-12 02:44:10.245027+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.245027+02	f
27233	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546633464	2026-05-12 02:43:53.464+02	2026-05-12 02:44:10.247266+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.247266+02	f
27235	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546633639	2026-05-12 02:43:53.639+02	2026-05-12 02:44:10.249032+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.249032+02	f
27237	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546633706	2026-05-12 02:43:53.706+02	2026-05-12 02:44:10.253031+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.253031+02	f
27238	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546634057	2026-05-12 02:43:54.057+02	2026-05-12 02:44:10.256105+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.256105+02	f
27240	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546634181	2026-05-12 02:43:54.181+02	2026-05-12 02:44:10.259954+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.259954+02	f
27242	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546634315	2026-05-12 02:43:54.315+02	2026-05-12 02:44:10.263752+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.263752+02	f
27243	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546634380	2026-05-12 02:43:54.38+02	2026-05-12 02:44:10.506618+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.506618+02	f
27523	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546728223	2026-05-12 02:45:28.223+02	2026-05-12 02:46:30.048924+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.048924+02	f
27530	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546728876	2026-05-12 02:45:28.876+02	2026-05-12 02:46:30.069943+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.069943+02	f
27544	9	E28011704000021D53DAB0CB	\N	-72	1	0	\N	\N	1778546730350	2026-05-12 02:45:30.35+02	2026-05-12 02:46:30.117198+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.117198+02	f
27551	9	E28011704000021D53DAB0CB	\N	-66	1	0	\N	\N	1778546744541	2026-05-12 02:45:44.541+02	2026-05-12 02:46:30.128922+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.128922+02	f
27558	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546744868	2026-05-12 02:45:44.868+02	2026-05-12 02:46:30.138815+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.138815+02	f
27566	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546745804	2026-05-12 02:45:45.804+02	2026-05-12 02:46:30.148377+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.148377+02	f
27245	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546634513	2026-05-12 02:43:54.513+02	2026-05-12 02:44:10.510921+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.510921+02	f
27276	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546634971	2026-05-12 02:43:54.971+02	2026-05-12 02:44:13.21465+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.21465+02	f
27278	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546635194	2026-05-12 02:43:55.194+02	2026-05-12 02:44:13.218676+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.218676+02	f
27280	9	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546635352	2026-05-12 02:43:55.352+02	2026-05-12 02:44:13.224931+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.224931+02	f
27282	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546635678	2026-05-12 02:43:55.678+02	2026-05-12 02:44:13.228942+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.228942+02	f
27283	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546635763	2026-05-12 02:43:55.763+02	2026-05-12 02:44:13.238035+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.238035+02	f
27285	9	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546635903	2026-05-12 02:43:55.903+02	2026-05-12 02:44:13.241862+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.241862+02	f
27288	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546636358	2026-05-12 02:43:56.358+02	2026-05-12 02:44:13.245482+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.245482+02	f
27223	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546621122	2026-05-12 02:43:41.122+02	2026-05-12 02:44:09.984362+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.984362+02	f
27224	10	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546621189	2026-05-12 02:43:41.189+02	2026-05-12 02:44:09.987181+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.987181+02	f
27225	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546621299	2026-05-12 02:43:41.299+02	2026-05-12 02:44:09.989559+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.989559+02	f
27226	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546621366	2026-05-12 02:43:41.366+02	2026-05-12 02:44:09.993613+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.993613+02	f
27227	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546621464	2026-05-12 02:43:41.464+02	2026-05-12 02:44:10.235377+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.235377+02	f
27228	10	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546621529	2026-05-12 02:43:41.529+02	2026-05-12 02:44:10.237979+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.237979+02	f
27229	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546621596	2026-05-12 02:43:41.596+02	2026-05-12 02:44:10.240463+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.240463+02	f
27230	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546621663	2026-05-12 02:43:41.663+02	2026-05-12 02:44:10.24245+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.24245+02	f
27260	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546618567	2026-05-12 02:43:38.567+02	2026-05-12 02:44:13.127765+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.127765+02	f
27262	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546618941	2026-05-12 02:43:38.941+02	2026-05-12 02:44:13.132078+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.132078+02	f
27264	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546619170	2026-05-12 02:43:39.17+02	2026-05-12 02:44:13.136596+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.136596+02	f
27266	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546619334	2026-05-12 02:43:39.334+02	2026-05-12 02:44:13.14365+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.14365+02	f
27267	9	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546619411	2026-05-12 02:43:39.411+02	2026-05-12 02:44:13.173101+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.173101+02	f
27269	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546619614	2026-05-12 02:43:39.614+02	2026-05-12 02:44:13.177071+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.177071+02	f
27271	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546619776	2026-05-12 02:43:39.776+02	2026-05-12 02:44:13.181039+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.181039+02	f
27273	9	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546619926	2026-05-12 02:43:39.926+02	2026-05-12 02:44:13.185484+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.185484+02	f
27290	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546636485	2026-05-12 02:43:56.485+02	2026-05-12 02:44:13.248292+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.248292+02	f
27292	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546636556	2026-05-12 02:43:56.556+02	2026-05-12 02:44:13.250929+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.250929+02	f
27294	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546636627	2026-05-12 02:43:56.627+02	2026-05-12 02:44:13.257729+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.257729+02	f
27295	9	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546637012	2026-05-12 02:43:57.012+02	2026-05-12 02:44:13.258674+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.258674+02	f
27298	9	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546636854	2026-05-12 02:43:56.854+02	2026-05-12 02:44:13.264771+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.264771+02	f
27232	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546633775	2026-05-12 02:43:53.775+02	2026-05-12 02:44:10.244638+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.244638+02	f
27667	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546814662	2026-05-12 02:46:54.662+02	2026-05-12 02:47:15.149978+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.149978+02	f
27669	10	E28011704000021D53DAB0CB	\N	-69	1	0	\N	\N	1778546814729	2026-05-12 02:46:54.729+02	2026-05-12 02:47:15.154983+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.154983+02	f
27234	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546633843	2026-05-12 02:43:53.843+02	2026-05-12 02:44:10.248047+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.248047+02	f
27236	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546633910	2026-05-12 02:43:53.91+02	2026-05-12 02:44:10.252993+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.252993+02	f
27239	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546634120	2026-05-12 02:43:54.12+02	2026-05-12 02:44:10.258014+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.258014+02	f
27241	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546634246	2026-05-12 02:43:54.246+02	2026-05-12 02:44:10.261722+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.261722+02	f
27244	10	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546634447	2026-05-12 02:43:54.447+02	2026-05-12 02:44:10.508736+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.508736+02	f
27671	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546814279	2026-05-12 02:46:54.279+02	2026-05-12 02:47:15.158534+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.158534+02	f
27674	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546814149	2026-05-12 02:46:54.149+02	2026-05-12 02:47:15.164604+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.164604+02	f
27677	10	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546814472	2026-05-12 02:46:54.472+02	2026-05-12 02:47:15.167309+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.167309+02	f
27680	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546814341	2026-05-12 02:46:54.341+02	2026-05-12 02:47:15.1702+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.1702+02	f
27683	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546814536	2026-05-12 02:46:54.536+02	2026-05-12 02:47:15.175856+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.175856+02	f
27480	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546761125	2026-05-12 02:46:01.125+02	2026-05-12 02:46:29.891037+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.891037+02	f
27488	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546761268	2026-05-12 02:46:01.268+02	2026-05-12 02:46:29.899757+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.899757+02	f
27494	10	E28011704000021D53DAB0CB	\N	-60	1	0	\N	\N	1778546762076	2026-05-12 02:46:02.076+02	2026-05-12 02:46:29.905678+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.905678+02	f
27501	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546761462	2026-05-12 02:46:01.462+02	2026-05-12 02:46:29.910987+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.910987+02	f
27577	9	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546758461	2026-05-12 02:45:58.461+02	2026-05-12 02:46:30.193765+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.193765+02	f
27585	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546758912	2026-05-12 02:45:58.912+02	2026-05-12 02:46:30.205067+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.205067+02	f
27599	9	E28011704000021D53DAB0CB	\N	-44	1	0	\N	\N	1778546759829	2026-05-12 02:45:59.829+02	2026-05-12 02:46:30.281907+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.281907+02	f
27606	9	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546775402	2026-05-12 02:46:15.402+02	2026-05-12 02:46:30.313359+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.313359+02	f
27613	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546776339	2026-05-12 02:46:16.339+02	2026-05-12 02:46:30.357762+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.357762+02	f
27441	10	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546731385	2026-05-12 02:45:31.385+02	2026-05-12 02:46:29.831454+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.831454+02	f
27443	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546731449	2026-05-12 02:45:31.449+02	2026-05-12 02:46:29.836992+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.836992+02	f
27448	10	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546731514	2026-05-12 02:45:31.514+02	2026-05-12 02:46:29.841717+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.841717+02	f
27452	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546731582	2026-05-12 02:45:31.582+02	2026-05-12 02:46:29.849113+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.849113+02	f
27521	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546727872	2026-05-12 02:45:27.872+02	2026-05-12 02:46:30.04471+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.04471+02	f
27528	9	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546728666	2026-05-12 02:45:28.666+02	2026-05-12 02:46:30.066136+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.066136+02	f
27535	9	E28011704000021D53DAB0CB	\N	-38	1	0	\N	\N	1778546729337	2026-05-12 02:45:29.337+02	2026-05-12 02:46:30.107016+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.107016+02	f
27317	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546669423	2026-05-12 02:44:29.423+02	2026-05-12 02:44:58.974619+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.974619+02	f
27320	9	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546669977	2026-05-12 02:44:29.977+02	2026-05-12 02:44:58.982381+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.982381+02	f
27322	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546670055	2026-05-12 02:44:30.055+02	2026-05-12 02:44:58.984435+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.984435+02	f
27324	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546670129	2026-05-12 02:44:30.129+02	2026-05-12 02:44:58.987753+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.987753+02	f
27326	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546670198	2026-05-12 02:44:30.198+02	2026-05-12 02:44:58.991698+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.991698+02	f
27328	9	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546670269	2026-05-12 02:44:30.269+02	2026-05-12 02:44:58.998929+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.998929+02	f
27330	9	E28011704000021D53DAB0CB	\N	-44	1	0	\N	\N	1778546670558	2026-05-12 02:44:30.558+02	2026-05-12 02:44:59.003872+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.003872+02	f
27332	9	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546670631	2026-05-12 02:44:30.631+02	2026-05-12 02:44:59.005929+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.005929+02	f
27334	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546670712	2026-05-12 02:44:30.712+02	2026-05-12 02:44:59.008592+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.008592+02	f
27336	9	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546670874	2026-05-12 02:44:30.874+02	2026-05-12 02:44:59.015454+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.015454+02	f
27542	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546730287	2026-05-12 02:45:30.287+02	2026-05-12 02:46:30.115367+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.115367+02	f
27456	10	E28011704000021D53DAB0CB	\N	-69	1	0	\N	\N	1778546742509	2026-05-12 02:45:42.509+02	2026-05-12 02:46:29.85465+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.85465+02	f
27458	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546742573	2026-05-12 02:45:42.573+02	2026-05-12 02:46:29.86247+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.86247+02	f
27467	10	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546742642	2026-05-12 02:45:42.642+02	2026-05-12 02:46:29.872708+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.872708+02	f
27472	10	E28011704000021D53DAB0CB	\N	-73	1	0	\N	\N	1778546744168	2026-05-12 02:45:44.168+02	2026-05-12 02:46:29.878852+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.878852+02	f
27556	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546744787	2026-05-12 02:45:44.787+02	2026-05-12 02:46:30.135307+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.135307+02	f
27347	9	E28011704000021D53DAB0CB	\N	-76	1	0	\N	\N	1778546685788	2026-05-12 02:44:45.788+02	2026-05-12 02:44:59.038568+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.038568+02	f
27349	9	E28011704000021D53DAB0CB	\N	-73	1	0	\N	\N	1778546685869	2026-05-12 02:44:45.869+02	2026-05-12 02:44:59.04032+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.04032+02	f
27643	10	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546812484	2026-05-12 02:46:52.484+02	2026-05-12 02:47:15.068004+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.068004+02	f
27645	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546812618	2026-05-12 02:46:52.618+02	2026-05-12 02:47:15.073042+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.073042+02	f
27647	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546812852	2026-05-12 02:46:52.852+02	2026-05-12 02:47:15.077186+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.077186+02	f
27216	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546620616	2026-05-12 02:43:40.616+02	2026-05-12 02:44:09.846023+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.846023+02	f
27217	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546620729	2026-05-12 02:43:40.729+02	2026-05-12 02:44:09.84935+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.84935+02	f
27218	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546620795	2026-05-12 02:43:40.795+02	2026-05-12 02:44:09.851388+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.851388+02	f
27219	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546620862	2026-05-12 02:43:40.862+02	2026-05-12 02:44:09.975786+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.975786+02	f
27220	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546620929	2026-05-12 02:43:40.929+02	2026-05-12 02:44:09.977729+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.977729+02	f
27221	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546620992	2026-05-12 02:43:40.992+02	2026-05-12 02:44:09.98005+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.98005+02	f
27222	10	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546621058	2026-05-12 02:43:41.058+02	2026-05-12 02:44:09.982087+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:09.982087+02	f
27259	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546618437	2026-05-12 02:43:38.437+02	2026-05-12 02:44:13.123417+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.123417+02	f
27261	9	E28011704000021D53DAB0CB	\N	-41	1	0	\N	\N	1778546618867	2026-05-12 02:43:38.867+02	2026-05-12 02:44:13.129702+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.129702+02	f
27263	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546619103	2026-05-12 02:43:39.103+02	2026-05-12 02:44:13.134414+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.134414+02	f
27265	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546619251	2026-05-12 02:43:39.251+02	2026-05-12 02:44:13.141148+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.141148+02	f
27268	9	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546619537	2026-05-12 02:43:39.537+02	2026-05-12 02:44:13.175067+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.175067+02	f
27270	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546619693	2026-05-12 02:43:39.693+02	2026-05-12 02:44:13.178894+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.178894+02	f
27272	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546619854	2026-05-12 02:43:39.854+02	2026-05-12 02:44:13.183142+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.183142+02	f
27274	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546620001	2026-05-12 02:43:40.001+02	2026-05-12 02:44:13.189078+02	2026-05-12 02:44:13.586+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.189078+02	f
27297	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546636774	2026-05-12 02:43:56.774+02	2026-05-12 02:44:13.262794+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:13.262794+02	f
27246	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546634581	2026-05-12 02:43:54.581+02	2026-05-12 02:44:10.512976+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.512976+02	f
27248	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546634755	2026-05-12 02:43:54.755+02	2026-05-12 02:44:10.516458+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.516458+02	f
27250	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546634897	2026-05-12 02:43:54.897+02	2026-05-12 02:44:10.519935+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.519935+02	f
27251	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546633775	2026-05-12 02:43:53.775+02	2026-05-12 02:44:10.814101+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.814101+02	f
27253	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546633910	2026-05-12 02:43:53.91+02	2026-05-12 02:44:10.819795+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.819795+02	f
27255	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546634120	2026-05-12 02:43:54.12+02	2026-05-12 02:44:10.823674+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.823674+02	f
27257	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546634246	2026-05-12 02:43:54.246+02	2026-05-12 02:44:10.827113+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.827113+02	f
27247	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546634689	2026-05-12 02:43:54.689+02	2026-05-12 02:44:10.514852+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.514852+02	f
27249	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546634828	2026-05-12 02:43:54.828+02	2026-05-12 02:44:10.518155+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.518155+02	f
27252	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546633843	2026-05-12 02:43:53.843+02	2026-05-12 02:44:10.81778+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.81778+02	f
27254	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546634057	2026-05-12 02:43:54.057+02	2026-05-12 02:44:10.821767+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.821767+02	f
27256	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546634181	2026-05-12 02:43:54.181+02	2026-05-12 02:44:10.825467+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.825467+02	f
27258	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546634315	2026-05-12 02:43:54.315+02	2026-05-12 02:44:10.831486+02	2026-05-12 02:44:13.61+02	\N	\N	offline_sync	synced	2026-05-12 02:44:10.831486+02	f
27323	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546669750	2026-05-12 02:44:29.75+02	2026-05-12 02:44:58.986732+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.986732+02	f
27325	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546669837	2026-05-12 02:44:29.837+02	2026-05-12 02:44:58.991602+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.991602+02	f
27327	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546669905	2026-05-12 02:44:29.905+02	2026-05-12 02:44:58.998851+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.998851+02	f
27329	9	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546670349	2026-05-12 02:44:30.349+02	2026-05-12 02:44:59.002763+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.002763+02	f
27331	9	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546670412	2026-05-12 02:44:30.412+02	2026-05-12 02:44:59.004897+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.004897+02	f
27333	9	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546670483	2026-05-12 02:44:30.483+02	2026-05-12 02:44:59.007772+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.007772+02	f
27335	9	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546670794	2026-05-12 02:44:30.794+02	2026-05-12 02:44:59.013222+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.013222+02	f
27337	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546670955	2026-05-12 02:44:30.955+02	2026-05-12 02:44:59.017409+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.017409+02	f
27340	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546671176	2026-05-12 02:44:31.176+02	2026-05-12 02:44:59.022151+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.022151+02	f
27342	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546671330	2026-05-12 02:44:31.33+02	2026-05-12 02:44:59.027017+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.027017+02	f
27344	9	E28011704000021D53DAB0CB	\N	-60	1	0	\N	\N	1778546671481	2026-05-12 02:44:31.481+02	2026-05-12 02:44:59.033942+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.033942+02	f
27471	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546760615	2026-05-12 02:46:00.615+02	2026-05-12 02:46:29.879442+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.879442+02	f
27526	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546728479	2026-05-12 02:45:28.479+02	2026-05-12 02:46:30.054906+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.054906+02	f
27533	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546729131	2026-05-12 02:45:29.131+02	2026-05-12 02:46:30.077929+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.077929+02	f
27539	9	E28011704000021D53DAB0CB	\N	-41	1	0	\N	\N	1778546729564	2026-05-12 02:45:29.564+02	2026-05-12 02:46:30.112209+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.112209+02	f
27547	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546729894	2026-05-12 02:45:29.894+02	2026-05-12 02:46:30.122968+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.122968+02	f
27453	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546743016	2026-05-12 02:45:43.016+02	2026-05-12 02:46:29.850016+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.850016+02	f
27457	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546743082	2026-05-12 02:45:43.082+02	2026-05-12 02:46:29.856673+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.856673+02	f
27461	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546743147	2026-05-12 02:45:43.147+02	2026-05-12 02:46:29.867141+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.867141+02	f
27465	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546743211	2026-05-12 02:45:43.211+02	2026-05-12 02:46:29.872835+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.872835+02	f
27553	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546745229	2026-05-12 02:45:45.229+02	2026-05-12 02:46:30.132548+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.132548+02	f
27561	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546745553	2026-05-12 02:45:45.553+02	2026-05-12 02:46:30.142697+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.142697+02	f
27568	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546746028	2026-05-12 02:45:46.028+02	2026-05-12 02:46:30.157127+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.157127+02	f
27575	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546746609	2026-05-12 02:45:46.609+02	2026-05-12 02:46:30.189928+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.189928+02	f
27351	9	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546686007	2026-05-12 02:44:46.007+02	2026-05-12 02:44:59.042603+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.042603+02	f
27353	9	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546686079	2026-05-12 02:44:46.079+02	2026-05-12 02:44:59.046581+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.046581+02	f
27300	9	E28011704000021D53DAB0CB	\N	-79	1	0	\N	\N	1778546667807	2026-05-12 02:44:27.807+02	2026-05-12 02:44:58.899978+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.899978+02	f
27301	9	E28011704000021D53DAB0CB	\N	-80	1	0	\N	\N	1778546668017	2026-05-12 02:44:28.017+02	2026-05-12 02:44:58.90453+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.90453+02	f
27302	9	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546668089	2026-05-12 02:44:28.089+02	2026-05-12 02:44:58.906868+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.906868+02	f
27355	9	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546686150	2026-05-12 02:44:46.15+02	2026-05-12 02:44:59.04962+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.04962+02	f
27357	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546686347	2026-05-12 02:44:46.347+02	2026-05-12 02:44:59.051398+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.051398+02	f
27359	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546686420	2026-05-12 02:44:46.42+02	2026-05-12 02:44:59.053903+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.053903+02	f
27362	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546686492	2026-05-12 02:44:46.492+02	2026-05-12 02:44:59.056534+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.056534+02	f
27350	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546686572	2026-05-12 02:44:46.572+02	2026-05-12 02:44:59.041849+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.041849+02	f
27352	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546686645	2026-05-12 02:44:46.645+02	2026-05-12 02:44:59.046568+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.046568+02	f
27354	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546686733	2026-05-12 02:44:46.733+02	2026-05-12 02:44:59.048791+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.048791+02	f
27356	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546686819	2026-05-12 02:44:46.819+02	2026-05-12 02:44:59.050469+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.050469+02	f
27358	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546686901	2026-05-12 02:44:46.901+02	2026-05-12 02:44:59.052408+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.052408+02	f
27360	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546686981	2026-05-12 02:44:46.981+02	2026-05-12 02:44:59.054517+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.054517+02	f
27363	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546687071	2026-05-12 02:44:47.071+02	2026-05-12 02:44:59.05736+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.05736+02	f
27365	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546687159	2026-05-12 02:44:47.159+02	2026-05-12 02:44:59.062916+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.062916+02	f
27361	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546687220	2026-05-12 02:44:47.22+02	2026-05-12 02:44:59.055542+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.055542+02	f
27364	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546687295	2026-05-12 02:44:47.295+02	2026-05-12 02:44:59.05799+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.05799+02	f
27366	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546687365	2026-05-12 02:44:47.365+02	2026-05-12 02:44:59.062916+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.062916+02	f
27367	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546687433	2026-05-12 02:44:47.433+02	2026-05-12 02:44:59.065877+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.065877+02	f
27368	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546687510	2026-05-12 02:44:47.51+02	2026-05-12 02:44:59.068045+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.068045+02	f
27369	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546687604	2026-05-12 02:44:47.604+02	2026-05-12 02:44:59.069938+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.069938+02	f
27370	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546687686	2026-05-12 02:44:47.686+02	2026-05-12 02:44:59.071618+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.071618+02	f
27371	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546687759	2026-05-12 02:44:47.759+02	2026-05-12 02:44:59.074017+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.074017+02	f
27372	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546687841	2026-05-12 02:44:47.841+02	2026-05-12 02:44:59.127756+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.127756+02	f
27381	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546688243	2026-05-12 02:44:48.243+02	2026-05-12 02:44:59.137348+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.137348+02	f
27373	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546688639	2026-05-12 02:44:48.639+02	2026-05-12 02:44:59.127769+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.127769+02	f
27377	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546688785	2026-05-12 02:44:48.785+02	2026-05-12 02:44:59.132413+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.132413+02	f
27519	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546727674	2026-05-12 02:45:27.674+02	2026-05-12 02:46:30.040598+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.040598+02	f
27534	9	E28011704000021D53DAB0CB	\N	-38	1	0	\N	\N	1778546729282	2026-05-12 02:45:29.282+02	2026-05-12 02:46:30.079819+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.079819+02	f
27540	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546730097	2026-05-12 02:45:30.097+02	2026-05-12 02:46:30.113173+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.113173+02	f
27548	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546744187	2026-05-12 02:45:44.187+02	2026-05-12 02:46:30.122992+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.122992+02	f
27554	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546744705	2026-05-12 02:45:44.705+02	2026-05-12 02:46:30.133451+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.133451+02	f
27562	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546745071	2026-05-12 02:45:45.071+02	2026-05-12 02:46:30.143646+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.143646+02	f
27569	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546746112	2026-05-12 02:45:46.112+02	2026-05-12 02:46:30.158933+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.158933+02	f
27303	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546668171	2026-05-12 02:44:28.171+02	2026-05-12 02:44:58.909287+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.909287+02	f
27304	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546668253	2026-05-12 02:44:28.253+02	2026-05-12 02:44:58.91202+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.91202+02	f
27305	9	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546668457	2026-05-12 02:44:28.457+02	2026-05-12 02:44:58.916298+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.916298+02	f
27306	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546668536	2026-05-12 02:44:28.536+02	2026-05-12 02:44:58.918736+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.918736+02	f
27307	9	E28011704000021D53DAB0CB	\N	-66	1	0	\N	\N	1778546668623	2026-05-12 02:44:28.623+02	2026-05-12 02:44:58.920951+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.920951+02	f
27308	9	E28011704000021D53DAB0CB	\N	-73	1	0	\N	\N	1778546668726	2026-05-12 02:44:28.726+02	2026-05-12 02:44:58.932543+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.932543+02	f
27309	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546668800	2026-05-12 02:44:28.8+02	2026-05-12 02:44:58.934918+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.934918+02	f
27310	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546668871	2026-05-12 02:44:28.871+02	2026-05-12 02:44:58.937035+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.937035+02	f
27311	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546668940	2026-05-12 02:44:28.94+02	2026-05-12 02:44:58.939011+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.939011+02	f
27312	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546669012	2026-05-12 02:44:29.012+02	2026-05-12 02:44:58.940777+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.940777+02	f
27313	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546669083	2026-05-12 02:44:29.083+02	2026-05-12 02:44:58.943309+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.943309+02	f
27314	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546669286	2026-05-12 02:44:29.286+02	2026-05-12 02:44:58.956054+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.956054+02	f
27315	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546669327	2026-05-12 02:44:29.327+02	2026-05-12 02:44:58.958373+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.958373+02	f
27316	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546669357	2026-05-12 02:44:29.357+02	2026-05-12 02:44:58.972403+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.972403+02	f
27318	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546669505	2026-05-12 02:44:29.505+02	2026-05-12 02:44:58.97731+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.97731+02	f
27319	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546669585	2026-05-12 02:44:29.585+02	2026-05-12 02:44:58.98165+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.98165+02	f
27321	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546669663	2026-05-12 02:44:29.663+02	2026-05-12 02:44:58.98389+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:58.98389+02	f
27338	9	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546671036	2026-05-12 02:44:31.036+02	2026-05-12 02:44:59.019751+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.019751+02	f
27339	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546671102	2026-05-12 02:44:31.102+02	2026-05-12 02:44:59.021646+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.021646+02	f
27341	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546671249	2026-05-12 02:44:31.249+02	2026-05-12 02:44:59.024979+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.024979+02	f
27343	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546671407	2026-05-12 02:44:31.407+02	2026-05-12 02:44:59.031736+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.031736+02	f
27345	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546671551	2026-05-12 02:44:31.551+02	2026-05-12 02:44:59.035953+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.035953+02	f
27346	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546671756	2026-05-12 02:44:31.756+02	2026-05-12 02:44:59.037679+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.037679+02	f
27348	9	E28011704000021D53DAB0CB	\N	-76	1	0	\N	\N	1778546671829	2026-05-12 02:44:31.829+02	2026-05-12 02:44:59.039469+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.039469+02	f
27386	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546671214	2026-05-12 02:44:31.214+02	2026-05-12 02:45:00.648895+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.648895+02	f
27388	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546671469	2026-05-12 02:44:31.469+02	2026-05-12 02:45:00.654144+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.654144+02	f
27391	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546671673	2026-05-12 02:44:31.673+02	2026-05-12 02:45:00.66249+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.66249+02	f
27394	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546671868	2026-05-12 02:44:31.868+02	2026-05-12 02:45:00.678307+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.678307+02	f
27398	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546672196	2026-05-12 02:44:32.196+02	2026-05-12 02:45:00.686104+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.686104+02	f
27401	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546672390	2026-05-12 02:44:32.39+02	2026-05-12 02:45:00.696551+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.696551+02	f
27405	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546672659	2026-05-12 02:44:32.659+02	2026-05-12 02:45:00.709398+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.709398+02	f
27408	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546672906	2026-05-12 02:44:32.906+02	2026-05-12 02:45:00.719004+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.719004+02	f
27374	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546687912	2026-05-12 02:44:47.912+02	2026-05-12 02:44:59.129666+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.129666+02	f
27378	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546688070	2026-05-12 02:44:48.07+02	2026-05-12 02:44:59.133434+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.133434+02	f
27382	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546688477	2026-05-12 02:44:48.477+02	2026-05-12 02:44:59.139102+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.139102+02	f
27411	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546684877	2026-05-12 02:44:44.877+02	2026-05-12 02:45:00.726061+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.726061+02	f
27415	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546685060	2026-05-12 02:44:45.06+02	2026-05-12 02:45:00.730154+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.730154+02	f
27419	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546685192	2026-05-12 02:44:45.192+02	2026-05-12 02:45:00.734157+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.734157+02	f
27423	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546685388	2026-05-12 02:44:45.388+02	2026-05-12 02:45:00.743434+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.743434+02	f
27673	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546814341	2026-05-12 02:46:54.341+02	2026-05-12 02:47:15.162725+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.162725+02	f
27676	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546814217	2026-05-12 02:46:54.217+02	2026-05-12 02:47:15.166481+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.166481+02	f
27679	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546814536	2026-05-12 02:46:54.536+02	2026-05-12 02:47:15.169376+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.169376+02	f
27682	10	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546814472	2026-05-12 02:46:54.472+02	2026-05-12 02:47:15.173953+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.173953+02	f
27387	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546671280	2026-05-12 02:44:31.28+02	2026-05-12 02:45:00.651142+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.651142+02	f
27389	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546671534	2026-05-12 02:44:31.534+02	2026-05-12 02:45:00.656331+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.656331+02	f
27392	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546671737	2026-05-12 02:44:31.737+02	2026-05-12 02:45:00.671216+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.671216+02	f
27396	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546672065	2026-05-12 02:44:32.065+02	2026-05-12 02:45:00.68231+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.68231+02	f
27403	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546672587	2026-05-12 02:44:32.587+02	2026-05-12 02:45:00.701024+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.701024+02	f
27407	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546672839	2026-05-12 02:44:32.839+02	2026-05-12 02:45:00.714017+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.714017+02	f
27410	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546673035	2026-05-12 02:44:33.035+02	2026-05-12 02:45:00.724838+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.724838+02	f
27383	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546688559	2026-05-12 02:44:48.559+02	2026-05-12 02:44:59.14096+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.14096+02	f
27375	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546688717	2026-05-12 02:44:48.717+02	2026-05-12 02:44:59.130522+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.130522+02	f
27379	9	E28011704000021D53DAB0CB	\N	-69	1	0	\N	\N	1778546688857	2026-05-12 02:44:48.857+02	2026-05-12 02:44:59.134197+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.134197+02	f
27414	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546684566	2026-05-12 02:44:44.566+02	2026-05-12 02:45:00.729068+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.729068+02	f
27418	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546684745	2026-05-12 02:44:44.745+02	2026-05-12 02:45:00.733239+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.733239+02	f
27422	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546685324	2026-05-12 02:44:45.324+02	2026-05-12 02:45:00.737966+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.737966+02	f
27425	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546685563	2026-05-12 02:44:45.563+02	2026-05-12 02:45:00.746557+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.746557+02	f
27429	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546685827	2026-05-12 02:44:45.827+02	2026-05-12 02:45:00.753741+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.753741+02	f
27481	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546760748	2026-05-12 02:46:00.748+02	2026-05-12 02:46:29.892415+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.892415+02	f
27489	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546760883	2026-05-12 02:46:00.883+02	2026-05-12 02:46:29.901427+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.901427+02	f
27496	10	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546761059	2026-05-12 02:46:01.059+02	2026-05-12 02:46:29.907372+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.907372+02	f
27502	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546762209	2026-05-12 02:46:02.209+02	2026-05-12 02:46:29.911628+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.911628+02	f
27479	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546761725	2026-05-12 02:46:01.725+02	2026-05-12 02:46:29.889232+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.889232+02	f
27486	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546761909	2026-05-12 02:46:01.909+02	2026-05-12 02:46:29.899576+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.899576+02	f
27495	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546761397	2026-05-12 02:46:01.397+02	2026-05-12 02:46:29.907374+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.907374+02	f
27505	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546761526	2026-05-12 02:46:01.526+02	2026-05-12 02:46:29.915543+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.915543+02	f
27522	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546728113	2026-05-12 02:45:28.113+02	2026-05-12 02:46:30.046935+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.046935+02	f
27529	9	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546728797	2026-05-12 02:45:28.797+02	2026-05-12 02:46:30.06813+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.06813+02	f
27536	9	E28011704000021D53DAB0CB	\N	-38	1	0	\N	\N	1778546729453	2026-05-12 02:45:29.453+02	2026-05-12 02:46:30.108957+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.108957+02	f
27543	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546729740	2026-05-12 02:45:29.74+02	2026-05-12 02:46:30.116345+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.116345+02	f
27462	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546743990	2026-05-12 02:45:43.99+02	2026-05-12 02:46:29.868349+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.868349+02	f
27464	10	E28011704000021D53DAB0CB	\N	-73	1	0	\N	\N	1778546744099	2026-05-12 02:45:44.099+02	2026-05-12 02:46:29.874186+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.874186+02	f
27470	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546743319	2026-05-12 02:45:43.319+02	2026-05-12 02:46:29.878874+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.878874+02	f
27469	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546743867	2026-05-12 02:45:43.867+02	2026-05-12 02:46:29.876966+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.876966+02	f
27474	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546743926	2026-05-12 02:45:43.926+02	2026-05-12 02:46:29.885389+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.885389+02	f
27550	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546744458	2026-05-12 02:45:44.458+02	2026-05-12 02:46:30.128218+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.128218+02	f
27557	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546745400	2026-05-12 02:45:45.4+02	2026-05-12 02:46:30.138757+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.138757+02	f
27565	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546745721	2026-05-12 02:45:45.721+02	2026-05-12 02:46:30.146515+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.146515+02	f
27475	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546761655	2026-05-12 02:46:01.655+02	2026-05-12 02:46:29.886876+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.886876+02	f
27482	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546761839	2026-05-12 02:46:01.839+02	2026-05-12 02:46:29.893257+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.893257+02	f
27490	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546761333	2026-05-12 02:46:01.333+02	2026-05-12 02:46:29.903058+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.903058+02	f
27510	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546773635	2026-05-12 02:46:13.635+02	2026-05-12 02:46:29.922299+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.922299+02	f
27518	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546774507	2026-05-12 02:46:14.507+02	2026-05-12 02:46:29.934885+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.934885+02	f
27512	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546773702	2026-05-12 02:46:13.702+02	2026-05-12 02:46:29.924976+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.924976+02	f
27503	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546773971	2026-05-12 02:46:13.971+02	2026-05-12 02:46:29.915443+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.915443+02	f
27513	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546774279	2026-05-12 02:46:14.279+02	2026-05-12 02:46:29.92598+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.92598+02	f
27650	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546813042	2026-05-12 02:46:53.042+02	2026-05-12 02:47:15.092477+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.092477+02	f
27652	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546813232	2026-05-12 02:46:53.232+02	2026-05-12 02:47:15.099918+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.099918+02	f
27654	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546813337	2026-05-12 02:46:53.337+02	2026-05-12 02:47:15.103675+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.103675+02	f
27656	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546813466	2026-05-12 02:46:53.466+02	2026-05-12 02:47:15.108559+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.108559+02	f
27657	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546813528	2026-05-12 02:46:53.528+02	2026-05-12 02:47:15.115559+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.115559+02	f
27659	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546813656	2026-05-12 02:46:53.656+02	2026-05-12 02:47:15.119793+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.119793+02	f
27661	10	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546813788	2026-05-12 02:46:53.788+02	2026-05-12 02:47:15.123866+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.123866+02	f
27663	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546813916	2026-05-12 02:46:53.916+02	2026-05-12 02:47:15.129993+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.129993+02	f
27666	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546814040	2026-05-12 02:46:54.04+02	2026-05-12 02:47:15.147036+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.147036+02	f
27668	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546814149	2026-05-12 02:46:54.149+02	2026-05-12 02:47:15.150628+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.150628+02	f
27670	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546814217	2026-05-12 02:46:54.217+02	2026-05-12 02:47:15.155036+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.155036+02	f
27672	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546814040	2026-05-12 02:46:54.04+02	2026-05-12 02:47:15.159467+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.159467+02	f
27675	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546814409	2026-05-12 02:46:54.409+02	2026-05-12 02:47:15.165476+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.165476+02	f
27678	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546814279	2026-05-12 02:46:54.279+02	2026-05-12 02:47:15.16844+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.16844+02	f
27681	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546814409	2026-05-12 02:46:54.409+02	2026-05-12 02:47:15.17216+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.17216+02	f
27506	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546773569	2026-05-12 02:46:13.569+02	2026-05-12 02:46:29.918987+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.918987+02	f
27516	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546773904	2026-05-12 02:46:13.904+02	2026-05-12 02:46:29.9309+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.9309+02	f
27514	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546773839	2026-05-12 02:46:13.839+02	2026-05-12 02:46:29.926985+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.926985+02	f
27384	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546671019	2026-05-12 02:44:31.019+02	2026-05-12 02:45:00.64292+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.64292+02	f
27395	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546672000	2026-05-12 02:44:32+02	2026-05-12 02:45:00.68034+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.68034+02	f
27399	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546672260	2026-05-12 02:44:32.26+02	2026-05-12 02:45:00.688064+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.688064+02	f
27402	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546672456	2026-05-12 02:44:32.456+02	2026-05-12 02:45:00.698868+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.698868+02	f
27406	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546672725	2026-05-12 02:44:32.725+02	2026-05-12 02:45:00.711916+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.711916+02	f
27409	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546672970	2026-05-12 02:44:32.97+02	2026-05-12 02:45:00.720946+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.720946+02	f
27427	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546685699	2026-05-12 02:44:45.699+02	2026-05-12 02:45:00.750251+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.750251+02	f
27376	9	E28011704000021D53DAB0CB	\N	-60	1	0	\N	\N	1778546687988	2026-05-12 02:44:47.988+02	2026-05-12 02:44:59.131507+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.131507+02	f
27380	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546688151	2026-05-12 02:44:48.151+02	2026-05-12 02:44:59.135079+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:44:59.135079+02	f
27412	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546684499	2026-05-12 02:44:44.499+02	2026-05-12 02:45:00.72707+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.72707+02	f
27416	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546684679	2026-05-12 02:44:44.679+02	2026-05-12 02:45:00.731102+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.731102+02	f
27420	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546684809	2026-05-12 02:44:44.809+02	2026-05-12 02:45:00.735186+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.735186+02	f
27426	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546685630	2026-05-12 02:44:45.63+02	2026-05-12 02:45:00.748445+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.748445+02	f
27430	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546685893	2026-05-12 02:44:45.893+02	2026-05-12 02:45:00.757014+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.757014+02	f
27478	10	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546760681	2026-05-12 02:46:00.681+02	2026-05-12 02:46:29.889243+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.889243+02	f
27485	10	E28011704000021D53DAB0CB	\N	-42	1	0	\N	\N	1778546760813	2026-05-12 02:46:00.813+02	2026-05-12 02:46:29.895674+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.895674+02	f
27493	10	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546760948	2026-05-12 02:46:00.948+02	2026-05-12 02:46:29.90371+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.90371+02	f
27499	10	E28011704000021D53DAB0CB	\N	-60	1	0	\N	\N	1778546762149	2026-05-12 02:46:02.149+02	2026-05-12 02:46:29.909065+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.909065+02	f
27484	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546760229	2026-05-12 02:46:00.229+02	2026-05-12 02:46:29.893284+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.893284+02	f
27491	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546760359	2026-05-12 02:46:00.359+02	2026-05-12 02:46:29.903094+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.903094+02	f
27507	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546761591	2026-05-12 02:46:01.591+02	2026-05-12 02:46:29.919023+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.919023+02	f
27520	9	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546727771	2026-05-12 02:45:27.771+02	2026-05-12 02:46:30.042725+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.042725+02	f
27527	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546728566	2026-05-12 02:45:28.566+02	2026-05-12 02:46:30.063949+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.063949+02	f
27541	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546729658	2026-05-12 02:45:29.658+02	2026-05-12 02:46:30.114394+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.114394+02	f
27463	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546731320	2026-05-12 02:45:31.32+02	2026-05-12 02:46:29.86914+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.86914+02	f
27564	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546745149	2026-05-12 02:45:45.149+02	2026-05-12 02:46:30.145464+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.145464+02	f
27571	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546746293	2026-05-12 02:45:46.293+02	2026-05-12 02:46:30.162623+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.162623+02	f
27572	9	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546746375	2026-05-12 02:45:46.375+02	2026-05-12 02:46:30.16436+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.16436+02	f
27549	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546744269	2026-05-12 02:45:44.269+02	2026-05-12 02:46:30.126091+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.126091+02	f
27555	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546745312	2026-05-12 02:45:45.312+02	2026-05-12 02:46:30.134414+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.134414+02	f
27563	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546745642	2026-05-12 02:45:45.642+02	2026-05-12 02:46:30.144665+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.144665+02	f
27570	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546746209	2026-05-12 02:45:46.209+02	2026-05-12 02:46:30.160942+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.160942+02	f
27582	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546757847	2026-05-12 02:45:57.847+02	2026-05-12 02:46:30.199+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.199+02	f
27611	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546776140	2026-05-12 02:46:16.14+02	2026-05-12 02:46:30.353905+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.353905+02	f
27607	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546775507	2026-05-12 02:46:15.507+02	2026-05-12 02:46:30.317041+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.317041+02	f
27614	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546776428	2026-05-12 02:46:16.428+02	2026-05-12 02:46:30.359942+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.359942+02	f
27642	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546812419	2026-05-12 02:46:52.419+02	2026-05-12 02:47:15.065603+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.065603+02	f
27644	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546812553	2026-05-12 02:46:52.553+02	2026-05-12 02:47:15.070738+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.070738+02	f
27646	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546812789	2026-05-12 02:46:52.789+02	2026-05-12 02:47:15.07509+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.07509+02	f
27648	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546812915	2026-05-12 02:46:52.915+02	2026-05-12 02:47:15.081461+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.081461+02	f
27649	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546812980	2026-05-12 02:46:52.98+02	2026-05-12 02:47:15.089582+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.089582+02	f
27651	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546813105	2026-05-12 02:46:53.105+02	2026-05-12 02:47:15.097402+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.097402+02	f
27653	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546813284	2026-05-12 02:46:53.284+02	2026-05-12 02:47:15.101856+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.101856+02	f
27655	10	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546813405	2026-05-12 02:46:53.405+02	2026-05-12 02:47:15.106278+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.106278+02	f
27658	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546813592	2026-05-12 02:46:53.592+02	2026-05-12 02:47:15.117833+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.117833+02	f
27660	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546813734	2026-05-12 02:46:53.734+02	2026-05-12 02:47:15.12195+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.12195+02	f
27393	10	E28011704000021D53DAB0CB	\N	-44	1	0	\N	\N	1778546671804	2026-05-12 02:44:31.804+02	2026-05-12 02:45:00.67305+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.67305+02	f
27397	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546672129	2026-05-12 02:44:32.129+02	2026-05-12 02:45:00.684115+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.684115+02	f
27400	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546672325	2026-05-12 02:44:32.325+02	2026-05-12 02:45:00.694492+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.694492+02	f
27404	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546672622	2026-05-12 02:44:32.622+02	2026-05-12 02:45:00.703522+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.703522+02	f
27413	10	E28011704000021D53DAB0CB	\N	-60	1	0	\N	\N	1778546684990	2026-05-12 02:44:44.99+02	2026-05-12 02:45:00.728012+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.728012+02	f
27417	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546685131	2026-05-12 02:44:45.131+02	2026-05-12 02:45:00.732067+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.732067+02	f
27421	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546685257	2026-05-12 02:44:45.257+02	2026-05-12 02:45:00.736105+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.736105+02	f
27424	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546685499	2026-05-12 02:44:45.499+02	2026-05-12 02:45:00.744304+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.744304+02	f
27428	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546685764	2026-05-12 02:44:45.764+02	2026-05-12 02:45:00.751963+02	2026-05-12 02:45:01.034+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.751963+02	f
27435	10	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546730520	2026-05-12 02:45:30.52+02	2026-05-12 02:46:29.800135+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.800135+02	f
27436	10	E28011704000021D53DAB0CB	\N	-41	1	0	\N	\N	1778546730585	2026-05-12 02:45:30.585+02	2026-05-12 02:46:29.805191+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.805191+02	f
27438	10	E28011704000021D53DAB0CB	\N	-44	1	0	\N	\N	1778546730657	2026-05-12 02:45:30.657+02	2026-05-12 02:46:29.817033+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.817033+02	f
27439	10	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546730752	2026-05-12 02:45:30.752+02	2026-05-12 02:46:29.81967+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.81967+02	f
27437	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546730818	2026-05-12 02:45:30.818+02	2026-05-12 02:46:29.815715+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.815715+02	f
27440	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546730883	2026-05-12 02:45:30.883+02	2026-05-12 02:46:29.82132+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.82132+02	f
27442	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546730989	2026-05-12 02:45:30.989+02	2026-05-12 02:46:29.832055+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.832055+02	f
27445	10	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546731058	2026-05-12 02:45:31.058+02	2026-05-12 02:46:29.838006+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.838006+02	f
27449	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546731122	2026-05-12 02:45:31.122+02	2026-05-12 02:46:29.841831+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.841831+02	f
27455	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546731186	2026-05-12 02:45:31.186+02	2026-05-12 02:46:29.851399+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.851399+02	f
27460	10	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546731253	2026-05-12 02:45:31.253+02	2026-05-12 02:46:29.862634+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.862634+02	f
27444	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546743449	2026-05-12 02:45:43.449+02	2026-05-12 02:46:29.834952+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.834952+02	f
27446	10	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546743515	2026-05-12 02:45:43.515+02	2026-05-12 02:46:29.839926+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.839926+02	f
27450	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546743581	2026-05-12 02:45:43.581+02	2026-05-12 02:46:29.846264+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.846264+02	f
27454	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546743646	2026-05-12 02:45:43.646+02	2026-05-12 02:46:29.851412+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.851412+02	f
27459	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546743809	2026-05-12 02:45:43.809+02	2026-05-12 02:46:29.862585+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.862585+02	f
27466	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546743837	2026-05-12 02:45:43.837+02	2026-05-12 02:46:29.874184+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.874184+02	f
27473	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546742819	2026-05-12 02:45:42.819+02	2026-05-12 02:46:29.878843+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.878843+02	f
27476	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546743385	2026-05-12 02:45:43.385+02	2026-05-12 02:46:29.88842+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.88842+02	f
27447	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546742884	2026-05-12 02:45:42.884+02	2026-05-12 02:46:29.839265+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.839265+02	f
27451	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546742949	2026-05-12 02:45:42.949+02	2026-05-12 02:46:29.847075+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.847075+02	f
27483	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546761198	2026-05-12 02:46:01.198+02	2026-05-12 02:46:29.893801+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.893801+02	f
27492	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546762037	2026-05-12 02:46:02.037+02	2026-05-12 02:46:29.903111+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.903111+02	f
27497	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546760424	2026-05-12 02:46:00.424+02	2026-05-12 02:46:29.907397+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.907397+02	f
27468	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546760549	2026-05-12 02:46:00.549+02	2026-05-12 02:46:29.875957+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.875957+02	f
27477	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546760049	2026-05-12 02:46:00.049+02	2026-05-12 02:46:29.888464+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.888464+02	f
27487	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546760294	2026-05-12 02:46:00.294+02	2026-05-12 02:46:29.899613+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.899613+02	f
27500	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546762339	2026-05-12 02:46:02.339+02	2026-05-12 02:46:29.910953+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.910953+02	f
27504	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546773439	2026-05-12 02:46:13.439+02	2026-05-12 02:46:29.915527+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.915527+02	f
27511	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546774166	2026-05-12 02:46:14.166+02	2026-05-12 02:46:29.924047+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.924047+02	f
27591	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546774572	2026-05-12 02:46:14.572+02	2026-05-12 02:46:30.213429+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.213429+02	f
27509	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546774102	2026-05-12 02:46:14.102+02	2026-05-12 02:46:29.921899+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.921899+02	f
27517	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546774437	2026-05-12 02:46:14.437+02	2026-05-12 02:46:29.932816+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.932816+02	f
27508	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546774036	2026-05-12 02:46:14.036+02	2026-05-12 02:46:29.919093+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.919093+02	f
27515	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546774348	2026-05-12 02:46:14.348+02	2026-05-12 02:46:29.928006+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.928006+02	f
27385	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546671149	2026-05-12 02:44:31.149+02	2026-05-12 02:45:00.646709+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.646709+02	f
27390	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546671605	2026-05-12 02:44:31.605+02	2026-05-12 02:45:00.660338+02	2026-05-12 02:45:01.007+02	\N	\N	offline_sync	synced	2026-05-12 02:45:00.660338+02	f
27662	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546813850	2026-05-12 02:46:53.85+02	2026-05-12 02:47:15.126073+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.126073+02	f
27664	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546813979	2026-05-12 02:46:53.979+02	2026-05-12 02:47:15.131982+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.131982+02	f
27665	10	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546814599	2026-05-12 02:46:54.599+02	2026-05-12 02:47:15.146988+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:15.146988+02	f
27583	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546758713	2026-05-12 02:45:58.713+02	2026-05-12 02:46:30.200223+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.200223+02	f
27524	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546728309	2026-05-12 02:45:28.309+02	2026-05-12 02:46:30.050876+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.050876+02	f
27531	9	E28011704000021D53DAB0CB	\N	-40	1	0	\N	\N	1778546728966	2026-05-12 02:45:28.966+02	2026-05-12 02:46:30.074348+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.074348+02	f
27537	9	E28011704000021D53DAB0CB	\N	-38	1	0	\N	\N	1778546729497	2026-05-12 02:45:29.497+02	2026-05-12 02:46:30.110613+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.110613+02	f
27545	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546729819	2026-05-12 02:45:29.819+02	2026-05-12 02:46:30.118276+02	2026-05-12 02:46:31.883+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.118276+02	f
27552	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546744624	2026-05-12 02:45:44.624+02	2026-05-12 02:46:30.131417+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.131417+02	f
27560	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546744997	2026-05-12 02:45:44.997+02	2026-05-12 02:46:30.141718+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.141718+02	f
27567	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546745892	2026-05-12 02:45:45.892+02	2026-05-12 02:46:30.155225+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.155225+02	f
27573	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546746454	2026-05-12 02:45:46.454+02	2026-05-12 02:46:30.166114+02	2026-05-12 02:46:31.903+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.166114+02	f
27498	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546762274	2026-05-12 02:46:02.274+02	2026-05-12 02:46:29.908067+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:29.908067+02	f
27590	9	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546759143	2026-05-12 02:45:59.143+02	2026-05-12 02:46:30.212067+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.212067+02	f
27597	9	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546759669	2026-05-12 02:45:59.669+02	2026-05-12 02:46:30.277966+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.277966+02	f
27604	9	E28011704000021D53DAB0CB	\N	-70	1	0	\N	\N	1778546760315	2026-05-12 02:46:00.315+02	2026-05-12 02:46:30.309913+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.309913+02	f
27576	9	E28011704000021D53DAB0CB	\N	-73	1	0	\N	\N	1778546757497	2026-05-12 02:45:57.497+02	2026-05-12 02:46:30.192143+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.192143+02	f
27584	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546758157	2026-05-12 02:45:58.157+02	2026-05-12 02:46:30.203413+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.203413+02	f
27578	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546757656	2026-05-12 02:45:57.656+02	2026-05-12 02:46:30.194137+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.194137+02	f
27586	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546758241	2026-05-12 02:45:58.241+02	2026-05-12 02:46:30.206113+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.206113+02	f
27592	9	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546759228	2026-05-12 02:45:59.228+02	2026-05-12 02:46:30.267734+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.267734+02	f
27596	9	E28011704000021D53DAB0CB	\N	-41	1	0	\N	\N	1778546759594	2026-05-12 02:45:59.594+02	2026-05-12 02:46:30.275864+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.275864+02	f
27603	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546760212	2026-05-12 02:46:00.212+02	2026-05-12 02:46:30.30792+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.30792+02	f
27581	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546758629	2026-05-12 02:45:58.629+02	2026-05-12 02:46:30.197975+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.197975+02	f
27589	9	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546759065	2026-05-12 02:45:59.065+02	2026-05-12 02:46:30.209673+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.209673+02	f
27595	9	E28011704000021D53DAB0CB	\N	-43	1	0	\N	\N	1778546759467	2026-05-12 02:45:59.467+02	2026-05-12 02:46:30.274146+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.274146+02	f
27602	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546760124	2026-05-12 02:46:00.124+02	2026-05-12 02:46:30.306072+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.306072+02	f
27579	9	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546758544	2026-05-12 02:45:58.544+02	2026-05-12 02:46:30.195996+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.195996+02	f
27587	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546758987	2026-05-12 02:45:58.987+02	2026-05-12 02:46:30.207044+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.207044+02	f
27593	9	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546759307	2026-05-12 02:45:59.307+02	2026-05-12 02:46:30.27008+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.27008+02	f
27600	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546759948	2026-05-12 02:45:59.948+02	2026-05-12 02:46:30.301569+02	2026-05-12 02:46:31.92+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.301569+02	f
27610	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546775965	2026-05-12 02:46:15.965+02	2026-05-12 02:46:30.35196+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.35196+02	f
27617	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546776674	2026-05-12 02:46:16.674+02	2026-05-12 02:46:30.462954+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.462954+02	f
27619	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546776877	2026-05-12 02:46:16.877+02	2026-05-12 02:46:30.466765+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.466765+02	f
27609	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546775716	2026-05-12 02:46:15.716+02	2026-05-12 02:46:30.350066+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.350066+02	f
27615	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546776504	2026-05-12 02:46:16.504+02	2026-05-12 02:46:30.361537+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.361537+02	f
27616	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546776584	2026-05-12 02:46:16.584+02	2026-05-12 02:46:30.461101+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.461101+02	f
27618	9	E28011704000021D53DAB0CB	\N	-60	1	0	\N	\N	1778546776790	2026-05-12 02:46:16.79+02	2026-05-12 02:46:30.464877+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.464877+02	f
27620	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546776958	2026-05-12 02:46:16.958+02	2026-05-12 02:46:30.468721+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.468721+02	f
27621	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546776998	2026-05-12 02:46:16.998+02	2026-05-12 02:46:30.471118+02	2026-05-12 02:46:31.938+02	\N	\N	offline_sync	synced	2026-05-12 02:46:30.471118+02	f
27684	10	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546850359	2026-05-12 02:47:30.359+02	2026-05-12 02:48:15.300616+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.300616+02	f
27685	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546850421	2026-05-12 02:47:30.421+02	2026-05-12 02:48:15.304444+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.304444+02	f
27686	10	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546850549	2026-05-12 02:47:30.549+02	2026-05-12 02:48:15.306898+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.306898+02	f
27687	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546850614	2026-05-12 02:47:30.614+02	2026-05-12 02:48:15.309248+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.309248+02	f
27688	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546850676	2026-05-12 02:47:30.676+02	2026-05-12 02:48:15.314197+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.314197+02	f
27622	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546810557	2026-05-12 02:46:50.557+02	2026-05-12 02:47:10.227117+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.227117+02	f
27623	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546810687	2026-05-12 02:46:50.687+02	2026-05-12 02:47:10.230571+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.230571+02	f
27624	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546810771	2026-05-12 02:46:50.771+02	2026-05-12 02:47:10.234044+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.234044+02	f
27625	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546810855	2026-05-12 02:46:50.855+02	2026-05-12 02:47:10.23968+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.23968+02	f
27626	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546811098	2026-05-12 02:46:51.098+02	2026-05-12 02:47:10.244741+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.244741+02	f
27627	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546811178	2026-05-12 02:46:51.178+02	2026-05-12 02:47:10.247101+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.247101+02	f
27628	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546811265	2026-05-12 02:46:51.265+02	2026-05-12 02:47:10.249449+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.249449+02	f
27629	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546811342	2026-05-12 02:46:51.342+02	2026-05-12 02:47:10.254143+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.254143+02	f
27630	9	E28011704000021D53DAB0CB	\N	-42	1	0	\N	\N	1778546811421	2026-05-12 02:46:51.421+02	2026-05-12 02:47:10.26579+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.26579+02	f
27631	9	E28011704000021D53DAB0CB	\N	-41	1	0	\N	\N	1778546811494	2026-05-12 02:46:51.494+02	2026-05-12 02:47:10.270497+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.270497+02	f
27632	9	E28011704000021D53DAB0CB	\N	-39	1	0	\N	\N	1778546811570	2026-05-12 02:46:51.57+02	2026-05-12 02:47:10.273207+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.273207+02	f
27633	9	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546811646	2026-05-12 02:46:51.646+02	2026-05-12 02:47:10.275241+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.275241+02	f
27634	9	E28011704000021D53DAB0CB	\N	-38	1	0	\N	\N	1778546811726	2026-05-12 02:46:51.726+02	2026-05-12 02:47:10.277396+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.277396+02	f
27635	9	E28011704000021D53DAB0CB	\N	-39	1	0	\N	\N	1778546811859	2026-05-12 02:46:51.859+02	2026-05-12 02:47:10.279469+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.279469+02	f
27636	9	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546812091	2026-05-12 02:46:52.091+02	2026-05-12 02:47:10.278629+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.278629+02	f
27637	9	E28011704000021D53DAB0CB	\N	-47	1	0	\N	\N	1778546811937	2026-05-12 02:46:51.937+02	2026-05-12 02:47:10.281909+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.281909+02	f
27638	9	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546812170	2026-05-12 02:46:52.17+02	2026-05-12 02:47:10.282877+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.282877+02	f
27639	9	E28011704000021D53DAB0CB	\N	-44	1	0	\N	\N	1778546812027	2026-05-12 02:46:52.027+02	2026-05-12 02:47:10.284062+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.284062+02	f
27640	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546812253	2026-05-12 02:46:52.253+02	2026-05-12 02:47:10.287631+02	2026-05-12 02:47:16.498+02	\N	\N	offline_sync	synced	2026-05-12 02:47:10.287631+02	f
27689	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546850740	2026-05-12 02:47:30.74+02	2026-05-12 02:48:15.316432+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.316432+02	f
27690	10	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546850930	2026-05-12 02:47:30.93+02	2026-05-12 02:48:15.318701+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.318701+02	f
27691	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546850995	2026-05-12 02:47:30.995+02	2026-05-12 02:48:15.321029+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.321029+02	f
27692	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546851120	2026-05-12 02:47:31.12+02	2026-05-12 02:48:15.329546+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.329546+02	f
27693	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546851183	2026-05-12 02:47:31.183+02	2026-05-12 02:48:15.331666+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.331666+02	f
27694	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546851248	2026-05-12 02:47:31.248+02	2026-05-12 02:48:15.334254+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.334254+02	f
27695	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546851314	2026-05-12 02:47:31.314+02	2026-05-12 02:48:15.336615+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.336615+02	f
27696	10	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546866139	2026-05-12 02:47:46.139+02	2026-05-12 02:48:15.339592+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.339592+02	f
27697	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546866939	2026-05-12 02:47:46.939+02	2026-05-12 02:48:15.342177+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.342177+02	f
27714	10	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546879239	2026-05-12 02:47:59.239+02	2026-05-12 02:48:15.394442+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.394442+02	f
27716	10	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546879303	2026-05-12 02:47:59.303+02	2026-05-12 02:48:15.39632+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.39632+02	f
27748	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546852539	2026-05-12 02:47:32.539+02	2026-05-12 02:48:16.742958+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.742958+02	f
27751	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546852792	2026-05-12 02:47:32.792+02	2026-05-12 02:48:16.749079+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.749079+02	f
27699	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546867209	2026-05-12 02:47:47.209+02	2026-05-12 02:48:15.349127+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.349127+02	f
27700	10	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546867274	2026-05-12 02:47:47.274+02	2026-05-12 02:48:15.354193+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.354193+02	f
27701	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546867337	2026-05-12 02:47:47.337+02	2026-05-12 02:48:15.356344+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.356344+02	f
27702	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546867400	2026-05-12 02:47:47.4+02	2026-05-12 02:48:15.358513+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.358513+02	f
27703	10	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546867464	2026-05-12 02:47:47.464+02	2026-05-12 02:48:15.363145+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.363145+02	f
27704	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546867526	2026-05-12 02:47:47.526+02	2026-05-12 02:48:15.365441+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.365441+02	f
27705	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546867629	2026-05-12 02:47:47.629+02	2026-05-12 02:48:15.367788+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.367788+02	f
27706	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546867693	2026-05-12 02:47:47.693+02	2026-05-12 02:48:15.369783+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.369783+02	f
27707	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546867756	2026-05-12 02:47:47.756+02	2026-05-12 02:48:15.371964+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.371964+02	f
27708	10	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546867819	2026-05-12 02:47:47.819+02	2026-05-12 02:48:15.378386+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.378386+02	f
27715	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546879419	2026-05-12 02:47:59.419+02	2026-05-12 02:48:15.39539+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.39539+02	f
27717	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546879482	2026-05-12 02:47:59.482+02	2026-05-12 02:48:15.397821+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.397821+02	f
27719	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546879611	2026-05-12 02:47:59.611+02	2026-05-12 02:48:15.401972+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.401972+02	f
27721	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546880057	2026-05-12 02:48:00.057+02	2026-05-12 02:48:15.405559+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.405559+02	f
27723	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546880099	2026-05-12 02:48:00.099+02	2026-05-12 02:48:15.407509+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.407509+02	f
27725	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546880137	2026-05-12 02:48:00.137+02	2026-05-12 02:48:15.413023+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.413023+02	f
27727	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546880239	2026-05-12 02:48:00.239+02	2026-05-12 02:48:15.416024+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.416024+02	f
27718	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546879547	2026-05-12 02:47:59.547+02	2026-05-12 02:48:15.39982+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.39982+02	f
27720	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546879729	2026-05-12 02:47:59.729+02	2026-05-12 02:48:15.404103+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.404103+02	f
27722	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546879797	2026-05-12 02:47:59.797+02	2026-05-12 02:48:15.4065+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.4065+02	f
27724	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546879861	2026-05-12 02:47:59.861+02	2026-05-12 02:48:15.410978+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.410978+02	f
27726	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546879925	2026-05-12 02:47:59.925+02	2026-05-12 02:48:15.414068+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.414068+02	f
27728	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546880301	2026-05-12 02:48:00.301+02	2026-05-12 02:48:15.418036+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.418036+02	f
27741	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546879611	2026-05-12 02:47:59.611+02	2026-05-12 02:48:15.443007+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.443007+02	f
27743	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546879797	2026-05-12 02:47:59.797+02	2026-05-12 02:48:15.448172+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.448172+02	f
27782	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546881087	2026-05-12 02:48:01.087+02	2026-05-12 02:48:16.864322+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.864322+02	f
27788	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546881510	2026-05-12 02:48:01.51+02	2026-05-12 02:48:16.875587+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.875587+02	f
27797	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546882016	2026-05-12 02:48:02.016+02	2026-05-12 02:48:16.891154+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.891154+02	f
27800	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546882745	2026-05-12 02:48:02.745+02	2026-05-12 02:48:16.894044+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.894044+02	f
27803	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546882255	2026-05-12 02:48:02.255+02	2026-05-12 02:48:16.897209+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.897209+02	f
27805	9	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546883014	2026-05-12 02:48:03.014+02	2026-05-12 02:48:16.902045+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.902045+02	f
27808	9	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546882474	2026-05-12 02:48:02.474+02	2026-05-12 02:48:16.905117+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.905117+02	f
27810	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546883295	2026-05-12 02:48:03.295+02	2026-05-12 02:48:16.957857+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.957857+02	f
27813	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546883663	2026-05-12 02:48:03.663+02	2026-05-12 02:48:16.964483+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.964483+02	f
27816	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546883788	2026-05-12 02:48:03.788+02	2026-05-12 02:48:16.971016+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.971016+02	f
27747	9	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546852447	2026-05-12 02:47:32.447+02	2026-05-12 02:48:16.740913+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.740913+02	f
27750	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546852699	2026-05-12 02:47:32.699+02	2026-05-12 02:48:16.746988+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.746988+02	f
27753	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546852959	2026-05-12 02:47:32.959+02	2026-05-12 02:48:16.752698+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.752698+02	f
27755	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546853124	2026-05-12 02:47:33.124+02	2026-05-12 02:48:16.774135+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.774135+02	f
27758	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546853352	2026-05-12 02:47:33.352+02	2026-05-12 02:48:16.780015+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.780015+02	f
27761	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546853603	2026-05-12 02:47:33.603+02	2026-05-12 02:48:16.80728+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.80728+02	f
27763	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546853758	2026-05-12 02:47:33.758+02	2026-05-12 02:48:16.817657+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.817657+02	f
27765	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546854345	2026-05-12 02:47:34.345+02	2026-05-12 02:48:16.823859+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.823859+02	f
27768	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546854012	2026-05-12 02:47:34.012+02	2026-05-12 02:48:16.826963+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.826963+02	f
27771	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546854582	2026-05-12 02:47:34.582+02	2026-05-12 02:48:16.830047+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.830047+02	f
27774	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546854262	2026-05-12 02:47:34.262+02	2026-05-12 02:48:16.833172+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.833172+02	f
27709	10	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546867881	2026-05-12 02:47:47.881+02	2026-05-12 02:48:15.380791+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.380791+02	f
27710	10	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546867946	2026-05-12 02:47:47.946+02	2026-05-12 02:48:15.383093+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.383093+02	f
27711	10	E28011704000021D53DAB0CB	\N	-66	1	0	\N	\N	1778546868009	2026-05-12 02:47:48.009+02	2026-05-12 02:48:15.385355+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.385355+02	f
27712	10	E28011704000021D53DAB0CB	\N	-68	1	0	\N	\N	1778546868071	2026-05-12 02:47:48.071+02	2026-05-12 02:48:15.387906+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.387906+02	f
27713	10	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546868133	2026-05-12 02:47:48.133+02	2026-05-12 02:48:15.389864+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.389864+02	f
27777	9	E28011704000021D53DAB0CB	\N	-74	1	0	\N	\N	1778546864687	2026-05-12 02:47:44.687+02	2026-05-12 02:48:16.840962+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.840962+02	f
27779	9	E28011704000021D53DAB0CB	\N	-80	1	0	\N	\N	1778546864926	2026-05-12 02:47:44.926+02	2026-05-12 02:48:16.860718+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.860718+02	f
27785	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546865420	2026-05-12 02:47:45.42+02	2026-05-12 02:48:16.87167+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.87167+02	f
27791	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546865680	2026-05-12 02:47:45.68+02	2026-05-12 02:48:16.878425+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.878425+02	f
27729	10	E28011704000021D53DAB0CB	\N	-48	1	0	\N	\N	1778546880364	2026-05-12 02:48:00.364+02	2026-05-12 02:48:15.420611+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.420611+02	f
27730	10	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546880428	2026-05-12 02:48:00.428+02	2026-05-12 02:48:15.422605+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.422605+02	f
27731	10	E28011704000021D53DAB0CB	\N	-49	1	0	\N	\N	1778546880492	2026-05-12 02:48:00.492+02	2026-05-12 02:48:15.427092+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.427092+02	f
27732	10	E28011704000021D53DAB0CB	\N	-50	1	0	\N	\N	1778546880559	2026-05-12 02:48:00.559+02	2026-05-12 02:48:15.427917+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.427917+02	f
27733	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546880622	2026-05-12 02:48:00.622+02	2026-05-12 02:48:15.429816+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.429816+02	f
27734	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546880688	2026-05-12 02:48:00.688+02	2026-05-12 02:48:15.432746+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.432746+02	f
27735	10	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546879419	2026-05-12 02:47:59.419+02	2026-05-12 02:48:15.434317+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.434317+02	f
27736	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546880752	2026-05-12 02:48:00.752+02	2026-05-12 02:48:15.435831+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.435831+02	f
27778	9	E28011704000021D53DAB0CB	\N	-71	1	0	\N	\N	1778546864762	2026-05-12 02:47:44.762+02	2026-05-12 02:48:16.8588+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.8588+02	f
27780	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546865797	2026-05-12 02:47:45.797+02	2026-05-12 02:48:16.862093+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.862093+02	f
27783	9	E28011704000021D53DAB0CB	\N	-67	1	0	\N	\N	1778546865240	2026-05-12 02:47:45.24+02	2026-05-12 02:48:16.865312+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.865312+02	f
27781	9	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546865128	2026-05-12 02:47:45.128+02	2026-05-12 02:48:16.863257+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.863257+02	f
27787	9	E28011704000021D53DAB0CB	\N	-54	1	0	\N	\N	1778546865508	2026-05-12 02:47:45.508+02	2026-05-12 02:48:16.874728+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.874728+02	f
27742	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546879729	2026-05-12 02:47:59.729+02	2026-05-12 02:48:15.446111+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.446111+02	f
27745	10	E28011704000021D53DAB0CB	\N	-46	1	0	\N	\N	1778546879925	2026-05-12 02:47:59.925+02	2026-05-12 02:48:15.452292+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.452292+02	f
27786	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546881429	2026-05-12 02:48:01.429+02	2026-05-12 02:48:16.872499+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.872499+02	f
27784	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546881347	2026-05-12 02:48:01.347+02	2026-05-12 02:48:16.866205+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.866205+02	f
27790	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546881581	2026-05-12 02:48:01.581+02	2026-05-12 02:48:16.87758+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.87758+02	f
27793	9	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546881736	2026-05-12 02:48:01.736+02	2026-05-12 02:48:16.881552+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.881552+02	f
27756	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546853198	2026-05-12 02:47:33.198+02	2026-05-12 02:48:16.77591+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.77591+02	f
27759	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546853432	2026-05-12 02:47:33.432+02	2026-05-12 02:48:16.782029+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.782029+02	f
27764	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546853842	2026-05-12 02:47:33.842+02	2026-05-12 02:48:16.822108+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.822108+02	f
27767	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546854434	2026-05-12 02:47:34.434+02	2026-05-12 02:48:16.825972+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.825972+02	f
27770	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546854095	2026-05-12 02:47:34.095+02	2026-05-12 02:48:16.829125+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.829125+02	f
27773	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546854650	2026-05-12 02:47:34.65+02	2026-05-12 02:48:16.832053+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.832053+02	f
27776	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546854810	2026-05-12 02:47:34.81+02	2026-05-12 02:48:16.838967+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.838967+02	f
27746	9	E28011704000021D53DAB0CB	\N	-63	1	0	\N	\N	1778546852127	2026-05-12 02:47:32.127+02	2026-05-12 02:48:16.73877+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.73877+02	f
27749	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546852620	2026-05-12 02:47:32.62+02	2026-05-12 02:48:16.745019+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.745019+02	f
27752	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546852876	2026-05-12 02:47:32.876+02	2026-05-12 02:48:16.75097+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.75097+02	f
27754	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546853047	2026-05-12 02:47:33.047+02	2026-05-12 02:48:16.772141+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.772141+02	f
27757	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546853273	2026-05-12 02:47:33.273+02	2026-05-12 02:48:16.777916+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.777916+02	f
27760	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546853515	2026-05-12 02:47:33.515+02	2026-05-12 02:48:16.805016+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.805016+02	f
27762	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546853676	2026-05-12 02:47:33.676+02	2026-05-12 02:48:16.815288+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.815288+02	f
27766	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546853926	2026-05-12 02:47:33.926+02	2026-05-12 02:48:16.824094+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.824094+02	f
27769	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546854500	2026-05-12 02:47:34.5+02	2026-05-12 02:48:16.827942+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.827942+02	f
27772	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546854179	2026-05-12 02:47:34.179+02	2026-05-12 02:48:16.83107+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.83107+02	f
27775	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546854730	2026-05-12 02:47:34.73+02	2026-05-12 02:48:16.834197+02	2026-05-12 02:48:18.273+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.834197+02	f
27795	9	E28011704000021D53DAB0CB	\N	-64	1	0	\N	\N	1778546881943	2026-05-12 02:48:01.943+02	2026-05-12 02:48:16.888845+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.888845+02	f
27798	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546882640	2026-05-12 02:48:02.64+02	2026-05-12 02:48:16.892143+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.892143+02	f
27801	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546882171	2026-05-12 02:48:02.171+02	2026-05-12 02:48:16.895278+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.895278+02	f
27804	9	E28011704000021D53DAB0CB	\N	-56	1	0	\N	\N	1778546882934	2026-05-12 02:48:02.934+02	2026-05-12 02:48:16.898234+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.898234+02	f
27789	9	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546865590	2026-05-12 02:47:45.59+02	2026-05-12 02:48:16.876563+02	2026-05-12 02:48:18.295+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.876563+02	f
27792	9	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546881658	2026-05-12 02:48:01.658+02	2026-05-12 02:48:16.8793+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.8793+02	f
27794	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546881867	2026-05-12 02:48:01.867+02	2026-05-12 02:48:16.886768+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.886768+02	f
27796	9	E28011704000021D53DAB0CB	\N	-55	1	0	\N	\N	1778546882553	2026-05-12 02:48:02.553+02	2026-05-12 02:48:16.890068+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.890068+02	f
27799	9	E28011704000021D53DAB0CB	\N	-57	1	0	\N	\N	1778546882093	2026-05-12 02:48:02.093+02	2026-05-12 02:48:16.893143+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.893143+02	f
27802	9	E28011704000021D53DAB0CB	\N	-45	1	0	\N	\N	1778546882835	2026-05-12 02:48:02.835+02	2026-05-12 02:48:16.896212+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.896212+02	f
27806	9	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546882355	2026-05-12 02:48:02.355+02	2026-05-12 02:48:16.902024+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.902024+02	f
27809	9	E28011704000021D53DAB0CB	\N	-61	1	0	\N	\N	1778546883163	2026-05-12 02:48:03.163+02	2026-05-12 02:48:16.906155+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.906155+02	f
27811	9	E28011704000021D53DAB0CB	\N	-62	1	0	\N	\N	1778546883546	2026-05-12 02:48:03.546+02	2026-05-12 02:48:16.960231+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.960231+02	f
27814	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546883707	2026-05-12 02:48:03.707+02	2026-05-12 02:48:16.966575+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.966575+02	f
27807	9	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546883083	2026-05-12 02:48:03.083+02	2026-05-12 02:48:16.903963+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.903963+02	f
27812	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546883588	2026-05-12 02:48:03.588+02	2026-05-12 02:48:16.962547+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.962547+02	f
27815	9	E28011704000021D53DAB0CB	\N	-59	1	0	\N	\N	1778546883747	2026-05-12 02:48:03.747+02	2026-05-12 02:48:16.968921+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:16.968921+02	f
27737	10	E28011704000021D53DAB0CB	\N	-51	1	0	\N	\N	1778546879482	2026-05-12 02:47:59.482+02	2026-05-12 02:48:15.436817+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.436817+02	f
27738	10	E28011704000021D53DAB0CB	\N	-58	1	0	\N	\N	1778546880816	2026-05-12 02:48:00.816+02	2026-05-12 02:48:15.437811+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.437811+02	f
27739	10	E28011704000021D53DAB0CB	\N	-53	1	0	\N	\N	1778546879547	2026-05-12 02:47:59.547+02	2026-05-12 02:48:15.438806+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.438806+02	f
27740	10	E28011704000021D53DAB0CB	\N	-65	1	0	\N	\N	1778546880881	2026-05-12 02:48:00.881+02	2026-05-12 02:48:15.439644+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.439644+02	f
27744	10	E28011704000021D53DAB0CB	\N	-52	1	0	\N	\N	1778546879861	2026-05-12 02:47:59.861+02	2026-05-12 02:48:15.450291+02	2026-05-12 02:48:18.313+02	\N	\N	offline_sync	synced	2026-05-12 02:48:15.450291+02	f
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

SELECT pg_catalog.setval('public.lighthouse_connection_events_id_seq', 649, true);


--
-- Name: lighthouse_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_groups_id_seq', 5, true);


--
-- Name: lighthouse_health_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lighthouse_health_snapshots_id_seq', 9642, true);


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

SELECT pg_catalog.setval('public.raw_scans_id_seq', 27816, true);


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

\unrestrict GxSEO7wh3gm8OYjUNM9ef4TBdneiWqsWkittRTfQvUNhawZIUBxuIKMvsjCgJgq

