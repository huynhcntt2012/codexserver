-- Phase 1 baseline. Applied once by the PostgreSQL image on a fresh volume.
BEGIN;
CREATE TABLE accounts (
    id VARCHAR(36) PRIMARY KEY,
    username VARCHAR(24) UNIQUE,
    display_name VARCHAR(24) NOT NULL,
    password VARCHAR(255),
    vip_until TIMESTAMPTZ
);
CREATE TABLE inventory (
    account_id VARCHAR(36) REFERENCES accounts(id) ON DELETE CASCADE,
    item_id VARCHAR(64) NOT NULL,
    PRIMARY KEY (account_id, item_id)
);
COMMIT;
