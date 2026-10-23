CREATE TABLE epg_feeds (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    name VARCHAR(80) NOT NULL,
    url VARCHAR(2048) NOT NULL,
    interval_minutes INTEGER NOT NULL,
    enabled BOOLEAN NOT NULL,
    content TEXT,
    updated_at BIGINT NOT NULL DEFAULT 0,
    next_refresh BIGINT NOT NULL DEFAULT 0,
    last_attempt BIGINT NOT NULL DEFAULT 0,
    last_error VARCHAR(100)
);
CREATE INDEX epg_feeds_by_user ON epg_feeds(user_id);
CREATE INDEX epg_feeds_due ON epg_feeds(next_refresh);
CREATE TABLE epg_budget (id INTEGER PRIMARY KEY, version INTEGER NOT NULL);
INSERT INTO epg_budget(id,version) VALUES(1,1);
