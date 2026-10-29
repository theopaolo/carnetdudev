# 🥋 Katas : Concepts avancés

Tous les katas se font en Node 22 natif (`node:sqlite`, `node:test`), sans dépendance. Place tes fichiers dans `06-concepts-avances/` et lance-les avec :

```bash
node --disable-warning=ExperimentalWarning kata.mjs
node --disable-warning=ExperimentalWarning --test kata.test.mjs   # pour les katas de test
```

Chaque solution a été exécutée telle quelle. Essaie d'abord sans l'ouvrir : l'intérêt est de **mesurer** (nombre de requêtes, plan d'exécution, lignes vues) avant et après ta correction.

| Kata | Sujet | Niveau |
|---|---|---|
| 1 | Reproduire un N+1 et le corriger de deux façons | ⭐ |
| 2 | Un test qui échoue en cas de N+1 | ⭐⭐ |
| 3 | DataLoader complet (relations 1-1 et 1-n, erreurs par clé) | ⭐⭐ |
| 4 | Identity Map : la modification perdue dans une même requête | ⭐⭐ |
| 5 | Unit of Work : ordre des écritures, dirty checking, échec | ⭐⭐⭐ |
| 6 | Verrouillage optimiste avec fusion des modifications | ⭐⭐ |
| 7 | Pagination par curseur opaque et plan d'exécution | ⭐⭐⭐ |
| 8 | Outbox transactionnelle | ⭐⭐⭐ |

---

## Kata 1 : Reproduire un N+1, le corriger deux fois ⭐

**Contexte.** Une page affiche, pour chaque membre, la liste des projets auxquels il contribue avec son rôle.

```javascript
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

const db = withQueryLog(openDb(), { print: false });

function contributionsByMemberNaive(db) {
  const members = db.prepare('SELECT id, handle FROM members ORDER BY handle').all();
  return members.map((m) => ({
    handle: m.handle,
    projects: db
      .prepare(
        `SELECT p.title, c.role FROM contributions c
         JOIN projects p ON p.id = c.project_id
         WHERE c.member_id = ? ORDER BY p.title`
      )
      .all(m.id)
      .map(({ title, role }) => ({ title, role })),
  }));
}
```

**Consignes.**

1. Mesure le nombre de requêtes avec `db.queries.length`.
2. Écris `contributionsByMemberJoin` (une seule requête, jointure, regroupement en JS) et `contributionsByMemberPreload` (une requête pour les membres, une avec `IN (...)` pour les contributions).
3. Vérifie que les trois fonctions renvoient **exactement** le même résultat (y compris pour un membre sans contribution).
4. Ajoute 50 membres dans une transaction que tu annules ensuite, et mesure à nouveau : qu'est-ce qui croît, qu'est-ce qui reste constant ?

**Critère de réussite :** naïf = 1 + N requêtes ; jointure = 1 ; préchargement = 2, quel que soit N.

<details><summary>✅ Solution</summary>

```javascript
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

const db = withQueryLog(openDb(), { print: false });

// Énoncé : version naïve fournie
function contributionsByMemberNaive(db) {
  const members = db.prepare('SELECT id, handle FROM members ORDER BY handle').all();
  return members.map((m) => ({
    handle: m.handle,
    projects: db
      .prepare(
        `SELECT p.title, c.role FROM contributions c
         JOIN projects p ON p.id = c.project_id
         WHERE c.member_id = ? ORDER BY p.title`
      )
      .all(m.id)
      .map(({ title, role }) => ({ title, role })),
  }));
}

// Solution 1 : jointure + regroupement
function contributionsByMemberJoin(db) {
  const rows = db
    .prepare(
      `SELECT m.id, m.handle, p.title, c.role
       FROM members m
       LEFT JOIN contributions c ON c.member_id = m.id
       LEFT JOIN projects p      ON p.id = c.project_id
       ORDER BY m.handle, p.title`
    )
    .all();
  const byMember = new Map();
  for (const row of rows) {
    if (!byMember.has(row.id)) byMember.set(row.id, { handle: row.handle, projects: [] });
    if (row.title !== null) byMember.get(row.id).projects.push({ title: row.title, role: row.role });
  }
  return [...byMember.values()];
}

// Solution 2 : préchargement par IN
function contributionsByMemberPreload(db) {
  const members = db.prepare('SELECT id, handle FROM members ORDER BY handle').all();
  if (members.length === 0) return [];
  const ids = members.map((m) => m.id);
  const rows = db
    .prepare(
      `SELECT c.member_id, p.title, c.role FROM contributions c
       JOIN projects p ON p.id = c.project_id
       WHERE c.member_id IN (${ids.map(() => '?').join(', ')})
       ORDER BY p.title`
    )
    .all(...ids);
  const byMember = Map.groupBy(rows, (row) => row.member_id);
  return members.map((m) => ({
    handle: m.handle,
    projects: (byMember.get(m.id) ?? []).map(({ title, role }) => ({ title, role })),
  }));
}

function measure(label, fn) {
  const before = db.queries.length;
  const result = fn(db);
  console.log(`${label.padEnd(8)} ${db.queries.length - before} requête(s)`);
  return result;
}

const naive = measure('naïf', contributionsByMemberNaive);
const joined = measure('jointure', contributionsByMemberJoin);
const preloaded = measure('préchargement', contributionsByMemberPreload);
console.log(JSON.stringify(naive) === JSON.stringify(joined), JSON.stringify(naive) === JSON.stringify(preloaded));
console.log(JSON.stringify(naive[0]));

// Vérification de la croissance : on ajoute 50 membres
db.exec('BEGIN');
const ins = db.prepare('INSERT INTO members (handle, email) VALUES (?, ?)');
for (let i = 0; i < 50; i++) ins.run(`m${i}`, `m${i}@atelier.test`);
measure('naïf', contributionsByMemberNaive);
measure('jointure', contributionsByMemberJoin);
measure('préchargement', contributionsByMemberPreload);
db.exec('ROLLBACK');
```

Sortie obtenue :

```
naïf     5 requête(s)
jointure 1 requête(s)
préchargement 2 requête(s)
true true
{"handle":"ada","projects":[{"title":"Carnet du dev","role":"relecture"},{"title":"Typographie variable","role":"auteur"}]}
naïf     55 requête(s)
jointure 1 requête(s)
préchargement 2 requête(s)
```

Points d'attention :

- La jointure doit être un `LEFT JOIN` : avec un `JOIN` interne, un membre sans contribution disparaît.
- Dans la version jointe, `row.title !== null` distingue « pas de contribution » d'une vraie ligne.
- L'ordre des projets doit être imposé par `ORDER BY` dans les **trois** versions : sans lui, l'égalité des résultats tient du hasard.

</details>

---

## Kata 2 : Un test qui échoue en cas de N+1 ⭐⭐

**Objectif.** Rendre le N+1 **impossible à fusionner** : un test qui échoue si une fonction dépasse un budget de requêtes, ou si une même requête SQL est répétée.

**Consignes.**

1. Écris `profileQueries(db, fn, { repeatThreshold })` qui renvoie `{ result, count, repeated }`, où `repeated` liste les requêtes au SQL identique exécutées au moins `repeatThreshold` fois.
2. Écris `assertQueryBudget(db, fn, { max, repeatThreshold })` qui échoue avec un message lisible (le SQL fautif et son nombre d'exécutions).
3. Avec `node:test`, montre qu'une version jointe passe et qu'une version naïve est signalée.

**Contrainte :** au plus 3 requêtes pour lister les titres de projets avec le pseudo de leur propriétaire.

<details><summary>✅ Solution</summary>

```javascript
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

// Exécute fn et renvoie le nombre de requêtes + les requêtes répétées (même SQL, paramètres différents).
function profileQueries(db, fn, { repeatThreshold = 3 } = {}) {
  const before = db.queries.length;
  const result = fn();
  const executed = db.queries.slice(before);
  const bySql = Map.groupBy(executed, (q) => q.sql.replace(/\s+/g, ' ').trim());
  const repeated = [...bySql]
    .filter(([, runs]) => runs.length >= repeatThreshold)
    .map(([sql, runs]) => ({ sql, times: runs.length }));
  return { result, count: executed.length, repeated };
}

function assertQueryBudget(db, fn, { max, repeatThreshold = 3 }) {
  const { result, count, repeated } = profileQueries(db, fn, { repeatThreshold });
  const report = repeated.map((r) => `  ${r.times}× ${r.sql}`).join('\n');
  assert.equal(repeated.length, 0, `N+1 probable :\n${report}`);
  assert.ok(count <= max, `${count} requêtes pour un budget de ${max}`);
  return result;
}

const titlesWithOwnerNaive = (db) =>
  db.prepare('SELECT title, owner_id FROM projects ORDER BY id').all()
    .map((p) => `${p.title} (${db.prepare('SELECT handle FROM members WHERE id = ?').get(p.owner_id).handle})`);

const titlesWithOwner = (db) =>
  db.prepare('SELECT p.title, m.handle FROM projects p JOIN members m ON m.id = p.owner_id ORDER BY p.id').all()
    .map((row) => `${row.title} (${row.handle})`);

test('la version jointe respecte le budget', () => {
  const db = withQueryLog(openDb(), { print: false });
  const titles = assertQueryBudget(db, () => titlesWithOwner(db), { max: 2 });
  assert.equal(titles[0], 'Carnet du dev (theo)');
});

test('la version naïve est signalée comme N+1', () => {
  const db = withQueryLog(openDb(), { print: false });
  assert.throws(
    () => assertQueryBudget(db, () => titlesWithOwnerNaive(db), { max: 2 }),
    /N\+1 probable :\n {2}5× SELECT handle FROM members WHERE id = \?/
  );
});

test('les deux versions renvoient la même chose', () => {
  const db = withQueryLog(openDb(), { print: false });
  assert.deepEqual(titlesWithOwnerNaive(db), titlesWithOwner(db));
});
```

```
ok 1 - la version jointe respecte le budget
ok 2 - la version naïve est signalée comme N+1
ok 3 - les deux versions renvoient la même chose
```

Pourquoi détecter la **répétition** en plus du total : un budget global finit toujours par être relevé « parce que la page a grossi » ; une même requête exécutée 5 fois avec des paramètres différents est, elle, presque toujours un N+1. C'est l'heuristique des détecteurs comme Bullet (Rails).

</details>

---

## Kata 3 : DataLoader complet ⭐⭐

**Contexte.** Des *resolvers* indépendants (comme dans GraphQL) construisent des cartes de projet : propriétaire et étiquettes. Aucun ne connaît les autres.

**Consignes.** Écris une classe `DataLoader` qui :

1. regroupe les `load(key)` émis pendant le même tour de boucle d'événements en un seul appel à `batchFn(keys)` ;
2. déduplique les clés et met les promesses en cache (par instance) ;
3. propose `loadMany(keys)` et `clear(key)` ;
4. accepte `maxBatchSize` (découpe des lots trop gros) ;
5. permet à `batchFn` de renvoyer une `Error` **pour une clé** sans faire échouer les autres, et ne met pas les échecs en cache.

Puis utilise-la pour une relation 1-1 (propriétaire) et une relation 1-n (étiquettes : une clé → un tableau).

<details><summary>✅ Solution</summary>

```javascript
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

class DataLoader {
  #batchFn;
  #maxBatchSize;
  #queue = [];
  #cache = new Map();

  constructor(batchFn, { maxBatchSize = Infinity } = {}) {
    this.#batchFn = batchFn;
    this.#maxBatchSize = maxBatchSize;
  }

  load(key) {
    if (this.#cache.has(key)) return this.#cache.get(key);
    const promise = new Promise((resolve, reject) => {
      this.#queue.push({ key, resolve, reject });
      if (this.#queue.length === 1) queueMicrotask(() => this.#dispatch());
    });
    this.#cache.set(key, promise);
    return promise;
  }

  loadMany(keys) {
    return Promise.all(keys.map((key) => this.load(key)));
  }

  clear(key) {
    this.#cache.delete(key);
    return this;
  }

  #dispatch() {
    const queue = this.#queue;
    this.#queue = [];
    for (let i = 0; i < queue.length; i += this.#maxBatchSize) {
      this.#runBatch(queue.slice(i, i + this.#maxBatchSize));
    }
  }

  async #runBatch(batch) {
    try {
      const values = await this.#batchFn(batch.map((item) => item.key));
      if (!Array.isArray(values) || values.length !== batch.length) {
        throw new TypeError(`batchFn doit renvoyer ${batch.length} valeurs, une par clé`);
      }
      batch.forEach((item, i) => {
        // Une erreur pour UNE clé ne doit pas faire échouer les autres.
        if (values[i] instanceof Error) {
          this.#cache.delete(item.key); // ne pas mettre un échec en cache
          item.reject(values[i]);
        } else {
          item.resolve(values[i]);
        }
      });
    } catch (error) {
      batch.forEach((item) => {
        this.#cache.delete(item.key);
        item.reject(error);
      });
    }
  }
}

const db = withQueryLog(openDb(), { print: false });
const inList = (values) => values.map(() => '?').join(', ');

// Relation 1-1 : propriétaire d'un projet. Clé absente → erreur pour cette clé seulement.
const members = new DataLoader((ids) => {
  const rows = db.prepare(`SELECT id, handle FROM members WHERE id IN (${inList(ids)})`).all(...ids);
  const byId = new Map(rows.map((row) => [row.id, row]));
  return ids.map((id) => byId.get(id) ?? new Error(`membre ${id} introuvable`));
});

// Relation 1-n : étiquettes d'un projet. Une clé → un tableau (éventuellement vide).
const tagsOfProject = new DataLoader((projectIds) => {
  const rows = db
    .prepare(
      `SELECT pt.project_id, t.label FROM project_tags pt JOIN tags t ON t.id = pt.tag_id
       WHERE pt.project_id IN (${inList(projectIds)}) ORDER BY t.label`
    )
    .all(...projectIds);
  const byProject = Map.groupBy(rows, (row) => row.project_id);
  return projectIds.map((id) => (byProject.get(id) ?? []).map((row) => row.label));
}, { maxBatchSize: 2 });

// « Resolvers » indépendants, comme dans GraphQL : aucun ne sait que les autres existent.
const resolveCard = async (project) => ({
  title: project.title,
  owner: (await members.load(project.owner_id)).handle,
  tags: await tagsOfProject.load(project.id),
});

const projects = db.prepare('SELECT id, title, owner_id FROM projects ORDER BY id').all();
const before = db.queries.length;
const cards = await Promise.all(projects.map(resolveCard));
console.log(cards.map((c) => `${c.title} · ${c.owner} · ${c.tags.join('/')}`));
console.log(`requêtes : ${db.queries.length - before}`); // 1 (membres) + 3 (étiquettes, lots de 2)

const results = await Promise.allSettled([members.load(1), members.load(404)]);
console.log(results.map((r) => r.status), results[1].reason.message);
const again = db.queries.length;
await members.load(1); // en cache
console.log('cache :', db.queries.length - again);
const ok = await members.loadMany([2, 3]);
console.log(ok.map((m) => m.handle));
```

```
[
  'Carnet du dev · theo · pedagogie/web',
  'Typographie variable · ada · typographie/web',
  'Synthé web · theo · audio/web',
  'Atlas sonore · chloe · audio',
  'Éthique des données · bruno · ethique/pedagogie'
]
requêtes : 4
[ 'fulfilled', 'rejected' ] membre 404 introuvable
cache : 0
[ 'ada', 'bruno' ]
```

À remarquer : les `tagsOfProject.load()` sont émis **après** un `await` ; ils sont quand même regroupés, parce que les cinq resolvers reprennent dans la même vague de microtâches. Avec `maxBatchSize: 2`, cinq clés donnent trois requêtes. Une requête pour les membres + trois pour les étiquettes = 4, contre 10 sans DataLoader (5 + 5).

</details>

---

## Kata 4 : Identity Map, la modification perdue ⭐⭐

**Contexte.** Pendant une même requête HTTP, deux services travaillent sur le projet 3 : l'un le renomme, l'autre le publie. Chacun charge le projet par le mapper, puis on enregistre.

**Consignes.**

1. Écris un `ProjectMapper` (`find(id)`, `findByStatus(status)`, `save(project)` qui écrit `title` et `status`).
2. Montre que **sans** Identity Map, l'une des deux modifications est perdue, sans aucune concurrence entre utilisateurs.
3. Ajoute une `IdentityMap` optionnelle et montre que les deux services reçoivent le même objet, qu'une seule lecture de `projects#3` part en base, et que `findByStatus` réutilise les objets déjà chargés.

<details><summary>✅ Solution</summary>

```javascript
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

class IdentityMap {
  #entries = new Map(); // clé "table:id" → entité

  #key(table, id) {
    return `${table}:${id}`;
  }
  get(table, id) {
    return this.#entries.get(this.#key(table, id));
  }
  add(table, entity) {
    this.#entries.set(this.#key(table, entity.id), entity);
    return entity;
  }
  get size() {
    return this.#entries.size;
  }
}

// Un mapper minimal, avec ou sans Identity Map
class ProjectMapper {
  #db;
  #identityMap;

  constructor(db, identityMap = null) {
    this.#db = db;
    this.#identityMap = identityMap;
  }

  find(id) {
    const cached = this.#identityMap?.get('projects', id);
    if (cached) return cached; // aucune requête
    const row = this.#db.prepare('SELECT id, title, status FROM projects WHERE id = ?').get(id);
    return row ? this.#resolve(row) : null;
  }

  findByStatus(status) {
    // La requête part toujours en base : l'Identity Map sert à RÉUTILISER les objets déjà connus.
    return this.#db
      .prepare('SELECT id, title, status FROM projects WHERE status = ? ORDER BY id')
      .all(status)
      .map((row) => this.#resolve(row));
  }

  // Si la ligne correspond à un objet déjà chargé, on renvoie CET objet
  // (et ses modifications en mémoire priment sur la ligne relue).
  #resolve(row) {
    if (!this.#identityMap) return { ...row };
    return this.#identityMap.get('projects', row.id) ?? this.#identityMap.add('projects', { ...row });
  }

  save(project) {
    this.#db.prepare('UPDATE projects SET title = ?, status = ? WHERE id = ?').run(project.title, project.status, project.id);
  }
}

// Deux « services » qui travaillent sur le même projet pendant la même requête HTTP
function renameService(mapper) {
  const p = mapper.find(3);
  p.title = 'Synthé web — v2';
  return p;
}
function publishService(mapper) {
  const p = mapper.find(3);
  p.status = 'active';
  return p;
}

function scenario(label, mapper, db) {
  const a = renameService(mapper);
  const b = publishService(mapper);
  mapper.save(a);
  mapper.save(b);
  console.log(label, db.prepare('SELECT title, status FROM projects WHERE id = 3').get(), 'même objet :', a === b);
}

{
  const db = openDb();
  scenario('sans IM :', new ProjectMapper(db), db); // le renommage est perdu
}
{
  const db = withQueryLog(openDb(), { print: false });
  const im = new IdentityMap();
  const mapper = new ProjectMapper(db, im);
  scenario('avec IM :', mapper, db);
  console.log('lectures de projects#3 :', db.queries.filter((q) => q.sql.startsWith('SELECT') && q.params[0] === 3).length);
  const active = mapper.findByStatus('active');
  console.log('objet réutilisé :', active.find((p) => p.id === 3) === mapper.find(3), 'taille IM :', im.size);
}
```

```
sans IM : [Object: null prototype] { title: 'Synthé web', status: 'active' } même objet : false
avec IM : [Object: null prototype] { title: 'Synthé web — v2', status: 'active' } même objet : true
lectures de projects#3 : 1
objet réutilisé : true taille IM : 4
```

Le dernier point est une vraie décision de conception : quand `findByStatus` relit une ligne déjà en mémoire, **l'objet en mémoire gagne**, même si la base a changé entre-temps. C'est le comportement de Doctrine ou d'Hibernate (il faut un `refresh` explicite pour relire). Cohérence interne contre fraîcheur : on ne peut pas avoir les deux sans règle.

</details>

---

## Kata 5 : Unit of Work complète ⭐⭐⭐

**Objectif.** Construire une Unit of Work qui :

1. utilise une Identity Map (`find(table, id)`) ;
2. détecte **seule** les entités modifiées (instantané au chargement, comparaison au `commit`) et n'écrit que les colonnes changées ;
3. accepte des entités nouvelles qui référencent d'autres entités **pas encore insérées** (`project.owner = newMember`), et insère dans le bon ordre quel que soit l'ordre d'enregistrement ;
4. supprime les enfants avant les parents ;
5. fait tout dans une transaction, et **se ferme** après un échec (comme l'`EntityManager` de Doctrine).

Métadonnées de mapping fournies :

```javascript
const MAPPING = {
  members: { columns: ['handle', 'email'], refs: {} },
  projects: { columns: ['title', 'status'], refs: { owner: 'owner_id' } },
};
const TABLE_ORDER = ['members', 'projects']; // ordre topologique : parents d'abord
```

**Vérifications attendues :** un projet modifié sans appel explicite est mis à jour ; un membre chargé et non modifié ne génère aucune écriture ; un second `commit` sans changement n'écrit rien ; un échec n'écrit rien et rend l'unité de travail inutilisable.

<details><summary>✅ Solution</summary>

```javascript
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

// Métadonnées de mapping : colonnes écrites, et références « propriété objet → colonne FK ».
const MAPPING = {
  members: { columns: ['handle', 'email'], refs: {} },
  projects: { columns: ['title', 'status'], refs: { owner: 'owner_id' } },
};
const TABLE_ORDER = ['members', 'projects']; // ordre topologique : parents d'abord

class UnitOfWork {
  #db;
  #identity = new Map(); // "table:id" → entité
  #tableOf = new Map(); // entité → table
  #snapshots = new Map(); // entité suivie → valeurs des colonnes au dernier état connu en base
  #new = new Set();
  #removed = new Set();
  #closed = false;

  constructor(db) {
    this.#db = db;
  }

  find(table, id) {
    this.#assertOpen();
    const key = `${table}:${id}`;
    if (this.#identity.has(key)) return this.#identity.get(key);
    const row = this.#db.prepare(`SELECT * FROM ${table} WHERE id = ?`).get(id);
    if (!row) return null;
    const entity = { ...row };
    this.#tableOf.set(entity, table);
    this.#identity.set(key, entity);
    this.#snapshots.set(entity, this.#values(entity));
    return entity;
  }

  registerNew(table, entity) {
    this.#assertOpen();
    this.#tableOf.set(entity, table);
    this.#new.add(entity);
    return entity;
  }

  registerRemoved(entity) {
    this.#assertOpen();
    if (this.#new.delete(entity)) return; // jamais inséré : rien à supprimer en base
    this.#removed.add(entity);
  }

  // Valeurs des colonnes d'une entité ; une référence objet est traduite en clé étrangère.
  #values(entity) {
    const { columns, refs } = MAPPING[this.#tableOf.get(entity)];
    const values = Object.fromEntries(columns.map((c) => [c, entity[c]]));
    for (const [property, column] of Object.entries(refs)) {
      values[column] = property in entity ? (entity[property]?.id ?? null) : entity[column];
    }
    return values;
  }

  #dirty() {
    const changes = [];
    for (const [entity, snapshot] of this.#snapshots) {
      if (this.#removed.has(entity)) continue;
      const current = this.#values(entity);
      const changed = Object.keys(current).filter((c) => current[c] !== snapshot[c]);
      if (changed.length > 0) changes.push({ entity, changed, current });
    }
    return changes;
  }

  #byTableOrder(entities, { reverse = false } = {}) {
    const rank = (e) => TABLE_ORDER.indexOf(this.#tableOf.get(e));
    return [...entities].sort((a, b) => (reverse ? rank(b) - rank(a) : rank(a) - rank(b)));
  }

  commit() {
    this.#assertOpen();
    const db = this.#db;
    db.exec('BEGIN');
    try {
      for (const entity of this.#byTableOrder(this.#new)) {
        const table = this.#tableOf.get(entity);
        const values = this.#values(entity);
        const columns = Object.keys(values).filter((c) => values[c] !== undefined);
        const { lastInsertRowid } = db
          .prepare(`INSERT INTO ${table} (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`)
          .run(...columns.map((c) => values[c]));
        entity.id = Number(lastInsertRowid); // les enfants insérés ensuite liront cet id
      }
      for (const { entity, changed, current } of this.#dirty()) {
        db.prepare(`UPDATE ${this.#tableOf.get(entity)} SET ${changed.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`)
          .run(...changed.map((c) => current[c]), entity.id);
      }
      for (const entity of this.#byTableOrder(this.#removed, { reverse: true })) {
        db.prepare(`DELETE FROM ${this.#tableOf.get(entity)} WHERE id = ?`).run(entity.id);
      }
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      this.#closed = true; // la mémoire ne reflète plus la base : on refuse de continuer
      throw error;
    }
    this.#afterCommit();
  }

  #afterCommit() {
    for (const entity of this.#new) {
      this.#identity.set(`${this.#tableOf.get(entity)}:${entity.id}`, entity);
      this.#snapshots.set(entity, null);
    }
    for (const entity of this.#removed) {
      this.#identity.delete(`${this.#tableOf.get(entity)}:${entity.id}`);
      this.#snapshots.delete(entity);
    }
    for (const entity of this.#snapshots.keys()) this.#snapshots.set(entity, this.#values(entity));
    this.#new.clear();
    this.#removed.clear();
  }

  #assertOpen() {
    if (this.#closed) throw new Error('Unit of Work fermée après un échec : en créer une nouvelle');
  }
}

// --- Vérifications ---
const db = withQueryLog(openDb(), { print: false });
const writes = () => db.queries.filter((q) => !q.sql.startsWith('SELECT')).map((q) => q.sql.split(' ').slice(0, 3).join(' '));

const uow = new UnitOfWork(db);
const carnet = uow.find('projects', 1);
console.log('identité :', carnet === uow.find('projects', 1), '| requêtes :', db.queries.length);

carnet.title = 'Carnet du dev (v2)';                                                          // modifié sans rien signaler
const fanzine = uow.registerNew('projects', { title: 'Fanzine', status: 'draft', owner: null }); // enregistré AVANT son propriétaire
const dora = uow.registerNew('members', { handle: 'dora', email: 'dora@atelier.test' });
fanzine.owner = dora;                                                                           // référence vers une entité sans id
uow.find('members', 4);                                                                         // chargé, non modifié : aucune écriture
uow.commit();
console.log(writes());
console.log(db.prepare("SELECT p.title, m.handle FROM projects p JOIN members m ON m.id = p.owner_id WHERE p.id IN (1, ?) ORDER BY p.id").all(fanzine.id));

const before = db.queries.length;
uow.commit();
console.log('second commit sans changement :', db.queries.length - before, 'écriture'); // 0

// Suppression : enfant avant parent
uow.registerRemoved(fanzine);
uow.registerRemoved(dora);
uow.commit();
console.log('dora supprimée :', db.prepare("SELECT count(*) n FROM members WHERE handle = 'dora'").get().n === 0);

// Échec : rien n'est écrit, l'UoW se ferme
const synth = uow.find('projects', 3);
synth.title = 'Synthé web (renommé)';
uow.registerNew('members', { handle: 'theo', email: 'doublon@atelier.test' }); // viole UNIQUE(handle)
try { uow.commit(); } catch (e) { console.log('échec :', e.message); }
console.log('titre inchangé :', db.prepare('SELECT title FROM projects WHERE id = 3').get().title);
try { uow.find('projects', 1); } catch (e) { console.log(e.message); }
```

```
identité : true | requêtes : 1
[
  'INSERT INTO members',
  'INSERT INTO projects',
  'UPDATE projects SET'
]
[
  [Object: null prototype] {
    title: 'Carnet du dev (v2)',
    handle: 'theo'
  },
  [Object: null prototype] { title: 'Fanzine', handle: 'dora' }
]
second commit sans changement : 0 écriture
dora supprimée : true
échec : UNIQUE constraint failed: members.handle
titre inchangé : Synthé web
Unit of Work fermée après un échec : en créer une nouvelle
```

Ce que ce kata rend tangible :

- **L'ordre des écritures n'est pas celui du code.** Le projet a été enregistré avant son propriétaire ; l'Unit of Work insère quand même le membre d'abord. C'est pratique, et c'est exactement ce qui rend un `flush` difficile à déboguer : les requêtes ne suivent plus le fil du code.
- **Le *dirty checking* coûte un parcours de toutes les entités suivies** à chaque `commit`. Charger 10 000 entités « pour lire » dans une Unit of Work les fait toutes comparer au `flush` : d'où les modes « lecture seule » des ORMs.
- Un vrai ORM gère en plus les cycles de clés étrangères, les collections (ajout/retrait dans une n-n), les clés composites et le verrouillage optimiste.

</details>

---

## Kata 6 : Verrouillage optimiste avec fusion ⭐⭐

**Contexte.** Plusieurs onglets éditent le même projet. On ajoute une colonne `version` :

```javascript
db.exec('ALTER TABLE projects ADD COLUMN version INTEGER NOT NULL DEFAULT 1');
```

**Consignes.**

1. Écris `updateProject(db, id, { version, changes })` : liste blanche des champs éditables (`title`, `status`), incrément de `version`, `ConflictError` (avec l'état actuel attaché) ou `NotFoundError` quand aucune ligne n'est touchée.
2. Simule deux onglets ouverts sur la même version : le second doit être refusé.
3. **Bonus** : `updateProjectWithMerge` reçoit aussi l'état de départ du formulaire (`base`). En cas de conflit, si les champs modifiés par l'utilisateur **n'ont pas changé** en base depuis `base`, réapplique sur la version courante ; sinon, refuse.

<details><summary>✅ Solution</summary>

```javascript
import { openDb } from '../fil-rouge/open-db.mjs';

class ConflictError extends Error {
  constructor(message, current) {
    super(message);
    this.current = current; // l'état actuel, pour que l'interface puisse proposer une résolution
  }
}
class NotFoundError extends Error {}

const EDITABLE = ['title', 'status'];

function updateProject(db, id, { version, changes }) {
  const fields = Object.keys(changes).filter((f) => EDITABLE.includes(f));
  if (fields.length === 0) return version;
  const { changes: touched } = db
    .prepare(
      `UPDATE projects SET ${fields.map((f) => `${f} = ?`).join(', ')}, version = version + 1
       WHERE id = ? AND version = ?`
    )
    .run(...fields.map((f) => changes[f]), id, version);
  if (touched === 1) return version + 1;

  const current = db.prepare(`SELECT id, ${EDITABLE.join(', ')}, version FROM projects WHERE id = ?`).get(id);
  if (!current) throw new NotFoundError(`projet ${id} introuvable`);
  throw new ConflictError(`projet ${id} : version ${version} attendue, ${current.version} trouvée`, { ...current });
}

// Bonus : fusion automatique quand les modifications ne se chevauchent pas.
// Le client envoie l'état sur lequel il s'est basé (base) en plus de ses changements.
function updateProjectWithMerge(db, id, { version, base, changes }) {
  try {
    return updateProject(db, id, { version, changes });
  } catch (error) {
    if (!(error instanceof ConflictError)) throw error;
    const { current } = error;
    const overlapping = Object.keys(changes).filter((f) => current[f] !== base[f]);
    if (overlapping.length > 0) throw error; // quelqu'un a modifié les mêmes champs : à l'humain de trancher
    return updateProject(db, id, { version: current.version, changes }); // peut encore échouer : c'est voulu
  }
}

const db = openDb();
db.exec('ALTER TABLE projects ADD COLUMN version INTEGER NOT NULL DEFAULT 1');
const load = (id) => db.prepare('SELECT id, title, status, version FROM projects WHERE id = ?').get(id);

// Deux onglets sur la même version
const tabA = { ...load(3) };
const tabB = { ...load(3) };
console.log(updateProject(db, 3, { version: tabA.version, changes: { title: 'Synthé web — A' } })); // 2
try {
  updateProject(db, 3, { version: tabB.version, changes: { title: 'Synthé web — B' } });
} catch (e) {
  console.log(e.constructor.name, '|', e.message, '|', e.current.title);
}

// Fusion : B ne change que le statut, A n'a changé que le titre → fusion acceptée
console.log(updateProjectWithMerge(db, 3, { version: tabB.version, base: tabB, changes: { status: 'active' } })); // 3
console.log(load(3)); // titre de A + statut de B, version 3

// Chevauchement : C part de la version 1 et modifie aussi le titre → refus
const tabC = { id: 3, title: 'Synthé web', status: 'draft', version: 1 };
try {
  updateProjectWithMerge(db, 3, { version: tabC.version, base: tabC, changes: { title: 'Synthé web — C' } });
} catch (e) { console.log('refus :', e.constructor.name); }

try { updateProject(db, 999, { version: 1, changes: { title: 'x' } }); } catch (e) { console.log(e.constructor.name); }
console.log('champ non éditable ignoré :', updateProject(db, 3, { version: 3, changes: { owner_id: 1 } }), load(3).version);
```

```
2
ConflictError | projet 3 : version 1 attendue, 2 trouvée | Synthé web — A
3
[Object: null prototype] {
  id: 3,
  title: 'Synthé web — A',
  status: 'active',
  version: 3
}
refus : ConflictError
NotFoundError
champ non éditable ignoré : 3 3
```

Deux remarques :

- La fusion compare des **valeurs**, pas des intentions : si A remet un champ à sa valeur d'origine entre-temps, la fusion croit que personne n'y a touché. Pour un éditeur de texte collaboratif, il faut d'autres outils (CRDT, voir le chapitre offline-first).
- La seconde tentative de `updateProjectWithMerge` peut échouer à son tour si un troisième onglet est passé : c'est voulu, on ne boucle pas sans fin.

</details>

---

## Kata 7 : Pagination par curseur opaque ⭐⭐⭐

**Contexte.** 5 000 projets, dont plusieurs partagent le même `created_at` (quatre par minute). On veut paginer les projets actifs, du plus récent au plus ancien.

**Consignes.**

1. Écris `listProjects(db, { status, limit, after })` qui renvoie `{ items, nextCursor }`. Le curseur est **opaque** (base64url d'un JSON `[created_at, id]`) et **validé** : c'est une entrée utilisateur.
2. Utilise l'astuce `LIMIT limit + 1` pour savoir s'il existe une page suivante sans `COUNT(*)`.
3. Affiche le plan d'exécution (`EXPLAIN QUERY PLAN`) avant et après un index adapté.
4. Parcours toutes les pages en insérant un nouveau projet en tête de liste pendant le parcours : chaque projet existant au départ doit être vu **une fois et une seule**.

<details><summary>✅ Solution</summary>

```javascript
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb({ seed: false });
db.exec("INSERT INTO members (id, handle, email) VALUES (1, 'theo', 'theo@atelier.test')");
const insert = db.prepare('INSERT INTO projects (owner_id, title, status, created_at) VALUES (1, ?, ?, ?)');
db.exec('BEGIN');
for (let i = 0; i < 5_000; i++) {
  // Volontairement : plusieurs projets partagent le même created_at (pas de 4 par minute)
  const at = new Date(Date.UTC(2025, 0, 1) + Math.floor(i / 4) * 60_000).toISOString().replace('T', ' ').slice(0, 19);
  insert.run(`Projet ${i}`, i % 2 ? 'active' : 'draft', at);
}
db.exec('COMMIT');

// --- Curseur opaque : le client ne doit ni le lire ni le fabriquer ---
const encodeCursor = (row) => Buffer.from(JSON.stringify([row.created_at, row.id])).toString('base64url');

function decodeCursor(cursor) {
  try {
    const [createdAt, id] = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (typeof createdAt !== 'string' || !Number.isInteger(id)) throw new Error();
    return { createdAt, id };
  } catch {
    throw new RangeError('curseur invalide'); // entrée non fiable → 400 côté HTTP
  }
}

function listProjects(db, { status, limit = 20, after = null }) {
  const conditions = ['status = ?'];
  const params = [status];
  if (after !== null) {
    const { createdAt, id } = decodeCursor(after);
    conditions.push('(created_at, id) < (?, ?)');
    params.push(createdAt, id);
  }
  const rows = db
    .prepare(
      `SELECT id, title, created_at FROM projects
       WHERE ${conditions.join(' AND ')}
       ORDER BY created_at DESC, id DESC
       LIMIT ?`
    )
    .all(...params, limit + 1); // une ligne de plus pour savoir s'il existe une page suivante
  const items = rows.slice(0, limit);
  return { items, nextCursor: rows.length > limit ? encodeCursor(items.at(-1)) : null };
}

// --- Plan d'exécution avant / après index ---
const plan = (sql) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all().map((r) => r.detail);
const pageSql = `SELECT id, title, created_at FROM projects
  WHERE status = 'active' AND (created_at, id) < ('2025-01-02', 100)
  ORDER BY created_at DESC, id DESC LIMIT 21`;
console.log('avant :', plan(pageSql));
db.exec('CREATE INDEX projects_status_created_id_idx ON projects (status, created_at, id)');
console.log('après :', plan(pageSql));

// --- Parcours complet : chaque ligne vue une fois et une seule, même avec des insertions en cours de route ---
const expected = db.prepare("SELECT count(*) AS n FROM projects WHERE status = 'active'").get().n;
const seen = new Set();
let cursor = null;
let pages = 0;
do {
  const { items, nextCursor } = listProjects(db, { status: 'active', limit: 100, after: cursor });
  for (const item of items) {
    if (seen.has(item.id)) throw new Error(`doublon ${item.id}`);
    seen.add(item.id);
  }
  if (pages === 3) insert.run('Arrivé pendant la lecture', 'active', '2099-01-01 00:00:00'); // en tête de liste
  cursor = nextCursor;
  pages++;
} while (cursor !== null);
console.log({ pages, seen: seen.size, expected });

try { listProjects(db, { status: 'active', after: 'pas-un-curseur' }); } catch (e) { console.log(e.name, e.message); }
```

```
avant : [ 'SCAN projects', 'USE TEMP B-TREE FOR ORDER BY' ]
après : [
  'SEARCH projects USING INDEX projects_status_created_id_idx (status=? AND created_at<?)'
]
{ pages: 25, seen: 2500, expected: 2500 }
RangeError curseur invalide
```

Points de rigueur :

- **Le départage par `id` est indispensable** : avec quatre projets par minute, un curseur sur `created_at` seul sauterait ou répéterait des lignes à chaque frontière de page.
- **L'index suit l'ordre de la requête** : égalité (`status`) puis tri (`created_at, id`). Avec `(created_at, status)`, SQLite ne pourrait pas filtrer et trier par le même parcours.
- Le projet inséré pendant le parcours n'apparaît pas : il est « avant » le curseur. C'est le comportement voulu d'un flux ; une liste qui doit le montrer recharge la première page.

</details>

---

## Kata 8 : Outbox transactionnelle ⭐⭐⭐

**Contexte.** Quand un projet est publié, il faut envoyer un e-mail aux contributeurs. L'envoyer dans la transaction est faux (il part même si la transaction est annulée) ; l'envoyer après le `COMMIT` est faux aussi (si le processus s'arrête entre les deux, l'e-mail ne part jamais).

**Consignes.**

1. Crée une table `outbox (id, topic, payload, created_at, published_at, attempts)`.
2. Écris `publishProject(db, projectId)` : passage `draft → active` **conditionnel** (compare-and-set) et insertion de l'événement, dans la même transaction.
3. Écris `relayOutbox(db, send)` : lit les événements non publiés, appelle `send`, marque `published_at` ou incrémente `attempts`.
4. Simule une panne du service d'envoi au premier essai, puis une redélivrance : le consommateur doit être **idempotent**.

<details><summary>✅ Solution</summary>

```javascript
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();
db.exec(`
  CREATE TABLE outbox (
    id           INTEGER PRIMARY KEY,
    topic        TEXT NOT NULL,
    payload      TEXT NOT NULL,                       -- JSON
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    published_at TEXT,
    attempts     INTEGER NOT NULL DEFAULT 0
  );
  CREATE INDEX outbox_pending_idx ON outbox (id) WHERE published_at IS NULL;
`);

// Écriture métier + événement : même transaction, donc tout ou rien.
function publishProject(db, projectId) {
  db.exec('BEGIN');
  try {
    const { changes } = db
      .prepare("UPDATE projects SET status = 'active' WHERE id = ? AND status = 'draft'")
      .run(projectId);
    if (changes === 0) throw new Error(`projet ${projectId} absent ou déjà publié`);
    db.prepare("INSERT INTO outbox (topic, payload) VALUES ('project.published', ?)")
      .run(JSON.stringify({ projectId }));
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

// Relais : lit les événements en attente, les envoie, les marque publiés.
// L'envoi peut réussir puis le marquage échouer : le relais garantit « au moins une fois », pas « exactement une fois ».
async function relayOutbox(db, send, { batchSize = 10, maxAttempts = 5 } = {}) {
  const pending = db
    .prepare('SELECT id, topic, payload FROM outbox WHERE published_at IS NULL AND attempts < ? ORDER BY id LIMIT ?')
    .all(maxAttempts, batchSize);
  for (const event of pending) {
    try {
      await send({ id: event.id, topic: event.topic, payload: JSON.parse(event.payload) });
      db.prepare("UPDATE outbox SET published_at = datetime('now') WHERE id = ?").run(event.id);
    } catch {
      db.prepare('UPDATE outbox SET attempts = attempts + 1 WHERE id = ?').run(event.id);
    }
  }
  return pending.length;
}

// Consommateur idempotent : il se souvient des ids déjà traités.
const processed = new Set();
const sent = [];
let failNext = true;
async function send(event) {
  if (failNext) { failNext = false; throw new Error('service e-mail indisponible'); }
  if (processed.has(event.id)) return; // doublon ignoré
  processed.add(event.id);
  sent.push(`${event.topic} #${event.payload.projectId}`);
}

publishProject(db, 3);
try { publishProject(db, 3); } catch (e) { console.log('refus :', e.message); }
console.log('événements :', db.prepare('SELECT count(*) AS n FROM outbox').get().n); // 1, pas 2

await relayOutbox(db, send); // premier envoi : échec simulé
console.log('après échec :', db.prepare('SELECT attempts, published_at FROM outbox').get());
await relayOutbox(db, send); // rejoué
console.log('envoyés :', sent, db.prepare('SELECT attempts, published_at IS NOT NULL AS done FROM outbox').get());
await send({ id: 1, topic: 'project.published', payload: { projectId: 3 } }); // redélivrance
console.log('après doublon :', sent.length);
```

```
refus : projet 3 absent ou déjà publié
événements : 1
après échec : [Object: null prototype] { attempts: 1, published_at: null }
envoyés : [ 'project.published #3' ] [Object: null prototype] { attempts: 1, done: 1 }
après doublon : 1
```

Ce qu'il faut retenir :

- L'outbox garantit **« au moins une fois »** : `send` peut réussir et le marquage échouer, l'événement repartira. D'où le consommateur idempotent (il mémorise les `id` traités). « Exactement une fois » de bout en bout n'existe pas sans coopération du destinataire.
- Avec plusieurs relais en parallèle sur PostgreSQL, on lit les événements avec `FOR UPDATE SKIP LOCKED` pour que deux relais ne prennent pas le même.
- Le passage conditionnel (`WHERE status = 'draft'`) empêche aussi de publier deux fois : sans lui, deux clics produiraient deux événements.

</details>

---

**🎯 Objectif :** katas 1, 2, 4 et 6 sans regarder les solutions ; 3, 5, 7 et 8 avec au plus un coup d'œil.
