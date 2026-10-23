CREATE TABLE app_users (
    id VARCHAR(36) PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    password_salt VARCHAR(64) NOT NULL,
    password_hash VARCHAR(64) NOT NULL,
    password_iterations INTEGER NOT NULL DEFAULT 600000,
    created_at BIGINT NOT NULL
);
CREATE TABLE devices (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    name VARCHAR(80) NOT NULL,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX devices_by_user ON devices(user_id);
CREATE TABLE user_library (
    user_id VARCHAR(36) PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
    revision BIGINT NOT NULL,
    content TEXT NOT NULL,
    updated_at BIGINT NOT NULL
);
CREATE TABLE device_pairings (
    code_hash VARCHAR(64) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    creator_device VARCHAR(36) NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    expires_at BIGINT NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX pairings_by_expiry ON device_pairings(expires_at);
