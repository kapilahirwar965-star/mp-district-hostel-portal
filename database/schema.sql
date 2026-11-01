-- ============================================================================
-- मध्य प्रदेश शासन — जिला छात्रावास मॉनिटरिंग एवं स्थापना शाखा प्रबंधन पोर्टल
-- PostgreSQL Database Schema (Zero Pre-populated Government Data)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. अधिकृत उपयोगकर्ता (Authorized Establishment Branch Users)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name VARCHAR(200),
    designation VARCHAR(150),
    role VARCHAR(50) NOT NULL DEFAULT 'ESTABLISHMENT_INCHARGE',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. पदनाम मास्टर (Configurable Designation Categories)
CREATE TABLE designations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title_hi VARCHAR(150) UNIQUE NOT NULL,
    category VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. छात्रावास मुख्य रिकॉर्ड (Hostels Master Table - Strictly Empty Initially)
-- केवल 5 अधिकृत छात्रावास प्रकार अनुमत हैं:
-- 1. जूनियर छात्रावास
-- 2. सीनियर छात्रावास
-- 3. उत्कृष्ट छात्रावास
-- 4. पोस्ट-मेट्रिक छात्रावास
-- 5. आश्रम छात्रावास
CREATE TABLE hostels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hostel_code VARCHAR(100) UNIQUE NOT NULL,
    hostel_name VARCHAR(255) NOT NULL,
    hostel_type VARCHAR(150) NOT NULL
        CHECK (hostel_type IN (
            'जूनियर छात्रावास',
            'सीनियर छात्रावास',
            'उत्कृष्ट छात्रावास',
            'पोस्ट-मेट्रिक छात्रावास',
            'आश्रम छात्रावास'
        )),
    legacy_unmigrated_type VARCHAR(150),
    gender_category VARCHAR(50),
    department VARCHAR(200),
    district VARCHAR(150),
    tehsil_block VARCHAR(150),
    address TEXT,
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    location_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
        CHECK (location_status IN ('PENDING', 'VERIFIED', 'CORRECTION_REQUIRED')),
    location_verified_by VARCHAR(200),
    location_verified_at TIMESTAMPTZ,
    superintendent_name VARCHAR(200),
    superintendent_mobile VARCHAR(30),
    sanctioned_seats INTEGER CHECK (sanctioned_seats IS NULL OR sanctioned_seats >= 0),
    enrolled_students INTEGER CHECK (enrolled_students IS NULL OR enrolled_students >= 0),
    vacant_seats INTEGER CHECK (vacant_seats IS NULL OR vacant_seats >= 0),
    building_status VARCHAR(150),
    total_rooms INTEGER CHECK (total_rooms IS NULL OR total_rooms >= 0),
    drinking_water_status VARCHAR(150),
    electricity_status VARCHAR(150),
    toilet_status VARCHAR(150),
    kitchen_mess_status VARCHAR(150),
    security_arrangements TEXT,
    other_facilities TEXT,
    last_inspection_date DATE,
    inspection_officer VARCHAR(200),
    inspection_remarks TEXT,
    source_doc_name VARCHAR(255) NOT NULL,
    source_page_ref VARCHAR(100),
    entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
    record_verification_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    operational_status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    is_test_record BOOLEAN NOT NULL DEFAULT FALSE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. छात्रावास वार स्वीकृत एवं रिक्त पद (Sanctioned Posts per Hostel)
CREATE TABLE hostel_sanctioned_posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hostel_id UUID NOT NULL REFERENCES hostels(id) ON DELETE CASCADE,
    designation_title VARCHAR(150) NOT NULL,
    sanctioned_count INTEGER,
    filled_count INTEGER,
    vacant_count INTEGER,
    source_order_ref VARCHAR(200),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. कर्मचारी रिकॉर्ड (Employees Master Table - Strictly Empty Initially)
CREATE TABLE employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_code VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    designation VARCHAR(150) NOT NULL,
    employee_category VARCHAR(100),
    employment_type VARCHAR(50),
    mobile_number VARCHAR(30),
    current_hostel_id UUID REFERENCES hostels(id) ON DELETE SET NULL,
    current_office_name VARCHAR(255),
    posting_order_no VARCHAR(150),
    posting_date DATE,
    joining_date DATE,
    service_status VARCHAR(50) NOT NULL DEFAULT 'कार्यरत',
    source_doc_name VARCHAR(255) NOT NULL,
    source_page_ref VARCHAR(100),
    verification_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    remarks TEXT,
    is_test_record BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. कर्मचारी पदस्थापना एवं स्थानांतरण इतिहास (Employee Posting & Transfer History)
CREATE TABLE employee_posting_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    from_place_name VARCHAR(255),
    to_place_name VARCHAR(255),
    order_number VARCHAR(150),
    order_date DATE,
    relieving_date DATE,
    joining_date DATE,
    source_reference VARCHAR(255),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. स्थापना शाखा प्रकरण प्रबंधन (Establishment Branch Cases)
CREATE TABLE establishment_cases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_number VARCHAR(100) UNIQUE NOT NULL,
    inward_number VARCHAR(100),
    inward_date DATE,
    case_category VARCHAR(150) NOT NULL,
    subject TEXT NOT NULL,
    related_hostel_id UUID REFERENCES hostels(id) ON DELETE SET NULL,
    related_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    workflow_stage VARCHAR(60) NOT NULL DEFAULT 'प्राप्त',
    due_date DATE,
    notesheet_draft TEXT,
    final_order_number VARCHAR(150),
    final_order_date DATE,
    final_order_text TEXT,
    source_doc_name VARCHAR(255) NOT NULL,
    source_page_ref VARCHAR(100),
    is_test_record BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. प्रकरण कार्यवाही इतिहास (Establishment Case Action History)
CREATE TABLE case_action_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID NOT NULL REFERENCES establishment_cases(id) ON DELETE CASCADE,
    from_stage VARCHAR(60),
    to_stage VARCHAR(60) NOT NULL,
    action_note TEXT,
    acted_by VARCHAR(150),
    acted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. अपलोड किए गए दस्तावेज एवं अभिलेख (Uploaded Documents)
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    document_title VARCHAR(255) NOT NULL,
    document_category VARCHAR(100),
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    sha256_checksum VARCHAR(64) NOT NULL,
    source_register_name VARCHAR(255) NOT NULL,
    source_page_number VARCHAR(100),
    uploaded_by VARCHAR(150),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. ऑडिट लॉग एवं परिवर्तन इतिहास (Immutable Audit Logs)
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_username VARCHAR(150) NOT NULL,
    environment VARCHAR(30) NOT NULL DEFAULT 'PROD',
    action_type VARCHAR(80) NOT NULL,
    entity_type VARCHAR(80) NOT NULL,
    detail TEXT,
    source_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 11. मासिक छात्र उपस्थिति एवं भोजनालय लॉग (Step 4: Monthly Attendance & Mess Tracker)
CREATE TABLE IF NOT EXISTS hostel_monthly_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hostel_id UUID NOT NULL REFERENCES hostels(id) ON DELETE CASCADE,
    month_year VARCHAR(20) NOT NULL,
    avg_present_students INTEGER NOT NULL CHECK (avg_present_students >= 0),
    mess_expense_inr NUMERIC(12, 2),
    grain_allocation_status TEXT,
    source_register_ref VARCHAR(255) NOT NULL,
    recorded_by VARCHAR(150),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 12. भवन रखरखाव एवं मरम्मत मांग-पत्र (Step 5: Infrastructure Maintenance & Work Demand Tickets)
CREATE TABLE IF NOT EXISTS maintenance_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_number VARCHAR(50) UNIQUE NOT NULL,
    hostel_id UUID NOT NULL REFERENCES hostels(id) ON DELETE CASCADE,
    work_category VARCHAR(150) NOT NULL,
    work_description TEXT NOT NULL,
    estimated_cost_inr NUMERIC(12, 2),
    ticket_status VARCHAR(80) NOT NULL DEFAULT 'मांग-पत्र प्राप्त',
    source_demand_ref VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 13. क्लाउड पोर्टल स्टेट सिंक टेबल (Cloud State Snapshot for Instant Online Multi-Device Sync)
CREATE TABLE IF NOT EXISTS portal_state_snapshots (
    env_key VARCHAR(20) PRIMARY KEY,
    state_json JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
