# AGRINOVA: Anomaly-Free Post-Harvest Cold-Chain Management Database System

**Course:** Database Engineering (DBE) – Semester 3  
**Domain:** Agricultural Supply Chain & Cold-Chain Post-Harvest Preservation  
**Primary Paradigm:** Relational Database Management Systems (RDBMS) & Boyce-Codd Normal Form (BCNF)  
**Live Local Web App:** [http://localhost:8000/AGRINOVA.html](http://localhost:8000/AGRINOVA.html) (or [http://localhost:8000/](http://localhost:8000/))

---

## 1. Project Overview

In agricultural logistics, lack of proper database normalization causes severe **Insertion, Deletion, and Update anomalies**, leading to contradictory temperature records, duplicate warehouse entries, and unseen crop spoilage.

**AGRINOVA** demonstrates a robust database engineering solution where:
- Every agricultural producer, commodity threshold, and warehouse facility is stored exactly once in **Boyce-Codd Normal Form (BCNF)**.
- Real-time IoT cold-chain pulses (Temperature, Ethylene gas in ppm, Relative Humidity) are captured in segregated time-series tables with declarative **CHECK constraints**.
- ACID transactions with **Two-Phase Locking (2PL)** prevent lost updates and overbooking during concurrent cold storage reservations.

---

## 2. Project File Structure & Segregation

The project has been cleanly segregated into dedicated layers:

```
AGRINOVA/
│
├── agrinova.sql          # ★ MASTER SQL FILE: DDL, Constraints, Clean DML, Views, Anomaly Proofs, ACID TCL
├── agrinova_schema.sql   # Standalone schema and DDL mirror
├── AGRINOVA.html         # Interactive web dashboard, live anomaly lab, and data studio
├── index.html            # Default web server entry point (mirrors AGRINOVA.html)
└── README.md             # Project documentation and evaluation guide
```

---

## 3. Relational Schema Architecture (BCNF)

The database schema is organized into three segregated tiers:

### Tier 1: Master Reference Entities (Independent Catalogs)
- **`Farmer`** (`farmer_id` PK): Primary agricultural producers.
  - Functional Dependency: $\text{farmer\_id} \to \text{name}, \text{village}, \text{contact\_phone}, \text{registered\_date}$
- **`Crop`** (`crop_id` PK): Commodity specifications with strict biological thresholds.
  - Functional Dependency: $\text{crop\_id} \to \text{crop\_name}, \text{temp\_min\_c}, \text{temp\_max\_c}, \text{ethylene\_max\_ppm}, \text{shelf\_life\_days}$
  - Domain Constraints: `temp_min_c <= temp_max_c`, `ethylene_max_ppm > 0`
- **`Warehouse`** (`wh_id` PK): Cold storage facilities and controlled atmosphere hubs.
  - Functional Dependency: $\text{wh\_id} \to \text{name}, \text{city}, \text{state}, \text{capacity\_kg}, \text{chamber\_type}$
  - Constraint: `capacity_kg > 0`

### Tier 2: Transaction Hub Entity
- **`Batch`** (`batch_id` PK): Central hub connecting Farmer, Crop, and Warehouse.
  - Foreign Keys: `farmer_id` $\to$ `Farmer`, `crop_id` $\to$ `Crop`, `wh_id` $\to$ `Warehouse`
  - Referential Action: `ON DELETE RESTRICT` (prevents deleting active master entities)
  - Constraint: `qty_kg > 0`, `status IN ('IN_STORAGE', 'IN_TRANSIT', 'DELIVERED', 'QUARANTINED', 'DISCARDED')`

### Tier 3: Operational Stream & Logistics
- **`SensorReading`** (`reading_id` PK): High-frequency IoT telemetry monitoring cold-chain pulses.
  - Foreign Key: `batch_id` $\to$ `Batch` (`ON DELETE CASCADE`)
  - Check Constraints: `temp_c BETWEEN -20.0 AND 50.0`, `ethylene_ppm >= 0.00`
- **`Shipment`** (`trip_id` PK): Transit ledger between storage hubs and terminal markets.
  - Foreign Keys: `from_wh_id` $\to$ `Warehouse`, `to_wh_id` $\to$ `Warehouse` (`from_wh_id <> to_wh_id`)
- **`ColdRoomBooking`** (`booking_id` PK): Concurrency control ledger demonstrating 2PL row-level locking.

---

## 4. Anomaly Prevention Proofs

| Anomaly Type | Unnormalized Flat Table Behavior | AGRINOVA BCNF Solution |
| :--- | :--- | :--- |
| **Update Anomaly** | Changing a warehouse city requires updating hundreds of batch rows. A partial update leaves the database in a contradictory state. | City is stored exclusively in `Warehouse`. Updating 1 record propagates losslessly to all batches via foreign key joins. |
| **Insertion Anomaly** | Cannot record a newly commissioned warehouse without dummy/NULL batch information, violating Entity Integrity. | `Warehouse` is an independent entity. Storage hubs can be registered immediately with 0 batches. |
| **Deletion Anomaly** | Deleting a depleted batch erases the only record of the warehouse and its capacity, causing irreversible data loss. | Deleting a `Batch` preserves the `Warehouse` and `Crop` records completely. |

---

## 5. SQL Verification & Execution

The SQL script `agrinova.sql` is written in standard ANSI SQL and is directly executable on **PostgreSQL**, **MySQL 8.0+**, or **SQLite**.

### Running in PostgreSQL (`psql`):
```bash
psql -U postgres -d agrinova_db -f agrinova.sql
```

### Running in MySQL:
```bash
mysql -u root -p agrinova_db < agrinova.sql
```

---

## 6. How to Run the Web Application Locally

The project is currently served on your local machine using an active HTTP server:

- **Local Link:** **[http://localhost:8000/AGRINOVA.html](http://localhost:8000/AGRINOVA.html)**
- **Alternative Root Link:** **[http://localhost:8000/](http://localhost:8000/)**

To run or restart the web server at any time:
```powershell
python -m http.server 8000
```
Open your browser and navigate to `http://localhost:8000/AGRINOVA.html`.
