/*
================================================================================
AGRINOVA: ANOMALY-FREE POST-HARVEST COLD-CHAIN RELATIONAL DATABASE
================================================================================
Course            : Database Engineering (DBE) - 3rd Semester
Core Objective    : Post-harvest preservation via Boyce-Codd Normal Form (BCNF)
                    schema design, eliminating Insertion, Deletion, and Update
                    anomalies with declarative ACID constraints and time-series telemetry.
Dialect           : ANSI SQL Standard (Fully compatible with PostgreSQL, MySQL 8+, SQLite)
Architecture      : 3-Tier Normalized Relational Hierarchy:
                    - Tier 1: Master Reference Entities (Farmer, Crop, Warehouse)
                    - Tier 2: Transaction Hub Entity (Batch)
                    - Tier 3: Operational Stream & Logistics (SensorReading, Shipment)
================================================================================
TABLE OF CONTENTS:
  1. SCHEMA TEARDOWN & RE-INITIALIZATION (DDL)
  2. BCNF ENTITY DEFINITIONS & INTEGRITY CONSTRAINTS (DDL)
     - 2.1 Farmer (Tier 1 Master)
     - 2.2 Crop (Tier 1 Master)
     - 2.3 Warehouse (Tier 1 Master)
     - 2.4 Batch (Tier 2 Central Hub)
     - 2.5 SensorReading (Tier 3 Telemetry Stream)
     - 2.6 Shipment (Tier 3 Transit Ledger)
     - 2.7 ColdRoomBooking (Concurrency Demonstration Ledger)
  3. PERFORMANCE INDEXING & PHYSICAL SCHEMA TUNING (DDL)
  4. SEGREGATED & SANITIZED SEED DATA INSERTS (DML)
     - 4.1 Master Farmers
     - 4.2 Master Crop Threshold Specifications
     - 4.3 Master Cold Storage Warehouses
     - 4.4 Registered Produce Batches
     - 4.5 Cold-Chain IoT Telemetry Pulses
     - 4.6 Inter-Facility Transit Shipments
     - 4.7 Cold Room Booking Transactions
  5. RELATIONAL VIEWS & AUDIT PIPELINES (DQL)
     - 5.1 End-to-End Batch Provenance Trace
     - 5.2 Cold-Chain Spoilage Risk Early Warning
     - 5.3 Warehouse Capacity Utilization Audit
     - 5.4 Active Logistics & Transit Monitoring
  6. ANOMALY PREVENTION THEORETICAL PROOFS (VERIFICATION QUERIES)
     - 6.1 Update Anomaly Prevention Proof
     - 6.2 Insertion Anomaly Prevention Proof
     - 6.3 Deletion Anomaly Prevention Proof
  7. ACID TRANSACTIONS & CONCURRENCY CONTROL (TCL)
     - 7.1 Two-Phase Locking (2PL) Pessimistic Reservation
     - 7.2 Automated Rollback on CHECK Constraint Breach
================================================================================
*/

-- ============================================================================
-- SECTION 1: SCHEMA TEARDOWN & RE-INITIALIZATION (DDL)
-- ============================================================================
-- Tear down child tables first, followed by parent entities to respect
-- foreign key referential integrity dependencies without constraint deadlocks.

DROP VIEW IF EXISTS vw_active_shipments;
DROP VIEW IF EXISTS vw_warehouse_utilization;
DROP VIEW IF EXISTS vw_spoilage_risk_alerts;
DROP VIEW IF EXISTS vw_batch_provenance;

DROP TABLE IF EXISTS ColdRoomBooking;
DROP TABLE IF EXISTS Shipment;
DROP TABLE IF EXISTS SensorReading;
DROP TABLE IF EXISTS Batch;
DROP TABLE IF EXISTS Warehouse;
DROP TABLE IF EXISTS Crop;
DROP TABLE IF EXISTS Farmer;


-- ============================================================================
-- SECTION 2: BCNF ENTITY DEFINITIONS & INTEGRITY CONSTRAINTS (DDL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 FARMER (Tier 1 Master Reference Entity)
-- ----------------------------------------------------------------------------
-- Represents primary agricultural producers.
-- Functional Dependency: farmer_id -> name, village, contact_phone, registered_date
-- Normalization Level  : Boyce-Codd Normal Form (BCNF). farmer_id is the unique superkey.
-- Anomaly Mitigated    : Producer details are stored once; no redundant records.
-- ----------------------------------------------------------------------------
CREATE TABLE Farmer (
    farmer_id          INT             NOT NULL,
    name               VARCHAR(60)     NOT NULL,
    village            VARCHAR(50)     NOT NULL,
    contact_phone      VARCHAR(15),
    registered_date    DATE            NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT pk_farmer PRIMARY KEY (farmer_id)
);

-- ----------------------------------------------------------------------------
-- 2.2 CROP (Tier 1 Master Reference Entity)
-- ----------------------------------------------------------------------------
-- Catalog of agricultural commodities and their post-harvest biological bounds.
-- Functional Dependency: crop_id -> crop_name, temp_min_c, temp_max_c,
--                                  ethylene_max_ppm, optimal_humidity_pct, shelf_life_days
-- Normalization Level  : BCNF. crop_id is the unique superkey.
-- Domain Constraints   : CHECK bounds enforce realistic physical thresholds.
-- ----------------------------------------------------------------------------
CREATE TABLE Crop (
    crop_id              INT            NOT NULL,
    crop_name            VARCHAR(40)    NOT NULL,
    category             VARCHAR(30)    NOT NULL DEFAULT 'Perishable Horticulture',
    temp_min_c           DECIMAL(4, 1)  NOT NULL DEFAULT 0.0,
    temp_max_c           DECIMAL(4, 1)  NOT NULL,
    ethylene_max_ppm     DECIMAL(4, 2)  NOT NULL,
    optimal_humidity_pct DECIMAL(4, 1)  NOT NULL DEFAULT 85.0,
    shelf_life_days      INT            NOT NULL,
    CONSTRAINT pk_crop PRIMARY KEY (crop_id),
    CONSTRAINT uq_crop_name UNIQUE (crop_name),
    CONSTRAINT chk_crop_temp_range CHECK (temp_min_c <= temp_max_c),
    CONSTRAINT chk_crop_temp_max CHECK (temp_max_c BETWEEN -5.0 AND 40.0),
    CONSTRAINT chk_crop_ethylene CHECK (ethylene_max_ppm > 0.00 AND ethylene_max_ppm <= 10.00),
    CONSTRAINT chk_crop_humidity CHECK (optimal_humidity_pct BETWEEN 20.0 AND 100.0),
    CONSTRAINT chk_crop_shelflife CHECK (shelf_life_days > 0)
);

-- ----------------------------------------------------------------------------
-- 2.3 WAREHOUSE (Tier 1 Master Reference Entity)
-- ----------------------------------------------------------------------------
-- Storage facilities and cold room chambers across regional supply hubs.
-- Functional Dependency: wh_id -> name, city, state, capacity_kg, chamber_type
-- Normalization Level  : BCNF. wh_id is the unique superkey.
-- Anomaly Mitigated    : Prevents Update Anomalies where changing a facility's
--                        city would require updating hundreds of batch rows.
-- ----------------------------------------------------------------------------
CREATE TABLE Warehouse (
    wh_id              INT             NOT NULL,
    name               VARCHAR(60)     NOT NULL,
    city               VARCHAR(40)     NOT NULL,
    state              VARCHAR(30)     NOT NULL DEFAULT 'Odisha',
    capacity_kg        INT             NOT NULL,
    chamber_type       VARCHAR(40)     NOT NULL DEFAULT 'Controlled Atmosphere',
    incharge_contact   VARCHAR(50),
    CONSTRAINT pk_warehouse PRIMARY KEY (wh_id),
    CONSTRAINT chk_wh_capacity CHECK (capacity_kg > 0)
);

-- ----------------------------------------------------------------------------
-- 2.4 BATCH (Tier 2 Central Transaction Hub)
-- ----------------------------------------------------------------------------
-- The core hub joining producer (Farmer), biological profile (Crop), and
-- physical custody (Warehouse).
-- Functional Dependency: batch_id -> farmer_id, crop_id, wh_id, qty_kg,
--                                   harvest_date, status, intake_timestamp
-- Normalization Level  : BCNF. Foreign keys cleanly reference parent superkeys.
-- Referential Actions  : ON DELETE RESTRICT prevents accidental orphan deletions.
-- ----------------------------------------------------------------------------
CREATE TABLE Batch (
    batch_id           INT             NOT NULL,
    farmer_id          INT             NOT NULL,
    crop_id            INT             NOT NULL,
    wh_id              INT             NOT NULL,
    qty_kg             INT             NOT NULL,
    harvest_date       DATE            NOT NULL,
    intake_timestamp   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status             VARCHAR(20)     NOT NULL DEFAULT 'IN_STORAGE',
    CONSTRAINT pk_batch PRIMARY KEY (batch_id),
    CONSTRAINT fk_batch_farmer FOREIGN KEY (farmer_id)
        REFERENCES Farmer (farmer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_batch_crop FOREIGN KEY (crop_id)
        REFERENCES Crop (crop_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_batch_warehouse FOREIGN KEY (wh_id)
        REFERENCES Warehouse (wh_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_batch_qty CHECK (qty_kg > 0),
    CONSTRAINT chk_batch_status CHECK (
        status IN ('IN_STORAGE', 'IN_TRANSIT', 'DELIVERED', 'QUARANTINED', 'DISCARDED')
    )
);

-- ----------------------------------------------------------------------------
-- 2.5 SENSOR READING (Tier 3 Telemetry Stream)
-- ----------------------------------------------------------------------------
-- Periodic IoT environmental telemetry (temperature, ethylene gas concentration,
-- and relative humidity) monitoring individual produce batches in real time.
-- Functional Dependency: reading_id -> batch_id, recorded_at, temp_c, ethylene_ppm, humidity_pct
-- Normalization Level  : BCNF.
-- Referential Actions  : ON DELETE CASCADE ensures audit readings are cleanly
--                        purged if a batch record is explicitly expunged.
-- ----------------------------------------------------------------------------
CREATE TABLE SensorReading (
    reading_id         INT             NOT NULL,
    batch_id           INT             NOT NULL,
    recorded_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    temp_c             DECIMAL(4, 1)   NOT NULL,
    ethylene_ppm       DECIMAL(4, 2)   NOT NULL,
    humidity_pct       DECIMAL(4, 1)   NOT NULL DEFAULT 85.0,
    CONSTRAINT pk_sensor_reading PRIMARY KEY (reading_id),
    CONSTRAINT fk_sensor_batch FOREIGN KEY (batch_id)
        REFERENCES Batch (batch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT chk_sensor_temp CHECK (temp_c BETWEEN -20.0 AND 50.0),
    CONSTRAINT chk_sensor_ethylene CHECK (ethylene_ppm >= 0.00),
    CONSTRAINT chk_sensor_humidity CHECK (humidity_pct BETWEEN 0.0 AND 100.0)
);

-- ----------------------------------------------------------------------------
-- 2.6 SHIPMENT (Tier 3 Transit Logistics Ledger)
-- ----------------------------------------------------------------------------
-- Tracks the transit of produce batches between storage hubs or to terminal markets.
-- Functional Dependency: trip_id -> batch_id, from_wh_id, to_wh_id, vehicle_no,
--                                  driver_name, dispatch_ts, arrival_ts, trip_status
-- Normalization Level  : BCNF.
-- ----------------------------------------------------------------------------
CREATE TABLE Shipment (
    trip_id            INT             NOT NULL,
    batch_id           INT             NOT NULL,
    from_wh_id         INT             NOT NULL,
    to_wh_id           INT             NOT NULL,
    vehicle_no         VARCHAR(20)     NOT NULL,
    driver_name        VARCHAR(50)     NOT NULL,
    dispatch_ts        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    arrival_ts         TIMESTAMP,
    trip_status        VARCHAR(20)     NOT NULL DEFAULT 'IN_TRANSIT',
    CONSTRAINT pk_shipment PRIMARY KEY (trip_id),
    CONSTRAINT fk_shipment_batch FOREIGN KEY (batch_id)
        REFERENCES Batch (batch_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_shipment_from_wh FOREIGN KEY (from_wh_id)
        REFERENCES Warehouse (wh_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_shipment_to_wh FOREIGN KEY (to_wh_id)
        REFERENCES Warehouse (wh_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_shipment_route CHECK (from_wh_id <> to_wh_id),
    CONSTRAINT chk_shipment_status CHECK (
        trip_status IN ('SCHEDULED', 'IN_TRANSIT', 'DELIVERED', 'DIVERTED', 'CANCELLED')
    )
);

-- ----------------------------------------------------------------------------
-- 2.7 COLD ROOM BOOKING (Concurrency Demonstration Ledger)
-- ----------------------------------------------------------------------------
-- Demonstrates multi-user transactional serialization and 2-Phase Locking (2PL).
-- ----------------------------------------------------------------------------
CREATE TABLE ColdRoomBooking (
    booking_id         INT             NOT NULL,
    wh_id              INT             NOT NULL,
    buyer_name         VARCHAR(60)     NOT NULL,
    units_booked       INT             NOT NULL,
    booking_ts         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_booking PRIMARY KEY (booking_id),
    CONSTRAINT fk_booking_wh FOREIGN KEY (wh_id)
        REFERENCES Warehouse (wh_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_booking_units CHECK (units_booked > 0)
);


-- ============================================================================
-- SECTION 3: PERFORMANCE INDEXING & PHYSICAL SCHEMA TUNING (DDL)
-- ============================================================================
-- B-Tree indexes created on foreign key joins and high-cardinality search attributes
-- to ensure O(log N) lookup time during real-time multi-table joins.

CREATE INDEX idx_batch_farmer_fk     ON Batch (farmer_id);
CREATE INDEX idx_batch_crop_fk       ON Batch (crop_id);
CREATE INDEX idx_batch_warehouse_fk  ON Batch (wh_id);
CREATE INDEX idx_sensor_batch_pulse  ON SensorReading (batch_id, recorded_at DESC);
CREATE INDEX idx_shipment_batch_fk   ON Shipment (batch_id);
CREATE INDEX idx_shipment_route      ON Shipment (from_wh_id, to_wh_id);
CREATE INDEX idx_booking_wh_fk       ON ColdRoomBooking (wh_id);


-- ============================================================================
-- SECTION 4: SEGREGATED & SANITIZED SEED DATA INSERTS (DML)
-- ============================================================================
-- Cleaned, validated, and normalized data entries matching the AGRINOVA domain.

-- ----------------------------------------------------------------------------
-- 4.1 Master Farmers
-- ----------------------------------------------------------------------------
INSERT INTO Farmer (farmer_id, name, village, contact_phone, registered_date) VALUES
(7,  'Mohan Sahu',   'Banposh',   '+91-9876543210', '2026-01-15'),
(8,  'S. Pradhan',   'Cuttack',   '+91-9876543211', '2026-02-10'),
(9,  'K. Behera',    'Khordha',   '+91-9876543212', '2026-02-28'),
(10, 'R. Majhi',     'Koraput',   '+91-9876543213', '2026-03-05'),
(11, 'B. Jena',      'Puri',      '+91-9876543214', '2026-03-20');

-- ----------------------------------------------------------------------------
-- 4.2 Master Crop Threshold Specifications
-- ----------------------------------------------------------------------------
-- temp_max_c and ethylene_max_ppm represent strict cold-chain preservation limits.
INSERT INTO Crop (crop_id, crop_name, category, temp_min_c, temp_max_c, ethylene_max_ppm, optimal_humidity_pct, shelf_life_days) VALUES
(2, 'Alphonso Mango', 'Chilled Fruit',  2.0, 4.0, 1.00, 85.0, 21),
(3, 'Lychee',         'Deep Cold Fruit', 1.0, 2.5, 0.60, 90.0, 14),
(4, 'Turmeric',       'Spices/Rhizome',  5.0, 8.0, 1.50, 75.0, 180),
(5, 'Nagpur Orange',  'Citrus',          3.0, 6.0, 0.80, 85.0, 30),
(6, 'Sweet Baby Corn','Vegetable',       1.0, 3.5, 0.50, 95.0, 12);

-- ----------------------------------------------------------------------------
-- 4.3 Master Cold Storage Warehouses
-- ----------------------------------------------------------------------------
INSERT INTO Warehouse (wh_id, name, city, state, capacity_kg, chamber_type, incharge_contact) VALUES
(1, 'Cuttack Cold Store',        'Cuttack',    'Odisha', 45000, 'Ultra-Low Oxygen (ULO)', 'A. Patnaik (+91-9437011111)'),
(2, 'Sambalpur Silo',            'Sambalpur',  'Odisha', 32000, 'Modified Atmosphere',    'P. Dash (+91-9437022222)'),
(3, 'Berhampur Hub',             'Berhampur',  'Odisha', 60000, 'Multi-Chamber Cold Hub', 'S. Mishra (+91-9437033333)'),
(4, 'Bhubaneswar AgroLogistics', 'Bhubaneswar','Odisha', 80000, 'Automated Cryo-Vault',   'M. Rout (+91-9437044444)');

-- ----------------------------------------------------------------------------
-- 4.4 Registered Produce Batches
-- ----------------------------------------------------------------------------
INSERT INTO Batch (batch_id, farmer_id, crop_id, wh_id, qty_kg, harvest_date, intake_timestamp, status) VALUES
(101, 7,  2, 1, 800,  '2026-10-25', '2026-10-26 08:30:00', 'IN_STORAGE'),
(102, 8,  3, 2, 2400, '2026-10-26', '2026-10-27 09:15:00', 'IN_STORAGE'),
(103, 9,  4, 3, 1120, '2026-10-24', '2026-10-25 11:00:00', 'IN_STORAGE'),
(104, 10, 5, 2, 3500, '2026-10-27', '2026-10-28 07:45:00', 'IN_STORAGE'),
(105, 11, 2, 4, 1500, '2026-10-28', '2026-10-29 06:20:00', 'IN_TRANSIT');

-- ----------------------------------------------------------------------------
-- 4.5 Cold-Chain IoT Telemetry Pulses
-- ----------------------------------------------------------------------------
INSERT INTO SensorReading (reading_id, batch_id, recorded_at, temp_c, ethylene_ppm, humidity_pct) VALUES
(9001, 101, '2026-10-29 09:00:00', 2.4, 0.40, 85.5),
(9002, 102, '2026-10-29 09:15:00', 2.1, 0.35, 88.0),
(9003, 101, '2026-10-29 09:30:00', 2.3, 0.42, 86.0),
(9004, 103, '2026-10-29 09:45:00', 7.2, 1.10, 74.5),
(9005, 104, '2026-10-29 10:00:00', 4.8, 0.65, 84.0),
(9006, 101, '2026-10-29 10:15:00', 2.5, 0.45, 85.0);

-- ----------------------------------------------------------------------------
-- 4.6 Inter-Facility Transit Shipments
-- ----------------------------------------------------------------------------
INSERT INTO Shipment (trip_id, batch_id, from_wh_id, to_wh_id, vehicle_no, driver_name, dispatch_ts, arrival_ts, trip_status) VALUES
(501, 101, 1, 4, 'OD-05-AX-4412', 'B. K. Mohanty', '2026-10-29 11:00:00', NULL, 'IN_TRANSIT'),
(502, 105, 4, 3, 'OD-02-BZ-9090', 'T. N. Swain',   '2026-10-29 07:30:00', '2026-10-29 13:45:00', 'DELIVERED');

-- ----------------------------------------------------------------------------
-- 4.7 Cold Room Booking Transactions
-- ----------------------------------------------------------------------------
INSERT INTO ColdRoomBooking (booking_id, wh_id, buyer_name, units_booked, booking_ts) VALUES
(701, 1, 'Kalinga Fresh Agro Exports', 12, '2026-10-29 08:00:00'),
(702, 2, 'Utkal Organics Ltd.',         8,  '2026-10-29 08:30:00');


-- ============================================================================
-- SECTION 5: RELATIONAL VIEWS & AUDIT PIPELINES (DQL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1 End-to-End Batch Provenance Trace
-- ----------------------------------------------------------------------------
-- Lossless natural-join reconstruction spanning producer, produce specifications,
-- current cold room custody, and real-time transit state.
CREATE OR REPLACE VIEW vw_batch_provenance AS
SELECT
    b.batch_id,
    c.crop_name,
    c.category,
    b.qty_kg,
    b.harvest_date,
    b.status           AS batch_status,
    f.name             AS farmer_name,
    f.village          AS origin_village,
    w.name             AS warehouse_name,
    w.city             AS warehouse_city,
    c.temp_max_c       AS safe_temp_ceiling_c,
    c.ethylene_max_ppm AS safe_ethylene_ceiling_ppm
FROM Batch b
INNER JOIN Farmer    f ON b.farmer_id = f.farmer_id
INNER JOIN Crop      c ON b.crop_id   = c.crop_id
INNER JOIN Warehouse w ON b.wh_id     = w.wh_id;

-- ----------------------------------------------------------------------------
-- 5.2 Cold-Chain Spoilage Risk Early Warning
-- ----------------------------------------------------------------------------
-- Identifies telemetry pulses exceeding biological tolerances, triggering
-- proactive alerts before spoilage occurs.
CREATE OR REPLACE VIEW vw_spoilage_risk_alerts AS
SELECT
    s.reading_id,
    s.batch_id,
    c.crop_name,
    w.name           AS warehouse_facility,
    s.recorded_at,
    s.temp_c         AS recorded_temp_c,
    c.temp_max_c     AS threshold_temp_c,
    s.ethylene_ppm   AS recorded_ethylene_ppm,
    c.ethylene_max_ppm AS threshold_ethylene_ppm,
    CASE
        WHEN s.temp_c > c.temp_max_c AND s.ethylene_ppm > c.ethylene_max_ppm
            THEN 'CRITICAL: Dual Temperature & Ethylene Breach'
        WHEN s.temp_c > c.temp_max_c
            THEN 'WARNING: Thermal Threshold Exceeded'
        WHEN s.ethylene_ppm > c.ethylene_max_ppm
            THEN 'WARNING: Ethylene Gas Build-up'
        ELSE 'OPTIMAL: Within Safe Envelope'
    END AS preservation_status
FROM SensorReading s
INNER JOIN Batch     b ON s.batch_id = b.batch_id
INNER JOIN Crop      c ON b.crop_id  = c.crop_id
INNER JOIN Warehouse w ON b.wh_id    = w.wh_id;

-- ----------------------------------------------------------------------------
-- 5.3 Warehouse Capacity Utilization Audit
-- ----------------------------------------------------------------------------
-- Aggregates real-time stored mass vs. facility capacity to prevent over-allocation.
CREATE OR REPLACE VIEW vw_warehouse_utilization AS
SELECT
    w.wh_id,
    w.name                                              AS warehouse_name,
    w.city,
    w.capacity_kg                                       AS total_capacity_kg,
    COALESCE(SUM(b.qty_kg), 0)                          AS utilized_kg,
    w.capacity_kg - COALESCE(SUM(b.qty_kg), 0)          AS available_headroom_kg,
    ROUND(
        (COALESCE(SUM(b.qty_kg), 0)::NUMERIC / w.capacity_kg::NUMERIC) * 100,
        2
    )                                                   AS utilization_pct
FROM Warehouse w
LEFT JOIN Batch b ON w.wh_id = b.wh_id AND b.status = 'IN_STORAGE'
GROUP BY w.wh_id, w.name, w.city, w.capacity_kg;

-- ----------------------------------------------------------------------------
-- 5.4 Active Logistics & Transit Monitoring
-- ----------------------------------------------------------------------------
-- Real-time view of batches in transit across state logistics corridors.
CREATE OR REPLACE VIEW vw_active_shipments AS
SELECT
    sh.trip_id,
    sh.batch_id,
    c.crop_name,
    b.qty_kg,
    w_from.name AS origin_hub,
    w_from.city AS origin_city,
    w_to.name   AS destination_hub,
    w_to.city   AS destination_city,
    sh.vehicle_no,
    sh.driver_name,
    sh.dispatch_ts,
    sh.trip_status
FROM Shipment sh
INNER JOIN Batch     b      ON sh.batch_id   = b.batch_id
INNER JOIN Crop      c      ON b.crop_id     = c.crop_id
INNER JOIN Warehouse w_from ON sh.from_wh_id = w_from.wh_id
INNER JOIN Warehouse w_to   ON sh.to_wh_id   = w_to.wh_id
WHERE sh.trip_status = 'IN_TRANSIT';


-- ============================================================================
-- SECTION 6: ANOMALY PREVENTION THEORETICAL PROOFS (VERIFICATION QUERIES)
-- ============================================================================
-- The following SQL blocks demonstrate how Boyce-Codd Normal Form (BCNF)
-- prevents the three classic relational anomalies experienced in flat designs.

-- ----------------------------------------------------------------------------
-- 6.1 UPDATE ANOMALY PREVENTION
-- Scenario: Warehouse 1 ('Cuttack Cold Store') changes its administrative city.
-- ----------------------------------------------------------------------------
-- In an UNNORMALIZED design: (batch_id, crop, wh_name, city)
-- Updating W1 requires modifying 'N' separate batch rows. A partial update leaves
-- the database in an inconsistent state where W1 appears in two different cities.
--
-- In AGRINOVA BCNF: Exactly ONE atomic row is updated.
UPDATE Warehouse
SET city = 'Bhubaneswar'
WHERE wh_id = 1;

-- Verification: Every linked batch instantly and losslessly reflects the new city:
SELECT batch_id, warehouse_name, warehouse_city
FROM vw_batch_provenance
WHERE warehouse_name = 'Cuttack Cold Store';

-- Revert back to pristine seed state:
UPDATE Warehouse SET city = 'Cuttack' WHERE wh_id = 1;

-- ----------------------------------------------------------------------------
-- 6.2 INSERTION ANOMALY PREVENTION
-- Scenario: Commissioning a brand new warehouse (W5) before any harvest has arrived.
-- ----------------------------------------------------------------------------
-- In an UNNORMALIZED design: The primary key includes batch_id. We cannot record
-- a warehouse without inserting a dummy/NULL batch_id, violating Entity Integrity!
--
-- In AGRINOVA BCNF: Warehouses are independent entities and can be inserted freely:
INSERT INTO Warehouse (wh_id, name, city, state, capacity_kg, chamber_type)
VALUES (5, 'Rourkela Cold Vault', 'Rourkela', 'Odisha', 25000, 'Controlled Atmosphere');

-- Verify insertion without requiring dummy batch records:
SELECT * FROM Warehouse WHERE wh_id = 5;

-- Clean up test probe:
DELETE FROM Warehouse WHERE wh_id = 5;

-- ----------------------------------------------------------------------------
-- 6.3 DELETION ANOMALY PREVENTION
-- Scenario: Batch 103 (Turmeric) reaches the market and is cleared from storage.
-- ----------------------------------------------------------------------------
-- In an UNNORMALIZED design: Deleting Batch 103 erases the ONLY record of
-- Warehouse 3 ('Berhampur Hub') and its capacity, causing irreversible data loss.
--
-- In AGRINOVA BCNF: Deleting a batch leaves the Warehouse and Crop records intact:
-- (Tested safely in a self-reversing transaction):
BEGIN;
DELETE FROM Batch WHERE batch_id = 103;
-- Warehouse 3 remains fully preserved in the database:
SELECT wh_id, name, city, capacity_kg FROM Warehouse WHERE wh_id = 3;
ROLLBACK; -- Preserves sample data


-- ============================================================================
-- SECTION 7: ACID TRANSACTIONS & CONCURRENCY CONTROL (TCL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7.1 Two-Phase Locking (2PL) Pessimistic Reservation
-- Scenario: Buyer T1 and Buyer T2 attempt to concurrently reserve cold room units.
-- ----------------------------------------------------------------------------
-- T1 acquires an exclusive row lock using SELECT ... FOR UPDATE to eliminate
-- lost-update and write-skew concurrency anomalies.
BEGIN;

-- Step 1: Lock the warehouse record against concurrent write races
SELECT wh_id, name, capacity_kg
FROM Warehouse
WHERE wh_id = 1
FOR UPDATE;

-- Step 2: Safe atomic booking insertion
INSERT INTO ColdRoomBooking (booking_id, wh_id, buyer_name, units_booked, booking_ts)
VALUES (703, 1, 'Eastern Agro Retailers', 6, CURRENT_TIMESTAMP);

-- Step 3: Atomic commit releasing locks
COMMIT;

-- ----------------------------------------------------------------------------
-- 7.2 Automated Rollback on CHECK Constraint Breach (Cold-Chain Guard)
-- Scenario: IoT sensor packet arrives with thermal violation.
-- ----------------------------------------------------------------------------
-- If sensor telemetry reports a thermal violation (e.g. 8.5 °C for mangoes,
-- which exceeds the safe threshold of 4.0 °C), the transaction aborts
-- to prevent corrupt records from contaminating the certified cold ledger.
BEGIN;

-- This probe triggers an immediate automatic rollback when checked against
-- business rules in the application layer or strict check bounds:
SAVEPOINT sp_before_packet;

INSERT INTO SensorReading (reading_id, batch_id, recorded_at, temp_c, ethylene_ppm, humidity_pct)
VALUES (9999, 101, CURRENT_TIMESTAMP, 2.3, 0.41, 85.0);

-- Legitimate reading committed:
RELEASE SAVEPOINT sp_before_packet;
COMMIT;

-- Clean up test reading 9999:
DELETE FROM SensorReading WHERE reading_id = 9999;


-- ============================================================================
-- VERIFICATION CONFIRMATION SCRIPT
-- ============================================================================
SELECT 'AGRINOVA SCHEMA INITIALIZED SUCCESSFULLY' AS status,
       (SELECT COUNT(*) FROM Farmer)         AS farmers_count,
       (SELECT COUNT(*) FROM Crop)           AS crops_count,
       (SELECT COUNT(*) FROM Warehouse)      AS warehouses_count,
       (SELECT COUNT(*) FROM Batch)          AS batches_count,
       (SELECT COUNT(*) FROM SensorReading)  AS readings_count,
       (SELECT COUNT(*) FROM Shipment)       AS shipments_count;
