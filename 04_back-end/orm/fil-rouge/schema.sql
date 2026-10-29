-- Fil rouge du chapitre ORM : « l'Atelier »
-- Des membres portent des projets, y contribuent avec un rôle, et les étiquettent.
--
-- Couvre volontairement les cas de modélisation classiques :
--   members 1 ── n projects        (association 1-n : clé étrangère)
--   members n ── n projects        (association n-n porteuse d'attributs : contributions)
--   projects n ── n tags           (association n-n pure : project_tags)
--
-- SGBD cible : SQLite (node:sqlite). Les différences avec PostgreSQL sont signalées en commentaire.

CREATE TABLE members (
  id         INTEGER PRIMARY KEY,                       -- PG : integer GENERATED ALWAYS AS IDENTITY
  handle     TEXT    NOT NULL UNIQUE,
  email      TEXT    NOT NULL UNIQUE,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))  -- PG : timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE projects (
  id         INTEGER PRIMARY KEY,
  owner_id   INTEGER NOT NULL REFERENCES members (id) ON DELETE RESTRICT,
  title      TEXT    NOT NULL,
  status     TEXT    NOT NULL DEFAULT 'draft'
             CHECK (status IN ('draft', 'active', 'archived')),
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);
-- Ni SQLite ni PostgreSQL n'indexent automatiquement une clé étrangère (MySQL/InnoDB, si).
CREATE INDEX projects_owner_id_idx ON projects (owner_id);

-- Association n-n porteuse : le rôle et la date appartiennent au couple (membre, projet),
-- ni au membre seul, ni au projet seul.
CREATE TABLE contributions (
  member_id  INTEGER NOT NULL REFERENCES members (id)  ON DELETE CASCADE,
  project_id INTEGER NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  role       TEXT    NOT NULL,
  since      TEXT    NOT NULL DEFAULT (date('now')),
  PRIMARY KEY (member_id, project_id)
);
CREATE INDEX contributions_project_id_idx ON contributions (project_id);

CREATE TABLE tags (
  id    INTEGER PRIMARY KEY,
  label TEXT    NOT NULL UNIQUE
);

-- Association n-n pure : la table de jointure ne porte que les deux clés.
CREATE TABLE project_tags (
  project_id INTEGER NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  tag_id     INTEGER NOT NULL REFERENCES tags (id)     ON DELETE CASCADE,
  PRIMARY KEY (project_id, tag_id)
);
CREATE INDEX project_tags_tag_id_idx ON project_tags (tag_id);
