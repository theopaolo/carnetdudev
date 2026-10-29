# 🥋 Katas : Migrations

Place tes fichiers directement dans `03-migrations/` : l'import `../fil-rouge/open-db.mjs` fonctionne alors tel quel. Lance-les avec :

```bash
node --disable-warning=ExperimentalWarning nom-du-fichier.mjs
```

Toutes les solutions ont été exécutées avec Node 22.22 (SQLite 3.50). Elles utilisent `node:assert/strict` : si une vérification échoue, le script s'arrête avec une erreur explicite.

---

## Kata 1 : Une migration à la main, testée en aller-retour ⭐

Écris la migration `005_add_projects_slug` qui ajoute à `projects` une colonne `slug` **unique**, calculée à partir du titre (`'Éthique des données'` → `'ethique-des-donnees'`), et son `down`.

Puis écris le test que toute CI devrait exécuter : `up` → `down` → `up`, en vérifiant que

1. après le `down`, le schéma est **identique** au schéma de départ ;
2. après le second `up`, le schéma est identique à celui obtenu après le premier.

Contraintes :

- SQLite refuse `ALTER TABLE … ADD COLUMN … UNIQUE`. Trouve l'ordre d'opérations qui contourne cette limite.
- L'« empreinte » du schéma se lit dans `sqlite_schema` (colonnes `type`, `name`, `tbl_name`, `sql`).

<details><summary>✅ Solution</summary>

Fichier `aller-retour.mjs` :

```javascript
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

const slugify = (text) => text
  .normalize('NFD').replace(/[̀-ͯ]/g, '') // retire les accents
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-|-$/g, '');

export const migration = {
  name: '005_add_projects_slug',
  up(db) {
    // SQLite refuse ADD COLUMN ... UNIQUE : colonne d'abord, données ensuite, index unique enfin.
    db.exec('ALTER TABLE projects ADD COLUMN slug TEXT');
    const setSlug = db.prepare('UPDATE projects SET slug = ? WHERE id = ?');
    for (const { id, title } of db.prepare('SELECT id, title FROM projects').all()) {
      setSlug.run(slugify(title), id);
    }
    db.exec('CREATE UNIQUE INDEX projects_slug_key ON projects (slug)');
  },
  down(db) {
    // Ordre inverse de l'up : l'index d'abord, sinon DROP COLUMN échoue.
    db.exec('DROP INDEX projects_slug_key');
    db.exec('ALTER TABLE projects DROP COLUMN slug');
  },
};

// Empreinte du schéma : tout ce que SQLite sait des tables, index, vues et triggers.
const fingerprint = (db) => JSON.stringify(
  db.prepare(`SELECT type, name, tbl_name, sql FROM sqlite_schema
              WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`).all(),
);

const db = openDb();
const initial = fingerprint(db);

migration.up(db);
const afterUp = fingerprint(db);
console.log(db.prepare('SELECT id, slug FROM projects ORDER BY id').all());

migration.down(db);
assert.equal(fingerprint(db), initial, 'down ne restaure pas le schéma initial');

migration.up(db);
assert.equal(fingerprint(db), afterUp, "l'up n'est pas rejouable après un down");

console.log('Aller-retour up → down → up : OK');
```

Points clés :

- **Colonne, données, index**, dans cet ordre : c'est la seule façon d'obtenir une colonne unique sous SQLite, et c'est aussi la bonne pratique ailleurs (un index unique créé sur une colonne remplie échoue clairement si les données violent la contrainte).
- **Le `down` défait dans l'ordre inverse** : `DROP COLUMN` échoue tant que l'index existe (`error in index projects_slug_key after drop column`).
- **Limite de ce test** : il compare des schémas, pas des données. Il ne voit pas que le `down` détruit les slugs. C'est l'objet du kata 3.

</details>

---

## Kata 2 : Ton propre moteur de migrations ⭐⭐⭐

Écris `moteur/migrate.mjs`, un moteur de migrations complet, sans dépendance.

**Format d'une migration** : un fichier `moteur/migrations/NNN_nom.mjs` qui exporte `up(db)` (obligatoire), `down(db)` (facultatif : son absence signifie « irréversible ») et éventuellement `transaction = false`.

**Commandes** :

```bash
node migrate.mjs atelier.db up          # applique toutes les migrations en attente
node migrate.mjs atelier.db down 2      # annule les 2 dernières (1 par défaut)
node migrate.mjs atelier.db status      # état de chaque migration
```

**Exigences** :

1. Une table `schema_migrations (version, name, checksum, applied_at)`, créée si absente.
2. Chaque migration **et** sa ligne d'historique dans la **même** transaction, sauf si la migration exporte `transaction = false`.
3. Un checksum SHA-256 (`node:crypto`) de chaque fichier ; refus d'agir si une migration appliquée a été modifiée.
4. Refus si deux fichiers ont la même version, ou si une migration en attente est **antérieure** à la dernière appliquée (conflit de branches).
5. `down` refuse une migration sans fonction `down`.
6. Deux processus lancés en même temps ne doivent jamais appliquer deux fois la même migration.

Écris aussi quatre migrations qui reconstruisent une partie du fil rouge : `001_create_members`, `002_create_projects`, `003_create_contributions`, `004_add_members_bio`.

<details><summary>💡 Indices</summary>

- `readdirSync(dir).sort()` donne l'ordre lexicographique, donc l'ordre des versions si elles ont toutes trois chiffres.
- `import(pathToFileURL(path).href)` charge un module ES depuis un chemin.
- Pour l'exigence 6 sous SQLite : `BEGIN IMMEDIATE` prend le verrou d'écriture dès le début de la transaction. Il reste à **revérifier, sous ce verrou**, que la migration n'a pas été appliquée entre-temps. `PRAGMA busy_timeout = 5000` fait attendre le second processus au lieu d'échouer.

</details>

<details><summary>✅ Solution</summary>

Fichier `moteur/migrate.mjs` :

```javascript
// migrate.mjs — moteur de migrations minimal, zéro dépendance (Node 22+, node:sqlite)
//
//   node migrate.mjs <fichier.db> up            applique toutes les migrations en attente
//   node migrate.mjs <fichier.db> down [n]      annule les n dernières migrations (1 par défaut)
//   node migrate.mjs <fichier.db> status        affiche l'état de chaque migration
//
// Une migration est un fichier migrations/NNN_nom.mjs qui exporte :
//   export function up(db) { ... }              obligatoire
//   export function down(db) { ... }            facultatif (absent = irréversible)
//   export const transaction = false;           facultatif (défaut : true)
import { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const FILE_PATTERN = /^(\d{3})_([a-z0-9_]+)\.mjs$/;

export function ensureHistoryTable(db) {
  db.exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    checksum   TEXT NOT NULL,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`);
}

export function listMigrations(dir) {
  const files = readdirSync(dir).filter((file) => file.endsWith('.mjs')).sort();
  const seen = new Map();
  return files.map((file) => {
    const match = file.match(FILE_PATTERN);
    if (!match) throw new Error(`Nom de fichier invalide : ${file} (attendu : NNN_nom.mjs)`);
    const [, version, name] = match;
    // Deux branches qui créent chacune une « 004 » : on refuse plutôt que de choisir au hasard.
    if (seen.has(version)) throw new Error(`Version ${version} en double : ${seen.get(version)} et ${file}`);
    seen.set(version, file);
    const path = join(dir, file);
    const checksum = createHash('sha256').update(readFileSync(path)).digest('hex');
    return { version, name, file, path, checksum };
  });
}

const appliedRows = (db) =>
  db.prepare('SELECT version, name, checksum, applied_at FROM schema_migrations ORDER BY version').all();

// Vérifie que l'historique de la base et le dossier racontent la même histoire.
function verify(local, applied) {
  const byVersion = new Map(local.map((m) => [m.version, m]));
  for (const row of applied) {
    const m = byVersion.get(row.version);
    if (!m) throw new Error(`Migration ${row.version}_${row.name} appliquée en base mais absente du dossier`);
    if (m.checksum !== row.checksum) {
      throw new Error(`${m.file} a été modifiée après application (checksum différent). ` +
        'Ne modifie jamais une migration appliquée : écris-en une nouvelle.');
    }
  }
  const last = applied.at(-1)?.version ?? '000';
  const appliedVersions = new Set(applied.map((row) => row.version));
  const late = local.filter((m) => !appliedVersions.has(m.version) && m.version < last);
  if (late.length) {
    throw new Error(`Migration(s) en attente antérieure(s) à la dernière appliquée (${last}) : ` +
      `${late.map((m) => m.file).join(', ')}. Conflit de branches probable : renumérote-la(les).`);
  }
}

// Exécute fn dans une transaction, sauf si la migration demande explicitement à s'en passer.
// BEGIN IMMEDIATE prend tout de suite le verrou d'écriture : deux processus ne migrent pas en même temps.
async function inTransaction(db, useTransaction, fn) {
  if (!useTransaction) return fn();
  db.exec('BEGIN IMMEDIATE');
  try {
    await fn();
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

const load = (m) => import(pathToFileURL(m.path).href);

export async function up(db, dir) {
  ensureHistoryTable(db);
  const local = listMigrations(dir);
  verify(local, appliedRows(db));
  const done = [];
  for (const m of local) {
    const mod = await load(m);
    const useTransaction = mod.transaction !== false;
    await inTransaction(db, useTransaction, async () => {
      // Re-vérifié sous verrou : un autre processus a pu l'appliquer entre-temps.
      if (db.prepare('SELECT 1 FROM schema_migrations WHERE version = ?').get(m.version)) return;
      await mod.up(db);
      // Même transaction que le changement : soit les deux sont écrits, soit aucun.
      db.prepare('INSERT INTO schema_migrations (version, name, checksum) VALUES (?, ?, ?)')
        .run(m.version, m.name, m.checksum);
      done.push(m.file);
    });
  }
  return done;
}

export async function down(db, dir, steps = 1) {
  ensureHistoryTable(db);
  const local = listMigrations(dir);
  const applied = appliedRows(db);
  verify(local, applied);
  const byVersion = new Map(local.map((m) => [m.version, m]));
  const targets = applied.slice(-steps).reverse();
  const done = [];
  for (const row of targets) {
    const m = byVersion.get(row.version);
    const mod = await load(m);
    if (typeof mod.down !== 'function') throw new Error(`${m.file} est irréversible (pas de down)`);
    await inTransaction(db, mod.transaction !== false, async () => {
      await mod.down(db);
      db.prepare('DELETE FROM schema_migrations WHERE version = ?').run(m.version);
      done.push(m.file);
    });
  }
  return done;
}

export function status(db, dir) {
  ensureHistoryTable(db);
  const applied = new Map(appliedRows(db).map((row) => [row.version, row]));
  const local = listMigrations(dir);
  const rows = local.map((m) => {
    const row = applied.get(m.version);
    const state = !row ? 'en attente' : row.checksum === m.checksum ? `appliquée ${row.applied_at}` : 'MODIFIÉE !';
    return { migration: m.file, state };
  });
  for (const [version, row] of applied) {
    if (!local.some((m) => m.version === version)) rows.push({ migration: `${version}_${row.name}.mjs`, state: 'ABSENTE du dossier !' });
  }
  return rows;
}

// Point d'entrée CLI (ignoré quand le fichier est importé, par exemple dans les tests).
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [file, command, arg] = process.argv.slice(2);
  const dir = new URL('./migrations/', import.meta.url).pathname;
  const db = new DatabaseSync(file ?? ':memory:');
  db.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  try {
    if (command === 'up') console.log('Appliquées :', await up(db, dir));
    else if (command === 'down') console.log('Annulées :', await down(db, dir, Number(arg ?? 1)));
    else if (command === 'status') console.table(status(db, dir));
    else console.log('Usage : node migrate.mjs <fichier.db> up | down [n] | status');
  } catch (error) {
    console.error('✖', error.message);
    process.exitCode = 1;
  } finally {
    db.close();
  }
}
```

Fichier `moteur/migrations/001_create_members.mjs` :

```javascript
export function up(db) {
  db.exec(`CREATE TABLE members (
    id         INTEGER PRIMARY KEY,
    handle     TEXT NOT NULL UNIQUE,
    email      TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`);
}

export function down(db) {
  db.exec('DROP TABLE members');
}
```

Fichier `moteur/migrations/002_create_projects.mjs` :

```javascript
export function up(db) {
  db.exec(`CREATE TABLE projects (
    id         INTEGER PRIMARY KEY,
    owner_id   INTEGER NOT NULL REFERENCES members (id) ON DELETE RESTRICT,
    title      TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`);
  db.exec('CREATE INDEX projects_owner_id_idx ON projects (owner_id)');
}

export function down(db) {
  db.exec('DROP TABLE projects'); // supprime aussi son index
}
```

Fichier `moteur/migrations/003_create_contributions.mjs` :

```javascript
export function up(db) {
  db.exec(`CREATE TABLE contributions (
    member_id  INTEGER NOT NULL REFERENCES members (id)  ON DELETE CASCADE,
    project_id INTEGER NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    role       TEXT NOT NULL,
    since      TEXT NOT NULL DEFAULT (date('now')),
    PRIMARY KEY (member_id, project_id)
  )`);
  db.exec('CREATE INDEX contributions_project_id_idx ON contributions (project_id)');
}

export function down(db) {
  db.exec('DROP TABLE contributions');
}
```

Fichier `moteur/migrations/004_add_members_bio.mjs` :

```javascript
export function up(db) {
  db.exec('ALTER TABLE members ADD COLUMN bio TEXT');
}

export function down(db) {
  db.exec('ALTER TABLE members DROP COLUMN bio'); // ⚠️ détruit les bios saisies depuis l'up
}
```

**Protocole de vérification** (dans `moteur/`) :

| Scénario | Commande | Résultat attendu |
|---|---|---|
| Première application | `node migrate.mjs atelier.db up` | les 4 migrations appliquées |
| Idempotence | relancer `up` | `Appliquées : []` |
| Retour arrière | `down 2` puis `status` | 003 et 004 « en attente » |
| Migration modifiée | ajouter un commentaire dans `002_…`, relancer `up` | refus : « modifiée après application » ; `status` affiche `MODIFIÉE !` |
| Doublon | copier `004_…` en `004_add_tags.mjs` | refus : « Version 004 en double » |
| Conflit de branches | après application d'une `005`, ajouter une `004` | refus : « en attente antérieure à la dernière appliquée » |
| Échec en cours de migration | une migration qui crée une table puis ajoute une colonne existante | erreur, la table n'existe pas, pas de ligne d'historique |
| Irréversible | une migration sans `down`, puis `down 1` | refus : « irréversible » |
| Concurrence | deux `up` lancés en même temps sur une base neuve, avec une migration lente | l'un applique tout, l'autre `[]` ; chaque version enregistrée une seule fois |

Choix de conception à savoir justifier :

- **Pourquoi revérifier sous verrou ?** La liste des migrations en attente est calculée avant le verrou. Entre-temps, un autre processus a pu les appliquer. C'est le schéma classique *check-then-act* : la vérification doit être faite dans la même section critique que l'action.
- **Pourquoi refuser plutôt que réordonner ?** Un moteur qui choisit un ordre à ta place produit des bases différentes selon l'environnement. Un refus bruyant oblige un humain à trancher.
- **Ce qui manque pour la production** : un vrai verrou pour les migrations non transactionnelles (ici, elles ne sont protégées par rien), la journalisation de la durée de chaque migration, un mode `--dry-run` qui affiche le SQL sans l'exécuter, et le support de PostgreSQL (`pg_advisory_lock`).

</details>

---

## Kata 3 : Le down qui ment ⭐⭐

Voici quatre migrations candidates. Pour chacune, `probe` est une écriture qu'un utilisateur pourrait faire **après** l'`up`.

```javascript
const candidates = [
  {
    name: 'A_add_members_bio',
    up: 'ALTER TABLE members ADD COLUMN bio TEXT',
    down: 'ALTER TABLE members DROP COLUMN bio',
    probe: "UPDATE members SET bio = 'Écrit après la migration' WHERE id = 1",
  },
  {
    name: 'B_drop_contributions_since',
    up: 'ALTER TABLE contributions DROP COLUMN since',
    down: "ALTER TABLE contributions ADD COLUMN since TEXT NOT NULL DEFAULT '1970-01-01'",
    probe: "INSERT INTO contributions (member_id, project_id, role) VALUES (3, 1, 'test')",
  },
  {
    name: 'C_rename_tags_label',
    up: 'ALTER TABLE tags RENAME COLUMN label TO name',
    down: 'ALTER TABLE tags RENAME COLUMN name TO label',
    probe: "INSERT INTO tags (name) VALUES ('nouvelle')",
  },
  {
    name: 'D_archive_drafts',
    up: "UPDATE projects SET status = 'archived' WHERE status = 'draft'",
    down: "UPDATE projects SET status = 'draft' WHERE status = 'archived'",
    probe: "INSERT INTO projects (owner_id, title, status) VALUES (2, 'Brouillon tardif', 'draft')",
  },
];
```

1. **À la main d'abord** : pour chacune, le `down` restaure-t-il l'état d'avant l'`up` ? Les données écrites après l'`up` survivent-elles à un `down` suivi d'un `up` ?
2. Écris un **linter** naïf qui signale les instructions dangereuses dans un `up` ou un `down`.
3. Écris un **audit empirique** qui vérifie ces deux propriétés sur une vraie base :
   - **P1** : `down(up(S)) = S` (le `down` restaure l'état d'avant) ;
   - **P2** : après `up`, puis des écritures, `up(down(S')) = S'` (l'information écrite après l'`up` survit).
4. Compare les résultats du linter et de l'audit. Lequel des deux se trompe, et sur quel cas ?

<details><summary>✅ Solution</summary>

Fichier `down-qui-ment.mjs` :

```javascript
import { openDb } from '../fil-rouge/open-db.mjs';

const candidates = [
  {
    name: 'A_add_members_bio',
    up: 'ALTER TABLE members ADD COLUMN bio TEXT',
    down: 'ALTER TABLE members DROP COLUMN bio',
    probe: "UPDATE members SET bio = 'Écrit après la migration' WHERE id = 1",
  },
  {
    name: 'B_drop_contributions_since',
    up: 'ALTER TABLE contributions DROP COLUMN since',
    down: "ALTER TABLE contributions ADD COLUMN since TEXT NOT NULL DEFAULT '1970-01-01'",
    probe: "INSERT INTO contributions (member_id, project_id, role) VALUES (3, 1, 'test')",
  },
  {
    name: 'C_rename_tags_label',
    up: 'ALTER TABLE tags RENAME COLUMN label TO name',
    down: 'ALTER TABLE tags RENAME COLUMN name TO label',
    probe: "INSERT INTO tags (name) VALUES ('nouvelle')",
  },
  {
    name: 'D_archive_drafts',
    up: "UPDATE projects SET status = 'archived' WHERE status = 'draft'",
    down: "UPDATE projects SET status = 'draft' WHERE status = 'archived'",
    probe: "INSERT INTO projects (owner_id, title, status) VALUES (2, 'Brouillon tardif', 'draft')",
  },
];

// Étape 1 : heuristique statique. Rapide, mais aveugle à la sémantique.
const RULES = [
  { pattern: /\bDROP\s+(TABLE|COLUMN)\b/i, message: 'supprime une structure et ses données' },
  { pattern: /\b(DELETE\s+FROM|TRUNCATE)\b/i, message: 'supprime des lignes' },
  { pattern: /\bUPDATE\b/i, message: 'transforme des données : la transformation est-elle inversible ?' },
];
const lint = (sql) => RULES.filter(({ pattern }) => pattern.test(sql)).map(({ message }) => message);

// Étape 2 : test empirique.
// Photographie de toutes les données (hors historique) : table → lignes triées.
function snapshot(db) {
  const tables = db.prepare(`SELECT name FROM sqlite_schema
    WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'schema_migrations' ORDER BY name`).all();
  return Object.fromEntries(tables.map(({ name }) =>
    [name, JSON.stringify(db.prepare(`SELECT * FROM "${name}" ORDER BY rowid`).all())]));
}

const changedTables = (a, b) =>
  [...new Set([...Object.keys(a), ...Object.keys(b)])].filter((t) => a[t] !== b[t]);

function audit({ up, down, probe }) {
  // Propriété 1 : down ∘ up = identité. Le down restaure-t-il l'état d'avant ?
  const db1 = openDb();
  const before = snapshot(db1);
  db1.exec(up);
  db1.exec(down);
  const restoresBefore = changedTables(before, snapshot(db1));

  // Propriété 2 : l'information écrite après l'up survit-elle à un down puis un up ?
  const db2 = openDb();
  db2.exec(up);
  db2.exec(probe);
  const afterWrites = snapshot(db2);
  db2.exec(down);
  db2.exec(up);
  const keepsNewWrites = changedTables(afterWrites, snapshot(db2));

  return { restoresBefore, keepsNewWrites };
}

for (const candidate of candidates) {
  const { restoresBefore, keepsNewWrites } = audit(candidate);
  console.log(candidate.name);
  console.log('  lint up   :', lint(candidate.up).join(' ; ') || '—');
  console.log('  lint down :', lint(candidate.down).join(' ; ') || '—');
  console.log('  état d’avant restauré          :', restoresBefore.length ? `NON (${restoresBefore})` : 'oui');
  console.log('  écritures postérieures gardées :', keepsNewWrites.length ? `NON (${keepsNewWrites})` : 'oui');
}
```

Résultat :

```
A_add_members_bio
  lint up   : —
  lint down : supprime une structure et ses données
  état d’avant restauré          : oui
  écritures postérieures gardées : NON (members)
B_drop_contributions_since
  lint up   : supprime une structure et ses données
  lint down : —
  état d’avant restauré          : NON (contributions)
  écritures postérieures gardées : oui
C_rename_tags_label
  lint up   : —
  lint down : —
  état d’avant restauré          : oui
  écritures postérieures gardées : oui
D_archive_drafts
  lint up   : transforme des données : la transformation est-elle inversible ?
  lint down : transforme des données : la transformation est-elle inversible ?
  état d’avant restauré          : NON (projects)
  écritures postérieures gardées : NON (projects)
```

Lecture :

| Migration | P1 | P2 | Verdict |
|---|---|---|---|
| A — ajouter `bio` | ✅ | ❌ | Réversible tant que personne n'a écrit de bio. Ensuite, le `down` détruit de l'information. À **signaler**, pas forcément à interdire. |
| B — supprimer `since` | ❌ | ✅ | L'`up` détruit l'information ; le `down` recrée une colonne pleine de `1970-01-01`. **Irréversible** : ce `down` ment, il faut le supprimer et déclarer la migration irréversible. |
| C — renommer `label` | ✅ | ✅ | Bijection : réversible sans perte. |
| D — archiver les brouillons | ❌ | ❌ | `draft → archived` n'est pas injective : après l'`up`, on ne sait plus quels projets étaient archivés **avant**. Le `down` « dés-archive » aussi le projet 4, archivé depuis toujours. |

Le linter et l'audit sont **complémentaires** : le linter ne voit rien de dangereux dans la migration D au-delà d'un avertissement générique sur `UPDATE`, alors que c'est la seule qui viole les deux propriétés. Inversement, il signale le `DROP` du `down` de A, qui ne pose problème que si des données ont été écrites. Une analyse syntaxique ne peut pas juger de l'**inversibilité d'une fonction** sur les données ; seul un test sur des données le peut.

Pour corriger D, il faut **conserver l'information** que l'`up` écrase : par exemple une colonne `archived_from_draft_at` remplie par l'`up`, que le `down` utilise pour savoir quoi restaurer. Un `down` correct se prépare dans l'`up`.

</details>

---

## Kata 4 : Reconstruire une table SQLite sans rien perdre ⭐⭐

SQLite ne sait pas ajouter une contrainte `CHECK` à une table existante. Tu veux imposer `length(title) BETWEEN 1 AND 120` sur `projects`.

1. Écris d'abord la **version naïve** de la reconstruction : `BEGIN`, créer `new_projects` avec la contrainte, copier, `DROP TABLE projects`, renommer, `COMMIT`. Compte les lignes de `projects`, `contributions` et `project_tags` avant et après. Que s'est-il passé ?
2. Écris la **version sûre** en suivant la procédure de la documentation SQLite (voir les notes du module). Vérifie ensuite que :
   - aucune ligne n'a disparu ;
   - les clés étrangères sont réactivées ;
   - l'index `projects_owner_id_idx` existe toujours ;
   - la nouvelle contrainte est active ;
   - les clés étrangères et les cascades fonctionnent toujours.

<details><summary>✅ Solution</summary>

Fichier `reconstruction.mjs` :

```javascript
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

const NEW_PROJECTS = `CREATE TABLE new_projects (
  id         INTEGER PRIMARY KEY,
  owner_id   INTEGER NOT NULL REFERENCES members (id) ON DELETE RESTRICT,
  title      TEXT    NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
  status     TEXT    NOT NULL DEFAULT 'draft'
             CHECK (status IN ('draft', 'active', 'archived')),
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
)`;

const counts = (db) => ({ ...db.prepare(`SELECT
  (SELECT count(*) FROM projects)      AS projects,
  (SELECT count(*) FROM contributions) AS contributions,
  (SELECT count(*) FROM project_tags)  AS project_tags`).get() });

// Version naïve : ce que l'on écrit spontanément.
function naiveRebuild(db) {
  db.exec('BEGIN');
  db.exec(NEW_PROJECTS);
  db.exec('INSERT INTO new_projects SELECT id, owner_id, title, status, created_at FROM projects');
  db.exec('DROP TABLE projects');
  db.exec('ALTER TABLE new_projects RENAME TO projects');
  db.exec('COMMIT');
}

// Procédure recommandée par la documentation SQLite (« Making Other Kinds Of Table Schema Changes »).
function safeRebuild(db) {
  // 1. Les FK doivent être coupées HORS transaction : à l'intérieur, ce PRAGMA est sans effet.
  const fkWasOn = db.prepare('PRAGMA foreign_keys').get().foreign_keys === 1;
  db.exec('PRAGMA foreign_keys = OFF');
  try {
    db.exec('BEGIN');
    try {
      // 2. Mémoriser index et triggers de la table : DROP TABLE les emporte.
      const dependents = db.prepare(`SELECT sql FROM sqlite_schema
        WHERE tbl_name = 'projects' AND type IN ('index', 'trigger') AND sql IS NOT NULL`).all();
      // 3. Nouvelle table, copie, échange.
      db.exec(NEW_PROJECTS);
      db.exec('INSERT INTO new_projects SELECT id, owner_id, title, status, created_at FROM projects');
      db.exec('DROP TABLE projects');
      db.exec('ALTER TABLE new_projects RENAME TO projects');
      // 4. Recréer index et triggers.
      for (const { sql } of dependents) db.exec(sql);
      // 5. Vérifier l'intégrité référentielle avant de valider.
      const violations = db.prepare('PRAGMA foreign_key_check').all();
      if (violations.length) throw new Error(`Violations de FK : ${JSON.stringify(violations)}`);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  } finally {
    if (fkWasOn) db.exec('PRAGMA foreign_keys = ON');
  }
}

const naive = openDb();
const before = counts(naive);
naiveRebuild(naive);
console.log('naïf :', before, '→', counts(naive));

const db = openDb();
safeRebuild(db);
assert.deepEqual(counts(db), before, 'des lignes ont disparu');
assert.equal(db.prepare('PRAGMA foreign_keys').get().foreign_keys, 1);
assert.ok(db.prepare("SELECT 1 FROM sqlite_schema WHERE name = 'projects_owner_id_idx'").get(), 'index perdu');
assert.throws(() => db.prepare("UPDATE projects SET title = '' WHERE id = 1").run(), /CHECK constraint failed/);
assert.throws(() => db.prepare('DELETE FROM members WHERE id = 1').run(), /FOREIGN KEY constraint failed/);
console.log('sûr  :', before, '→', counts(db));
db.prepare('DELETE FROM projects WHERE id = 3').run(); // la cascade vers contributions fonctionne toujours
assert.equal(db.prepare('SELECT count(*) AS n FROM contributions WHERE project_id = 3').get().n, 0);
console.log('Contraintes, index, FK et cascades vérifiés.');
```

Résultat :

```
naïf : { projects: 5, contributions: 10, project_tags: 9 } → { projects: 5, contributions: 0, project_tags: 0 }
sûr  : { projects: 5, contributions: 10, project_tags: 9 } → { projects: 5, contributions: 10, project_tags: 9 }
Contraintes, index, FK et cascades vérifiés.
```

Ce qu'il fallait comprendre :

- **La version naïve ne lève aucune erreur.** Avec les clés étrangères actives, `DROP TABLE projects` exécute un `DELETE` implicite qui déclenche les `ON DELETE CASCADE` : les tables filles sont vidées. C'est le pire type de bug : silencieux et destructeur.
- **`PRAGMA foreign_keys = OFF` doit être exécuté hors transaction** : à l'intérieur, il est sans effet. Conséquence pour le moteur du kata 2 : une migration qui reconstruit une table doit exporter `transaction = false` et gérer sa propre transaction.
- **`DROP TABLE` emporte les index et triggers** : il faut les mémoriser avant et les recréer après.
- **`PRAGMA foreign_key_check`** avant le `COMMIT` : pendant la reconstruction, aucune contrainte de clé étrangère n'était vérifiée.

</details>

---

## Kata 5 : Expand/contract en cinq migrations ⭐⭐⭐

Objectif : renommer `projects.title` en `projects.name` **sans interruption de service**, sous SQLite.

Trois versions de l'application vont se succéder, et deux versions consécutives tournent toujours **en même temps** pendant un déploiement :

- **v1** écrit et lit `title` (le code actuel) ;
- **v2** écrit les **deux** colonnes et lit `name` ;
- **v3** n'écrit et ne lit plus que `name`.

Écris cinq migrations `{ name, compatible, up, down }`, où `compatible` liste les versions de l'application qui doivent fonctionner **ensemble** une fois la migration appliquée. Le script fourni vérifie, après chaque `up` puis après chaque `down`, que chaque version listée peut lire ce qu'écrivent les autres. À la fin, après un retour arrière complet, v1 doit pouvoir lire **tous** les projets, y compris ceux écrits par v3.

Différence avec PostgreSQL (voir notes) : un trigger SQLite ne peut pas modifier `NEW`. Un trigger `AFTER INSERT` peut en revanche faire un `UPDATE` de la ligne qui vient d'être insérée.

Fichier `expand-contract.mjs`, à compléter :

```javascript
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

// --- Fourni : reconstruction SQLite sûre (cf. kata 4), généralisée -------------------------
function rebuildTable(db, table, createNew, copy) {
  const fkWasOn = db.prepare('PRAGMA foreign_keys').get().foreign_keys === 1;
  db.exec('PRAGMA foreign_keys = OFF');
  try {
    db.exec('BEGIN');
    try {
      const indexes = db.prepare(`SELECT sql FROM sqlite_schema
        WHERE tbl_name = ? AND type = 'index' AND sql IS NOT NULL`).all(table);
      db.exec(createNew);
      db.exec(copy);
      db.exec(`DROP TABLE ${table}`);
      db.exec(`ALTER TABLE new_${table} RENAME TO ${table}`);
      for (const { sql } of indexes) db.exec(sql);
      const violations = db.prepare('PRAGMA foreign_key_check').all();
      if (violations.length) throw new Error(`Violations de FK : ${JSON.stringify(violations)}`);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  } finally {
    if (fkWasOn) db.exec('PRAGMA foreign_keys = ON');
  }
}

const projectsTable = ({ title, name }) => `CREATE TABLE new_projects (
  id         INTEGER PRIMARY KEY,
  owner_id   INTEGER NOT NULL REFERENCES members (id) ON DELETE RESTRICT,
  title      TEXT ${title},
  status     TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  name       TEXT ${name}
)`;
const COPY = 'INSERT INTO new_projects (id, owner_id, title, status, created_at, name) ' +
             'SELECT id, owner_id, title, status, created_at, name FROM projects';

// --- Fourni : les versions successives de l'application ------------------------------------
const apps = {
  v1: { // écrit et lit title
    create: (db, label) => db.prepare('INSERT INTO projects (owner_id, title) VALUES (1, ?)').run(label).lastInsertRowid,
    read: (db, id) => db.prepare('SELECT title AS label FROM projects WHERE id = ?').get(id).label,
  },
  v2: { // écrit les deux colonnes, lit name
    create: (db, label) => db.prepare('INSERT INTO projects (owner_id, title, name) VALUES (1, ?, ?)').run(label, label).lastInsertRowid,
    read: (db, id) => db.prepare('SELECT name AS label FROM projects WHERE id = ?').get(id).label,
  },
  v3: { // n'écrit et ne lit plus que name
    create: (db, label) => db.prepare('INSERT INTO projects (owner_id, name) VALUES (1, ?)').run(label).lastInsertRowid,
    read: (db, id) => db.prepare('SELECT name AS label FROM projects WHERE id = ?').get(id).label,
  },
};

// Toutes les versions qui cohabitent doivent pouvoir lire ce que les autres écrivent.
function assertCompatible(db, versions, step) {
  for (const writer of versions) {
    const label = `écrit par ${writer} (${step})`;
    const id = apps[writer].create(db, label);
    for (const reader of versions) {
      assert.equal(apps[reader].read(db, id), label, `${reader} ne lit pas ce qu'écrit ${writer} après ${step}`);
    }
  }
}

// --- À toi : les 5 migrations ---------------------------------------------------------
const migrations = [ /* … */ ];

// --- Vérification -------------------------------------------------------------------------
const db = openDb();
assertCompatible(db, ['v1'], 'état initial');
const count = () => db.prepare('SELECT count(*) AS n FROM projects').get().n;

for (const m of migrations) {
  m.up(db);
  assertCompatible(db, m.compatible, m.name);
  console.log(`↑ ${m.name.padEnd(30)} compatible avec ${m.compatible.join(' + ')} (${count()} projets)`);
}
assert.throws(() => apps.v2.create(db, 'trop tard'), /no column named title/);

for (let i = migrations.length - 1; i >= 0; i--) {
  migrations[i].down(db);
  const previous = i === 0 ? ['v1'] : migrations[i - 1].compatible;
  assertCompatible(db, previous, `down de ${migrations[i].name}`);
  console.log(`↓ ${migrations[i].name.padEnd(30)} retour à ${previous.join(' + ')}`);
}

// Après rollback complet, v1 relit tous les projets, y compris ceux écrits par v3.
const unreadable = db.prepare('SELECT count(*) AS n FROM projects WHERE title IS NULL').get().n;
assert.equal(unreadable, 0);
assert.equal(db.prepare('SELECT count(*) AS n FROM contributions').get().n, 10 + 0);
console.log(`Rollback complet : ${count()} projets lisibles par v1, contributions intactes.`);
```

<details><summary>💡 Indices</summary>

- Expand : une colonne facultative, puis une synchronisation `title → name` pour les écritures de v1.
- Migrate : un backfill. Ce n'est qu'après lui que v2 peut lire `name`.
- Contract en deux temps : v3 n'écrit pas `title`, qui est `NOT NULL`… Quelle migration doit précéder l'arrivée de v3 ?
- Le `down` d'une étape *contract* doit parfois **reconstituer** des données : que vaut `title` pour une ligne écrite par v3 ?

</details>

<details><summary>✅ Solution</summary>

À la place de `const migrations = [ /* … */ ];` :

```javascript
const SYNC_TRIGGERS = `
  CREATE TRIGGER projects_name_on_insert AFTER INSERT ON projects WHEN NEW.name IS NULL
  BEGIN UPDATE projects SET name = NEW.title WHERE id = NEW.id; END;
  CREATE TRIGGER projects_name_on_update AFTER UPDATE OF title ON projects
  BEGIN UPDATE projects SET name = NEW.title WHERE id = NEW.id; END;`;
const DROP_SYNC_TRIGGERS = `
  DROP TRIGGER IF EXISTS projects_name_on_insert;
  DROP TRIGGER IF EXISTS projects_name_on_update;`;

const migrations = [
  { // EXPAND : nouvelle colonne, facultative, que personne n'utilise encore
    name: '001_add_projects_name', compatible: ['v1'],
    up: (db) => db.exec('ALTER TABLE projects ADD COLUMN name TEXT'),
    down: (db) => db.exec('ALTER TABLE projects DROP COLUMN name'),
  },
  { // EXPAND : ce que v1 écrit dans title est recopié dans name
    name: '002_sync_projects_name', compatible: ['v1'],
    up: (db) => db.exec(SYNC_TRIGGERS),
    down: (db) => db.exec(DROP_SYNC_TRIGGERS),
  },
  { // MIGRATE : les lignes historiques reçoivent leur name ; v2 peut alors lire name
    name: '003_backfill_projects_name', compatible: ['v1', 'v2'],
    up: (db) => db.exec('UPDATE projects SET name = title WHERE name IS NULL'),
    down: () => {}, // volontairement vide : name sera supprimée par le down de 001
  },
  { // CONTRACT (1/2) : v1 a disparu. title devient facultative, name obligatoire.
    name: '004_swap_projects_constraints', compatible: ['v2', 'v3'],
    up: (db) => {
      db.exec(DROP_SYNC_TRIGGERS);
      rebuildTable(db, 'projects', projectsTable({ title: '', name: 'NOT NULL' }), COPY);
    },
    down: (db) => {
      db.exec('UPDATE projects SET title = name WHERE title IS NULL'); // lignes écrites par v3
      rebuildTable(db, 'projects', projectsTable({ title: 'NOT NULL', name: '' }), COPY);
      db.exec(SYNC_TRIGGERS);
    },
  },
  { // CONTRACT (2/2) : v2 a disparu. L'ancienne colonne peut partir.
    name: '005_drop_projects_title', compatible: ['v3'],
    up: (db) => db.exec('ALTER TABLE projects DROP COLUMN title'),
    down: (db) => {
      db.exec('ALTER TABLE projects ADD COLUMN title TEXT');
      db.exec('UPDATE projects SET title = name');
    },
  },
];
```

Résultat :

```
↑ 001_add_projects_name          compatible avec v1 (7 projets)
↑ 002_sync_projects_name         compatible avec v1 (8 projets)
↑ 003_backfill_projects_name     compatible avec v1 + v2 (10 projets)
↑ 004_swap_projects_constraints  compatible avec v2 + v3 (12 projets)
↑ 005_drop_projects_title        compatible avec v3 (13 projets)
↓ 005_drop_projects_title        retour à v2 + v3
↓ 004_swap_projects_constraints  retour à v1 + v2
↓ 003_backfill_projects_name     retour à v1
↓ 002_sync_projects_name         retour à v1
↓ 001_add_projects_name          retour à v1
Rollback complet : 20 projets lisibles par v1, contributions intactes.
```

Deux expériences pour vérifier que chaque étape est nécessaire :

- **Supprime la migration 002** (le trigger) : `AssertionError: v2 ne lit pas ce qu'écrit v1 après 003_backfill_projects_name`. Sans synchronisation, ce que v1 écrit pendant la cohabitation n'arrive jamais dans `name`.
- **Déclare v3 compatible dès la 003** : `NOT NULL constraint failed: projects.title`. v3 ne peut arriver qu'après la migration qui rend `title` facultative.

Ce qu'il faut retenir :

- La migration 004 est le **point de non-retour pour v1** : `name` devient obligatoire et le trigger disparaît. Elle ne doit être appliquée que lorsque plus aucune instance v1 ne tourne **et** qu'on a renoncé à revenir à v1.
- Le `down` de 004 **reconstitue** `title` pour les lignes écrites par v3 (`title = name`). Un `down` correct n'est pas toujours l'inverse syntaxique de l'`up` ; c'est l'inverse **sémantique**.
- Le `down` vide de 003 est volontaire : remettre `name` à `NULL` casserait v2, qui lit déjà `name`. Une migration de données peut avoir un `down` vide, à condition de **dire pourquoi**.

</details>

---

## Kata 6 : Backfill par lots, idempotent et reprenable ⭐⭐

Une migration de schéma vient d'ajouter `members.email_normalized`. Il faut la remplir avec `lower(trim(email))` pour 20 000 membres, **sans** une transaction géante.

Écris `backfillEmails(db, { batchSize, startAfter, onBatch })` qui :

1. traite les lignes par lots de `batchSize`, une transaction par lot ;
2. avance avec un **curseur sur la clé primaire**, pas avec `OFFSET` ;
3. ne touche que les lignes pas encore traitées (idempotence) ;
4. peut reprendre après une interruption à partir du dernier curseur (`startAfter`) ;
5. appelle `onBatch({ cursor, updated })` après chaque lot validé.

Fichier `backfill.mjs`, à compléter :

```javascript
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

// Mise en place : 20 000 membres aux emails « sales », et la colonne ajoutée par une migration de schéma.
const db = openDb({ seed: false });
const insert = db.prepare('INSERT INTO members (handle, email) VALUES (?, ?)');
db.exec('BEGIN');
for (let i = 1; i <= 20_000; i++) insert.run(`user${i}`, `  User${i}@Atelier.TEST `);
db.exec('COMMIT');
db.exec('ALTER TABLE members ADD COLUMN email_normalized TEXT');

// --- À toi --------------------------------------------------------------------------------
export function backfillEmails(db, { batchSize = 1000, startAfter = 0, onBatch = () => {} } = {}) {
  // …
}

// --- Vérification : on simule un arrêt brutal au 7ᵉ lot, puis une reprise -------------------
let batches = 0;
let lastCursor = 0;
assert.throws(() => backfillEmails(db, {
  onBatch: ({ cursor }) => {
    lastCursor = cursor;
    if (++batches === 7) throw new Error('déploiement interrompu');
  },
}), /interrompu/);
const remaining = () => db.prepare('SELECT count(*) AS n FROM members WHERE email_normalized IS NULL').get().n;
console.log(`Interrompu après ${batches} lots, curseur ${lastCursor}, ${remaining()} lignes restantes`);

const resumed = backfillEmails(db, { startAfter: lastCursor });
console.log(`Reprise : ${resumed.updated} lignes mises à jour`);
assert.equal(remaining(), 0);
assert.equal(resumed.updated, 20_000 - 7_000);

// Relancer depuis zéro ne fait rien : idempotence.
assert.equal(backfillEmails(db).updated, 0);
assert.equal(db.prepare('SELECT email_normalized AS e FROM members WHERE id = 42').get().e, 'user42@atelier.test');
console.log('Backfill complet, idempotent et reprenable.');
```

<details><summary>✅ Solution</summary>

```javascript
// Une transaction par lot : les verrous sont courts, et un arrêt ne perd que le lot en cours.
// Idempotent (on ne touche que les lignes encore à NULL) et reprenable (curseur sur la clé primaire).
export function backfillEmails(db, { batchSize = 1000, startAfter = 0, onBatch = () => {} } = {}) {
  const nextBatch = db.prepare(`SELECT id FROM members
    WHERE id > ? AND email_normalized IS NULL ORDER BY id LIMIT ?`);
  const update = db.prepare(`UPDATE members SET email_normalized = lower(trim(email))
    WHERE id BETWEEN ? AND ? AND email_normalized IS NULL`);

  let cursor = startAfter;
  let updated = 0;
  for (;;) {
    const ids = nextBatch.all(cursor, batchSize);
    if (ids.length === 0) return { updated, cursor };
    const [first, last] = [ids[0].id, ids.at(-1).id];
    db.exec('BEGIN');
    try {
      updated += Number(update.run(first, last).changes);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
    cursor = last;
    onBatch({ cursor, updated }); // point de reprise à persister, et endroit où temporiser
  }
}
```

Résultat :

```
Interrompu après 7 lots, curseur 7000, 13000 lignes restantes
Reprise : 13000 lignes mises à jour
Backfill complet, idempotent et reprenable.
```

Pourquoi ces choix :

- **Curseur plutôt qu'`OFFSET`** : `OFFSET 19000` oblige la base à parcourir 19 000 lignes pour les ignorer. Le curseur `id > ?` utilise l'index de la clé primaire et coûte le même prix à chaque lot (voir la pagination par curseur, module 06).
- **Une transaction par lot** : les verrous sont tenus quelques millisecondes ; une interruption ne perd que le lot en cours.
- **`email_normalized IS NULL` dans les deux requêtes** : relancer le backfill depuis zéro ne fait rien de mal. Ce n'est pas une optimisation, c'est ce qui rend la reprise sûre.
- **Limite** : relancer depuis zéro reste correct mais relit les lignes déjà traitées. Sur une très grande table, on persiste le curseur (dans une table de suivi) au lieu de le garder en mémoire.
- **Et les écritures concurrentes ?** Pendant le backfill, le code applicatif doit déjà remplir `email_normalized` pour les nouvelles lignes (écriture double, comme v2 au kata 5). Sinon, une ligne insérée derrière le curseur ne sera jamais traitée.

</details>

---

## Kata 7 : Diagnostic — trois incidents en production ⭐⭐

Pas de code. Pour chaque incident, choisis une stratégie (**rollback du code**, **`down`**, **roll-forward**, **restauration**) et justifie-la. Rédige ta réponse avant d'ouvrir la solution.

**Incident 1.** À 14 h, la migration `add_projects_priority` (ajout d'une colonne facultative) est appliquée. À 14 h 05, la version 42 du code est déployée. À 14 h 20, les erreurs 500 explosent sur la page projet : un bug dans le nouveau composant de tri, sans rapport avec la base.

**Incident 2.** Sur MySQL, une migration contient trois instructions : `ALTER TABLE members ADD COLUMN bio TEXT`, `ALTER TABLE members ADD COLUMN avatar_url TEXT`, `CREATE INDEX …`. La deuxième échoue (nom de colonne déjà pris par un hotfix manuel de la semaine dernière). L'outil affiche une erreur et la migration n'apparaît pas dans l'historique.

**Incident 3.** Lundi à 10 h, la migration *contract* `drop_members_bio` est appliquée. À 16 h, on découvre que l'export RGPD, une tâche nocturne que personne n'a migrée, lisait cette colonne. Les utilisateurs ont bien sûr continué à utiliser le site entre-temps.

<details><summary>✅ Solution</summary>

**Incident 1 → rollback du code seul.** La migration est additive : la version 41 du code fonctionne sur le nouveau schéma (c'est exactement la règle de compatibilité N/N+1). Exécuter le `down` n'apporterait rien et ajouterait un risque. Le schéma et le code n'ont pas à être annulés ensemble ; c'est précisément pour pouvoir annuler le code seul qu'on écrit des migrations compatibles avec la version précédente.

**Incident 2 → constat, puis roll-forward.** MySQL a validé implicitement la première instruction : `bio` existe, l'historique dit que la migration n'est pas appliquée. Ni la transaction ni un `down` ne peuvent aider : le `down` supposerait un état que la base n'a pas. Démarche :
1. Constater l'état réel (`SHOW CREATE TABLE members`) plutôt que supposer.
2. Écrire la migration qui reproduit le hotfix manuel (c'est une **dérive** : cause racine de l'incident).
3. Corriger la migration fautive pour qu'elle parte de l'état réel, ou la découper (une instruction DDL par migration, la règle sous MySQL), puis mettre l'historique en cohérence avec l'outil (Prisma : `migrate resolve --applied` ou `--rolled-back` ; Flyway : `repair`).
4. Ajouter en CI une comparaison du schéma réel avec le schéma attendu.

**Incident 3 → restauration partielle, puis roll-forward.** Les bios ont disparu de la base ; un `down` recréerait une colonne vide. Restaurer toute la base à 9 h 59 effacerait six heures d'écritures légitimes. La bonne démarche :
1. Restaurer la sauvegarde (ou la PITR à 9 h 59) dans une **instance séparée**.
2. En extraire `id, bio`.
3. Écrire une migration (roll-forward) qui recrée `members.bio`, puis un script qui réinjecte les valeurs.
4. Migrer l'export RGPD, puis refaire le *contract* proprement.
5. Cause racine : la phase *contract* a été lancée sans inventaire de **tous** les lecteurs (tâches planifiées, exports, outils de BI, répliques). Remède : retirer d'abord la colonne du mapping et des droits (`REVOKE`, ou renommer en `bio_deprecated`) et attendre un cycle complet avant de la supprimer.

**Bonus — incident 4.** Une migration exécute `CREATE INDEX projects_title_idx ON projects (title)` sur une table de 40 millions de lignes en PostgreSQL. Le site ne répond plus : toutes les écritures sur `projects` attendent. → **Annuler la requête** (`pg_cancel_backend`) : la transaction est annulée, aucune donnée n'est perdue. Puis roll-forward avec `CREATE INDEX CONCURRENTLY` dans une migration non transactionnelle, avec `lock_timeout`, et supprimer l'éventuel index `INVALID` si la construction concurrente échoue.

</details>

---

**🎉 Prochaine étape : documenter tout ça (module 05), ou voir ce qui casse en production (module 06).**
