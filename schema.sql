CREATE TABLE clients (
  id serial PRIMARY KEY,
  name text NOT NULL
);

CREATE TABLE projects (
  id serial PRIMARY KEY,
  name text NOT NULL,
  color_tag text DEFAULT 'blue',
  client_id integer REFERENCES clients(id)
);

CREATE TABLE tasks (
  id serial PRIMARY KEY,
  name text NOT NULL,
  start_time timestamp DEFAULT NOW(),
  stop_time timestamp,
  project_id integer REFERENCES projects (id)
);

ALTER TABLE clients
ADD UNIQUE (name);

ALTER TABLE projects
ADD UNIQUE (name, client_id)