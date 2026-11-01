const express = require('express');
const session = require('express-session');
const pgSession = require('connect-pg-simple')(session);
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const multer = require('multer');
const crypto = require('crypto');
const bcrypt = require('bcrypt');
const path = require('path');
const fs = require('fs');
const { execFile } = require('child_process');
const { Pool } = require('pg');
const { z } = require('zod');
require('dotenv').config();

const ALLOWED_HOSTEL_TYPES = [
  'जूनियर छात्रावास',
  'सीनियर छात्रावास',
  'उत्कृष्ट छात्रावास',
  'पोस्ट-मेट्रिक छात्रावास',
  'आश्रम छात्रावास'
];

const hostelCreateSchema = z.object({
  hostel_code: z.string().min(1, 'छात्रावास कोड आवश्यक है'),
  hostel_name: z.string().min(1, 'छात्रावास का नाम आवश्यक है'),
  hostel_type: z.enum(ALLOWED_HOSTEL_TYPES, {
    errorMap: () => ({ message: 'छात्रावास का प्रकार केवल 5 अधिकृत विकल्पों (जूनियर छात्रावास, सीनियर छात्रावास, उत्कृष्ट छात्रावास, पोस्ट-मेट्रिक छात्रावास, आश्रम छात्रावास) में से एक होना आवश्यक है।' })
  }),
  gender_category: z.string().optional().nullable(),
  department: z.string().optional().nullable(),
  district: z.string().optional().nullable(),
  tehsil_block: z.string().optional().nullable(),
  address: z.string().optional().nullable(),
  latitude: z.number().min(-90).max(90).optional().nullable(),
  longitude: z.number().min(-180).max(180).optional().nullable(),
  location_status: z.enum(['PENDING', 'VERIFIED', 'CORRECTION_REQUIRED']).default('PENDING'),
  superintendent_name: z.string().optional().nullable(),
  superintendent_mobile: z.string().optional().nullable(),
  sanctioned_seats: z.number().int().nonnegative().optional().nullable(),
  enrolled_students: z.number().int().nonnegative().optional().nullable(),
  vacant_seats: z.number().int().nonnegative().optional().nullable(),
  source_doc_name: z.string().min(1, 'स्रोत अभिलेख का नाम आवश्यक है'),
  source_page_ref: z.string().optional().nullable(),
  is_test_record: z.boolean().default(false)
});

const app = express();
const PORT = process.env.PORT || 4000;
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const UPLOAD_DIR = path.resolve(process.env.UPLOAD_DIR || './uploads');
const BACKUP_DIR = path.resolve(process.env.BACKUP_DIR || './backups');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
fs.mkdirSync(BACKUP_DIR, { recursive: true });

app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: '5mb' }));
app.use(session({
  store: new pgSession({ pool, createTableIfMissing: true }),
  name: 'mp_hostel_sid',
  secret: process.env.SESSION_SECRET || 'replace_in_production_secret',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', maxAge: 8 * 3600 * 1000 }
}));

function requireAuth(req, res, next) {
  if (!req.session || !req.session.user) {
    return res.status(401).json({ error: 'अधिकृत लॉगिन आवश्यक है।' });
  }
  next();
}

function verifyCsrf(req, res, next) {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) return next();
  const token = req.headers['x-csrf-token'] || req.body?._csrf;
  if (!req.session || !token || token !== req.session.csrfToken) {
    return res.status(403).json({ error: 'अमान्य CSRF सुरक्षा टोकन।' });
  }
  next();
}

app.get('/api/hostels', requireAuth, async (req, res) => {
  const isTest = req.query.env === 'TEST';
  const { type, q } = req.query;
  const params = [isTest];
  let sql = 'SELECT * FROM hostels WHERE is_test_record = $1';
  if (type) {
    params.push(type);
    sql += ` AND hostel_type = $${params.length}`;
  }
  if (q) {
    params.push(`%${q}%`);
    sql += ` AND (hostel_name ILIKE $${params.length} OR hostel_code ILIKE $${params.length} OR hostel_type ILIKE $${params.length})`;
  }
  sql += ' ORDER BY created_at DESC';
  const { rows } = await pool.query(sql, params);
  res.json({ hostels: rows, allowedTypes: ALLOWED_HOSTEL_TYPES });
});

// पुराने छात्रावास रिकॉर्ड्स की जाँच (बिना डिलीट या स्वतः परिवर्तित किए)
app.get('/api/hostels/legacy-unmigrated', requireAuth, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT * FROM hostels WHERE hostel_type IS NULL OR hostel_type NOT IN ($1, $2, $3, $4, $5)`,
    ALLOWED_HOSTEL_TYPES
  );
  res.json({ unmigratedHostels: rows, allowedTypes: ALLOWED_HOSTEL_TYPES });
});

// अधिकृत उपयोगकर्ता की अनुमति से पुराने रिकॉर्ड का सुरक्षित प्रकार माइग्रेशन
app.patch('/api/hostels/:id/migrate-type', requireAuth, verifyCsrf, async (req, res) => {
  const { new_hostel_type } = req.body;
  if (!ALLOWED_HOSTEL_TYPES.includes(new_hostel_type)) {
    return res.status(400).json({ error: 'कृपया केवल 5 अधिकृत छात्रावास प्रकारों में से एक चुनें।' });
  }
  const { rows } = await pool.query(
    `UPDATE hostels
     SET legacy_unmigrated_type = COALESCE(legacy_unmigrated_type, hostel_type),
         hostel_type = $1,
         updated_at = NOW()
     WHERE id = $2
     RETURNING *`,
    [new_hostel_type, req.params.id]
  );
  if (!rows.length) return res.status(404).json({ error: 'छात्रावास रिकॉर्ड नहीं मिला।' });
  res.json({ hostel: rows[0] });
});

app.post('/api/hostels', requireAuth, verifyCsrf, async (req, res) => {
  try {
    const b = hostelCreateSchema.parse(req.body);
    const hasCoords = b.latitude !== null && b.latitude !== undefined && b.longitude !== null && b.longitude !== undefined;
    const locStatus = hasCoords ? (b.location_status || 'PENDING') : 'PENDING';
    const { rows } = await pool.query(
      `INSERT INTO hostels (hostel_code, hostel_name, hostel_type, gender_category, department, district, tehsil_block, address, latitude, longitude, location_status, superintendent_name, superintendent_mobile, sanctioned_seats, enrolled_students, vacant_seats, source_doc_name, source_page_ref, is_test_record)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19) RETURNING *`,
      [b.hostel_code, b.hostel_name, b.hostel_type, b.gender_category || null, b.department || null, b.district || null, b.tehsil_block || null, b.address || null, hasCoords ? b.latitude : null, hasCoords ? b.longitude : null, locStatus, b.superintendent_name || null, b.superintendent_mobile || null, b.sanctioned_seats ?? null, b.enrolled_students ?? null, b.vacant_seats ?? null, b.source_doc_name, b.source_page_ref || null, Boolean(b.is_test_record)]
    );
    res.status(201).json({ hostel: rows[0] });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.get('/api/employees', requireAuth, async (req, res) => {
  const isTest = req.query.env === 'TEST';
  const { rows } = await pool.query('SELECT * FROM employees WHERE is_test_record = $1 ORDER BY created_at DESC', [isTest]);
  res.json({ employees: rows });
});

app.get('/api/cases', requireAuth, async (req, res) => {
  const isTest = req.query.env === 'TEST';
  const { rows } = await pool.query('SELECT * FROM establishment_cases WHERE is_test_record = $1 ORDER BY created_at DESC', [isTest]);
  res.json({ cases: rows });
});

app.post('/api/admin/backup', requireAuth, verifyCsrf, (req, res) => {
  const file = path.join(BACKUP_DIR, `mp_hostel_backup_${Date.now()}.sql`);
  execFile('pg_dump', [process.env.DATABASE_URL, '-f', file], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.download(file);
  });
});


// Auto-initialize database tables on first cloud boot so 1-click deployments work immediately
async function initCloudDatabase() {
  try {
    const schemaPath = path.join(__dirname, '../../database/schema.sql');
    if (fs.existsSync(schemaPath)) {
      const sql = fs.readFileSync(schemaPath, 'utf8');
      await pool.query(sql);
      console.log('PostgreSQL schema verified/initialized.');
    }
  } catch (err) {
    console.warn('Database auto-init notice:', err.message);
  }
}

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', portal: 'MP District Hostel Monitoring Portal' });
});

app.get('/api/sync/state', async (req, res) => {
  try {
    const envKey = req.query.env === 'TEST' ? 'TEST' : 'PROD';
    const { rows } = await pool.query('SELECT state_json, updated_at FROM portal_state_snapshots WHERE env_key = $1', [envKey]);
    if (!rows.length) {
      return res.json({ env: envKey, data: null });
    }
    res.json({ env: envKey, data: rows[0].state_json, updatedAt: rows[0].updated_at });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/sync/state', async (req, res) => {
  try {
    const envKey = req.body.env === 'TEST' ? 'TEST' : 'PROD';
    const data = req.body.data || {};
    await pool.query(
      `INSERT INTO portal_state_snapshots (env_key, state_json, updated_at)
       VALUES ($1, $2::jsonb, NOW())
       ON CONFLICT (env_key) DO UPDATE SET state_json = EXCLUDED.state_json, updated_at = NOW()`,
      [envKey, JSON.stringify(data)]
    );
    res.json({ status: 'synced', env: envKey, updatedAt: new Date().toISOString() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.use(express.static(path.join(__dirname, '../../frontend')));

if (require.main === module) {
  initCloudDatabase().then(() => {
    app.listen(PORT, () => console.log(`MP Hostel Portal active on http://localhost:${PORT}`));
  });
}
module.exports = { app, ALLOWED_HOSTEL_TYPES, hostelCreateSchema };
