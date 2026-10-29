# 🥋 Katas : Fondamentaux des ORMs

> Place tes fichiers `.mjs` dans `01-fondamentaux/` (ils importent `../fil-rouge/open-db.mjs`) et lance-les avec `node --disable-warning=ExperimentalWarning kata.mjs`. Les solutions utilisent `node:assert/strict` : si rien ne lève d'erreur, c'est réussi. Chaque base est en mémoire et repart des données de `seed.sql` à chaque exécution.

---

## Kata 1 : Reconnaître le pattern ⭐

Pour chaque extrait, nomme le pattern d'accès aux données (Table Data Gateway, Row Data Gateway, Active Record, Data Mapper + Unit of Work, client généré, micro-ORM) et **justifie par un indice lisible dans le code**.

```ruby
# A — Ruby on Rails
member = Member.find(2)
member.email = "ada@studio.test"
member.save!
```

```php
// B — PHP, Doctrine
$member = $entityManager->find(Member::class, 2);
$member->changeEmail('ada@studio.test');
$entityManager->flush();
```

```javascript
// C — JavaScript, code maison
const rows = projectGateway.findByStatus('active');
const total = rows.length;
projectGateway.archiveOlderThan('2026-01-01');
```

```typescript
// D — TypeScript, Prisma
const ada = await prisma.member.update({
  where: { id: 2 },
  data: { email: 'ada@studio.test' },
});
```

```csharp
// E — C#, Dapper
var member = connection.QuerySingle<Member>(
    "SELECT id, handle, email FROM members WHERE id = @Id", new { Id = 2 });
```

```python
# F (bonus) — Python, SQLAlchemy
with Session(engine) as session:
    member = session.get(Member, 2)
    member.email = "ada@studio.test"
    session.commit()
```

<details><summary>✅ Solution</summary>

| Extrait | Pattern | Indice |
|---|---|---|
| A | **Active Record** | c'est l'objet lui-même qui se sauvegarde (`member.save!`) et la classe qui cherche (`Member.find`) |
| B | **Data Mapper + Unit of Work** | l'entité ne se sauvegarde pas ; on modifie l'objet par une méthode métier, puis `flush()` écrit ce que l'`EntityManager` a détecté comme modifié |
| C | **Table Data Gateway** | un objet par table, qui renvoie des lignes brutes et expose des opérations ensemblistes (`archiveOlderThan`) ; la logique est dans le code appelant (*Transaction Script*) |
| D | **Client généré** (passerelle de table typée) | pas de classe d'entité, pas de `save()` : un appel de requête sur `prisma.member`, qui renvoie un objet JavaScript simple. Ni Active Record, ni Data Mapper au sens strict |
| E | **Micro-ORM** | le SQL est écrit à la main ; l'outil ne fait que mapper les colonnes du résultat vers les propriétés de `Member` |
| F | **Data Mapper + Unit of Work** | même logique que B : la `Session` suit les changements de `member`, `commit()` les écrit. La `Session` est aussi une Identity Map |

**À retenir** : la question discriminante est « **qui** déclenche l'écriture ? ». L'objet (Active Record), un gestionnaire qui a suivi les changements (Unit of Work), ou ton code qui appelle explicitement une requête (gateways, client généré, micro-ORM).

</details>

---

## Kata 2 : Hydrater sans perdre l'heure ⭐

Ce code a l'air juste :

```javascript
const project = { ...row, createdAt: new Date(row.created_at) };
```

1. Lance `TZ=Europe/Paris node -e "console.log(new Date('2026-04-03 09:10:00').toISOString())"`, puis la même commande avec `TZ=UTC`. Explique la différence.
2. Écris `toProject(row)` qui transforme une ligne de `projects` en objet du domaine :
   - propriétés en `camelCase` (`ownerId`, `createdAt`)
   - `createdAt` est une `Date` correcte **quel que soit le fuseau de la machine**
   - une propriété dérivée `isArchived` (non stockée en base)
3. Écris `toRow(project)`, l'opération inverse (déshydratation), qui ne doit **pas** écrire `isArchived`.
4. Vérifie que l'aller-retour `toRow(toProject(row))` redonne exactement la ligne d'origine, sous `TZ=UTC`, `TZ=Europe/Paris` et `TZ=Asia/Tokyo`.

<details><summary>✅ Solution</summary>

1. SQLite écrit `datetime('now')` en UTC, sans indicateur de fuseau. Une chaîne `'AAAA-MM-JJ HH:MM:SS'` (sans `T` ni `Z`) est interprétée par V8 comme une **heure locale** : à Paris en avril (UTC+2), on obtient `07:10Z` au lieu de `09:10Z`. Piège supplémentaire : une date seule (`'2026-04-03'`) est, elle, interprétée en UTC. Le comportement change selon le format, sans erreur.

```javascript
// kata2.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

// SQLite (datetime('now')) écrit 'YYYY-MM-DD HH:MM:SS' en UTC, sans fuseau.
const parseSqliteDate = (text) => (text === null ? null : new Date(text.replace(' ', 'T') + 'Z'));
const formatSqliteDate = (date) => date.toISOString().slice(0, 19).replace('T', ' ');

function toProject(row) {
  return {
    id: row.id,
    ownerId: row.owner_id,
    title: row.title,
    status: row.status,
    isArchived: row.status === 'archived', // propriété dérivée : n'existe pas en base
    createdAt: parseSqliteDate(row.created_at),
  };
}

function toRow(project) {
  return {
    id: project.id,
    owner_id: project.ownerId,
    title: project.title,
    status: project.status,
    created_at: formatSqliteDate(project.createdAt),
    // isArchived n'est pas persisté : il se recalcule depuis status
  };
}

const db = openDb();
const row = db.prepare('SELECT * FROM projects WHERE id = ?').get(4);
const project = toProject(row);

assert.ok(project.createdAt instanceof Date);
assert.equal(project.createdAt.toISOString(), '2026-04-03T09:10:00.000Z');
assert.equal(project.isArchived, true);
assert.deepEqual(toRow(project), { ...row }); // aller-retour sans perte
console.log('kata 2 OK', process.env.TZ ?? '(TZ système)');
```

```bash
for tz in UTC Europe/Paris Asia/Tokyo; do TZ=$tz node --disable-warning=ExperimentalWarning kata2.mjs; done
```

`{ ...row }` est nécessaire : `node:sqlite` renvoie des objets sans prototype (`[Object: null prototype]`), et `deepEqual` strict compare aussi les prototypes.

**À retenir** : l'hydratation n'est pas une copie de champs. C'est une **conversion de représentation** (noms, types, fuseaux, valeurs dérivées), et c'est exactement le travail que fait un ORM pour chaque ligne lue. Un ORM bien configuré règle le fuseau une fois pour toutes ; un mapping écrit à la main doit le faire explicitement.

</details>

---

## Kata 3 : Un mini Active Record ⭐⭐

Écris une classe `Member` de type Active Record sur la table `members` :

- `Member.find(id)` → une instance, ou `null` si absente
- `Member.all()` → toutes les instances, triées par `id`
- `member.isPersisted` (getter) → `true` si l'objet existe en base
- `member.save()` → `INSERT` si nouveau (et récupère `id` et `created_at` calculés par la base), `UPDATE` sinon ; renvoie `this`
- `member.delete()` → supprime la ligne et repasse l'objet à l'état « non persisté »

Contrainte : une seule connexion, partagée en propriété statique `Member.db`.

<details><summary>✅ Solution</summary>

```javascript
// kata3.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

class Member {
  static db;

  constructor({ id = null, handle, email, created_at = null }) {
    Object.assign(this, { id, handle, email, created_at });
  }

  static find(id) {
    const row = Member.db.prepare('SELECT * FROM members WHERE id = ?').get(id);
    return row ? new Member(row) : null;
  }

  static all() {
    return Member.db.prepare('SELECT * FROM members ORDER BY id').all().map((row) => new Member(row));
  }

  get isPersisted() {
    return this.id !== null;
  }

  save() {
    if (this.isPersisted) {
      Member.db
        .prepare('UPDATE members SET handle = ?, email = ? WHERE id = ?')
        .run(this.handle, this.email, this.id);
    } else {
      const row = Member.db
        .prepare('INSERT INTO members (handle, email) VALUES (?, ?) RETURNING id, created_at')
        .get(this.handle, this.email);
      Object.assign(this, row);
    }
    return this;
  }

  delete() {
    if (!this.isPersisted) return;
    Member.db.prepare('DELETE FROM members WHERE id = ?').run(this.id);
    this.id = null;
  }
}

Member.db = openDb();

assert.equal(Member.find(99), null);
assert.equal(Member.all().length, 4);

const dora = new Member({ handle: 'dora', email: 'dora@atelier.test' });
assert.equal(dora.isPersisted, false);
dora.save();
assert.equal(dora.isPersisted, true);
assert.match(dora.created_at, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);

dora.email = 'dora@studio.test';
dora.save();
assert.equal(Member.find(dora.id).email, 'dora@studio.test');

const doraId = dora.id;
dora.delete();
assert.equal(dora.isPersisted, false);
assert.equal(Member.find(doraId), null);
console.log('kata 3 OK');
```

**Questions pour aller plus loin**

- `save()` réécrit toutes les colonnes, même inchangées. Que faudrait-il ajouter pour n'écrire que les champs modifiés ? (C'est le *dirty checking*, [module 06](../06-concepts-avances/notes.md).)
- Que se passe-t-il si deux instances de `Member` pour l'id 2 sont modifiées puis sauvegardées ? Laquelle gagne, et le sait-on ?
- Essaie `Member.find(1).delete()`. Pourquoi l'erreur `FOREIGN KEY constraint failed` est-elle une bonne nouvelle ?

</details>

---

## Kata 4 : Les trois formes d'association ⭐⭐

Dans le même fichier que le kata 3, ajoute une classe `Project` (Active Record) et des méthodes de relation :

- `project.owner()` → le `Member` propriétaire (association n-1)
- `project.tags()` → la liste triée des libellés (n-n pure via `project_tags`)
- `project.contributors()` → `[{ member, role, since }]`, trié par `since` (n-n porteuse via `contributions`)
- `member.projects()` → les `Project` dont il est propriétaire (1-n, le sens inverse de `owner()`)

Puis active le journal (`openDb({ log: true })`) et compte les requêtes exécutées.

<details><summary>✅ Solution</summary>

```javascript
// À ajouter à kata3.mjs, JUSTE APRÈS la classe Member
// (une classe n'est pas « remontée » comme une fonction : il faut la déclarer avant `Project.db = db`)

// Dans la classe Member, ajoute :
//   projects() {
//     return Member.db
//       .prepare('SELECT * FROM projects WHERE owner_id = ? ORDER BY id')
//       .all(this.id)
//       .map((row) => new Project(row));
//   }

class Project {
  static db;

  constructor({ id = null, owner_id, title, status = 'draft', created_at = null }) {
    Object.assign(this, { id, owner_id, title, status, created_at });
  }

  static find(id) {
    const row = Project.db.prepare('SELECT * FROM projects WHERE id = ?').get(id);
    return row ? new Project(row) : null;
  }

  // n-1 : la clé étrangère est de MON côté
  owner() {
    return Member.find(this.owner_id);
  }

  // n-n pure : la table de jointure disparaît du modèle objet
  tags() {
    return Project.db
      .prepare(`SELECT t.label FROM tags t
                JOIN project_tags pt ON pt.tag_id = t.id
                WHERE pt.project_id = ? ORDER BY t.label`)
      .all(this.id)
      .map((row) => row.label);
  }

  // n-n porteuse : le rôle n'appartient ni au membre ni au projet, il faut le rendre visible
  contributors() {
    return Project.db
      .prepare(`SELECT m.*, c.role, c.since FROM contributions c
                JOIN members m ON m.id = c.member_id
                WHERE c.project_id = ? ORDER BY c.since`)
      .all(this.id)
      .map(({ role, since, ...member }) => ({ member: new Member(member), role, since }));
  }
}

// Remplace `Member.db = openDb();` par :
const db = openDb({ log: true });
Member.db = db;
Project.db = db;

// Tests
db.queries.length = 0;
const typo = Project.find(2);
assert.equal(typo.owner().handle, 'ada');
assert.deepEqual(typo.tags(), ['typographie', 'web']);
assert.deepEqual(
  typo.contributors().map(({ member, role }) => `${member.handle}:${role}`),
  ['ada:auteur', 'theo:dev', 'chloe:design'],
);
assert.deepEqual(Member.find(1).projects().map((p) => p.title), ['Carnet du dev', 'Synthé web']);
console.log(`kata 4 OK — ${db.queries.length} requêtes`); // 6
```

**À retenir**

- `contributors()` ne peut pas renvoyer de simples `Member` : on perdrait le rôle. Une association porteuse d'attributs **devient une entité** dans le modèle objet, que l'ORM le dise ou non.
- Chaque méthode de relation est une requête. Appelle `owner()` dans une boucle sur 100 projets et tu obtiens 101 requêtes : c'est le problème N+1, que le [module 06](../06-concepts-avances/notes.md) apprend à corriger.
- `owner()` et `projects()` sont **la même clé étrangère** lue dans deux sens. En base, rien à synchroniser ; en mémoire, deux références distinctes.

</details>

---

## Kata 5 : Un Data Mapper avec des règles métier ⭐⭐

Écris :

1. Une entité `Project` **pure** (aucun import de base) qui protège son cycle de vie :
   - `draft → active`, `draft → archived`, `active → archived` ; `archived` est terminal
   - `activate()`, `archive()` lèvent une erreur sur une transition interdite
   - `rename(title)` refuse un titre vide et refuse tout renommage d'un projet archivé
   - le titre est nettoyé des espaces en trop
2. Un `ProjectMapper` : `find(id)`, `findByOwner(ownerId)`, `insert(project)`, `update(project)`, avec conversion `created_at` ↔ `createdAt: Date`.
3. Des tests des règles **sans base**, puis des tests du mapper **avec** la base.

<details><summary>✅ Solution</summary>

```javascript
// kata5.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

// ---------- Domaine ----------
const TRANSITIONS = {
  draft: ['active', 'archived'],
  active: ['archived'],
  archived: [], // état terminal
};

class Project {
  constructor({ id = null, ownerId, title, status = 'draft', createdAt = new Date() }) {
    if (!title?.trim()) throw new Error('titre obligatoire');
    Object.assign(this, { id, ownerId, title: title.trim(), status, createdAt });
  }
  #moveTo(next) {
    if (!TRANSITIONS[this.status].includes(next)) {
      throw new Error(`transition interdite : ${this.status} → ${next}`);
    }
    this.status = next;
  }
  activate() {
    this.#moveTo('active');
  }
  archive() {
    this.#moveTo('archived');
  }
  rename(title) {
    if (this.status === 'archived') throw new Error('projet archivé : lecture seule');
    if (!title?.trim()) throw new Error('titre obligatoire');
    this.title = title.trim();
  }
}

// ---------- Persistance ----------
const parseSqliteDate = (text) => new Date(text.replace(' ', 'T') + 'Z');
const formatSqliteDate = (date) => date.toISOString().slice(0, 19).replace('T', ' ');

class ProjectMapper {
  constructor(db) {
    this.db = db;
  }
  find(id) {
    const row = this.db.prepare('SELECT * FROM projects WHERE id = ?').get(id);
    return row ? this.#toEntity(row) : null;
  }
  findByOwner(ownerId) {
    return this.db
      .prepare('SELECT * FROM projects WHERE owner_id = ? ORDER BY id')
      .all(ownerId)
      .map((row) => this.#toEntity(row));
  }
  insert(project) {
    const { id } = this.db
      .prepare('INSERT INTO projects (owner_id, title, status, created_at) VALUES (?, ?, ?, ?) RETURNING id')
      .get(project.ownerId, project.title, project.status, formatSqliteDate(project.createdAt));
    project.id = id;
  }
  update(project) {
    this.db
      .prepare('UPDATE projects SET owner_id = ?, title = ?, status = ? WHERE id = ?')
      .run(project.ownerId, project.title, project.status, project.id);
  }
  #toEntity(row) {
    return new Project({
      id: row.id,
      ownerId: row.owner_id,
      title: row.title,
      status: row.status,
      createdAt: parseSqliteDate(row.created_at),
    });
  }
}

// 1. Les règles métier se testent SANS base
const p = new Project({ ownerId: 1, title: '  Fanzine  ' });
assert.equal(p.title, 'Fanzine');
p.activate();
p.archive();
assert.throws(() => p.activate(), /archived → active/);
assert.throws(() => p.rename('Autre'), /lecture seule/);

// 2. La persistance se teste avec la base
const projects = new ProjectMapper(openDb());
const synth = projects.find(3);
assert.ok(synth instanceof Project);
synth.activate();
projects.update(synth);
assert.equal(projects.find(3).status, 'active');

const zine = new Project({ ownerId: 2, title: 'Fanzine' });
projects.insert(zine);
assert.deepEqual(projects.findByOwner(2).map((x) => x.title), ['Typographie variable', 'Fanzine']);
console.log('kata 5 OK');
```

**À retenir**

- La table a déjà une contrainte `CHECK (status IN (...))`. Elle garantit que la **valeur** est valide, pas que la **transition** l'est : passer de `archived` à `active` respecte le `CHECK`. Les invariants dynamiques vivent dans le domaine ; les invariants statiques peuvent (et devraient) aussi vivre en base.
- `#toEntity` passe par le constructeur, donc revalide le titre à chaque lecture. Doctrine, lui, contourne le constructeur à l'hydratation. Les deux choix se défendent : revalider détecte des données corrompues, mais empêche de charger une ligne devenue invalide après un changement de règle.

</details>

---

## Kata 6 : Metadata Mapping, ou comment naît un ORM ⭐⭐⭐

Les katas 3 et 5 répètent le même SQL pour chaque table. Écris une classe de base générique `Model` qui produit le SQL **à partir de métadonnées déclarées** par chaque sous-classe :

```javascript
class Member extends Model {
  static table = 'members';
  static fields = {
    id: { column: 'id' },
    handle: { column: 'handle' },
    email: { column: 'email' },
    createdAt: { column: 'created_at', fromDb: parseSqliteDate, toDb: formatSqliteDate, readOnly: true },
  };
}
```

`Model` doit fournir : `find(id)`, `findBy(criteria, { orderBy })` (critères par **nom de propriété**, pas de colonne), `save()` (insertion ou mise à jour, en relisant les valeurs calculées par la base) et `delete()`.

Contrainte de sécurité : un nom de propriété inconnu des métadonnées doit lever une erreur. Explique pourquoi on ne peut pas simplement passer le nom de colonne en paramètre `?`.

<details><summary>💡 Indice</summary>

- Les paramètres liés (`?`) ne remplacent que des **valeurs**, jamais des identifiants (noms de tables, de colonnes) ni des mots-clés (`ASC`, `DESC`).
- Dans une méthode statique héritée, `this` désigne la sous-classe (`Member`, `Project`) : `this.table`, `this.fields`, `new this()` fonctionnent.
- Piège : un champ privé statique (`static #x`) appelé via `this.#x` depuis une sous-classe lève une `TypeError`. Utilise une fonction de module.

</details>

<details><summary>✅ Solution</summary>

```javascript
// kata6.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

const parseSqliteDate = (text) => new Date(text.replace(' ', 'T') + 'Z');
const formatSqliteDate = (date) => date.toISOString().slice(0, 19).replace('T', ' ');

// Les identifiants (tables, colonnes) ne peuvent PAS être passés en paramètre « ? » :
// on ne les accepte que s'ils viennent des métadonnées, jamais de l'appelant.
function columnOf(Model, prop) {
  const field = Model.fields[prop];
  if (!field) throw new Error(`champ inconnu : ${Model.name}.${prop}`);
  return field.column;
}
const quote = (identifier) => `"${identifier}"`;

class Model {
  static db;
  static table;   // défini par chaque sous-classe
  static fields;  // { propriété: { column, fromDb?, toDb?, readOnly? } }

  static fromRow(row) {
    const entity = new this();
    for (const [prop, { column, fromDb }] of Object.entries(this.fields)) {
      entity[prop] = fromDb ? fromDb(row[column]) : row[column];
    }
    return entity;
  }

  static toDb(prop, value) {
    const { toDb } = this.fields[prop];
    return toDb && value != null ? toDb(value) : value;
  }

  static findBy(criteria = {}, { orderBy = 'id' } = {}) {
    const props = Object.keys(criteria);
    const where = props.length
      ? ` WHERE ${props.map((p) => `${quote(columnOf(this, p))} = ?`).join(' AND ')}`
      : '';
    const sql = `SELECT * FROM ${quote(this.table)}${where} ORDER BY ${quote(columnOf(this, orderBy))}`;
    const params = props.map((p) => this.toDb(p, criteria[p]));
    return this.db.prepare(sql).all(...params).map((row) => this.fromRow(row));
  }

  static find(id) {
    return this.findBy({ id })[0] ?? null;
  }

  save() {
    const Model = this.constructor;
    const writable = Object.keys(Model.fields).filter(
      (p) => p !== 'id' && !Model.fields[p].readOnly && this[p] !== undefined,
    );
    const columns = writable.map((p) => quote(columnOf(Model, p)));
    const params = writable.map((p) => Model.toDb(p, this[p]));
    const row =
      this.id == null
        ? Model.db
            .prepare(`INSERT INTO ${quote(Model.table)} (${columns.join(', ')})
                      VALUES (${columns.map(() => '?').join(', ')}) RETURNING *`)
            .get(...params)
        : Model.db
            .prepare(`UPDATE ${quote(Model.table)} SET ${columns.map((c) => `${c} = ?`).join(', ')}
                      WHERE "id" = ? RETURNING *`)
            .get(...params, this.id);
    Object.assign(this, Model.fromRow(row)); // récupère les valeurs calculées par la base (id, défauts)
    return this;
  }

  delete() {
    const Model = this.constructor;
    Model.db.prepare(`DELETE FROM ${quote(Model.table)} WHERE "id" = ?`).run(this.id);
    this.id = null;
  }
}

// ---------- Les métadonnées de mapping : la seule chose à écrire par entité ----------
class Member extends Model {
  static table = 'members';
  static fields = {
    id: { column: 'id' },
    handle: { column: 'handle' },
    email: { column: 'email' },
    createdAt: { column: 'created_at', fromDb: parseSqliteDate, toDb: formatSqliteDate, readOnly: true },
  };
}

class Project extends Model {
  static table = 'projects';
  static fields = {
    id: { column: 'id' },
    ownerId: { column: 'owner_id' },
    title: { column: 'title' },
    status: { column: 'status' },
    createdAt: { column: 'created_at', fromDb: parseSqliteDate, toDb: formatSqliteDate, readOnly: true },
  };
}

Model.db = openDb({ log: true });

assert.equal(Member.find(2).handle, 'ada');
assert.ok(Member.find(2).createdAt instanceof Date);
assert.deepEqual(Project.findBy({ ownerId: 1, status: 'active' }).map((p) => p.title), ['Carnet du dev']);
assert.deepEqual(Project.findBy({}, { orderBy: 'title' }).map((p) => p.id), [4, 1, 3, 2, 5]);

const zine = Object.assign(new Project(), { ownerId: 3, title: 'Fanzine' });
zine.save();
assert.equal(zine.status, 'draft');          // valeur par défaut renvoyée par la base
assert.ok(zine.createdAt instanceof Date);
zine.status = 'active';
zine.save();
assert.equal(Project.find(zine.id).status, 'active');
zine.delete();
assert.equal(Project.find(6), null);

assert.throws(() => Member.findBy({ 'handle" = handle OR 1=1 --': 'x' }), /champ inconnu/);
console.log('kata 6 OK');
```

**À retenir**

- Avec ~80 lignes génériques, chaque nouvelle entité ne coûte plus que ses métadonnées. C'est le pattern **Metadata Mapping** (Fowler), et le cœur de tout ORM : décorateurs TypeORM, attributs Doctrine, `schema.prisma` sont des façons de fournir ces métadonnées.
- La liste blanche des identifiants n'est pas optionnelle. Sans elle, `findBy(req.query)` laisserait l'appelant injecter du SQL **dans un nom de colonne**, là où aucun paramètre lié ne protège.
- Le tri `[4, 1, 3, 2, 5]` place « Éthique des données » après « Typographie variable » : SQLite compare les octets UTF-8 (collation `BINARY`), et `É` vient après toutes les lettres ASCII. L'ORM ne masque pas les collations.
- Ce qui manque encore pour un vrai ORM : relations déclarées, Identity Map, suivi des changements, transactions, dialectes multiples. Chacun de ces ajouts double la complexité. C'est l'argument de Fowler contre « l'ORM maison ».

</details>

---

## Kata 7 : D'Active Record à Data Mapper, et ce que ça rend testable ⭐⭐⭐

Voici un service écrit avec des Active Records :

```javascript
// kata7-before.mjs
import { openDb } from '../fil-rouge/open-db.mjs';

class Project {
  static db;
  constructor(row) {
    Object.assign(this, row);
  }
  static find(id) {
    const row = Project.db.prepare('SELECT * FROM projects WHERE id = ?').get(id);
    return row ? new Project(row) : null;
  }
  save() {
    Project.db.prepare('UPDATE projects SET owner_id = ?, status = ? WHERE id = ?').run(this.owner_id, this.status, this.id);
  }
}

export function transferOwnership(projectId, newOwnerId) {
  const project = Project.find(projectId);
  if (!project) throw new Error('projet introuvable');
  if (project.status === 'archived') throw new Error('projet archivé');
  const contributes = Project.db
    .prepare('SELECT 1 FROM contributions WHERE project_id = ? AND member_id = ?')
    .get(projectId, newOwnerId);
  if (!contributes) throw new Error('le nouveau propriétaire doit déjà contribuer au projet');
  project.owner_id = newOwnerId;
  project.save();
}

Project.db = openDb();
transferOwnership(2, 4);              // chloe contribue à « Typographie variable »
console.log(Project.find(2).owner_id); // 4
```

1. Liste ce qu'il faut mettre en place pour tester la règle « on ne transfère pas un projet archivé ».
2. Refactore en trois couches :
   - une entité `Project` pure, qui porte la règle dans une méthode `transferTo(newOwnerId)`
   - un service `transferOwnership(projects, projectId, newOwnerId)` qui reçoit un dépôt (*repository*) `{ findById, save }`
   - deux dépôts : `SqliteProjectRepository` et `InMemoryProjectRepository`
3. Écris trois niveaux de tests : la règle seule, le service avec le dépôt en mémoire, et un test d'intégration avec SQLite.
4. Dresse le bilan : qu'est-ce qui est devenu testable, qu'est-ce qui a coûté ?

<details><summary>✅ Solution</summary>

1. **Avant** : pour tester une seule condition, il faut une base, le schéma complet, des membres, un projet archivé, des contributions (les clés étrangères l'exigent), et assigner la connexion statique `Project.db`. La règle est inaccessible sans SQL.

```javascript
// kata7-after.mjs
import assert from 'node:assert/strict';
import { openDb } from '../fil-rouge/open-db.mjs';

// ---------- Domaine : la règle vit dans l'entité ----------
class Project {
  constructor({ id, ownerId, status, contributorIds = [] }) {
    Object.assign(this, { id, ownerId, status, contributorIds: new Set(contributorIds) });
  }
  transferTo(newOwnerId) {
    if (this.status === 'archived') throw new Error('projet archivé');
    if (!this.contributorIds.has(newOwnerId)) {
      throw new Error('le nouveau propriétaire doit déjà contribuer au projet');
    }
    this.ownerId = newOwnerId;
  }
}

// ---------- Service applicatif : orchestre, ne connaît pas SQL ----------
function transferOwnership(projects, projectId, newOwnerId) {
  const project = projects.findById(projectId);
  if (!project) throw new Error('projet introuvable');
  project.transferTo(newOwnerId);
  projects.save(project);
}

// ---------- Deux implémentations du même contrat { findById, save } ----------
class SqliteProjectRepository {
  constructor(db) {
    this.db = db;
  }
  findById(id) {
    const row = this.db.prepare('SELECT id, owner_id, status FROM projects WHERE id = ?').get(id);
    if (!row) return null;
    const contributorIds = this.db
      .prepare('SELECT member_id FROM contributions WHERE project_id = ?')
      .all(id)
      .map((r) => r.member_id);
    return new Project({ id: row.id, ownerId: row.owner_id, status: row.status, contributorIds });
  }
  save(project) {
    this.db.prepare('UPDATE projects SET owner_id = ?, status = ? WHERE id = ?').run(project.ownerId, project.status, project.id);
  }
}

class InMemoryProjectRepository {
  #items = new Map();
  constructor(projects = []) {
    for (const p of projects) this.#items.set(p.id, p);
  }
  findById(id) {
    return this.#items.get(id) ?? null;
  }
  save(project) {
    this.#items.set(project.id, project);
  }
}

// 1. Test unitaire de la règle : ni base, ni dépôt
const archived = new Project({ id: 1, ownerId: 1, status: 'archived', contributorIds: [2] });
assert.throws(() => archived.transferTo(2), /archivé/);
const active = new Project({ id: 2, ownerId: 1, status: 'active', contributorIds: [2] });
assert.throws(() => active.transferTo(3), /déjà contribuer/);
active.transferTo(2);
assert.equal(active.ownerId, 2);

// 2. Test du service avec un faux dépôt en mémoire (rapide, déterministe)
const repo = new InMemoryProjectRepository([new Project({ id: 7, ownerId: 1, status: 'draft', contributorIds: [1, 5] })]);
transferOwnership(repo, 7, 5);
assert.equal(repo.findById(7).ownerId, 5);
assert.throws(() => transferOwnership(repo, 99, 1), /introuvable/);

// 3. Test d'intégration, une seule fois, contre la vraie base
const sqlite = new SqliteProjectRepository(openDb());
transferOwnership(sqlite, 2, 4);
assert.equal(sqlite.findById(2).ownerId, 4);
assert.throws(() => transferOwnership(sqlite, 4, 1), /archivé/);
console.log('kata 7 OK');
```

**Bilan**

| | Avant (Active Record) | Après (Data Mapper + repository) |
|---|---|---|
| Tester la règle « archivé » | base + schéma + données + connexion statique | `new Project({...})`, une ligne |
| Tester l'orchestration du service | idem | faux dépôt en mémoire, aucune I/O |
| Tester le SQL | mêlé à la règle | isolé dans `SqliteProjectRepository`, testé à part |
| Lignes de code | ~25 | ~65 |
| Décision de conception ajoutée | aucune | *qu'est-ce qu'un projet chargé contient ?* (ici : ses `contributorIds`) |

Le dernier point est le plus important. En passant au Data Mapper, il a fallu décider que la liste des contributeurs **fait partie** du projet chargé, pour que la règle puisse être vérifiée en mémoire. C'est la notion d'**agrégat** d'Evans : la frontière de ce qu'on charge et sauvegarde ensemble pour protéger un invariant.

Les limites, honnêtement :

- Le faux dépôt peut diverger du vrai (il ne vérifie aucune clé étrangère). Le test d'intégration reste indispensable, mais il n'en faut qu'un par comportement de persistance, pas un par règle.
- Entre `findById` et `save`, un autre processus peut ajouter ou retirer une contribution : la règle a été vérifiée sur une copie. Il faudrait une transaction ou un verrouillage ([module 06](../06-concepts-avances/notes.md)).
- Pour un domaine aussi simple, ce refactoring est discutable. Il se justifie quand les règles se multiplient.

</details>

---

**Progression** : katas 1-2 (compréhension) → 3-5 (implémentation des patterns) → 6-7 (conception). Si le kata 6 te paraît évident, tu as compris ce qu'un ORM fait à ta place.
