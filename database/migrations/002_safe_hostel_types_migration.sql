-- ============================================================================
-- सुरक्षित माइग्रेशन स्क्रिप्ट (Safe Hostel Type Migration - Non-Destructive)
-- नियम: किसी भी पुराने छात्रावास रिकॉर्ड को बिना अनुमति डिलीट या गलत प्रकार में स्वतः परिवर्तित न करें।
-- ============================================================================

BEGIN;

-- 1. यदि पुराने प्रकार मौजूद हैं, तो उन्हें सुरक्षित रूप से legacy_unmigrated_type कॉलम में संरक्षित करें
ALTER TABLE hostels ADD COLUMN IF NOT EXISTS legacy_unmigrated_type VARCHAR(150);

UPDATE hostels
SET legacy_unmigrated_type = hostel_type,
    record_verification_status = 'CORRECTION_REQUIRED'
WHERE hostel_type IS NULL
   OR hostel_type NOT IN (
       'जूनियर छात्रावास',
       'सीनियर छात्रावास',
       'उत्कृष्ट छात्रावास',
       'पोस्ट-मेट्रिक छात्रावास',
       'आश्रम छात्रावास'
   );

-- 2. पुरानी CHECK constraint हटाकर नई 5-विकल्प वाली NOT VALID constraint जोड़ें
-- (NOT VALID यह सुनिश्चित करता है कि पुराने असंशोधित रिकॉर्ड बिना डिलीट हुए सुरक्षित रहें,
--  जबकि हर नया या संशोधित रिकॉर्ड केवल 5 अधिकृत प्रकारों में से ही सेव हो सके।)
ALTER TABLE hostels DROP CONSTRAINT IF EXISTS hostels_hostel_type_check;

ALTER TABLE hostels
ADD CONSTRAINT hostels_hostel_type_check
CHECK (hostel_type IN (
    'जूनियर छात्रावास',
    'सीनियर छात्रावास',
    'उत्कृष्ट छात्रावास',
    'पोस्ट-मेट्रिक छात्रावास',
    'आश्रम छात्रावास'
)) NOT VALID;

COMMIT;
