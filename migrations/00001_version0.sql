-- +goose Up
-- +goose StatementBegin
SELECT 'up SQL query';


--
-- Name: policies_versions_parent_version_id_migration(); Type: PROCEDURE; Schema: cwpp;
--

CREATE OR REPLACE PROCEDURE policies_versions_parent_version_id_migration()
    LANGUAGE plpgsql
    AS $$
DECLARE
  done BOOLEAN := FALSE;
  curr_version_id INT;
  curr_policy_id INT;
  curr_version INT;
  prev_version INT;

  policy_version_cursor CURSOR FOR SELECT id, policy_id, version FROM policies_versions;
BEGIN
  OPEN policy_version_cursor;

  LOOP
    FETCH policy_version_cursor INTO curr_version_id, curr_policy_id, curr_version;
    EXIT WHEN NOT FOUND;
    prev_version := curr_version - 1;
    UPDATE policies_versions AS current SET parent_version_id = prev.id
    FROM (SELECT * FROM policies_versions WHERE version = prev_version AND policy_id = curr_policy_id) AS prev
    WHERE current.id = curr_version_id;
  END LOOP;

  CLOSE policy_version_cursor;
END;
$$;




-- Create or replace the function to remove duplicate pods
CREATE OR REPLACE FUNCTION remove_duplicate_pods() RETURNS void AS $$
BEGIN
    DELETE FROM pods
    WHERE (cluster_id, namespace_id, pod_name, status) IN (
        SELECT cluster_id, namespace_id, pod_name, status
        FROM pods
        GROUP BY cluster_id, namespace_id, pod_name, status
        HAVING COUNT(*) > 1
    );
END;
$$ LANGUAGE plpgsql;


-- Create or replace the function to update label_mappings
CREATE OR REPLACE FUNCTION update_all_label_mappings() RETURNS void AS $$
DECLARE
    r record;
    min_label_id integer;
BEGIN
    FOR r IN 
        SELECT name, value, workspace_id, type
        FROM labels
        GROUP BY name, value, workspace_id, type
    LOOP
        -- Select the minimum label_id for each combination
        SELECT INTO min_label_id MIN(id)
        FROM labels
        WHERE name = r.name AND value = r.value AND workspace_id = r.workspace_id AND type = r.type;

        -- Update label_mappings to resolve conflicts of multiple label_ids
        UPDATE label_mappings lm
        SET label_id = min_label_id
        WHERE lm.label_id IN (
            SELECT id FROM labels
            WHERE name = r.name AND value = r.value AND workspace_id = r.workspace_id AND type = r.type
            AND id <> min_label_id
        )
        AND (lm.entity_id, lm.entity_type, lm.label_id) IN (
            SELECT entity_id, entity_type, label_id
            FROM label_mappings
            WHERE label_id <> min_label_id
        );

    END LOOP;
END;
$$ LANGUAGE plpgsql;



-- Create or replace the function to remove duplicate workloads
CREATE OR REPLACE FUNCTION remove_duplicate_workloads() RETURNS void AS $$
BEGIN
    DELETE FROM workloads
    WHERE (cluster_id, namespace_id, name, type, status) IN (
        SELECT cluster_id, namespace_id, name, type, status
        FROM workloads
        GROUP BY cluster_id, namespace_id, name, type, status
        HAVING COUNT(*) > 1
    );
END;
$$ LANGUAGE plpgsql;







--
-- Name: policy_type; Type: TYPE; Schema: ;
--

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'policy_type' AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) THEN
    -- Create the type
    CREATE TYPE public.policy_type AS ENUM (
      'NetworkPolicy',
      'KubeArmorPolicy',
      'KubeArmorHostPolicy',
      'CiliumNetworkPolicy'
    );
  END IF;
END $$;





--
-- Name: clusters; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS clusters (
    id BIGSERIAL NOT NULL,
    cluster_name character varying(50) NOT NULL,
    location character varying(50) NOT NULL,
    last_updated_time timestamp with time zone,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    status character varying(20) DEFAULT NULL::character varying,
    cloud_provider character varying(100) DEFAULT NULL::character varying,
    ca_data character varying(8000) NOT NULL,
    host character varying(30) NOT NULL,
    bearer_token character varying(5000) DEFAULT NULL::character varying,
    project_id character varying(150) DEFAULT NULL::character varying,
    domain_id integer,
    default_posture character varying(20) DEFAULT 'Audit'::character varying NOT NULL,
    CONSTRAINT clusters_pkey PRIMARY KEY (id)
);




--
-- Name: agents_onboarding_mappings; Type: TABLE; Schema: ;
--
CREATE TABLE IF NOT EXISTS agents_onboarding_mappings (
    id BIGSERIAL NOT NULL,
    agent_id integer NOT NULL,
    cluster_id integer references clusters(id) ON DELETE CASCADE NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    CONSTRAINT agents_onboarding_mappings_pkey PRIMARY KEY (id)
);




--
-- Name: agents_onboardings; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS agents_onboardings (
    id BIGSERIAL NOT NULL,
    name character varying(150) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    description character varying(5000) DEFAULT NULL::character varying,
    archived smallint NOT NULL,
    secret_1 character varying(3000) DEFAULT NULL::character varying,
    secret_2 character varying(5000) DEFAULT NULL::character varying,
    secret_3 character varying(3000) DEFAULT NULL::character varying,
    domain_id integer,
    CONSTRAINT agents_onboardings_pkey PRIMARY KEY (id),
    CONSTRAINT name_unique UNIQUE (name)
);




--
-- Name: filters; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS filters (
    id BIGSERIAL NOT NULL,
    tenant_id INT references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    filter_query character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    filter_type character varying(50) NOT NULL,
    status character varying(50) NOT NULL,
    filters character varying(50) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT filters_pkey PRIMARY KEY (id)
);




--
-- Name: alerts_triggers; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS alerts_triggers (
    id BIGSERIAL NOT NULL,
    filter_id integer NOT NULL,
    tenant_id INT references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    trigger_name character varying(100) NOT NULL,
    channel_type_id integer NOT NULL,
    frequency character varying(50) NOT NULL,
    status character varying(25) NOT NULL,
    priority character varying(25) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    last_sent timestamp with time zone DEFAULT NULL::timestamp without time zone,
    updated_at timestamp with time zone DEFAULT NULL::timestamp without time zone,
    toggle boolean NOT NULL,
    CONSTRAINT alerts_triggers_pkey PRIMARY KEY (id, filter_id),
    CONSTRAINT alerts_triggers_fk FOREIGN KEY (filter_id) REFERENCES filters(id) ON DELETE CASCADE
);







--
-- Name: channels; Type: TABLE; Schema: 
--

	CREATE TABLE IF NOT EXISTS channels (
		id BIGSERIAL NOT NULL,
		channel_type_id int NOT NULL,
		channel_type varchar NOT NULL,
		integration_name varchar(100) NOT NULL,
		status varchar(50) DEFAULT NULL,
	  	tenant_id INT references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
	  	created_by varchar(255) NOT NULL,
		created_at timestamp DEFAULT NULL,
		updated_at timestamp DEFAULT NULL,
		PRIMARY KEY (id)
  	);

--
-- Name: channel_slack_settings; Type: TABLE; Schema: 
--
	CREATE TABLE IF NOT EXISTS channel_slack_settings (
		channels_id BIGINT NOT NULL,
		webhook_url varchar(255) NOT NULL,
	  	sender_name varchar(50) NOT NULL,
	  	channel_name varchar(50) NOT NULL,
	  	title varchar(200),
		PRIMARY KEY (channels_id),
	 	FOREIGN KEY (channels_id) REFERENCES channels (id) ON DELETE CASCADE
  	);

--
-- Name: channel_splunk_settings; Type: TABLE; Schema: 
--
	  
	CREATE TABLE IF NOT EXISTS channel_splunk_settings (
        channels_id BIGINT NOT NULL,
        url varchar(2000) NOT NULL,
        token varchar(1000) NOT NULL,
        source varchar(100) NOT NULL,
        source_type varchar(100),
        splunk_index varchar(100),
        PRIMARY KEY (channels_id), 
        FOREIGN KEY (channels_id) REFERENCES channels (id) ON DELETE CASCADE
	);

--
-- Name: channel_cloudwatch_settings; Type: TABLE; Schema: 
--
	CREATE TABLE IF NOT EXISTS channel_cloudwatch_settings (
		channels_id BIGINT NOT NULL,
		access_key varchar(2000) NOT NULL,
	  	secret_key varchar(1000) NOT NULL,
	  	region varchar(100) NOT NULL,
	  	log_group_name varchar(100),
		PRIMARY KEY (channels_id),
	  	FOREIGN KEY (channels_id) REFERENCES channels (id) ON DELETE CASCADE
  	);

--
-- Name: channel_jira_settings; Type: TABLE; Schema: 
--
	
	CREATE TABLE IF NOT EXISTS channel_jira_settings (
		channels_id BIGINT NOT NULL,
		issue_summary varchar(2000) NOT NULL,
	  	site varchar(1000) NOT NULL,
	  	project varchar(100) NOT NULL,
	  	issue_type varchar(100),
	  	user_email varchar(100),
	  	token varchar(1000),
	  	user_id varchar(100),
		PRIMARY KEY (channels_id),
	  	FOREIGN KEY (channels_id) REFERENCES channels (id) ON DELETE CASCADE
  	);

--
-- Name: channel_rsyslog_settings; Type: TABLE; Schema: 
--
	  
	CREATE TABLE IF NOT EXISTS channel_rsyslog_settings (
		channels_id BIGINT NOT NULL,
		server_address varchar(2000) NOT NULL,
		port int NOT NULL,
		transport varchar(100) NOT NULL,
		PRIMARY KEY (channels_id),
		FOREIGN KEY (channels_id) REFERENCES channels (id) ON DELETE CASCADE
	);

--
-- Name: webhook_settings; Type: TABLE; Schema: 
--

	CREATE TABLE IF NOT EXISTS webhook_settings (
        channels_id BIGINT,
        webhook_url VARCHAR(2000) NOT NULL,
        group_name VARCHAR(1000) NOT NULL,
        group_value VARCHAR(1000) NOT NULL,
        PRIMARY KEY (channels_id),
        FOREIGN KEY (channels_id) REFERENCES channels(id) ON DELETE CASCADE
	);

--
-- Name: channel_email_settings; Type: TABLE; Schema: 
--
    CREATE TABLE IF NOT EXISTS channel_email_settings (
        channels_id bigserial NOT NULL,
        to_email varchar[] NOT NULL,
        cc_email varchar[],
        bcc_email varchar[],
        CONSTRAINT channel_email_settings_pkey PRIMARY KEY (channels_id),
        CONSTRAINT channel_email_settings_channels_id_fkey FOREIGN KEY (channels_id) REFERENCES channels(id) ON DELETE CASCADE
    );


--
-- Name: channel_lists; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS channel_lists (
    id BIGSERIAL NOT NULL,
    channel_type_id bigint,
    channel_name character varying(255),
    CONSTRAINT channel_lists_channel_id_key UNIQUE (channel_type_id),
    CONSTRAINT channel_lists_channel_id_key UNIQUE (channel_type_id),
    CONSTRAINT channel_lists_channel_name_key UNIQUE (channel_name)
);





--
-- Name: containers; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS containers (
    name_of_services character varying(50) NOT NULL,
    protocol_port character varying(50) NOT NULL,
    container_name character varying(50) NOT NULL,
    pod_id integer NOT NULL,
    last_updated_time timestamp with time zone DEFAULT now(),
    image character varying(1000) DEFAULT NULL::character varying,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    cluster_id integer NOT NULL,
    node_id integer NOT NULL,
    status character varying(50) NOT NULL,
    container_id character varying(100) NOT NULL,
    namespace_id integer NOT NULL,
    id BIGSERIAL NOT NULL,
    domain_id integer,
    CONSTRAINT containers_pkey PRIMARY KEY (id),
    CONSTRAINT cluster_ids FOREIGN KEY (cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);




--
-- Name: instance_groups; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS instance_groups (
    id BIGSERIAL NOT NULL,
    group_name character varying(50) DEFAULT NULL::character varying,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    location character varying(50) DEFAULT NULL::character varying,
    cloud_provider character varying(50) DEFAULT NULL::character varying,
    project_id character varying(50) DEFAULT NULL::character varying,
    status smallint,
    updated_at text,
    domain_id integer,
    CONSTRAINT instance_groups_pkey PRIMARY KEY (id)
);



--
-- Name: instances; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS instances (
    id BIGSERIAL NOT NULL,
    instance_name character varying(256) NOT NULL,
    host character varying(256) DEFAULT NULL::character varying,
    group_id integer,
    vpc character varying(256) DEFAULT NULL::character varying,
    internal_ip character varying(256) DEFAULT NULL::character varying,
    external_ip character varying(256) DEFAULT NULL::character varying,
    operating_system character varying(256) DEFAULT NULL::character varying,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    control_plane_domain character varying(100) NOT NULL,
    location character varying(50) DEFAULT NULL::character varying,
    cloud_provider character varying(50) DEFAULT NULL::character varying,
    project_id character varying(50) DEFAULT NULL::character varying,
    status smallint,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    domain_id integer,
    CONSTRAINT instances_pkey PRIMARY KEY (id)
);




--
-- Name: labels; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS labels (
    id BIGSERIAL NOT NULL,
    name character varying(100) DEFAULT NULL::character varying,
    value character varying(100) DEFAULT NULL::character varying,
    created_by character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_by character varying(36) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    color character varying(10) DEFAULT NULL::character varying,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    status character varying(15) DEFAULT NULL::character varying,
    type character varying(15) DEFAULT NULL::character varying,
    selector boolean DEFAULT false,
    domain_id integer,
    CONSTRAINT labels_pkey PRIMARY KEY (id),
    CONSTRAINT unique_labels_constraint UNIQUE (workspace_id, type, name, value)
);





--
-- Name: label_mappings; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS label_mappings (
    id BIGSERIAL NOT NULL,
    label_id integer NOT NULL,
    entity_id integer NOT NULL,
    entity_type character varying(20) NOT NULL,
    created_by character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_by character varying(36) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    domain_id integer,
    CONSTRAINT label_mappings_pkey PRIMARY KEY (id),
    CONSTRAINT label_mappings_fk FOREIGN KEY (label_id) REFERENCES labels(id) ON DELETE CASCADE,
    CONSTRAINT entity_type_label_id_entity_id_uni_idx UNIQUE (label_id, entity_id, entity_type)
);




--
-- Name: namespaces; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS namespaces (
    id BIGSERIAL NOT NULL,
    namespace character varying(100) NOT NULL,
    cluster_id integer NOT NULL,
    last_updated_time timestamp with time zone DEFAULT now(),
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    status character varying(20) DEFAULT NULL::character varying,
    domain_id integer,
    kubearmor_file_posture character varying(10) DEFAULT NULL::character varying,
    kubearmor_network_posture character varying(10) DEFAULT NULL::character varying,
    annotation_status character varying(20) DEFAULT NULL::character varying,
    CONSTRAINT namespaces_pkey PRIMARY KEY (id),
    CONSTRAINT namespaces_ibfk_1 FOREIGN KEY (cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);




--
-- Name: nodes; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS nodes (
    id BIGSERIAL NOT NULL,
    node_name character varying(3000) DEFAULT NULL::character varying,
    cluster_id integer references clusters(id) ON DELETE CASCADE NOT NULL,
    last_updated_time timestamp with time zone DEFAULT now() NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    status character varying(30) DEFAULT NULL::character varying,
    domain_id integer,
    CONSTRAINT nodes_pkey PRIMARY KEY (id)
);



--
-- Name: pods; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS pods (
    pod_name character varying(100) NOT NULL,
    node_id integer NOT NULL,
    last_updated_time timestamp with time zone DEFAULT now() NOT NULL,
    namespace character varying(50) NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    cluster_id integer NOT NULL,
    namespace_id integer NOT NULL,
    status character varying(20) DEFAULT NULL::character varying,
    id BIGSERIAL NOT NULL,
    pod_ip character varying(20) DEFAULT NULL::character varying,
    workload_id integer,
    processed_type character varying(32) DEFAULT NULL::character varying,
    domain_id integer,
    CONSTRAINT pods_pkey PRIMARY KEY (id),
    CONSTRAINT clusterid FOREIGN KEY (cluster_id) REFERENCES clusters(id) ON DELETE CASCADE
);




--
-- Name: policies_masters; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policies_masters (
    id BIGSERIAL NOT NULL,
    entity_id integer,
    group_id integer,
    name character varying(128) DEFAULT NULL::character varying,
    type character varying(30) DEFAULT NULL::character varying,
    status character varying(15) DEFAULT NULL::character varying,
    version integer NOT NULL,
    updated_by character varying(36) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    latest_commit_id character varying(100) DEFAULT NULL::character varying,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    owner_id integer,
    created_at timestamp with time zone NOT NULL,
    created_by character varying(36) NOT NULL,
    description character varying(1000) DEFAULT NULL::character varying,
    cluster_id integer references clusters(id) ON DELETE CASCADE,
    namespace_id integer,
    instance_group_id integer DEFAULT 0,
    instance_id integer,
    policy_version_id integer,
    approved_by character varying(36) DEFAULT NULL::character varying,
    is_discover boolean DEFAULT false,
    is_used character varying(5) DEFAULT 1::character varying,
    label_type character varying(15) DEFAULT 'Default'::character varying NOT NULL,
    domain_id integer,
    policy_kind character varying(30) DEFAULT NULL::character varying,
    is_pending boolean,
    is_staged boolean,
    applied_at timestamp with time zone,
    tldr VARCHAR(250),
    CONSTRAINT policies_masters_pkey PRIMARY KEY (id)
);





--
-- Name: policies_versions; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policies_versions (
    id BIGSERIAL NOT NULL,
    policy_id integer NOT NULL,
    name character varying(128) DEFAULT NULL::character varying,
    group_id integer NOT NULL,
    type character varying(30) DEFAULT NULL::character varying,
    created_by character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    cluster_id integer references clusters(id) ON DELETE CASCADE,
    namespace_id integer,
    instance_group_id integer DEFAULT 0,
    instance_id integer,
    description character varying(100) DEFAULT NULL::character varying,
    version integer,
    status character varying(15) DEFAULT NULL::character varying,
    updated_at timestamp with time zone,
    updated_by character varying(36) DEFAULT NULL::character varying,
    label_type character varying(15) DEFAULT 'Default'::character varying NOT NULL,
    domain_id integer,
    policy_yaml text,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    message character varying(128) DEFAULT NULL::character varying,
    action character varying(128) DEFAULT NULL::character varying,
    processing_status character varying(128) DEFAULT NULL::character varying,
    policy_kind character varying(30) DEFAULT NULL::character varying,
    commit_msg character varying(50) DEFAULT NULL::character varying,
    parent_version_id integer,
    CONSTRAINT policies_versions_pkey PRIMARY KEY (id)
);




--
-- Name: policies_yamls; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policies_yamls (
    id BIGSERIAL NOT NULL,
    policy_id integer NOT NULL,
    yaml_content character varying(1000) NOT NULL,
    date_modified timestamp with time zone NOT NULL,
    version integer NOT NULL,
    commit_id character varying(100) NOT NULL,
    json_content json,
    domain_id integer,
    CONSTRAINT policies_yamls_pkey PRIMARY KEY (id)
);





--
-- Name: policy_discovery_job; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policy_discovery_job (
    id BIGSERIAL NOT NULL,
    status character varying(15) DEFAULT NULL::character varying,
    "timestamp" bigint NOT NULL,
    datetime timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT policy_discovery_job_pkey PRIMARY KEY (id)
);




--
-- Name: policy_libraries; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policy_libraries (
    id BIGSERIAL NOT NULL,
    workspace_id bigint references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    domain_id bigint,
    cluster_id bigint references clusters(id) ON DELETE CASCADE,
    user_id text,
    policy_content text,
    date_created timestamp with time zone,
    date_modified timestamp with time zone,
    version bigint,
    name text,
    namespace_id bigint,
    status text,
    type text,
    vm_instance_group_id bigint,
    vm_instance_id bigint,
    namespace_name text,
    kind text,
    label_type text,
    CONSTRAINT policy_libraries_pkey PRIMARY KEY (id)
);





--
-- Name: policy_stagings; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policy_stagings (
    id BIGSERIAL NOT NULL,
    policy_id integer NOT NULL,
    name character varying(128) DEFAULT NULL::character varying,
    type public.policy_type,
    status character varying(10) DEFAULT NULL::character varying,
    updated_at timestamp with time zone,
    approved_yaml text,
    staged_yaml text,
    cluster_id integer references clusters(id) ON DELETE CASCADE,
    namespace_id integer,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    CONSTRAINT status_check CHECK (((status)::text = ANY (ARRAY[('approved'::character varying)::text, ('staged'::character varying)::text, ('processed'::character varying)::text]))),
    CONSTRAINT policy_stagings_pkey PRIMARY KEY (id)
);



--
-- Name: policy_yaml; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS policy_yaml (
    id BIGSERIAL NOT NULL,
    type character varying(50) DEFAULT NULL::character varying,
    kind character varying(50) DEFAULT NULL::character varying,
    cluster_name character varying(50) DEFAULT NULL::character varying,
    namespace character varying(50) DEFAULT NULL::character varying,
    labels text,
    policy_name character varying(150) DEFAULT NULL::character varying,
    policy_yaml bytea,
    updated_time bigint NOT NULL,
    cluster_id integer references clusters(id) ON DELETE CASCADE DEFAULT 0,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE DEFAULT 0,
    status VARCHAR(10),
    CONSTRAINT policy_yaml_pkey PRIMARY KEY (id)
);




--
-- Name: registries; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS registries (
    id BIGSERIAL NOT NULL,
    name character varying(100) NOT NULL,
    path character varying(100) DEFAULT NULL::character varying,
    auth_type character varying(100) DEFAULT NULL::character varying,
    status character varying(20) NOT NULL,
    registry_name character varying(100) DEFAULT NULL::character varying,
    CONSTRAINT registries_pkey PRIMARY KEY (id),
    CONSTRAINT registry_name UNIQUE (registry_name)
);



--
-- Name: registry_details; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS registry_details (
    id  SERIAL NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    domain_id integer,
    name character varying(100) NOT NULL,
    registry_id integer NOT NULL,
    description character varying(256) DEFAULT NULL::character varying,
    status character varying(20) NOT NULL,
    url character varying(100) NOT NULL,
    scan_status character varying(100) DEFAULT NULL::character varying,
    created_by character varying(36) NOT NULL,
    updated_by character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_pulled_days INT DEFAULT 0,
    criteria VARCHAR(255) DEFAULT '',
    auth_type VARCHAR(20),
    CONSTRAINT registry_details_pkey PRIMARY KEY (id)
);


--
-- Create Table | Name : registry_regions ; Type: TABLE; Schema: 
--
CREATE TABLE IF NOT EXISTS registry_regions (
	id serial4 NOT NULL,
	registry_type character varying(100) NOT NULL,
	regions jsonb NOT NULL,
	CONSTRAINT registry_regions_pkey PRIMARY KEY (id)
);



--
-- Name: review_details; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS review_details (
    id BIGSERIAL NOT NULL,
    policy_id integer NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by character varying(36) NOT NULL,
    review_body character varying(250) DEFAULT 'Default'::character varying,
    event character varying(250) DEFAULT NULL::character varying,
    tenant_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    status character varying,
    CONSTRAINT review_details_pkey PRIMARY KEY (id)
);



--
-- Name: scan_images; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS scan_images (
    id SERIAL NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    name character varying(200) NOT NULL,
    registry_name character varying(30) DEFAULT NULL::character varying,
    status character varying(20) DEFAULT NULL::character varying,
    tags character varying(100) DEFAULT NULL::character varying,
    registry_id integer,
    domain_id integer,
    image_url character varying(100) DEFAULT NULL::character varying,
    scan_type character varying(100) DEFAULT NULL::character varying,
    registry_type_id integer,
    scan_err character varying(2500) DEFAULT NULL::character varying,
    respbody character varying(2000) DEFAULT NULL::character varying,
    respstatus character varying(100) DEFAULT NULL::character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scan_images_pkey PRIMARY KEY (id)
);




--
-- Name: services; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS services (
    id  SERIAL PRIMARY KEY NOT NULL,
    name character varying(1000) NOT NULL,
    type character varying(100) NOT NULL,
    cluster_ip character varying(100) DEFAULT NULL::character varying,
    external_ip character varying(100) DEFAULT NULL::character varying,
    status character varying(100) NOT NULL,
    last_updated_time timestamp with time zone DEFAULT now() NOT NULL,
    cluster_id integer references clusters(id) ON DELETE CASCADE NOT NULL,
    namespace_id integer NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL
);






--
-- Name: workloads; Type: TABLE; Schema: ;
--

 CREATE TABLE IF NOT EXISTS workloads (
    id  SERIAL PRIMARY KEY NOT NULL,
    name character varying(1000) NOT NULL,
    type character varying(100) NOT NULL,
    status smallint NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    cluster_id integer references clusters(id) ON DELETE CASCADE NOT NULL,
    namespace_id integer NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL
);





--
-- Name: workspace_cluster_mappings; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS workspace_cluster_mappings (
    id BIGSERIAL NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    cluster_id integer references clusters(id) ON DELETE CASCADE NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    cluster_hash character varying(120) DEFAULT NULL::character varying,
    domain_id integer,
    status character varying(10) DEFAULT 'Active'::character varying,
    CONSTRAINT workspace_cluster_mappings_pkey PRIMARY KEY (id)
);





--
-- Name: workspace_users; Type: TABLE; Schema: ;
--

CREATE TABLE IF NOT EXISTS workspace_users (
    id BIGSERIAL NOT NULL,
    user_id character varying(100) NOT NULL,
    workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    high_level_role_id integer DEFAULT 0,
    status smallint DEFAULT 0::smallint,
    created_at timestamp with time zone NOT NULL,
    archived smallint DEFAULT 0::smallint,
    domain_id integer,
    CONSTRAINT workspace_users_pkey PRIMARY KEY (id)
);


--
-- Name: report_settings; Type: TABLE; Schema: 
--

    CREATE TABLE IF NOT EXISTS report_settings (
        id serial PRIMARY KEY,
        tenant_id INT references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
        name VARCHAR(1000) NOT NULL,
        email VARCHAR(1000) NOT NULL,
        description VARCHAR(1000) NOT NULL,
        status VARCHAR(100) NOT NULL,
        updated_at TIMESTAMP,
        last_report TIMESTAMP,
        next_report TIMESTAMP,
        frequency VARCHAR(100) NOT NULL
    );

--
-- Name: report_filters; Type: TABLE; Schema: 
--
    CREATE TABLE IF NOT EXISTS report_filters (
        id serial PRIMARY KEY,
        status VARCHAR(100) NOT NULL,
        report_settings_id INT REFERENCES report_settings(id) ON DELETE CASCADE, 
        filters JSONB NOT NULL,
        version INT,
        type VARCHAR(200)
    );
    --this

--
-- Name: reports; Type: TABLE; Schema: 
--

    CREATE TABLE IF NOT EXISTS reports (
        id UUID NOT NULL,
        report_settings_id INT REFERENCES report_settings(id) ON DELETE CASCADE,
        scheduled_at TIMESTAMP,
        status VARCHAR(10) NOT NULL,
        data JSONB,
        completed_at TIMESTAMP,
        PRIMARY KEY (id)
    );
    --this

--
-- Name: policy_alert_trends; Type: TABLE; Schema: 
--

    CREATE TABLE IF NOT EXISTS policy_alert_trends (
        id serial PRIMARY KEY,
        policy_count INT,
        alert_count INT,
        cluster_id INT  REFERENCES clusters(id) ON DELETE CASCADE,
        created_at TIMESTAMP,
        tenant_id INT references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
        report_settings_id INT REFERENCES report_settings(id) ON DELETE CASCADE,
        compliance_policy_count INT
    );
    --this
--
-- Name: cluster_status_history; Type: TABLE; Schema: 
--

    CREATE TABLE IF NOT EXISTS cluster_status_history (
        id serial PRIMARY KEY,
        cluster_id integer references clusters(id) ON DELETE CASCADE NOT NULL,
        updated_time timestamp with time zone,
        workspace_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
        status character varying(20) DEFAULT NULL::character varying
    );

--
-- Name: pod_security_admission_config; Type: TABLE; Schema: 
--

create table if not exists pod_security_admission_config (
    id SERIAL primary key,
    cluster_id integer references clusters(id) ON DELETE CASCADE not null,
    namespace_id integer references namespaces(id) ON DELETE CASCADE not null,
    tenant_id integer references public.tenant_client(id) ON DELETE CASCADE NOT NULL,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    mode character varying(100) not null,
    level character varying(25) not null,
    status character varying(25) default null,
    version character varying(25) default 'latest' not null
);








--
-- Name: alerts_triggers; Type: INDEX; Schema: ;
--
create index if NOT EXISTS idx_pod_security_admission_config_cluster_namespace on pod_security_admission_config (cluster_id, namespace_id);

--
-- Name: alerts_triggers; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS alerts_triggers_fk ON alerts_triggers USING btree (filter_id);



--
-- Name: label_mappings_fk; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS label_mappings_fk ON label_mappings USING btree (label_id);



--
-- Name: name_idx; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS name_idx ON labels USING btree (name);



--
-- Name: project_id; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS project_id ON clusters USING btree (workspace_id);


--
-- Name: projectid; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS projectid ON pods USING btree (workspace_id);


--
-- Name: workspace_cluster_id_status_idx; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS workspace_cluster_id_status_idx ON policies_masters USING btree (workspace_id, cluster_id, status);


--
-- Name: workspace_id_idx; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS workspace_id_idx ON agents_onboarding_mappings USING btree (workspace_id);


--
-- Name: workspace_id_status_idx; Type: INDEX; Schema: ;
--

CREATE INDEX IF NOT EXISTS workspace_id_status_idx ON clusters USING btree (workspace_id, status);

--
-- Add "entity_type_entity_id_idx" index
--

CREATE INDEX IF NOT EXISTS entity_type_entity_id_idx ON label_mappings (entity_type, entity_id);

--
-- Create "idx_cluster_id_policy_name" index
--

CREATE INDEX IF NOT EXISTS idx_cluster_id_policy_name ON policy_yaml USING btree (cluster_id, policy_name);


-- Create "channels_tenant_id" index
CREATE INDEX IF NOT EXISTS channels_tenant_id ON channels USING btree (tenant_id);


-- Create "alerts_triggers_tenant_id" index
CREATE INDEX IF NOT EXISTS alerts_triggers_tenant_id ON alerts_triggers USING btree (tenant_id);


-- Create "filters_tenant_id" index
CREATE INDEX IF NOT EXISTS filters_tenant_id ON filters USING btree (tenant_id);

--
-- Create "idx_containers_container_name_pod_id" index
--
CREATE INDEX IF NOT EXISTS idx_containers_container_name_pod_id ON containers USING btree (container_name, pod_id);

-- Create "idx_containers_workspace_id" index
CREATE INDEX IF NOT EXISTS idx_containers_workspace_id ON containers USING btree (workspace_id);

-- Create "idx_pods_cluster_id_status" index
CREATE INDEX IF NOT EXISTS idx_pods_cluster_id_status ON pods USING btree (cluster_id, status);

-- Create "idx_pods_node_id_status" index
CREATE INDEX IF NOT EXISTS idx_pods_node_id_status ON pods USING btree (node_id, status);

-- Create "idx_pods_namespace_id_status" index
CREATE INDEX IF NOT EXISTS idx_pods_namespace_id_status ON pods USING btree (namespace_id, status);

-- Create "unq_idx_pods_pod_name_namespace_id_cluster_id" index
CREATE UNIQUE INDEX IF NOT EXISTS unq_idx_pods_pod_name_namespace_id_cluster_id ON pods USING btree (pod_name, namespace_id, cluster_id) WHERE ((status)::text = 'Active'::text);

-- Create "idx_nodes_node_name_cluster_id" index
CREATE INDEX IF NOT EXISTS idx_nodes_node_name_cluster_id ON nodes USING btree (node_name,cluster_id);

-- Create "idx_nodes_workspace_id" index
CREATE INDEX IF NOT EXISTS idx_nodes_workspace_id ON nodes USING btree (workspace_id);

-- Create "idx_workloads_cluster_id_status" index
CREATE INDEX IF NOT EXISTS idx_workloads_cluster_id_status ON workloads USING btree (cluster_id, status);

-- Create "idx_workloads_namespace_id_status" index
CREATE INDEX IF NOT EXISTS idx_workloads_namespace_id_status ON workloads USING btree (namespace_id, status);

-- Create "unq_idx_workloads_name_type_cluster_id_namespace_id" index
CREATE UNIQUE INDEX IF NOT EXISTS unq_idx_workloads_name_type_cluster_id_namespace_id ON workloads USING btree (name, type, cluster_id, namespace_id) WHERE status::smallint = 1;

-- Create "idx_workloads_workspace_id" index
CREATE INDEX IF NOT EXISTS idx_workloads_workspace_id ON workloads USING btree (workspace_id);


-- Create "idx_labels_workspace_id_type_name_value" index
CREATE INDEX IF NOT EXISTS idx_labels_workspace_id_type_name_value ON labels USING btree (workspace_id,type,name,value);

-- Create "idx_namespaces_cluster_id_status" index
CREATE INDEX IF NOT EXISTS idx_namespaces_cluster_id_status ON namespaces USING btree (cluster_id, status);

-- Create "idx_namespaces_workspace_id_status" index
CREATE INDEX IF NOT EXISTS idx_namespaces_workspace_id_status ON namespaces USING btree (workspace_id, status);


-- Create "idx_workspace_cluster_mappings_cluster_id_workspace_id" index
CREATE INDEX IF NOT EXISTS idx_workspace_cluster_mappings_cluster_id_workspace_id ON workspace_cluster_mappings USING btree (cluster_id, workspace_id);


-- Create "idx_namespaces_cluster_id_workspace_id_status" index
CREATE INDEX IF NOT EXISTS idx_namespaces_cluster_id_workspace_id_status ON namespaces USING btree (workspace_id,cluster_id, status);

-- Create "idx_workloads_name_type_namespace_id_cluster_id_workspace_id_st" index
CREATE INDEX IF NOT EXISTS idx_workloads_name_type_namespace_id_cluster_id_workspace_id_st ON workloads USING btree (cluster_id, workspace_id, name,type, namespace_id, status);

-- Create "idx_pods_name_namespace_id_node_id_cluster_id_workspace_id_status" index
CREATE  INDEX IF NOT EXISTS idx_pods_name_namespace_id_node_id_cluster_id_workspace_id_status ON pods USING btree (cluster_id, workspace_id, node_id, pod_name, namespace_id,status);

-- Create "idx_services_name_cluster_id_workspace_id_namespace_id_status" index
CREATE  INDEX IF NOT EXISTS idx_services_name_cluster_id_workspace_id_namespace_id_status ON services USING btree (cluster_id, workspace_id, name, namespace_id, status);



--
-- PostgreSQL database dump complete
--



-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SELECT 'down SQL query';


-- +goose StatementEnd
