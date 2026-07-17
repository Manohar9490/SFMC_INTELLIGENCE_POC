-- Gold layer dimension and fact tables for HCP subscriber funnel
-- Co-authored with CoCo
USE DATABASE CEDP_HCP_OUTREACH;
USE SCHEMA GOLD;
USE WAREHOUSE CEDP_ETL_WH;
CREATE TABLE IF NOT EXISTS DIM_CHECKPOINT (
    CHECKPOINT_KEY NUMBER,
    CHECKPOINT_ID VARCHAR,
    CHECKPOINT_NAME VARCHAR,
    FUNNEL_STAGE VARCHAR,
    STEP_SEQUENCE NUMBER,
    BUILT_FROM VARCHAR
);
INSERT INTO
    DIM_CHECKPOINT
SELECT
    *
FROM
    (
        VALUES
            (
                -1,
                'UNKNOWN',
                'Unknown Checkpoint',
                'UNKNOWN',
                NULL,
                'n/a'
            ),
            (
                1,
                'CP_001',
                'DE_Entry',
                'AUTOMATION_STUDIO',
                0,
                'SILVER.SUBSCRIBER (as landed)'
            ),
            (
                2,
                'CP_002',
                'Consent_DNC_Filter',
                'AUTOMATION_STUDIO',
                1,
                'SILVER.SUBSCRIBER (CONSENT_STATUS / DO_NOT_CONTACT_FLAG)'
            ),
            (
                3,
                'CP_003',
                'Specialty_Eligibility_Filter',
                'AUTOMATION_STUDIO',
                2,
                'SILVER.SUBSCRIBER (SPECIALTY)'
            ),
            (
                4,
                'CP_004',
                'Tier_Engagement_Filter',
                'AUTOMATION_STUDIO',
                3,
                'SILVER.SUBSCRIBER (HCP_TIER)'
            ),
            (
                5,
                'CP_005',
                'Final_Send_Ready_Filter',
                'AUTOMATION_STUDIO',
                4,
                'SILVER.SUPPRESSION_STATE'
            ),
            (
                6,
                'CP_006',
                'Journey_Entry',
                'JOURNEY',
                5,
                'SILVER.JOURNEY_STATUS'
            ),
            (
                7,
                'CP_007',
                'Outreach_Attempt',
                'OUTREACH',
                6,
                'SILVER.OUTREACH_ATTEMPT'
            ),
            (
                8,
                'CP_008',
                'Contact_Outcome',
                'CONTACT',
                7,
                'SILVER.OUTREACH_EVENT'
            ),
            (
                9,
                'CP_009',
                'Post_Contact_Engagement',
                'ENGAGEMENT',
                8,
                'SILVER.OUTREACH_EVENT'
            )
    ) AS v
WHERE
    NOT EXISTS (
        SELECT
            1
        FROM
            DIM_CHECKPOINT
        WHERE
            CHECKPOINT_KEY = v.$1
    );
CREATE TABLE IF NOT EXISTS DIM_REASON (
        REASON_KEY NUMBER,
        REASON_CODE VARCHAR,
        REASON_DESCRIPTION VARCHAR,
        REASON_CATEGORY VARCHAR,
        IS_INTENTIONAL BOOLEAN,
        RESPONSIBLE_PARTY VARCHAR,
        RESPONSIBLE_PARTY_TYPE VARCHAR
    );
INSERT INTO
    DIM_REASON
SELECT
    *
FROM
    (
        VALUES
            (
                -1,
                'UNKNOWN',
                'No reason captured',
                'UNKNOWN',
                FALSE,
                'UNASSIGNED',
                'UNKNOWN'
            ),
            (
                1,
                'NO_CONSENT',
                'ConsentStatus is not Opted-In',
                'CONSENT',
                TRUE,
                'Compliance_Team',
                'COMPLIANCE_RULE'
            ),
            (
                2,
                'DO_NOT_CONTACT',
                'DoNotContactFlag is set',
                'CONSENT',
                TRUE,
                'Compliance_Team',
                'COMPLIANCE_RULE'
            ),
            (
                3,
                'SPECIALTY_INELIGIBLE',
                'Specialty not on approved list',
                'ELIGIBILITY',
                TRUE,
                'Brand_Ops',
                'BUSINESS_RULE'
            ),
            (
                4,
                'TIER3_LOW_ENGAGEMENT',
                'Tier 3 HCP with no recent engagement',
                'ELIGIBILITY',
                TRUE,
                'Brand_Ops',
                'BUSINESS_RULE'
            ),
            (
                5,
                'DUPLICATE_OR_PRIOR_BOUNCE',
                'Duplicate record or prior hard bounce on file',
                'SUPPRESSION',
                FALSE,
                'Data_Quality_Team',
                'DATA_QUALITY'
            ),
            (
                6,
                'CONTACT_FAILURE',
                'Email bounced on send',
                'CONTACT',
                FALSE,
                'Deliverability_Team',
                'DELIVERY_BEHAVIOR'
            ),
            (
                7,
                'OPT_OUT_AFTER_CONTACT',
                'HCP unsubscribed after being reached',
                'ENGAGEMENT',
                TRUE,
                'Compliance_Team',
                'COMPLIANCE_RULE'
            )
    ) AS v
WHERE
    NOT EXISTS (
        SELECT
            1
        FROM
            DIM_REASON
        WHERE
            REASON_KEY = v.$1
    );
CREATE TABLE IF NOT EXISTS DIM_BU_BRAND (
        BU_BRAND_KEY NUMBER,
        BUSINESS_UNIT_ID VARCHAR,
        BU_NAME VARCHAR,
        BRAND_ID VARCHAR,
        BRAND_NAME VARCHAR
    );
INSERT INTO
    DIM_BU_BRAND
SELECT
    *
FROM
    (
        VALUES
            (
                -1,
                'UNKNOWN',
                'Unknown BU',
                'UNKNOWN',
                'Unknown Brand'
            ),
            (
                1,
                'BU_PHARMA',
                'Pharma Business Unit',
                'BRAND_CARDIOMET',
                'CardioMet'
            )
    ) AS v
WHERE
    NOT EXISTS (
        SELECT
            1
        FROM
            DIM_BU_BRAND
        WHERE
            BU_BRAND_KEY = v.$1
    );
CREATE
    OR REPLACE DYNAMIC TABLE DIM_SUBSCRIBER TARGET_LAG = DOWNSTREAM WAREHOUSE = CEDP_ETL_WH AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            SUBSCRIBER_KEY
    ) AS SUBSCRIBER_SK,
    SUBSCRIBER_KEY,
    NPI,
    SPECIALTY,
    HCP_TIER,
    LICENSE_STATE,
    INSTITUTION_NAME,
    BUSINESS_UNIT_ID,
    BRAND_ID,
    SUBSCRIBER_STATUS
FROM
    SILVER.SUBSCRIBER
UNION ALL
SELECT
    -1,
    'UNKNOWN',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'UNKNOWN',
    'UNKNOWN',
    'UNKNOWN';
CREATE
    OR REPLACE DYNAMIC TABLE FACT_SUBSCRIBER_CHECKPOINT TARGET_LAG = DOWNSTREAM WAREHOUSE = CEDP_ETL_WH AS WITH cp1 AS (
        SELECT
            SUBSCRIBER_KEY,
            1 AS CHECKPOINT_KEY,
            -1 AS REASON_KEY,
            'ENTERED' AS EVENT_STATUS
        FROM
            SILVER.SUBSCRIBER
    ),
    cp2 AS (
        SELECT
            SUBSCRIBER_KEY,
            2 AS CHECKPOINT_KEY,
            CASE
                WHEN CONSENT_STATUS != 'Opted-In' THEN 1
                WHEN DO_NOT_CONTACT_FLAG THEN 2
                ELSE -1
            END AS REASON_KEY,
            CASE
                WHEN CONSENT_STATUS = 'Opted-In'
                AND NOT DO_NOT_CONTACT_FLAG THEN 'PASSED'
                ELSE 'EXCLUDED'
            END AS EVENT_STATUS
        FROM
            SILVER.SUBSCRIBER
    ),
    cp3 AS (
        SELECT
            s.SUBSCRIBER_KEY,
            3 AS CHECKPOINT_KEY,
            CASE
                WHEN s.SPECIALTY IN ('Oncology', 'Cardiology', 'Endocrinology') THEN -1
                ELSE 3
            END AS REASON_KEY,
            CASE
                WHEN s.SPECIALTY IN ('Oncology', 'Cardiology', 'Endocrinology') THEN 'PASSED'
                ELSE 'EXCLUDED'
            END AS EVENT_STATUS
        FROM
            SILVER.SUBSCRIBER s
            JOIN cp2 ON cp2.SUBSCRIBER_KEY = s.SUBSCRIBER_KEY
            AND cp2.EVENT_STATUS = 'PASSED'
    ),
    cp4 AS (
        SELECT
            s.SUBSCRIBER_KEY,
            4 AS CHECKPOINT_KEY,
            CASE
                WHEN s.HCP_TIER = 'Tier3' THEN 4
                ELSE -1
            END AS REASON_KEY,
            CASE
                WHEN s.HCP_TIER = 'Tier3' THEN 'EXCLUDED'
                ELSE 'PASSED'
            END AS EVENT_STATUS
        FROM
            SILVER.SUBSCRIBER s
            JOIN cp3 ON cp3.SUBSCRIBER_KEY = s.SUBSCRIBER_KEY
            AND cp3.EVENT_STATUS = 'PASSED'
    ),
    cp5 AS (
        SELECT
            cp4.SUBSCRIBER_KEY,
            5 AS CHECKPOINT_KEY,
            CASE
                WHEN ss.LIST_STATUS = 'Held' THEN 5
                ELSE -1
            END AS REASON_KEY,
            CASE
                WHEN ss.LIST_STATUS = 'Held' THEN 'EXCLUDED'
                ELSE 'PASSED'
            END AS EVENT_STATUS
        FROM
            cp4
            LEFT JOIN SILVER.SUPPRESSION_STATE ss ON ss.SUBSCRIBER_KEY = cp4.SUBSCRIBER_KEY
        WHERE
            cp4.EVENT_STATUS = 'PASSED'
    ),
    cp6 AS (
        SELECT
            js.SUBSCRIBER_KEY,
            6 AS CHECKPOINT_KEY,
            -1 AS REASON_KEY,
            js.JOURNEY_STATUS AS EVENT_STATUS
        FROM
            SILVER.JOURNEY_STATUS js
            JOIN cp5 ON cp5.SUBSCRIBER_KEY = js.SUBSCRIBER_KEY
            AND cp5.EVENT_STATUS = 'PASSED'
    ),
    cp7 AS (
        SELECT
            DISTINCT SUBSCRIBER_KEY,
            7 AS CHECKPOINT_KEY,
            -1 AS REASON_KEY,
            'SENT' AS EVENT_STATUS
        FROM
            SILVER.OUTREACH_ATTEMPT
    ),
    cp8 AS (
        SELECT
            SUBSCRIBER_KEY,
            8 AS CHECKPOINT_KEY,
            CASE
                WHEN EVENT_TYPE = 'FAILED' THEN 6
                ELSE -1
            END AS REASON_KEY,
            EVENT_TYPE AS EVENT_STATUS
        FROM
            SILVER.OUTREACH_EVENT
        WHERE
            EVENT_TYPE IN ('FAILED', 'REACHED')
    ),
    cp9 AS (
        SELECT
            SUBSCRIBER_KEY,
            9 AS CHECKPOINT_KEY,
            CASE
                WHEN EVENT_TYPE = 'OPTED_OUT' THEN 7
                ELSE -1
            END AS REASON_KEY,
            EVENT_TYPE AS EVENT_STATUS
        FROM
            SILVER.OUTREACH_EVENT
        WHERE
            EVENT_TYPE IN ('OPENED', 'CLICKED', 'OPTED_OUT')
    ),
    combined AS (
        SELECT
            *
        FROM
            cp1
        UNION ALL
        SELECT
            *
        FROM
            cp2
        UNION ALL
        SELECT
            *
        FROM
            cp3
        UNION ALL
        SELECT
            *
        FROM
            cp4
        UNION ALL
        SELECT
            *
        FROM
            cp5
        UNION ALL
        SELECT
            *
        FROM
            cp6
        UNION ALL
        SELECT
            *
        FROM
            cp7
        UNION ALL
        SELECT
            *
        FROM
            cp8
        UNION ALL
        SELECT
            *
        FROM
            cp9
    )
SELECT
    COALESCE(ds.SUBSCRIBER_SK, -1) AS SUBSCRIBER_SK,
    COALESCE(bb.BU_BRAND_KEY, -1) AS BU_BRAND_KEY,
    c.CHECKPOINT_KEY,
    c.REASON_KEY,
    c.EVENT_STATUS,
    CASE
        WHEN c.EVENT_STATUS IN (
            'ENTERED',
            'PASSED',
            'SENT',
            'REACHED',
            'OPENED',
            'CLICKED'
        ) THEN TRUE
        ELSE FALSE
    END AS PASSED_FLAG,
    CASE
        WHEN c.EVENT_STATUS = 'EXCLUDED' THEN TRUE
        ELSE FALSE
    END AS EXCLUDED_FLAG,
    CASE
        WHEN c.EVENT_STATUS IN ('FAILED', 'OPTED_OUT') THEN TRUE
        ELSE FALSE
    END AS FAILED_FLAG
FROM
    combined c
    LEFT JOIN DIM_SUBSCRIBER ds ON ds.SUBSCRIBER_KEY = c.SUBSCRIBER_KEY
    LEFT JOIN SILVER.SUBSCRIBER s ON s.SUBSCRIBER_KEY = c.SUBSCRIBER_KEY
    LEFT JOIN DIM_BU_BRAND bb ON bb.BUSINESS_UNIT_ID = s.BUSINESS_UNIT_ID
    AND bb.BRAND_ID = s.BRAND_ID;