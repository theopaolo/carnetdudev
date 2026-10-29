-- Jeu de données minimal et déterministe pour les exemples et les katas.

INSERT INTO members (id, handle, email, created_at) VALUES
  (1, 'theo',  'theo@atelier.test',  '2026-01-10 09:00:00'),
  (2, 'ada',   'ada@atelier.test',   '2026-02-02 14:30:00'),
  (3, 'bruno', 'bruno@atelier.test', '2026-03-15 11:00:00'),
  (4, 'chloe', 'chloe@atelier.test', '2026-04-01 08:45:00');

INSERT INTO projects (id, owner_id, title, status, created_at) VALUES
  (1, 1, 'Carnet du dev',        'active',   '2026-01-12 10:00:00'),
  (2, 2, 'Typographie variable', 'active',   '2026-02-05 16:00:00'),
  (3, 1, 'Synthé web',           'draft',    '2026-03-01 18:20:00'),
  (4, 4, 'Atlas sonore',         'archived', '2026-04-03 09:10:00'),
  (5, 3, 'Éthique des données',  'active',   '2026-04-20 13:00:00');

INSERT INTO contributions (member_id, project_id, role, since) VALUES
  (1, 1, 'auteur',    '2026-01-12'),
  (2, 1, 'relecture', '2026-02-10'),
  (2, 2, 'auteur',    '2026-02-05'),
  (1, 2, 'dev',       '2026-02-20'),
  (4, 2, 'design',    '2026-04-05'),
  (1, 3, 'auteur',    '2026-03-01'),
  (4, 4, 'auteur',    '2026-04-03'),
  (3, 4, 'son',       '2026-04-04'),
  (3, 5, 'auteur',    '2026-04-20'),
  (1, 5, 'relecture', '2026-05-02');

INSERT INTO tags (id, label) VALUES
  (1, 'pedagogie'), (2, 'typographie'), (3, 'audio'), (4, 'web'), (5, 'ethique');

INSERT INTO project_tags (project_id, tag_id) VALUES
  (1, 1), (1, 4),
  (2, 2), (2, 4),
  (3, 3), (3, 4),
  (4, 3),
  (5, 1), (5, 5);
