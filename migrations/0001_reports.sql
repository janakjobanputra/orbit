-- What Orbit's reports are stored as. Usage is only ever a count per day of identical reports, so there's no row
-- for any one person, and no ID or IP address is stored anywhere.
CREATE TABLE IF NOT EXISTS usage_daily (
  day TEXT NOT NULL,
  version TEXT NOT NULL,
  os TEXT NOT NULL,
  arch TEXT NOT NULL,
  events_view TEXT NOT NULL,
  menu_bar_style TEXT NOT NULL,
  text_size TEXT NOT NULL,
  event_density TEXT NOT NULL,
  calendars TEXT NOT NULL,
  reports INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, version, os, arch, events_view, menu_bar_style, text_size, event_density, calendars)
);

CREATE TABLE IF NOT EXISTS crashes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  day TEXT NOT NULL,
  version TEXT NOT NULL,
  build TEXT NOT NULL,
  os TEXT NOT NULL,
  arch TEXT NOT NULL,
  exception_type INTEGER,
  exception_code INTEGER,
  signal INTEGER,
  call_stack TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS crashes_by_version ON crashes (version, day);
