-- Example schema file
-- This will be applied after database creation

-- Create a sample table
CREATE TABLE IF NOT EXISTS app_config (
    id SERIAL PRIMARY KEY,
    key VARCHAR(255) NOT NULL UNIQUE,
    value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create an index
CREATE INDEX IF NOT EXISTS idx_app_config_key ON app_config(key);

-- Create a function for updating timestamps
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create a trigger
DROP TRIGGER IF EXISTS set_timestamp ON app_config;
CREATE TRIGGER set_timestamp
    BEFORE UPDATE ON app_config
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Insert sample data
INSERT INTO app_config (key, value) VALUES ('version', '1.0.0') ON CONFLICT (key) DO NOTHING;