CREATE TABLE IF NOT EXISTS store_enrichment_cache (
  store_id INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('PLACE', 'BLOGS')),
  payload TEXT NOT NULL,
  fetched_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL,
  PRIMARY KEY (store_id, kind),
  FOREIGN KEY (store_id) REFERENCES stores(store_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_store_enrichment_cache_expiry
  ON store_enrichment_cache(expires_at);
