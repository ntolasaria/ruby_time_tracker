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

ALTER TABLE projects
DROP CONSTRAINT projects_client_id_fkey;

ALTER TABLE projects
ADD FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;

ALTER TABLE tasks
DROP CONSTRAINT tasks_project_id_fkey;

ALTER TABLE tasks
ADD FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;