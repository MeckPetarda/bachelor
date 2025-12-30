# Attendance System Server - Task Assignment

## Overview
Build a Bun + TypeScript backend server that:
- Runs an embedded MQTT broker to receive RFID scan data from lighthouses
- Stores raw scans and processed events in PostgreSQL
- Detects entry/exit from dual-lighthouse temporal data
- Exposes REST APIs for lighthouse/user/event management
- Serves a React admin dashboard
- Provides pluggable integration adapters (Navigo3)

---

## Phase 1: Core Backend Infrastructure

### Task 1.1: Project Setup
**Steps:**
1. Create new Bun project: `bun init attendance-system-server`
2. Install dependencies:
   - `typescript`, `@types/bun`
   - `elysia` (REST framework)
   - `postgres` (PostgreSQL driver)
   - `aedes`, `mqtt` (MQTT broker)
   - `jsonwebtoken` (JWT auth)
   - `drizzle-orm`, `drizzle-kit` (query builder)
3. Configure TypeScript: `tsconfig.json` with strict mode enabled
4. Create directory structure as outlined in gameplan
5. Verify: `bun run index.ts` starts without errors

**Definition of Done:**
- Project builds without warnings
- Can import all dependencies
- Basic TypeScript compilation works

---

### Task 1.2: PostgreSQL Database Schema
**Steps:**
1. Create PostgreSQL database: `createdb attendance`
2. Implement schema as SQL file or Drizzle schema definitions:
   - `lighthouses` table (device registration)
   - `raw_scans` table (immutable audit log)
   - `processed_events` table (derived entry/exit)
   - `users` table (with internal_id / remote_id separation)
   - `tag_assignments` table (RFID tags to users)
   - `mqtt_clients` table (connection tracking)
   - `integration_configs` table (Navigo3 + extensible)
3. Create indexes for performance (see gameplan for specific indexes)
4. Write migration scripts (or use Drizzle migrations)
5. Test schema with sample inserts

**Definition of Done:**
- All tables created with correct columns
- Indexes applied
- Sample data can be inserted/queried
- Foreign key constraints work

---

### Task 1.3: PostgreSQL Connection Pool
**Steps:**
1. Create `src/database/client.ts`:
   - Initialize `postgres` client with connection pooling
   - Load DATABASE_URL from environment
   - Implement query helper functions
   - Add error handling and logging
2. Test connection: write script to query lighthouses table
3. Implement graceful shutdown (close pool on app exit)

**Definition of Done:**
- Connection pool initializes on startup
- Can execute queries without errors
- Pool closes cleanly on shutdown

---

### Task 1.4: MQTT Broker Integration
**Steps:**
1. Create `src/mqtt/broker.ts`:
   - Initialize Aedes MQTT broker
   - Configure to listen on port 1883 (or from env)
   - Implement client connection handler
   - Log connects/disconnects
2. Create `src/mqtt/handlers.ts`:
   - Handler for `attendance/lighthouse/{device_id}/scans` topic
   - Parse incoming JSON payload (lighthouse event)
   - Insert into `raw_scans` table immediately
   - Add to event processing queue (async, non-blocking)
   - Emit WebSocket event for dashboard
3. Test:
   - Use `mosquitto_pub` to send test message
   - Verify data appears in raw_scans table

**Definition of Done:**
- MQTT broker starts on port 1883
- Lighthouses can connect and publish
- Messages are received and stored in DB
- No payload is dropped

---

### Task 1.5: Basic REST API Endpoints
**Steps:**
1. Create `src/api/routes.ts` using Elysia:
   - `GET /health` → returns status
   - `POST /api/v1/auth/login` → validate credentials, return JWT
2. Create `src/api/middleware.ts`:
   - JWT validation middleware
   - Request logging middleware
   - Error handling middleware
3. Create lighthouse CRUD endpoints:
   - `GET /api/v1/lighthouses` → list all
   - `POST /api/v1/lighthouses` → register new
   - `GET /api/v1/lighthouses/{id}` → get details
   - `PATCH /api/v1/lighthouses/{id}` → update config
4. Test each endpoint with curl or Postman

**Definition of Done:**
- All endpoints return valid JSON
- JWT auth works (invalid tokens rejected)
- Lighthouse CRUD operations work
- Database transactions complete successfully

---

### Task 1.6: Environment Configuration
**Steps:**
1. Create `.env.example`:
   ```
   DATABASE_URL=postgresql://user:pass@localhost:5432/attendance
   JWT_SECRET=your-secret-key-here
   MQTT_PORT=1883
   HTTP_PORT=3000
   NODE_ENV=development
   ```
2. Create `src/config.ts`:
   - Load environment variables
   - Validate required vars present
   - Export config object for use throughout app
3. Create `.env` (git-ignored) with actual values

**Definition of Done:**
- App reads config from environment
- Validates required variables
- Graceful error if missing
- No hardcoded secrets

---

## Phase 2: Event Processing & Direction Detection

### Task 2.1: Direction Detection Algorithm
**Steps:**
1. Create `src/services/event-processor.ts`:
   - Implement `findMatchingScans()`: query raw_scans for same tag within 2-second window from other lighthouse
   - Implement `detectDirection()`: analyze temporal order and RSSI progression
     - If A→B with RSSI strengthening: ENTRY
     - If B→A with RSSI strengthening: EXIT
   - Implement `calculateConfidence()`: score 0-1 based on temporal proximity, RSSI change, lighthouse separation
2. Create `src/services/tag-lookup.ts`:
   - Function to find user_id given tag_epc
   - Handle unassigned tags (return null)
3. Create `src/services/processed-event.ts`:
   - Function to create processed_event from matched scans
   - Store references to raw_scan ids
   - Calculate and store confidence score

**Definition of Done:**
- Direction detection correctly identifies ENTRY vs EXIT
- Confidence scores are reasonable (0.5 = uncertain, 0.95 = very confident)
- Unassigned tags handled gracefully
- Matching logic accounts for time windows

---

### Task 2.2: Event Processing Queue
**Steps:**
1. Create `src/services/event-queue.ts`:
   - Background task that processes raw_scans asynchronously
   - When new raw_scan is inserted, trigger processing
   - Call direction detection for same-tag matches
   - Create processed_event if match found
   - Mark raw_scans as processed
2. Implement graceful shutdown (flush queue before exit)
3. Add error handling: log failures, mark for manual review

**Definition of Done:**
- Queue processes scans without blocking MQTT
- Entries and exits created with correct direction
- Raw scans marked as processed
- Errors logged, not silent

---

### Task 2.3: Event Processing REST Endpoints
**Steps:**
1. Add to `src/api/routes.ts`:
   - `GET /api/v1/scans` → query raw_scans (filters: EPC, time range, lighthouse)
   - `GET /api/v1/events` → query processed_events (filters: type, user, time range)
   - `POST /api/v1/events/manual` → create manual entry/exit (admin override)
2. Implement pagination for large result sets
3. Test with sample data

**Definition of Done:**
- Can query scans and events via API
- Filtering works correctly
- Results returned as JSON
- Manual event creation works

---

## Phase 3: User & Tag Management

### Task 3.1: User Management Service
**Steps:**
1. Create `src/services/user-service.ts`:
   - `createUser()`: insert into users table
   - `updateUser()`: modify user details
   - `deleteUser()`: soft delete (or hard delete)
   - `togglePersonalDataStorage()`: update personal_data_enabled flag
2. Implement validation:
   - internal_id must be unique
   - email format if provided
3. Add audit logging: track who changed user records when

**Definition of Done:**
- Can create/update/delete users
- Validation prevents bad data
- Personal data flag toggles correctly
- Audit trail recorded

---

### Task 3.2: Tag Assignment Service
**Steps:**
1. Create `src/services/tag-service.ts`:
   - `assignTagToUser()`: insert into tag_assignments
   - `deactivateTag()`: set deactivated_at timestamp
   - `getTagHistory()`: query all detections for a tag_epc
   - `getUserTags()`: get all active tags for a user
2. Enforce constraints:
   - Only one active tag per EPC (unique index)
   - Can't deactivate already-deactivated tag
3. Query optimization: use indexes on EPC and user_id

**Definition of Done:**
- Can assign tags to users
- Can deactivate tags (soft delete)
- Can view tag history
- Constraints enforced

---

### Task 3.3: User & Tag Management REST Endpoints
**Steps:**
1. Add to `src/api/routes.ts`:
   - `GET /api/v1/users` → list users
   - `POST /api/v1/users` → create user
   - `GET /api/v1/users/{id}` → get user details
   - `PATCH /api/v1/users/{id}` → update user
   - `GET /api/v1/users/{id}/timeline` → get entry/exit history
   - `GET /api/v1/tags` → list all tag assignments
   - `POST /api/v1/tags` → assign tag to user
   - `DELETE /api/v1/tags/{id}` → deactivate tag
   - `GET /api/v1/tags/{epc}/history` → view all detections

**Definition of Done:**
- All endpoints implemented
- CRUD operations work via API
- Authentication required
- Results properly formatted

---

## Phase 4: Integration Layer

### Task 4.1: Integration Configuration Storage
**Steps:**
1. Update `src/database/schema.ts`:
   - Ensure `integration_configs` table exists with JSONB config column
2. Create `src/services/integration-service.ts`:
   - `getIntegrationConfig()`: retrieve config from DB
   - `updateIntegrationConfig()`: store config (validate before saving)
   - `testIntegration()`: make test API call to validate config
   - `maskSecrets()`: hide API keys in API responses
3. Implement config validation:
   - Required fields per integration type (Navigo3 needs api_url, api_key)
   - URL format validation
   - Connectivity test

**Definition of Done:**
- Can store and retrieve integration configs
- Secrets are masked in API responses
- Can test connectivity
- Validation prevents invalid configs

---

### Task 4.2: Navigo3 Integration Adapter
**Steps:**
1. Create `src/services/integrations/navigo3-adapter.ts`:
   - Implement `sync()` method: call Navigo3 API with entry/exit events
   - Determine attendance interval from processed events (ENTRY → EXIT)
   - Call Navigo3 REST endpoint with check-in/check-out times
   - Handle API errors gracefully
2. Implement `syncProcessedEvent()`:
   - Fetch user's remote_id from users table
   - Look up user's last ENTRY time
   - Call Navigo3 with interval
   - Mark processed_event.synced_to_integration = true on success
3. Add retry logic: failed syncs retry on next pass

**Definition of Done:**
- Can sync entry/exit pairs to Navigo3
- Handles API failures without crashing
- Tracks sync status
- Respects personal_data_enabled flag

---

### Task 4.3: Integration Management REST Endpoints
**Steps:**
1. Add to `src/api/routes.ts`:
   - `GET /api/v1/integrations` → list configured integrations
   - `GET /api/v1/integrations/{type}/config` → get config (secrets masked)
   - `POST /api/v1/integrations/{type}/config` → update config
   - `POST /api/v1/integrations/{type}/test` → test connectivity
2. Implement as admin-only endpoints (require AUTH role)

**Definition of Done:**
- Integrations can be configured via API
- Test connectivity endpoint works
- Secrets never exposed
- Only authenticated admins can modify

---

## Phase 5: React Dashboard

### Task 5.1: Project Setup & Authentication
**Steps:**
1. Create React app: `npm create vite@latest frontend -- --template react-ts`
2. Install dependencies:
   - `react-router-dom` (routing)
   - `@tanstack/react-query` (data fetching)
   - `mobx`, `mobx-react-lite` (state management)
   - `sass` (SCSS support)
   - `axios` (HTTP client)
3. Create `src/config.ts`: API base URL
4. Create `src/auth/store.ts`:
   - MobX store for auth state (token, user role)
   - `login()`, `logout()`, `isAuthenticated()` methods
5. Create `src/pages/LoginPage.tsx`:
   - Form for username/password
   - Call `POST /api/v1/auth/login`
   - Store JWT in localStorage
   - Redirect to dashboard on success
6. Create route guards to protect pages

**Definition of Done:**
- React app starts without errors
- Login page loads
- Can authenticate and get JWT
- Token stored and sent with requests
- Protected routes redirect to login

---

### Task 5.2: Dashboard Layout & Navigation
**Steps:**
1. Create `src/layout/DashboardLayout.tsx`:
   - Top navigation bar
   - Sidebar with menu
   - Main content area
2. Create menu items:
   - Dashboard (overview)
   - Lighthouses
   - Events Timeline
   - Users & Tags
   - Settings (integrations)
   - Logout
3. Create `src/pages/Dashboard.tsx`:
   - Display today's scan count
   - Show lighthouse status (online/offline)
   - Display recent events (last 10)
   - System health metrics
4. Style with SCSS

**Definition of Done:**
- Dashboard layout responsive
- Navigation works
- Menu items route correctly
- Can logout

---

### Task 5.3: Lighthouse Management Page
**Steps:**
1. Create `src/pages/LighthousesPage.tsx`:
   - List all lighthouses (GET /api/v1/lighthouses)
   - Show status (online/offline, last seen)
   - Display metrics (scans/min, error rate)
2. Create `src/components/LighthouseCard.tsx`:
   - Show lighthouse details
   - Edit button (name, location, reader_id)
   - Real-time status indicator
3. Create `src/components/LighthouseForm.tsx`:
   - Form to register new lighthouse
   - Form to update existing
   - POST/PATCH to API
4. Create MobX store for lighthouse data:
   - `lighthouseStore.ts`: lighthouses array, update methods

**Definition of Done:**
- Can view all lighthouses
- Can create new lighthouse
- Can edit lighthouse config
- List updates when lighthouses come online/offline

---

### Task 5.4: Events Timeline Page
**Steps:**
1. Create `src/pages/EventsPage.tsx`:
   - Chronological list of entry/exit events
   - Filter by date range, user, event type
   - Pagination or infinite scroll
2. Create `src/components/EventRow.tsx`:
   - Show event details (user, type, timestamp, confidence)
   - Expand button to see raw scans that triggered it
   - "Confirm" / "Override" buttons for admin
3. Create MobX store:
   - `eventStore.ts`: events array, filter methods, sort
4. Implement filters:
   - Date range picker
   - User dropdown
   - Event type checkboxes

**Definition of Done:**
- Can view all events
- Filters work correctly
- Can drill down to raw scans
- Can override low-confidence events

---

### Task 5.5: Users & Tags Management
**Steps:**
1. Create `src/pages/UsersPage.tsx`:
   - List users (internal_id, name, active tags)
   - Search by internal_id or name
2. Create `src/components/UserForm.tsx`:
   - Create new user form
   - Edit user form (toggle personal_data_enabled)
   - Delete user button
3. Create `src/pages/TagsPage.tsx`:
   - List all assigned tags
   - Show user for each tag
   - Assign tag to user (form with EPC input)
   - Deactivate tag button
   - View tag detection history
4. Create MobX stores:
   - `userStore.ts`: users array
   - `tagStore.ts`: tags array

**Definition of Done:**
- Can manage users (create/update/delete)
- Can manage tag assignments
- Personal data toggle works
- Tag history viewable

---

### Task 5.6: Integration Settings Page
**Steps:**
1. Create `src/pages/SettingsPage.tsx`:
   - Integration configuration section
   - List available integrations (Navigo3, etc.)
2. Create `src/components/IntegrationForm.tsx`:
   - Form for Navigo3 API URL, API key
   - "Test Connection" button
   - Save button
   - Show last sync time and status
3. Create MobX store:
   - `integrationStore.ts`: config state, sync status
4. Add validation:
   - URL format
   - Required fields

**Definition of Done:**
- Can configure Navigo3
- Can test connectivity
- Configuration saved to backend
- Shows sync status

---

## Phase 6: Real-Time Updates & Polish

### Task 6.1: WebSocket Server for Real-Time Updates
**Steps:**
1. Add to `src/index.ts`:
   - Create WebSocket server endpoint: `GET /api/v1/ws`
   - Require JWT authentication
   - Accept WebSocket connections from dashboard
2. Emit events from backend:
   - When lighthouse connects: `{ type: "lighthouse_connected", data: {...} }`
   - When new event processed: `{ type: "new_event", data: {...} }`
   - When integration syncs: `{ type: "integration_synced", data: {...} }`
3. Frontend WebSocket client:
   - Connect on dashboard load
   - Listen for events
   - Update MobX stores in real-time
   - Disconnect on logout

**Definition of Done:**
- WebSocket connects successfully
- Messages received and processed
- Dashboard updates in real-time
- Connection drops gracefully on logout

---

### Task 6.2: Error Handling & Validation
**Steps:**
1. Implement input validation:
   - Validate API request payloads (email format, UUID format, etc.)
   - Return 400 Bad Request with error details
2. Implement error responses:
   - 401 Unauthorized (invalid JWT)
   - 403 Forbidden (insufficient permissions)
   - 404 Not Found
   - 500 Internal Server Error
3. Add logging:
   - Log all API requests/responses
   - Log errors with stack traces
   - Log database queries (debug mode only)
4. Frontend error handling:
   - Display error messages to user
   - Retry failed requests
   - Graceful degradation if API unavailable

**Definition of Done:**
- All error cases handled
- Users see helpful messages
- No silent failures
- Logs contain debugging info

---

### Task 6.3: Database Query Optimization
**Steps:**
1. Review all queries:
   - Ensure indexes exist (see schema)
   - Use `EXPLAIN ANALYZE` to check query plans
   - Add indexes if needed
2. Implement caching where appropriate:
   - Cache lighthouse list (update on changes)
   - Cache user list (update on changes)
   - Don't cache real-time events
3. Batch operations:
   - Process multiple scans in single transaction when possible
   - Use connection pooling correctly

**Definition of Done:**
- Queries execute quickly (< 100ms for typical operations)
- No N+1 query problems
- Indexes used effectively
- No memory leaks from caching

---

### Task 6.4: Audit Logging
**Steps:**
1. Create `audit_logs` table:
   ```sql
   CREATE TABLE audit_logs (
     id BIGSERIAL PRIMARY KEY,
     user_id UUID,
     action VARCHAR(100),
     resource_type VARCHAR(100),
     resource_id UUID,
     changes JSONB,
     timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
   )
   ```
2. Log on every state change:
   - User created/updated/deleted
   - Tag assignment/deactivation
   - Integration config changed
   - Manual event override
3. Create audit log view in dashboard (admin only)

**Definition of Done:**
- All changes tracked in audit log
- Can view who did what when
- Helps with compliance/debugging

---

### Task 6.5: Documentation
**Steps:**
1. Create `README.md`:
   - Project overview
   - Architecture diagram
   - Setup instructions (PostgreSQL, Bun, env vars)
   - How to start backend and frontend
2. Create API documentation:
   - List all endpoints
   - Request/response examples
   - Authentication requirements
3. Create deployment guide:
   - Docker setup
   - Environment variables for production
   - PostgreSQL backup strategy
   - On-site installation steps
4. Create user manual (dashboard usage)

**Definition of Done:**
- New developer can set up from scratch
- API endpoints documented
- Deployment process clear
- Operators know how to use dashboard

---

## Testing & Validation

### Before Each Phase Completion:
1. Test all endpoints with curl/Postman
2. Verify database transactions complete correctly
3. Check for console errors/warnings
4. Review error handling (what happens if DB down, API fails, etc.)
5. Validate data integrity (no orphaned records, foreign keys correct)

### Performance Baselines:
- API responses < 200ms (excluding network latency)
- Dashboard loads in < 3 seconds
- WebSocket message delivery < 100ms
- Event processing < 2 seconds after raw scan

### Security Checklist:
- JWT tokens validated on every request
- Secrets never logged or exposed in errors
- SQL injection prevented (use parameterized queries)
- CSRF tokens (if needed for forms)
- Rate limiting (future: prevent brute force)

---

## Success Criteria (All Phases Complete)

- [ ] Lighthouses connect to MQTT broker and send scans
- [ ] Raw scans stored in PostgreSQL with no data loss
- [ ] Direction detection creates entry/exit events with reasonable confidence
- [ ] Users can be created with internal_id / optional personal data
- [ ] Tags assigned to users are matched with scans
- [ ] Unassigned scans tracked separately
- [ ] REST API serves all data queries
- [ ] Dashboard displays real-time lighthouse status
- [ ] Dashboard shows events timeline with filtering
- [ ] User/tag management works (CRUD)
- [ ] Integration config stored and used
- [ ] Navigo3 sync works (or can be tested)
- [ ] Authentication required for dashboard
- [ ] WebSocket pushes real-time updates
- [ ] Error handling graceful throughout
- [ ] Code documented and deployment clear
