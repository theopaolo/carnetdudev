# 🥋 Katas : SQL brut, query builder, ORM

Place tes fichiers dans `04_back-end/orm/02-sql-query-builder-orm/` : l'import du fil rouge est alors `../fil-rouge/open-db.mjs`. Exécution :

```bash
node --disable-warning=ExperimentalWarning mon-fichier.mjs
```

Chaque solution se termine par des assertions (`node:assert/strict`) : si le fichier affiche `OK`, la solution est correcte sur le jeu de données du fil rouge.

---

## Kata 1 : Le besoin en SQL brut ⭐

Écris `findMemberProjects(memberId, page = 0)` qui renvoie, pour un membre, les projets **actifs** dont il est **propriétaire ou contributeur**, avec leurs **étiquettes** (tableau trié) et leur **nombre de contributeurs**, du plus récent au plus ancien, 10 par page. Les objets renvoyés ont des propriétés en camelCase.

Contraintes :
- une seule requête SQL, paramétrée ;
- pas de `GROUP BY` sur deux jointures 1-n (explique pourquoi en commentaire) ;
- tri déterministe.

Résultats attendus : membre 1 → projets `[5, 2, 1]` ; membre 4 → `[2]` ; membre 1 page 1 → `[]`.

<details><summary>✅ Solution</summary>

```javascript
// kata1.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();
const PAGE_SIZE = 10;

// EXISTS plutôt qu'un JOIN pour le filtre : on ne veut pas dupliquer le projet.
// Sous-requêtes scalaires plutôt que JOIN contributions + JOIN project_tags + GROUP BY :
// deux jointures 1-n sur la même ligne produisent un produit cartésien (comptes multipliés).
const memberProjectsStmt = db.prepare(`
  SELECT p.id,
         p.title,
         p.created_at,
         (SELECT count(*)
            FROM contributions c
           WHERE c.project_id = p.id)                        AS contributor_count,
         (SELECT json_group_array(t.label ORDER BY t.label)
            FROM project_tags pt
            JOIN tags t ON t.id = pt.tag_id
           WHERE pt.project_id = p.id)                       AS tags
    FROM projects p
   WHERE p.status = 'active'
     AND (p.owner_id = :memberId
          OR EXISTS (SELECT 1
                       FROM contributions c
                      WHERE c.project_id = p.id
                        AND c.member_id = :memberId))
   ORDER BY p.created_at DESC, p.id DESC
   LIMIT :limit OFFSET :offset
`);

function toProjectCard(row) {
  return {
    id: row.id,
    title: row.title,
    createdAt: row.created_at,
    contributorCount: row.contributor_count,
    tags: JSON.parse(row.tags),
  };
}

export function findMemberProjects(memberId, page = 0) {
  return memberProjectsStmt
    .all({ memberId, limit: PAGE_SIZE, offset: page * PAGE_SIZE })
    .map(toProjectCard);
}

assert.deepEqual(findMemberProjects(1).map((p) => p.id), [5, 2, 1]);
assert.deepEqual(findMemberProjects(1, 1), []);
assert.deepEqual(findMemberProjects(4).map((p) => p.id), [2]);
assert.deepEqual(findMemberProjects(3).map((p) => [p.id, p.contributorCount]), [[5, 2]]);
assert.deepEqual(findMemberProjects(99), []);
console.log('kata1: OK');
```

**Pour aller plus loin** : écris la version naïve (`JOIN` + `JOIN` + `count(*)`) et compare les comptes. Tu dois obtenir 4 au lieu de 2 pour « Carnet du dev ».

</details>

---

## Kata 2 : Un *tagged template* `sql` composable ⭐⭐

Écris un module `sql.mjs` qui exporte :

- `` sql`…` `` : renvoie un fragment `{ sql, params }` où chaque valeur interpolée devient un `?`, sauf si c'est elle-même un fragment (alors son texte et ses paramètres sont fusionnés) ;
- `sql.join(fragments, separator)` ;
- `sql.in(values)` : produit `(?, ?, ?)` et refuse une liste vide ;
- `sql.id(name, allowed)` : un identifiant cité, uniquement s'il est dans la liste blanche ;
- `sql.unsafe(text)` : l'échappatoire, nommée pour faire peur ;
- `isFragment(value)`.

Exigences de sécurité :
1. un objet `{ sql: '1=1', params: [] }` venu de `JSON.parse` ne doit **pas** être reconnu comme fragment ;
2. `sql(['SELECT … ' + input])` (appel comme fonction normale) doit lever une erreur.

<details><summary>✅ Solution</summary>

```javascript
// sql.mjs
// sql`…` : un tagged template qui produit { sql, params } et compose des fragments.
const FRAGMENT = Symbol('sql.fragment');

const fragment = (text, params) => Object.freeze({ [FRAGMENT]: true, sql: text, params });
export const isFragment = (value) => value?.[FRAGMENT] === true;

export function sql(strings, ...values) {
  // Un vrai appel `sql\`…\`` reçoit un TemplateStringsArray (qui a une propriété .raw).
  // On refuse sql(['SELECT …' + input]) : ce serait de la concaténation déguisée.
  if (!Array.isArray(strings?.raw)) throw new TypeError('sql doit être utilisé comme tagged template');
  let text = strings[0];
  const params = [];
  values.forEach((value, i) => {
    if (isFragment(value)) {
      text += value.sql;            // fragment imbriqué : on fusionne son texte…
      params.push(...value.params); // …et ses paramètres, dans l'ordre
    } else {
      text += '?';                  // valeur : toujours un paramètre, jamais du texte
      params.push(value);
    }
    text += strings[i + 1];
  });
  return fragment(text, params);
}

// Assemble des fragments avec un séparateur (SQL de confiance écrit par le développeur).
sql.join = (fragments, separator = ', ') => {
  const parts = fragments.map((f) => (isFragment(f) ? f : sql`${f}`));
  return fragment(parts.map((f) => f.sql).join(separator), parts.flatMap((f) => f.params));
};

// Liste de valeurs pour IN (…). Une liste vide est refusée : `IN ()` est invalide en
// PostgreSQL, et le bon comportement (aucun résultat ? aucun filtre ?) est une décision métier.
sql.in = (values) => {
  if (values.length === 0) throw new Error('sql.in : liste vide, décide explicitement du comportement');
  return sql`(${sql.join(values.map((v) => sql`${v}`))})`;
};

// Identifiant (table, colonne) : jamais paramétrable, donc uniquement via liste blanche.
sql.id = (name, allowed) => {
  if (!allowed.includes(name)) throw new Error(`Identifiant non autorisé : ${name}`);
  return fragment(`"${name}"`, []);
};

// Échappatoire volontairement mal nommée : le texte est inséré TEL QUEL.
// À n'utiliser qu'avec du texte que le code a lui-même validé.
sql.unsafe = (text) => fragment(String(text), []);
```

```javascript
// sql.test.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';
import { sql } from './sql.mjs';

const db = openDb();
const run = (q) => db.prepare(q.sql).all(...q.params);

const evil = "' OR '1'='1";
const q1 = sql`SELECT handle FROM members WHERE handle = ${evil}`;
assert.equal(q1.sql, 'SELECT handle FROM members WHERE handle = ?');
assert.deepEqual(q1.params, [evil]);
assert.equal(run(q1).length, 0);

const memberId = 1;
const isMember = sql`(p.owner_id = ${memberId}
  OR EXISTS (SELECT 1 FROM contributions c WHERE c.project_id = p.id AND c.member_id = ${memberId}))`;
const filters = [sql`p.status = ${'active'}`, isMember];
const q2 = sql`SELECT p.id, p.title FROM projects p
  WHERE ${sql.join(filters, ' AND ')}
  ORDER BY p.created_at DESC LIMIT ${10} OFFSET ${0}`;
assert.deepEqual(q2.params, ['active', 1, 1, 10, 0]);
assert.deepEqual(run(q2).map((r) => r.id), [5, 2, 1]);

const q3 = sql`SELECT label FROM tags WHERE id IN ${sql.in([1, 3, 5])} ORDER BY label`;
assert.equal(q3.sql, 'SELECT label FROM tags WHERE id IN (?, ?, ?) ORDER BY label');
assert.deepEqual(run(q3).map((r) => r.label), ['audio', 'ethique', 'pedagogie']);
assert.throws(() => sql.in([]));

const col = sql.id('title', ['title', 'created_at']);
assert.equal(sql`SELECT ${col} FROM projects ORDER BY ${col}`.sql, 'SELECT "title" FROM projects ORDER BY "title"');
assert.throws(() => sql.id('title; DROP TABLE members', ['title']));

// Exigence 1 : un « fragment » forgé depuis du JSON reste une simple valeur
const forged = JSON.parse('{"sql":"1=1; --","params":[]}');
assert.equal(sql`SELECT * FROM members WHERE ${forged}`.sql, 'SELECT * FROM members WHERE ?');

// Exigence 2 : pas d'appel comme fonction normale
assert.throws(() => sql(['SELECT * FROM members WHERE handle = ' + evil]));
console.log('sql: OK');
```

**Pourquoi un `Symbol`** : il ne peut pas être produit par `JSON.parse`, ni par un formulaire, ni par une base de données. Seul le code qui importe `sql.mjs` peut fabriquer un fragment.

**Pourquoi `Object.freeze`** : un fragment qu'on pourrait modifier après coup (`f.sql += '…'`) redeviendrait une porte d'entrée.

</details>

---

## Kata 3 : Chasse à l'injection ⭐⭐

Chaque extrait est vulnérable. Pour chacun : (1) écris une entrée qui exploite la faille, (2) corrige. Les extraits D et G contiennent chacun un **second** piège, plus discret.

```javascript
// A — connexion
const member = db.prepare(`SELECT id, handle FROM members WHERE email = '${req.body.email}'`).get();

// B — tri depuis l'URL : /projects?sort=title
const rows = db.prepare(`SELECT * FROM projects ORDER BY ${req.query.sort}`).all();

// C — recherche
const rows = db.prepare(`SELECT title FROM projects WHERE title LIKE '%${req.query.q}%'`).all();

// D — sélection multiple : /projects?ids=1,3
const rows = db.prepare(`SELECT id FROM projects WHERE id IN (${req.query.ids})`).all();
```

```typescript
// E — Prisma (illustratif)
await prisma.$queryRawUnsafe(`SELECT * FROM projects WHERE status = '${status}'`);

// F — Knex (illustratif)
await knex('projects').whereRaw(`title = '${title}'`);

// G — un endpoint générique : /api/:resource/:id
const row = db.prepare(`SELECT * FROM ${req.params.resource} WHERE id = ?`).get(req.params.id);
```

<details><summary>✅ Solution</summary>

**Exploits possibles**

| | Entrée | Effet |
|---|---|---|
| A | `x' OR '1'='1` | renvoie le premier membre : connexion sans connaître d'e-mail |
| B | `(SELECT CASE WHEN substr((SELECT email FROM members WHERE id = 1), 1, 1) = 't' THEN title ELSE id END)` | l'ordre des résultats révèle le secret, caractère par caractère (injection « aveugle ») |
| C | `' UNION SELECT email FROM members --` | lit la table des membres |
| D | `0) UNION SELECT id FROM members --` | lit une autre table |
| E | `' OR '1'='1` | même principe que A, malgré l'ORM |
| F | `' OR '1'='1` | même principe |
| G | `members WHERE id = ? OR 1=1 --` ou `(SELECT name AS id, sql FROM sqlite_master)` | lit n'importe quelle table, y compris le catalogue du schéma (avec l'id `members`, la seconde renvoie le `CREATE TABLE`) |

**Corrections**

```javascript
// injection-fixes.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';
const db = openDb();

// A — une valeur → un paramètre
const findMemberByEmail = (email) =>
  db.prepare('SELECT id, handle FROM members WHERE email = ?').get(email);
assert.equal(findMemberByEmail("x' OR '1'='1"), undefined);
assert.equal(findMemberByEmail('ada@atelier.test').handle, 'ada');

// B — voir le kata 4 : liste blanche, jamais de paramètre pour un identifiant

// C — paramètre ET échappement des jokers
const escapeLike = (text) => text.replace(/[\\%_]/g, (ch) => `\\${ch}`);
const searchTitles = (q) =>
  db.prepare(String.raw`SELECT title FROM projects WHERE title LIKE ? ESCAPE '\' ORDER BY id`)
    .all(`%${escapeLike(q)}%`).map((r) => r.title);
assert.deepEqual(searchTitles('web'), ['Synthé web']);
assert.deepEqual(searchTitles("' OR 1=1 --"), []);
assert.deepEqual(searchTitles('_'), []); // sans escapeLike, '_' trouverait tout

// D — générer les marqueurs, valider le TEXTE de chaque identifiant, borner la taille
const MAX_IDS = 100;
function projectsByIds(rawIds) {
  const parts = String(rawIds).split(',');
  // Number('') vaut 0 : on valide le TEXTE, pas le résultat de la conversion.
  if (parts.length > MAX_IDS || !parts.every((p) => /^[1-9]\d*$/.test(p))) throw new Error('ids invalides');
  const ids = parts.map(Number);
  const placeholders = ids.map(() => '?').join(', ');
  return db.prepare(`SELECT id FROM projects WHERE id IN (${placeholders}) ORDER BY id`).all(...ids).map((r) => r.id);
}
assert.deepEqual(projectsByIds('1,3'), [1, 3]);
assert.throws(() => projectsByIds('1) OR (1=1'));
assert.throws(() => projectsByIds(''));
assert.throws(() => projectsByIds('1,,2'));

// G — l'utilisateur choisit une clé, le code choisit la table
const RESOURCES = new Map([['members', 'members'], ['projects', 'projects'], ['tags', 'tags']]);
function findById(resource, id) {
  const table = RESOURCES.get(resource);
  if (!table) throw new Error(`Ressource inconnue : ${resource}`);
  return db.prepare(`SELECT * FROM ${table} WHERE id = ?`).get(id);
}
assert.equal(findById('tags', 3).label, 'audio');
assert.throws(() => findById('members WHERE 1=1 --', 1));
console.log('injection fixes: OK');
```

```typescript
// E — Prisma (illustratif) : le tagged template paramètre la valeur
await prisma.$queryRaw`SELECT * FROM projects WHERE status = ${status}`;

// F — Knex (illustratif) : API normale, ou raw avec liaisons
await knex('projects').where('title', title);
await knex('projects').whereRaw('title = ?', [title]);
```

**Les seconds pièges**

- **D** : la conversion naïve `ids.split(',').map(Number)` accepte `''` (→ `0`) et `'1,,2'`. Et une liste non bornée peut dépasser la limite de paramètres du SGBD (65 535 pour PostgreSQL ; la limite de SQLite dépend de sa compilation) ou servir à surcharger le serveur.
- **G** : même avec une liste blanche, un endpoint générique expose **toutes les colonnes** de chaque table autorisée (`SELECT *` sur `members` renvoie les e-mails). La liste blanche protège la syntaxe, pas la confidentialité : choisis aussi les colonnes.

**Retenir** : E et F montrent qu'un ORM ou un query builder ne protège que si l'on reste dans son API paramétrée. Dès qu'on lui passe une chaîne construite par JavaScript, on est revenu au SQL brut concaténé.

</details>

---

## Kata 4 : Tri et pagination sûrs depuis une URL ⭐⭐

Écris `listProjects(query)` où `query` vient de `new URLSearchParams(location.search)` : toutes les valeurs sont des **chaînes**, potentiellement hostiles. Paramètres : `sort` (`recent` par défaut, `oldest`, `title`), `page` (≥ 1, défaut 1), `pageSize` (défaut 10, maximum 50).

Cas à couvrir :
- `sort=title;DROP TABLE members` → tri par défaut ;
- `sort=constructor` et `sort=__proto__` → tri par défaut (piège des objets littéraux) ;
- `page=-3` → page 1 ; `pageSize=9999` → 50 ;
- tri toujours **total**.

<details><summary>✅ Solution</summary>

```javascript
// kata4.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();

// La clé publique (dans l'URL) est découplée du SQL : l'utilisateur choisit un nom, jamais du texte SQL.
// Chaque tri se termine par p.id pour être total (deux projets peuvent avoir la même date).
const SORTS = new Map([
  ['recent', 'p.created_at DESC, p.id DESC'],
  ['oldest', 'p.created_at ASC, p.id ASC'],
  ['title',  'p.title ASC, p.id ASC'],
]);
const MAX_PAGE_SIZE = 50;

function toPositiveInt(value, fallback) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 ? n : fallback;
}

export function listProjects(query = {}) {
  const sortKey = SORTS.has(query.sort) ? query.sort : 'recent';
  const page = toPositiveInt(query.page, 1);
  const pageSize = Math.min(toPositiveInt(query.pageSize, 10), MAX_PAGE_SIZE);

  return db.prepare(`
    SELECT p.id, p.title, p.created_at
      FROM projects p
     ORDER BY ${SORTS.get(sortKey)}
     LIMIT ? OFFSET ?
  `).all(pageSize, (page - 1) * pageSize);
}

const params = (qs) => Object.fromEntries(new URLSearchParams(qs));
const ids = (rows) => rows.map((p) => p.id);

assert.deepEqual(listProjects(params('sort=title&pageSize=2&page=2')).map((p) => p.title),
  ['Synthé web', 'Typographie variable']);
assert.deepEqual(ids(listProjects(params('sort=title;DROP TABLE members&page=-3'))), [5, 4, 3, 2, 1]);
assert.equal(listProjects(params('sort=constructor&pageSize=9999')).length, 5);
assert.equal(listProjects(params('sort=__proto__')).length, 5);
console.log('kata4: OK');
```

**Pourquoi une `Map`** : avec `const SORTS = { recent: '…' }`, `SORTS['constructor']` vaut la fonction `Object` ; un test `if (SORTS[key])` passerait, et `${SORTS[key]}` insérerait `function Object() { [native code] }` dans la requête. Ici ça ne fait qu'une erreur de syntaxe, mais c'est le genre de détail qui transforme une liste blanche en liste trouée.

**Observe le tri par titre** : `Éthique des données` arrive **en dernier**. SQLite compare les octets UTF-8 (collation `BINARY`), et `É` est codé après toutes les lettres ASCII. Un tri « alphabétique » correct dépend de la collation du SGBD : c'est une fuite d'abstraction que ni l'ORM ni le query builder ne corrigent à ta place.

</details>

---

## Kata 5 : Un query builder immuable ⭐⭐⭐

En t'appuyant sur `sql.mjs` (kata 2), écris `query-builder.mjs` qui exporte `from(table, alias)` et permet :

```javascript
from('projects', 'p')
  .select('p.id', 'p.title')                       // identifiants ou fragments sql`…`
  .join('members', 'm', 'm.id', 'p.owner_id')      // INNER par défaut, 'LEFT' en 5ᵉ argument
  .where('p.status', '=', 'active')                // ou .where(sql`…`)
  .where('m.handle', 'IN', ['theo', 'ada'])
  .orderBy('p.created_at', 'desc')
  .limit(10)
  .offset(0)
  .toSQL();                                        // → { sql, params }
```

Exigences :
1. **immuable** : chaque méthode renvoie une nouvelle requête ; la requête de départ réutilisée ailleurs ne change pas ;
2. les identifiants sont **validés** (lettres, chiffres, `_`, au plus un `.`) puis cités ;
3. opérateurs, directions et types de jointure passent par des **listes blanches** ;
4. `limit` et `offset` refusent tout ce qui n'est pas un entier ≥ 0.

<details><summary>✅ Solution</summary>

```javascript
// query-builder.mjs
// Mini query builder immuable : chaque méthode renvoie une NOUVELLE requête.
import { sql, isFragment } from './sql.mjs';

const IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$/;
const OPERATORS = new Set(['=', '<>', '<', '<=', '>', '>=', 'LIKE', 'IN']);
const DIRECTIONS = new Set(['ASC', 'DESC']);
const JOINS = new Set(['INNER', 'LEFT']);

// Un identifiant n'est jamais un paramètre : on le valide puis on le cite.
function ident(name) {
  if (!IDENTIFIER.test(name)) throw new Error(`Identifiant invalide : ${name}`);
  return name.split('.').map((part) => `"${part}"`).join('.');
}
const raw = (text) => sql.unsafe(text); // uniquement après validation

function nonNegativeInteger(n, what) {
  if (!Number.isInteger(n) || n < 0) throw new Error(`${what} doit être un entier ≥ 0`);
  return n;
}

class Query {
  #state;

  constructor(state) {
    this.#state = Object.freeze(state);
  }

  #with(patch) {
    return new Query({ ...this.#state, ...patch });
  }

  select(...columns) {
    const parsed = columns.map((c) => (isFragment(c) ? c : raw(ident(c))));
    return this.#with({ columns: [...this.#state.columns, ...parsed] });
  }

  join(table, alias, left, right, kind = 'INNER') {
    if (!JOINS.has(kind)) throw new Error(`Jointure inconnue : ${kind}`);
    const clause = raw(`${kind} JOIN ${ident(table)} AS ${ident(alias)} ON ${ident(left)} = ${ident(right)}`);
    return this.#with({ joins: [...this.#state.joins, clause] });
  }

  // where(fragment) ou where(colonne, opérateur, valeur)
  where(columnOrFragment, operator, value) {
    let condition;
    if (isFragment(columnOrFragment)) {
      condition = sql`(${columnOrFragment})`;
    } else {
      const op = String(operator).toUpperCase();
      if (!OPERATORS.has(op)) throw new Error(`Opérateur non autorisé : ${operator}`);
      const column = raw(ident(columnOrFragment));
      condition = op === 'IN'
        ? sql`${column} IN ${sql.in(value)}`
        : sql`${column} ${raw(op)} ${value}`;
    }
    return this.#with({ wheres: [...this.#state.wheres, condition] });
  }

  orderBy(column, direction = 'ASC') {
    const dir = String(direction).toUpperCase();
    if (!DIRECTIONS.has(dir)) throw new Error(`Direction invalide : ${direction}`);
    return this.#with({ orders: [...this.#state.orders, raw(`${ident(column)} ${dir}`)] });
  }

  limit(n) {
    return this.#with({ limit: nonNegativeInteger(n, 'limit') });
  }

  offset(n) {
    return this.#with({ offset: nonNegativeInteger(n, 'offset') });
  }

  toSQL() {
    const s = this.#state;
    const columns = s.columns.length ? sql.join(s.columns) : raw('*');
    const source = raw(`${ident(s.table)}${s.alias ? ` AS ${ident(s.alias)}` : ''}`);
    const parts = [sql`SELECT ${columns} FROM ${source}`];
    if (s.joins.length) parts.push(sql.join(s.joins, ' '));
    if (s.wheres.length) parts.push(sql`WHERE ${sql.join(s.wheres, ' AND ')}`);
    if (s.orders.length) parts.push(sql`ORDER BY ${sql.join(s.orders)}`);
    if (s.limit !== null) parts.push(sql`LIMIT ${s.limit}`);
    if (s.offset !== null) parts.push(sql`OFFSET ${s.offset}`);
    const { sql: text, params } = sql.join(parts, ' ');
    return { sql: text, params };
  }
}

export const from = (table, alias = null) =>
  new Query({ table, alias, columns: [], joins: [], wheres: [], orders: [], limit: null, offset: null });
```

```javascript
// query-builder.test.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';
import { from } from './query-builder.mjs';

const db = openDb();
const run = (query) => {
  const { sql: text, params } = query.toSQL();
  return db.prepare(text).all(...params);
};

const base = from('projects', 'p').select('p.id', 'p.title');
const active = base.where('p.status', '=', 'active');
const sorted = active.orderBy('p.created_at', 'desc').limit(2);

// Immuabilité : base n'a pas bougé
assert.equal(base.toSQL().sql, 'SELECT "p"."id", "p"."title" FROM "projects" AS "p"');
assert.deepEqual(sorted.toSQL(), {
  sql: 'SELECT "p"."id", "p"."title" FROM "projects" AS "p" WHERE "p"."status" = ? ORDER BY "p"."created_at" DESC LIMIT ?',
  params: ['active', 2],
});
assert.deepEqual(run(sorted).map((r) => r.id), [5, 2]);

const withOwner = active
  .join('members', 'm', 'm.id', 'p.owner_id')
  .select('m.handle')
  .where('m.handle', 'IN', ['theo', 'ada'])
  .orderBy('p.id');
assert.deepEqual(run(withOwner).map((r) => [r.id, r.handle]), [[1, 'theo'], [2, 'ada']]);

// Refus des entrées dangereuses
assert.throws(() => base.orderBy('title; DROP TABLE members'));
assert.throws(() => base.orderBy('p.title', 'desc; DROP TABLE members'));
assert.throws(() => base.where('p.id', 'OR 1=1 --', 1));
assert.throws(() => base.limit('10; DROP TABLE members'));
console.log('query-builder: OK');
```

**Choix de conception à expliquer**

- **Champ privé `#state` + `Object.freeze`** : l'immuabilité est garantie par le langage, pas par une convention. C'est ce qui permet de partager une requête de base entre plusieurs écrans sans effet de bord.
- **`sql.unsafe` n'est appelé qu'après `ident()`** : le seul texte inséré tel quel est soit écrit dans le code, soit passé par une expression régulière stricte.
- **Ce que ce builder ne sait pas faire** : `GROUP BY`, `OR` entre conditions, sous-requêtes typées, `RETURNING`… La porte de sortie est le fragment `sql`. C'est exactement l'architecture des vrais query builders : une API pour 90 % des cas, une échappatoire sûre pour le reste.

</details>

---

## Kata 6 : L'écran de recherche, par composition ⭐⭐⭐

Avec `from()` (kata 5) et `sql` (kata 2), écris `searchProjects(db, { memberId, q, tag, sort, page, pageSize })` qui reprend le besoin du kata 1, mais où **chaque critère est optionnel** :

- `memberId` : propriétaire ou contributeur ;
- `q` : recherche littérale dans le titre (les jokers saisis ne sont pas des jokers) ;
- `tag` : le projet porte cette étiquette ;
- `sort` : `recent` (défaut) ou `title`.

Puis compare : combien de lignes aurait demandé la même fonction en concaténant des chaînes ? Où aurait-il été facile de se tromper ?

<details><summary>✅ Solution</summary>

```javascript
// search-projects.mjs
import { from } from './query-builder.mjs';
import { sql } from './sql.mjs';

const escapeLike = (text) => text.replace(/[\\%_]/g, (ch) => `\\${ch}`);

const SORTS = new Map([
  ['recent', [['p.created_at', 'DESC'], ['p.id', 'DESC']]],
  ['title',  [['p.title', 'ASC'], ['p.id', 'ASC']]],
]);

const toProjectCard = (row) => ({
  id: row.id,
  title: row.title,
  createdAt: row.created_at,
  contributorCount: row.contributor_count,
  tags: JSON.parse(row.tags),
});

// Chaque critère est optionnel : la requête se construit par ajouts successifs,
// sans jamais concaténer de texte venant de l'appelant.
export function searchProjects(db, { memberId, q, tag, sort = 'recent', page = 0, pageSize = 10 } = {}) {
  let query = from('projects', 'p')
    .select(
      'p.id', 'p.title', 'p.created_at',
      sql`(SELECT count(*) FROM contributions c WHERE c.project_id = p.id) AS contributor_count`,
      sql`(SELECT json_group_array(t.label ORDER BY t.label)
             FROM project_tags pt JOIN tags t ON t.id = pt.tag_id
            WHERE pt.project_id = p.id) AS tags`,
    )
    .where('p.status', '=', 'active');

  if (memberId !== undefined) {
    query = query.where(sql`p.owner_id = ${memberId}
      OR EXISTS (SELECT 1 FROM contributions c WHERE c.project_id = p.id AND c.member_id = ${memberId})`);
  }
  if (q) {
    query = query.where(sql`p.title LIKE ${`%${escapeLike(q)}%`} ESCAPE '\\'`);
  }
  if (tag) {
    query = query.where(sql`EXISTS (SELECT 1 FROM project_tags pt JOIN tags t ON t.id = pt.tag_id
                                   WHERE pt.project_id = p.id AND t.label = ${tag})`);
  }
  for (const [column, direction] of SORTS.get(sort) ?? SORTS.get('recent')) {
    query = query.orderBy(column, direction);
  }

  const { sql: text, params } = query.limit(pageSize).offset(page * pageSize).toSQL();
  return db.prepare(text).all(...params).map(toProjectCard);
}
```

```javascript
// search-projects.test.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';
import { searchProjects } from './search-projects.mjs';

const db = openDb({ log: true }); // affiche chaque requête générée : lis-les
const ids = (rows) => rows.map((r) => r.id);

assert.deepEqual(searchProjects(db, { memberId: 1 }), [
  { id: 5, title: 'Éthique des données', createdAt: '2026-04-20 13:00:00', contributorCount: 2, tags: ['ethique', 'pedagogie'] },
  { id: 2, title: 'Typographie variable', createdAt: '2026-02-05 16:00:00', contributorCount: 3, tags: ['typographie', 'web'] },
  { id: 1, title: 'Carnet du dev', createdAt: '2026-01-12 10:00:00', contributorCount: 2, tags: ['pedagogie', 'web'] },
]);
assert.deepEqual(ids(searchProjects(db, { memberId: 1, tag: 'web' })), [2, 1]);
assert.deepEqual(ids(searchProjects(db, { q: 'carnet' })), [1]);   // LIKE de SQLite : insensible à la casse ASCII
assert.deepEqual(ids(searchProjects(db, { q: '%' })), []);         // joker échappé
assert.deepEqual(ids(searchProjects(db, { sort: 'title' })), [1, 2, 5]);
assert.deepEqual(ids(searchProjects(db, { sort: 'title; DROP TABLE x' })), [5, 2, 1]);
assert.deepEqual(ids(searchProjects(db, { memberId: 1, pageSize: 2, page: 1 })), [1]);
assert.equal(db.queries.length, 7); // une requête par appel, quels que soient les filtres
console.log('search-projects: OK');
```

**Ce que la concaténation aurait coûté** : gérer le premier `WHERE` contre les `AND` suivants, garder le tableau de paramètres synchronisé avec l'ordre des `?` (le filtre `memberId` en ajoute deux d'un coup), penser à `ESCAPE`, ne pas oublier le second critère de tri. Chaque oubli est un bug silencieux ou une faille.

**Fuite d'abstraction repérée** : `q: 'carnet'` trouve « Carnet du dev » parce que le `LIKE` de SQLite ignore la casse des caractères ASCII. En PostgreSQL, `LIKE` est sensible à la casse (il faut `ILIKE` ou `lower()`). Le même code, une autre base, un autre résultat.

</details>

---

## Kata 7 : Choisir et justifier ⭐

Pour chaque scénario, choisis un niveau (SQL brut, SQL-first typé, query builder, ORM, ou une combinaison) et justifie en trois phrases maximum, en nommant les critères de la grille.

1. Un script ponctuel qui importe 10 000 contacts depuis un CSV dans une base PostgreSQL existante.
2. Le back-office d'une association : 12 entités liées (adhérents, cotisations, événements, inscriptions…), beaucoup de formulaires, une équipe de deux développeurs juniors.
3. L'écran de recherche d'un catalogue : 15 filtres optionnels combinables, tri au choix, pagination.
4. Un tableau de bord de rétention : cohortes mensuelles, fonctions de fenêtre, percentiles, sur PostgreSQL. L'application principale utilise déjà Prisma.

<details><summary>✅ Réponse modèle</summary>

1. **Driver + SQL brut.** Un seul `INSERT` préparé, réutilisé dans une transaction, par lots ; aucune entité à mapper, aucun graphe à sauvegarder. Ajouter un ORM ajouterait une dépendance, un schéma à déclarer et de l'hydration inutile (critères : contrôle, performance, couplage). Vérifier aussi l'outil natif : `COPY` de PostgreSQL est fait pour ça.
2. **ORM**, idéalement avec migrations intégrées, journal des requêtes actif en développement, et du temps de formation SQL prévu. Le domaine est fait de CRUD sur des entités liées : c'est le cas d'usage pour lequel l'ORM a été conçu (lisibilité, courbe d'apprentissage initiale, migrations). Le risque, c'est que l'équipe n'apprenne jamais ce que l'ORM génère : à compenser par des revues du SQL journalisé.
3. **Query builder typé** (ou l'API de requêtes de l'ORM si elle exprime tous les filtres sans échappatoire). La composabilité est le critère dominant : chaque filtre est un `if` autour d'un `.where()`. Avec du SQL brut, la concaténation conditionnelle est la principale source de bugs et de failles de ce genre d'écran.
4. **SQL écrit à la main**, dans une vue (éventuellement matérialisée) créée par migration, ou en SQL-first typé (TypedSQL dans un projet Prisma, PgTyped ou sqlc ailleurs). Les fonctions de fenêtre et percentiles sont hors du vocabulaire de l'API de l'ORM ; les reproduire par des agrégations en mémoire serait plus lent et plus faux. Coexistence assumée : Prisma pour les écritures, SQL pour cette lecture, frontière documentée dans un ADR.

**Critère de correction** : une réponse qui dit seulement « ORM parce que c'est plus simple » ou « SQL parce que c'est plus performant » est incomplète. Il faut nommer **ce qui** est plus simple ou plus performant, **pour qui**, et **ce qu'on paie** en échange.

</details>

---

**🎯 Objectif** : katas 1 à 4 sans regarder les solutions ; 5 et 6 en t'autorisant à relire les notes.
