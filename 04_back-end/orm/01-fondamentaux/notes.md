# 🧩 Fondamentaux : qu'est-ce qu'un ORM ?

## 📋 Vue d'ensemble

Un ORM est une **couche de traduction** entre deux façons incompatibles de penser les données : le graphe d'objets de ton programme et les relations (tables) de ta base. Ce module pose les bases : le problème que l'ORM tente de résoudre, ce qu'il fait concrètement, les patterns dont il est fait, et un bilan argumenté de ce qu'il apporte et de ce qu'il coûte.

### 🎯 Objectifs

- Définir un ORM précisément, et dire ce qu'il n'est pas
- Expliquer l'*object-relational impedance mismatch* selon ses différentes dimensions
- Décrire les opérations qu'un ORM effectue à ta place (mapping, génération SQL, hydratation…)
- Implémenter en JavaScript natif les quatre patterns d'accès aux données de Fowler
- Comparer Active Record et Data Mapper sur des critères explicites
- Situer les ORMs courants (JS, PHP, Python, Ruby, Java, .NET) dans ces familles
- Argumenter pour ou contre un ORM dans un projet donné

> **Exécuter les exemples** : place les fichiers `.mjs` dans `01-fondamentaux/` (l'import `../fil-rouge/open-db.mjs` en dépend), puis `node --disable-warning=ExperimentalWarning fichier.mjs`. Tous les exemples marqués « exécutable » ont été testés avec Node 22.

---

## 📖 Définition

> Un **ORM** (*Object-Relational Mapper*) est une bibliothèque qui maintient une **correspondance déclarée** (les *métadonnées de mapping*) entre des types de ton langage et un schéma relationnel, et qui s'en sert pour **traduire automatiquement dans les deux sens** : des opérations sur des objets vers du SQL, et des lignes de résultat vers des objets.

Les trois lettres disent l'essentiel :

- **O**bject : le modèle de ton code (classes, références, collections)
- **R**elational : le modèle de la base (relations, clés, contraintes, requêtes ensemblistes)
- **M**apping : la correspondance entre les deux. C'est là que se trouve toute la difficulté.

### Ce qu'un ORM n'est pas

| Ce n'est pas… | Parce que… |
|---|---|
| une base de données | il ne stocke rien : il parle à un SGBD (PostgreSQL, MySQL, SQLite…) |
| un driver | le driver (`pg`, `mysql2`, `node:sqlite`) ouvre la connexion et transporte le SQL ; l'ORM s'appuie dessus |
| un query builder | un query builder construit du SQL ; un ORM fait cela **et** mappe les résultats vers un modèle objet. La plupart des ORMs contiennent un query builder (voir [module 02](../02-sql-query-builder-orm/notes.md)) |
| un substitut au SQL | il génère du SQL ; pour savoir si ce SQL est bon, il faut savoir lire du SQL |

### Où il se place

```
 Ton code (objets métier)
        │   member.rename('ada-l'); repo.save(member)
        ▼
 ┌─────────────────────────┐
 │ ORM                     │  métadonnées de mapping, suivi des changements,
 │  └─ query builder       │  génération SQL, hydratation des résultats
 └─────────────────────────┘
        │   UPDATE members SET handle = ? WHERE id = ?   ['ada-l', 2]
        ▼
 Driver (pg, mysql2, node:sqlite)  ── protocole réseau / appel natif ──►  SGBD
```

---

## 🤔 Le problème : l'*impedance mismatch*

Le terme vient de l'électronique : deux circuits d'impédances différentes se transmettent mal le signal. Ici, les deux « circuits » reposent sur des fondations différentes :

- **Le modèle relationnel** (Codd, 1970) repose sur la théorie des ensembles et la logique des prédicats : une relation est un **ensemble** de tuples, sans ordre, sans identité autre que les valeurs, manipulé par des opérations déclaratives (sélection, projection, jointure).
- **Le modèle objet** repose sur l'**identité** (un objet existe indépendamment de ses valeurs), l'**état encapsulé**, le **comportement** et des **références** navigables d'objet en objet.

Kleppmann (*Designing Data-Intensive Applications*, ch. 2) illustre ce décalage avec un profil de CV : naturel comme un document imbriqué en mémoire, il éclate en une demi-douzaine de tables reliées par des clés étrangères. Ireland, Bowers, Newton et Waugh (« A Classification of Object-Relational Impedance Mismatch », 2009) en proposent une classification systématique. Voici les dimensions qui te concerneront en pratique.

| Dimension | Côté objet | Côté relationnel |
|---|---|---|
| Identité | référence mémoire (`===`) | valeur de clé primaire |
| Granularité | beaucoup de petits objets (valeurs, composants) | peu de tables larges |
| Héritage | `class Video extends Media` | aucun équivalent natif |
| Associations | références, dans un sens donné | clés étrangères, interrogeables dans les deux sens |
| Navigation | parcours de graphe, objet par objet | opérations sur des ensembles |
| Types et absence | `Date`, `boolean`, `undefined`, `null` | types SQL, `NULL` et logique à trois valeurs |
| Encapsulation | état privé, invariants dans les méthodes | toutes les colonnes visibles, contraintes déclaratives |
| Fraîcheur | une copie en mémoire, peut-être périmée | l'état partagé et à jour |

### 1. Identité : trois notions qui ne coïncident pas

En JavaScript, deux objets sont **identiques** s'ils sont le même objet en mémoire (`a === b`), et **égaux** si leurs valeurs sont égales (selon une définition que tu choisis). En base, une ligne est identifiée par sa **clé primaire**. Rien ne garantit que « même clé » implique « même objet ».

```javascript
// mismatch.mjs (exécutable)
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();
const findMember = (id) => db.prepare('SELECT * FROM members WHERE id = ?').get(id);

const a = findMember(1);
const b = findMember(1);
console.log(a.id === b.id); // true  : même clé primaire, donc même ligne
console.log(a === b);       // false : deux objets distincts en mémoire
a.handle = 'theo-renamed';
console.log(b.handle);      // 'theo' : b ignore la modification de a, et la base aussi
```

Conséquence : si deux parties du code chargent le même membre, la modifient chacune, puis l'enregistrent, la dernière écriture écrase la première, sans erreur. Les ORMs de la famille Data Mapper répondent à ce problème avec une **Identity Map** (un objet par ligne et par session, [module 06](../06-concepts-avances/notes.md)).

### 2. Granularité

Le code objet aime les petits types : une `Address`, un `Money { amount, currency }`, un `Email` qui se valide lui-même. La base préfère les colonnes plates. Faut-il une table `addresses`, ou des colonnes `address_street`, `address_city` dans `members` ? Les ORMs proposent des **objets embarqués** (*Embeddable* en JPA et Doctrine, *composite types* ailleurs) pour mapper plusieurs colonnes sur un seul objet valeur. Inversement, un même objet peut être réparti sur plusieurs tables.

### 3. Héritage

Le relationnel n'a pas d'héritage. Une hiérarchie `Media → Image | Video | Sound` doit être aplatie selon l'une de trois stratégies (une table pour tout, une table par classe, une table par classe concrète), chacune avec ses compromis. C'est traité dans le [module 04](../04-modelisation-merise-uml-erd/notes.md).

### 4. Associations et directionnalité

Côté objet, une association est une **référence portée par un côté** : `project.owner` pointe vers un `Member`. Pour aller du membre vers ses projets, il faut une seconde référence (`member.projects`), et maintenir les deux en cohérence est ton problème.

Côté relationnel, l'association est **une seule clé étrangère**, placée du côté « plusieurs » (`projects.owner_id`), et elle s'interroge dans les deux sens par jointure. Il n'y a rien à synchroniser.

Deux cas cassent la correspondance un-pour-un :

- **n-n pure** (`projects` ↔ `tags`) : le relationnel a besoin d'une table de jointure (`project_tags`) qui n'a aucun équivalent dans le modèle objet, où l'on écrirait simplement `project.tags = [...]`. L'ORM la cache.
- **n-n porteuse d'attributs** (`contributions.role`) : l'attribut n'appartient ni au membre ni au projet. Le modèle objet est obligé de faire apparaître une entité `Contribution`. La plupart des ORMs t'y forcent (Prisma parle de *explicit many-to-many*, Doctrine exige une entité intermédiaire).

### 5. Navigation de graphe contre pensée ensembliste

Le code objet parcourt : « pour chaque projet, prends son propriétaire, regarde son email ». Le SQL décrit un ensemble résultat : « les emails des propriétaires de projets actifs », et laisse le moteur choisir comment le calculer.

```javascript
// Pensée objet : chaque flèche peut déclencher une requête
const emails = activeProjects.map((project) => project.owner().email);

// Pensée ensembliste : une seule requête, le moteur optimise
// SELECT DISTINCT m.email FROM projects p JOIN members m ON m.id = p.owner_id WHERE p.status = 'active'
```

Si `owner()` interroge la base, la première version exécute 1 + n requêtes : c'est le **problème N+1**, le défaut de performance le plus répandu des ORMs ([module 06](../06-concepts-avances/notes.md)).

Autre différence : une relation est un **ensemble non ordonné**. L'ordre d'un tableau JavaScript n'a pas d'équivalent en base sans colonne de position explicite et sans `ORDER BY`. Une requête sans `ORDER BY` n'a pas d'ordre garanti, même si elle semble stable sur ta machine.

### 6. Types et absence de valeur

Le driver ne parle pas le langage de ton domaine. Avec `node:sqlite` (Node 22), c'est très visible :

- `created_at` revient en `string` (`'2026-01-10 09:00:00'`), pas en `Date`.
- Lier `true`, un `Date` ou `undefined` comme paramètre **échoue** (« Provided value cannot be bound »). Il faut convertir en `1`, en texte ISO, en `null`.
- Un entier au-delà de `Number.MAX_SAFE_INTEGER` lève une `RangeError`, sauf à activer la lecture en `BigInt`.
- `'2026-01-10 09:00:00'` passé tel quel à `new Date()` est interprété en **heure locale** par V8. SQLite l'a écrit en UTC. Sur une machine réglée sur Paris, tu décales silencieusement toutes tes dates d'une ou deux heures.

Et `NULL` n'est pas `null` :

```sql
SELECT NULL = NULL;            -- NULL (inconnu), pas vrai
SELECT 1 WHERE NULL <> 'a';    -- aucune ligne : NULL <> 'a' est inconnu, donc filtré
```

En JavaScript, `null === null` vaut `true`. Un filtre « tous les membres dont le statut n'est pas *banni* » écrit `status <> 'banned'` exclut les statuts `NULL`, ce que la version JavaScript `m.status !== 'banned'` n'aurait pas fait. Convertir ces valeurs dans les deux sens s'appelle l'**hydratation** et la **déshydratation** : c'est une des tâches centrales d'un ORM.

### 7. Encapsulation contre exposition

Un objet bien conçu protège ses invariants : un `Project` archivé refuse qu'on le renomme, et son état n'est modifiable que par des méthodes. Une table expose toutes ses colonnes à quiconque a le droit d'y écrire.

L'ORM doit pouvoir lire et écrire l'état interne pour hydrater l'objet, ce qui entre en tension avec l'encapsulation. Les solutions concrètes :

- **Doctrine** (PHP) n'appelle jamais le constructeur lors de l'hydratation : il crée l'objet par réflexion et écrit directement dans les propriétés, même privées. Les invariants posés dans le constructeur ne sont donc pas revérifiés au chargement.
- **JPA** (Java) exige un constructeur sans argument (public ou protégé) dans chaque entité.
- Les ORMs JavaScript de type Active Record exposent en général les champs en propriétés publiques.

La conséquence : les invariants vivent à deux endroits, dans le code (méthodes) et dans la base (contraintes `NOT NULL`, `CHECK`, `UNIQUE`, `FOREIGN KEY`). Le second est le seul garanti pour **tous** les clients de la base.

### 8. Fraîcheur

Un objet chargé est une **copie** de la ligne à un instant donné. Pendant que tu le manipules, un autre processus peut modifier la ligne. L'objet ne le sait pas. Tout ORM est en pratique un cache d'objets placé devant une base partagée, et doit répondre à la question « que se passe-t-il si la ligne a changé entre la lecture et l'écriture ? » (verrouillage optimiste, transactions : [module 06](../06-concepts-avances/notes.md)).

---

## ⚙️ Ce que fait concrètement un ORM

```
            déshydratation                      exécution
 objets ───────────────────► paramètres + SQL ───────────► SGBD
   ▲                                                         │
   │        hydratation                                      │
   └──────────────────────── lignes de résultat ◄────────────┘
```

1. **Lire des métadonnées de mapping.** Quelle classe correspond à quelle table, quelle propriété à quelle colonne, avec quel type, quelles relations. Trois sources possibles : des conventions (Eloquent, Rails : `Member` → table `members`), des annotations dans le code (décorateurs TypeORM, attributs PHP Doctrine), un fichier de schéma séparé (`schema.prisma`, schéma Drizzle en TypeScript).
2. **Générer le SQL** dans le dialecte du SGBD cible (guillemets, pagination, `RETURNING`, *upsert*…), toujours avec des paramètres liés.
3. **Hydrater** : transformer chaque ligne en objet, avec conversion de types (texte → `Date`, `0/1` → booléen, `snake_case` → `camelCase`), et assembler les objets liés.
4. **Gérer les relations** : charger les objets associés (à la demande ou en avance), écrire les clés étrangères et les tables de jointure.
5. **Suivre les changements** (*change tracking*, *dirty checking*) : savoir quels objets et quels champs ont changé pour n'écrire que le nécessaire, dans le bon ordre ([module 06](../06-concepts-avances/notes.md)).
6. **Encadrer les transactions** : regrouper plusieurs écritures dans une unité atomique.
7. **Souvent, gérer les migrations** : générer et appliquer les évolutions du schéma ([module 03](../03-migrations/notes.md)).
8. **Parfois** : validation, hooks de cycle de vie (`beforeSave`…), cache, *soft delete*, filtres globaux. Ce sont les fonctionnalités qui créent le plus de comportements cachés.

Le même mapping, vu par trois outils (illustratif) :

```prisma
// Prisma : fichier de schéma séparé, le client est généré à partir de lui
model Member {
  id        Int       @id @default(autoincrement())
  handle    String    @unique
  email     String    @unique
  createdAt DateTime  @default(now()) @map("created_at")
  projects  Project[]

  @@map("members")
}
```

```typescript
// Drizzle : le schéma est du TypeScript, proche du DDL
import { sqliteTable, integer, text } from 'drizzle-orm/sqlite-core';
import { sql } from 'drizzle-orm';

export const members = sqliteTable('members', {
  id: integer('id').primaryKey(),
  handle: text('handle').notNull().unique(),
  email: text('email').notNull().unique(),
  createdAt: text('created_at').notNull().default(sql`(datetime('now'))`),
});
```

```php
// Doctrine : attributs PHP posés sur la classe du domaine
#[ORM\Entity]
#[ORM\Table(name: 'members')]
class Member
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(unique: true)]
    private string $handle;

    #[ORM\Column(name: 'created_at')]
    private \DateTimeImmutable $createdAt;

    #[ORM\OneToMany(targetEntity: Project::class, mappedBy: 'owner')]
    private Collection $projects;
}
```

Note où vit le mapping dans chaque cas : à côté du domaine (Prisma), dans un module de schéma (Drizzle), **dans** la classe du domaine (Doctrine). Ce choix détermine le couplage, on y revient plus bas.

---

## 🏛️ Les patterns de Fowler

Martin Fowler a nommé en 2002, dans *Patterns of Enterprise Application Architecture* (PoEAA), les façons d'organiser l'accès aux données. Ces noms sont devenus le vocabulaire commun : la documentation de TypeORM, Doctrine ou SQLAlchemy s'y réfère directement.

Une idée de Fowler est souvent oubliée : **le choix du pattern d'accès aux données dépend de la façon dont tu organises la logique métier** (PoEAA, ch. 9 et 10).

| Logique métier organisée en… | Pattern d'accès naturel |
|---|---|
| *Transaction Script* : une procédure par cas d'usage | Table Data Gateway ou Row Data Gateway |
| *Table Module* : une classe par table, qui manipule des ensembles de lignes | Table Data Gateway |
| *Domain Model* simple, calqué sur le schéma | Active Record |
| *Domain Model* riche, différent du schéma | Data Mapper |

### 1. Table Data Gateway

> « Un objet qui sert de passerelle vers une table. Une seule instance gère toutes les lignes. » (PoEAA)

Le SQL est rangé dans une classe par table, qui renvoie des données brutes. Aucune logique métier, aucun objet riche.

```javascript
// table-data-gateway.mjs (exécutable)
import { openDb } from '../fil-rouge/open-db.mjs';

// Table Data Gateway : UN objet pour TOUTE la table.
// Il encapsule le SQL et renvoie des données brutes ; aucune logique métier.
class MemberGateway {
  constructor(db) {
    this.db = db;
  }
  findById(id) {
    return this.db.prepare('SELECT * FROM members WHERE id = ?').get(id);
  }
  findByEmailDomain(domain) {
    return this.db.prepare("SELECT * FROM members WHERE email LIKE '%@' || ? ORDER BY handle").all(domain);
  }
  insert(handle, email) {
    const { lastInsertRowid } = this.db
      .prepare('INSERT INTO members (handle, email) VALUES (?, ?)')
      .run(handle, email);
    return Number(lastInsertRowid);
  }
  updateEmail(id, email) {
    this.db.prepare('UPDATE members SET email = ? WHERE id = ?').run(email, id);
  }
  delete(id) {
    this.db.prepare('DELETE FROM members WHERE id = ?').run(id);
  }
}

const members = new MemberGateway(openDb());
const id = members.insert('dora', 'dora@atelier.test');
members.updateEmail(id, 'dora@studio.test');
console.log(members.findById(id).email);                                     // 'dora@studio.test'
console.log(members.findByEmailDomain('atelier.test').map((m) => m.handle)); // [ 'ada', 'bruno', 'chloe', 'theo' ]
members.delete(id);
console.log(members.findById(id));                                           // undefined
```

**Quand c'est le bon choix** : beaucoup de code back-end « CRUD + règles simples » s'en contente très bien. Ce n'est pas un ORM, mais c'est souvent ce que tu écris en premier, et c'est honnête : le SQL est visible, testable, et ne cache rien.

### 2. Row Data Gateway

> « Un objet qui sert de passerelle vers un seul enregistrement. Une instance par ligne. » (PoEAA)

Chaque ligne devient un objet qui sait s'insérer, se mettre à jour et se supprimer. Les recherches sont dans un objet séparé (*finder*). Toujours aucune logique métier.

```javascript
// row-data-gateway.mjs (exécutable)
import { openDb } from '../fil-rouge/open-db.mjs';

class MemberRow {
  constructor(db, { id = null, handle, email, created_at = null }) {
    this.db = db;
    Object.assign(this, { id, handle, email, created_at });
  }
  insert() {
    const row = this.db
      .prepare('INSERT INTO members (handle, email) VALUES (?, ?) RETURNING id, created_at')
      .get(this.handle, this.email);
    Object.assign(this, row); // récupère ce que la base a calculé
  }
  update() {
    this.db.prepare('UPDATE members SET handle = ?, email = ? WHERE id = ?').run(this.handle, this.email, this.id);
  }
  delete() {
    this.db.prepare('DELETE FROM members WHERE id = ?').run(this.id);
  }
}

class MemberFinder {
  constructor(db) {
    this.db = db;
  }
  find(id) {
    const row = this.db.prepare('SELECT * FROM members WHERE id = ?').get(id);
    return row ? new MemberRow(this.db, row) : null;
  }
}

const db = openDb();
const dora = new MemberRow(db, { handle: 'dora', email: 'dora@atelier.test' });
dora.insert();
console.log(dora.id, dora.created_at);                 // 5 '2026-…' (date du jour, en UTC)
dora.email = 'dora@studio.test';
dora.update();
console.log(new MemberFinder(db).find(dora.id).email); // 'dora@studio.test'
```

`RETURNING` (PostgreSQL, SQLite ≥ 3.35, MariaDB pour `INSERT`/`DELETE` ; absent de MySQL) renvoie les valeurs calculées par la base (`id`, valeurs par défaut) dans la même requête.

### 3. Active Record

> « Un objet qui enveloppe une ligne d'une table ou d'une vue, encapsule l'accès à la base, **et ajoute de la logique métier sur ces données**. » (PoEAA)

Active Record = Row Data Gateway + logique métier + recherches. L'objet **est** la ligne. C'est le pattern de Rails (qui lui a donné son nom de bibliothèque), d'Eloquent (Laravel), de Django, de Sequelize.

```javascript
// active-record.mjs (exécutable)
import { openDb } from '../fil-rouge/open-db.mjs';

const DAY = 24 * 60 * 60 * 1000;

class Member {
  static db; // connexion partagée par toute la classe : c'est le couplage qu'on discute plus bas

  constructor({ id = null, handle, email, created_at = null }) {
    Object.assign(this, { id, handle, email, created_at });
  }

  // --- persistance ---
  static find(id) {
    const row = Member.db.prepare('SELECT * FROM members WHERE id = ?').get(id);
    return row ? new Member(row) : null;
  }
  static all() {
    return Member.db.prepare('SELECT * FROM members ORDER BY id').all().map((row) => new Member(row));
  }
  save() {
    if (this.id === null) {
      const row = Member.db
        .prepare('INSERT INTO members (handle, email) VALUES (?, ?) RETURNING id, created_at')
        .get(this.handle, this.email);
      Object.assign(this, row);
    } else {
      Member.db
        .prepare('UPDATE members SET handle = ?, email = ? WHERE id = ?')
        .run(this.handle, this.email, this.id);
    }
    return this;
  }
  delete() {
    Member.db.prepare('DELETE FROM members WHERE id = ?').run(this.id);
    this.id = null;
  }

  // --- relation ---
  projects() {
    return Member.db.prepare('SELECT * FROM projects WHERE owner_id = ? ORDER BY id').all(this.id);
  }

  // --- logique métier ---
  isNewcomer(now = new Date()) {
    const createdAt = new Date(this.created_at.replace(' ', 'T') + 'Z'); // SQLite stocke l'UTC sans « Z »
    return now - createdAt < 30 * DAY;
  }
}

Member.db = openDb();

const theo = Member.find(1);
console.log(theo.projects().map((p) => p.title));               // [ 'Carnet du dev', 'Synthé web' ]
console.log(theo.isNewcomer(new Date('2026-01-20T00:00:00Z'))); // true

const dora = new Member({ handle: 'dora', email: 'dora@atelier.test' }).save();
dora.email = 'dora@studio.test';
dora.save();
console.log(Member.find(dora.id).email);                        // 'dora@studio.test'
dora.delete();
console.log(Member.all().length);                               // 4
```

Remarque ce que coûte `isNewcomer` : pour tester une règle métier de deux lignes, il faut une base, un schéma, et une connexion statique. C'est le prix du pattern.

### 4. Data Mapper

> « Une couche de *mappers* qui déplace les données entre les objets et la base **en les gardant indépendants l'un de l'autre** et du mapper lui-même. » (PoEAA)

Le domaine ne sait pas qu'il existe une base. Le mapper connaît les deux côtés et fait la traduction. C'est le pattern de Doctrine, Hibernate/JPA, SQLAlchemy ORM, MikroORM, EF Core.

```javascript
// data-mapper.mjs (exécutable)
import { openDb } from '../fil-rouge/open-db.mjs';

const DAY = 24 * 60 * 60 * 1000;

// ---------- Domaine : aucun import de base de données ----------
class Member {
  constructor({ id = null, handle, email, createdAt = new Date() }) {
    if (!/^[a-z0-9-]{2,30}$/.test(handle)) throw new Error(`handle invalide : ${handle}`);
    Object.assign(this, { id, handle, email, createdAt });
  }
  rename(newHandle) {
    if (!/^[a-z0-9-]{2,30}$/.test(newHandle)) throw new Error(`handle invalide : ${newHandle}`);
    this.handle = newHandle;
  }
  isNewcomer(now = new Date()) {
    return now - this.createdAt < 30 * DAY;
  }
}

// ---------- Persistance : le mapper connaît la table ET la classe ; elles s'ignorent ----------
const parseSqliteDate = (text) => new Date(text.replace(' ', 'T') + 'Z');
const formatSqliteDate = (date) => date.toISOString().slice(0, 19).replace('T', ' ');

class MemberMapper {
  constructor(db) {
    this.db = db;
  }
  find(id) {
    const row = this.db.prepare('SELECT * FROM members WHERE id = ?').get(id);
    return row ? this.#toEntity(row) : null;
  }
  findAll() {
    return this.db.prepare('SELECT * FROM members ORDER BY id').all().map((row) => this.#toEntity(row));
  }
  insert(member) {
    const { id } = this.db
      .prepare('INSERT INTO members (handle, email, created_at) VALUES (?, ?, ?) RETURNING id')
      .get(member.handle, member.email, formatSqliteDate(member.createdAt));
    member.id = id;
  }
  update(member) {
    this.db
      .prepare('UPDATE members SET handle = ?, email = ? WHERE id = ?')
      .run(member.handle, member.email, member.id);
  }
  delete(member) {
    this.db.prepare('DELETE FROM members WHERE id = ?').run(member.id);
  }
  // Hydratation : ligne (snake_case, texte) → entité (camelCase, Date)
  #toEntity(row) {
    return new Member({
      id: row.id,
      handle: row.handle,
      email: row.email,
      createdAt: parseSqliteDate(row.created_at),
    });
  }
}

const mapper = new MemberMapper(openDb());

const ada = mapper.find(2);
console.log(ada instanceof Member, ada.createdAt.toISOString()); // true '2026-02-02T14:30:00.000Z'
ada.rename('ada-l');
mapper.update(ada);
console.log(mapper.find(2).handle);                               // 'ada-l'

const dora = new Member({ handle: 'dora', email: 'dora@atelier.test' });
mapper.insert(dora);
console.log(dora.id, mapper.findAll().length);                    // 5 5

// La logique métier se teste sans base :
const fresh = new Member({ handle: 'eve', email: 'eve@x.test', createdAt: new Date('2026-10-01T00:00:00Z') });
console.log(fresh.isNewcomer(new Date('2026-10-15T00:00:00Z')));  // true
```

Ce Data Mapper écrit à la main est volontairement naïf : il faut appeler `update()` explicitement, et charger deux fois le membre 2 produit deux objets. Un vrai ORM Data Mapper ajoute une Identity Map et une Unit of Work pour que `em.flush()` détecte et écrive seul ce qui a changé.

### Les patterns satellites

Ils complètent les quatre précédents. Chacun est repris en détail dans le [module 06](../06-concepts-avances/notes.md).

| Pattern | En deux lignes |
|---|---|
| **Metadata Mapping** | Le mapping est décrit par des données (décorateurs, fichier de schéma) plutôt que codé à la main pour chaque classe. Un code générique s'en sert pour produire le SQL. C'est ce qui distingue un ORM d'un tas de mappers écrits à la main (kata 6). |
| **Identity Map** | Une table « clé primaire → objet » par session : charger deux fois la même ligne renvoie le même objet. Résout le problème d'identité vu plus haut. |
| **Unit of Work** | Liste les objets créés, modifiés, supprimés pendant une transaction métier, puis écrit tout d'un coup, dans le bon ordre (clés étrangères), au moment du `flush`/`commit`. |
| **Lazy Load** | Un objet qui ne contient pas toutes ses données mais sait aller les chercher au premier accès. Pratique, et cause directe du problème N+1. |
| **Query Object** | Une requête représentée par un objet (critères, tri, pagination) plutôt que par une chaîne. Les query builders en sont une généralisation ([module 02](../02-sql-query-builder-orm/notes.md)). |
| **Repository** | Une interface de type collection (`findById`, `save`, `matching(spec)`) entre le domaine et le mapping. Popularisé par Evans (*Domain-Driven Design*, 2003) pour les agrégats. |

---

## ⚖️ Active Record contre Data Mapper

Ce n'est pas une question de goût. Les deux patterns répondent à des situations différentes, et Fowler les présente comme tels.

| Critère | Active Record | Data Mapper |
|---|---|---|
| Sens des dépendances | le domaine dépend de la base | le mapper dépend du domaine et de la base ; le domaine ne dépend de rien |
| Forme du domaine | calquée sur le schéma : une classe = une table, un champ = une colonne | libre : objets valeurs, agrégats, noms différents du schéma |
| Tester une règle métier | nécessite une base (ou des *mocks* de méthodes statiques) | objet JavaScript ordinaire, test en millisecondes |
| Quantité de code | faible : on hérite de `Model` et c'est fini | plus élevée : entité + mapping + repository |
| Écriture | `member.save()`, explicite, objet par objet | souvent `em.flush()` : la Unit of Work décide quoi écrire |
| Où vivent les requêtes | méthodes statiques de la classe | repositories / mappers |
| Courbe d'apprentissage | douce au début | plus raide (cycle de vie des entités, *flush*, états *managed/detached*) |
| Risque typique | classe « fourre-tout » qui mélange règles, SQL, validation, sérialisation | sur-ingénierie pour un domaine qui n'est qu'un CRUD |

### La notion de *persistence ignorance*

Un domaine *persistence ignorant* ne sait pas comment ni s'il sera stocké. C'est l'argument central du Data Mapper, et la base du DDD (Evans). Deux nuances honnêtes :

1. **Les annotations recouplent.** Une entité Doctrine ou TypeORM couverte d'attributs `#[ORM\Column]` ou de décorateurs `@Column()` contient son mapping. Elle ne dépend pas de la connexion, mais elle dépend de la bibliothèque. L'indépendance complète suppose un mapping externe (fichier XML Doctrine, schéma séparé).
2. **L'ignorance est toujours partielle.** Un domaine doit savoir qu'un `id` peut être absent avant la première sauvegarde, que les collections chargées à la demande ne sont pas de vrais tableaux, que les objets peuvent être périmés. La base « fuit » toujours un peu dans le modèle.

### Quand chacun gagne

- **Active Record gagne** quand le domaine est essentiellement des données avec peu de règles, que le schéma et le modèle se ressemblent, et que la vitesse de développement prime : back-offices, applications CRUD, prototypes, équipes qui suivent les conventions d'un framework (Rails, Laravel, Django).
- **Data Mapper gagne** quand les règles métier sont nombreuses et doivent être testées isolément, que le modèle objet diverge du schéma (objets valeurs, agrégats, héritage), et que l'application doit vivre longtemps.

**Le test qui tranche** : *puis-je instancier mon objet métier et tester sa règle la plus importante sans base de données ?* Si la réponse doit être oui, il te faut un Data Mapper, ou au minimum sortir la règle de l'Active Record.

---

## 🗺️ Cartographie des ORMs

Les familles ci-dessous sont des tendances, pas des cases étanches. Plusieurs outils mélangent les styles.

| Famille | Principe | Exemples |
|---|---|---|
| **Active Record** | l'objet est la ligne ; `save()` sur l'instance | Rails ActiveRecord (Ruby), Eloquent (Laravel, PHP), Django ORM (Python), Sequelize (JS) |
| **Data Mapper + Unit of Work + Identity Map** | entités indépendantes, un gestionnaire (*EntityManager*, *Session*, *DbContext*) suit les changements et écrit au `flush` | Hibernate / JPA (Java), Doctrine ORM (PHP), SQLAlchemy ORM (Python), MikroORM (TS), Entity Framework Core (.NET) |
| **Les deux au choix** | même bibliothèque, deux API | TypeORM (TS) : `BaseEntity` pour Active Record, `Repository` pour Data Mapper, sans Unit of Work complète |
| **Client généré depuis un schéma** | un fichier de schéma est la source de vérité ; un client typé est généré ; les résultats sont des objets simples | Prisma (TS) |
| **« Headless » / SQL-like** | schéma en code, API proche du SQL, résultats en objets simples, plus une API relationnelle optionnelle | Drizzle (TS) ; Objection.js (JS, bâti sur Knex) |
| **Micro-ORM** | tu écris le SQL, l'outil ne fait que mapper les lignes vers des objets | Dapper (.NET) ; en JS, un driver + des fonctions d'hydratation jouent ce rôle |

Pas des ORMs, mais souvent confondus avec : **Knex, Kysely** (JS), **jOOQ** (Java), **SQLAlchemy Core** (Python). Ce sont des query builders : ils construisent du SQL, pas un modèle objet ([module 02](../02-sql-query-builder-orm/notes.md)). SQLAlchemy illustre bien la frontière : *Core* est le query builder, *ORM* est le Data Mapper bâti dessus.

### Classements discutables

- **Prisma n'est ni Active Record ni Data Mapper au sens de Fowler.** Pas Active Record : il n'y a pas de classe d'entité, pas de `member.save()` ; les requêtes passent par `prisma.member.update({ where, data })` et renvoient des objets JavaScript simples. Pas vraiment Data Mapper non plus : il n'y a pas d'objets métier à mapper, pas d'Identity Map, pas de Unit of Work, pas de chargement paresseux. Structurellement, c'est une **passerelle de table typée et générée** : l'équivalent d'un Table Data Gateway par modèle, avec un langage de requête riche et la gestion des relations. Sa propre documentation (« Is Prisma ORM an ORM? ») se dit plus proche du Data Mapper que de l'Active Record, au sens où le schéma et les objets restent découplés. À vérifier dans la version courante de la doc.
- **Drizzle** se décrit comme un « ORM headless » : c'est surtout un query builder typé, avec une API relationnelle (`db.query.members.findMany({ with: { projects: true } })`) qui le rapproche d'un ORM.
- **Django ORM** revendique lui-même le pattern : la page *Design philosophies* de sa documentation demande que les modèles encapsulent toute la logique de l'objet « en suivant le pattern Active Record de Martin Fowler ».
- **Objection.js** a une gouvernance mouvementée : son auteur (Sami Koskimäki, qui a ensuite créé Kysely) a annoncé fin 2022 qu'il arrêtait de le développer ; la maintenance a été reprise par un contributeur en 2023, puis déplacée dans un fork (`ditojs/objection`) en octobre 2026 (discussion GitHub `Vincit/objection.js#2463`). Vérifie l'état de maintenance avant de l'adopter.

---

## ✅ Avantages, et leurs conditions

Chaque avantage est réel **sous condition**. Le connaître sans sa condition, c'est se préparer une mauvaise surprise.

### Productivité sur le CRUD
**Gain** : créer, lire, modifier, supprimer des entités et naviguer dans leurs relations demande très peu de code. C'est la majorité des écrans d'une application de gestion.
**Condition** : que les opérations soient effectivement du CRUD sur des entités. Dès que la requête est un rapport (agrégats, fenêtres, CTE), le gain disparaît, voire s'inverse.

### Sécurité par défaut
**Gain** : les valeurs sont toujours passées en paramètres liés, ce qui ferme l'injection SQL classique pour les requêtes générées.
**Condition** : ne pas utiliser les échappatoires brutes (`$queryRawUnsafe`, `sequelize.literal`, `whereRaw`, concaténation dans `DB::raw`) avec des entrées utilisateur. Et ne pas laisser l'utilisateur contrôler la **structure** d'un filtre : si un objet JSON reçu est passé tel quel comme critère `where`, l'attaquant peut ajouter des opérateurs ou filtrer sur des relations. Les recherches d'elttam sur les « ORM Leak » (Django, Prisma, 2024) montrent ainsi la fuite de hachages de mots de passe caractère par caractère, sans aucune injection SQL au sens strict.

### Cohérence et conventions
**Gain** : un seul endroit décrit le modèle ; l'équipe écrit l'accès aux données de la même façon partout ; les conversions de types sont centralisées.
**Condition** : que tout le monde passe par l'ORM. Un script de maintenance en SQL direct, un second service dans un autre langage, et la « source unique » ne l'est plus. La base, elle, reste partagée.

### Typage
**Gain** : avec Prisma, Drizzle, Kysely ou les ORMs TypeScript, le compilateur sait que `member.handle` est une `string` et qu'un `include` renvoie des projets.
**Condition** : que le schéma connu de l'outil soit le schéma réel. Les types décrivent ce que l'outil **croit**. Une migration appliquée à la main, une colonne modifiée par un autre service, et les types mentent sans erreur de compilation (on parle de *drift*, [module 03](../03-migrations/notes.md)).

### Portabilité (et son mythe)
**Gain** : le même code génère du SQL pour PostgreSQL, MySQL ou SQLite.
**Limite** : changer de SGBD en production est rare, et l'ORM n'abstrait que la **syntaxe**, pas la **sémantique**. Niveau d'isolation par défaut, comparaison de chaînes sensible ou non à la casse, ordre des `NULL` dans un tri, collations (dans l'Atelier, « Éthique » se trie après « Typographie » en SQLite avec la collation binaire), types JSON, comportements de verrouillage : tout cela diffère, et l'application qui a grandi sur l'un dépend de ces détails. La portabilité est surtout utile pour les tests (SQLite en mémoire)… et c'est précisément là qu'elle trompe, puisque les tests ne tournent plus sur le vrai moteur.

### Écosystème intégré
**Gain** : migrations, *seeds*, validation, interfaces d'administration (Django admin, EasyAdmin, Prisma Studio) s'appuient sur le même modèle.
**Condition** : accepter le couplage qui va avec. Plus l'écosystème est intégré, plus il est coûteux d'en sortir.

---

## ❌ Inconvénients, et leurs causes

### Une abstraction qui fuit
Joel Spolsky (« The Law of Leaky Abstractions », 2002) : toute abstraction non triviale laisse passer une partie de ce qu'elle cache. L'ORM cache le SQL jusqu'au jour où une page met huit secondes à charger. Pour comprendre pourquoi, il faut redescendre au SQL généré, au plan d'exécution, aux index. **L'ORM ne supprime pas le besoin de connaître le SQL, il le diffère** au moment où le problème est le plus coûteux : en production.

### Un SQL généré opaque
Le SQL produit est souvent correct, parfois sous-optimal (sous-requêtes imbriquées, `SELECT *`, jointures inutiles), et toujours **invisible par défaut**. Premier réflexe : activer le journal des requêtes (`openDb({ log: true })` dans ce chapitre, `log: ['query']` dans Prisma, `logging` dans Sequelize, le profiler de Symfony pour Doctrine).

### Des performances difficiles à prévoir
Les causes classiques : N+1 dû au chargement paresseux, sur-lecture (toutes les colonnes, toutes les relations), coût de l'hydratation de milliers d'objets, Unit of Work qui inspecte chaque objet au `flush`, opérations en masse lentes (un `UPDATE` par objet au lieu d'un seul `UPDATE … WHERE`). Aucun n'est une fatalité, tous demandent de savoir ce que l'ORM fait réellement ([module 06](../06-concepts-avances/notes.md)).

### Un double apprentissage
Il faut connaître le SQL **et** la sémantique de l'ORM : quand une requête part-elle ? Que contient le cache de session ? Qu'est-ce qu'une entité « détachée » ? Que fait la cascade sur `remove` ? Ces règles sont spécifiques à chaque ORM, et souvent plus difficiles que le SQL qu'elles remplacent.

### Un domaine couplé au mapping
Avec Active Record, le domaine **est** le schéma : renommer une colonne touche la logique métier, et la logique métier ne se teste pas sans base. Avec un Data Mapper annoté, le couplage est plus faible mais réel (voir *persistence ignorance*). Fowler le dit sans détour : l'ORM oblige souvent à rendre le modèle objet « plus relationnel » qu'on ne le voudrait.

### La magie
Les hooks de cycle de vie (`beforeSave`, `afterCreate`), les filtres globaux (*global scopes*, *soft delete*), les cascades, le chargement paresseux sont des **effets de bord invisibles au point d'appel**. Un `member.save()` peut envoyer un email, mettre à jour trois tables et filtrer silencieusement des lignes. Ce comportement doit être documenté ([module 05](../05-documenter/notes.md)), et les opérations en masse le contournent souvent sans prévenir.

### Le verrouillage technique
Les migrations, le format du schéma, l'API de requête, le comportement transactionnel sont propres à chaque ORM. Changer d'ORM sur une application mûre est un chantier comparable à changer de framework.

---

## 🥊 Neward contre Fowler

Deux textes structurent le débat. Ils méritent d'être lus en entier ; voici leurs thèses, en substance.

**Ted Neward, « The Vietnam of Computer Science » (2006).** L'ORM ressemble à un bourbier : les premiers succès sont rapides et encourageants (le CRUD fonctionne), puis chaque cas limite (héritage, identité, requêtes ad hoc, concurrence) exige un investissement croissant, sans jamais atteindre une solution complète ni offrir de sortie claire. Le coût d'abandon augmente avec l'investissement déjà consenti. Neward énumère les issues possibles : renoncer aux objets, renoncer au relationnel (bases objet), faire le mapping à la main, accepter les limites de l'ORM, intégrer les concepts relationnels dans le langage (ce que fera LINQ), ou dans les frameworks.

**Martin Fowler, « OrmHate » (2012).** Le problème est réellement difficile, et c'est pour cela que les ORMs sont complexes, pas parce qu'ils sont mal conçus. Une grande partie de la frustration vient d'attentes gonflées : un ORM ne permet pas d'ignorer la base. Il règle une grosse partie du problème, et ceux qui écrivent leur propre couche de mapping finissent souvent avec un ORM maison moins bon. Si l'on ne veut pas payer ce prix, l'alternative honnête est de changer de modèle (ne pas avoir de modèle objet riche, ou ne pas avoir de base relationnelle), pas de critiquer l'outil. Il suggère aussi de ne pas tout faire passer par l'ORM, en particulier les lectures complexes.

**Ce sur quoi ils s'accordent** : le décalage est irréductible, aucune bibliothèque ne le supprimera. **Ce qui les sépare** : la valeur d'une solution partielle. Neward insiste sur le coût caché des 20 % restants ; Fowler sur la valeur des 80 % couverts.

**Position pratique qui découle des deux** : utiliser l'ORM là où le modèle objet apporte quelque chose (les écritures sur le domaine, avec ses invariants), et écrire du SQL là où la pensée ensembliste est naturelle (lectures complexes, rapports, opérations en masse). C'est une forme légère de CQRS, discutée aux modules [02](../02-sql-query-builder-orm/notes.md) et [06](../06-concepts-avances/notes.md). Stonebraker et Pavlo (« What Goes Around Comes Around… And Around… », 2024) rappellent d'ailleurs que les modèles de données alternatifs reviennent cycliquement et que le relationnel reste : investir dans le SQL n'est jamais perdu, investir dans un ORM précis l'est parfois.

---

## 🚫 Quand ne pas utiliser un ORM

| Situation | Pourquoi l'ORM gêne | Alternative |
|---|---|---|
| Rapports, statistiques, tableaux de bord | agrégats, fonctions de fenêtre, CTE récursives : l'ORM les exprime mal ou pas du tout, et l'hydratation en objets est inutile | SQL brut paramétré, vues SQL |
| Traitements en masse (import, ETL, purge) | une écriture par objet, Unit of Work coûteuse, hooks inutiles | `INSERT … SELECT`, `COPY`, `UPDATE … WHERE` en une requête |
| Schéma que tu ne contrôles pas (*legacy*, base d'un autre service) | clés composites étranges, conventions incohérentes : le mapping devient plus complexe que les requêtes | query builder ou SQL, éventuellement un micro-ORM |
| Logique portée par la base (vues, procédures, RLS, triggers) | l'ORM ignore ou contourne ces mécanismes | SQL direct, le modèle objet n'est qu'une projection |
| Fonctionnalités spécifiques du SGBD (JSONB, tableaux, recherche plein texte, `LATERAL`) | l'ORM les couvre partiellement, souvent via des échappatoires brutes | query builder typé ou SQL |
| Domaine fin (peu de règles), équipe à l'aise en SQL | l'ORM apporte surtout du coût d'apprentissage | query builder + fonctions d'hydratation |
| Script court, outil en ligne de commande | l'installation et la configuration dépassent le travail utile | driver + SQL |
| Système *event-sourcé* | l'état n'est pas stocké sous forme d'entités à mettre à jour | journal d'événements + projections en SQL |

### Grille de décision rapide

Réponds honnêtement :

1. La majorité des accès sont-ils du CRUD sur des entités ? (oui → ORM pertinent)
2. Les règles métier sont-elles nombreuses et doivent-elles être testées sans base ? (oui → Data Mapper, ou séparer la logique)
3. Les lectures sont-elles dominées par des agrégats et des rapports ? (oui → SQL ou query builder pour ces lectures)
4. L'équipe sait-elle lire le SQL que l'ORM générera ? (non → former d'abord, sinon l'ORM masquera les problèmes au lieu de les éviter)
5. Le schéma est-il sous ton contrôle ? (non → éviter un ORM qui veut le posséder)

---

## ⚠️ Pièges et erreurs courantes

1. **Croire qu'on n'a plus besoin du SQL.** C'est l'inverse : l'ORM suppose que tu sais lire le SQL qu'il génère.
2. **Ne jamais regarder le SQL généré.** Active le journal des requêtes en développement, et compte les requêtes par page ou par requête HTTP.
3. **Confondre égalité de clé et identité d'objet.** Deux objets avec le même `id` ne sont pas le même objet, sauf Identity Map. Compare les `id`, pas les références.
4. **Laisser `new Date()` deviner le fuseau.** Une date sans fuseau stockée en UTC et relue en heure locale décale tout. Convertis explicitement à l'hydratation.
5. **Envoyer l'entité telle quelle en JSON.** Tu exposes tout ce qu'elle contient (hachage de mot de passe, champs internes) et tu peux déclencher des chargements paresseux pendant la sérialisation. Construis une représentation de sortie explicite.
6. **Passer un objet reçu du client directement comme données ou comme filtre.** Risque d'affectation de masse et de fuite par filtre ([module 06](../06-concepts-avances/notes.md)).
7. **Cacher la logique métier dans des hooks.** Elle devient invisible au point d'appel, et les opérations en masse la contournent.
8. **Se fier aux seules validations de l'ORM.** Elles ne protègent que le code qui passe par l'ORM. Les contraintes en base protègent tout le monde.

---

## 🧠 Modèles mentaux

- **Un traducteur entre deux langues qui n'ont pas les mêmes concepts.** Certaines phrases se traduisent mot à mot (le CRUD), d'autres demandent une périphrase (héritage, n-n porteuse), d'autres sont intraduisibles (une requête analytique ne « devient » pas un graphe d'objets).
- **Un cache d'objets placé devant une base partagée.** Tout objet chargé est une copie datée. La vérité est en base.
- **Deux gardiens pour les invariants.** Le code protège les règles riches et contextuelles ; la base protège les règles simples et universelles (unicité, non-nullité, intégrité référentielle). Ni l'un ni l'autre ne suffit seul.
- **Active Record : l'objet est la ligne. Data Mapper : l'objet a une ligne.** Formule à retenir, et à nuancer.

---

## 🔗 Liens avec les autres modules

- [02 · SQL brut, query builder, ORM](../02-sql-query-builder-orm/notes.md) → le même besoin écrit aux trois niveaux, injection SQL, critères de choix détaillés
- [03 · Migrations](../03-migrations/notes.md) → comment le schéma que l'ORM mappe évolue, et comment revenir en arrière
- [04 · Modélisation : Merise, ERD, UML](../04-modelisation-merise-uml-erd/notes.md) → les associations et l'héritage vus ici, modélisés avant d'être codés ; les trois stratégies de mapping de l'héritage
- [05 · Documenter un ORM](../05-documenter/notes.md) → documenter le mapping et surtout les comportements cachés (hooks, cascades, filtres globaux)
- [06 · Concepts avancés](../06-concepts-avances/notes.md) → Identity Map, Unit of Work, Lazy Load, N+1, transactions et concurrence, affectation de masse

---

## 📚 Pour aller plus loin

- **Martin Fowler**, *Patterns of Enterprise Application Architecture*, 2002 : ch. 9 (organisation de la logique métier), ch. 10 (patterns d'accès aux données), ch. 11-13 (comportement, structure et métadonnées du mapping objet-relationnel).
- **Ted Neward**, « The Vietnam of Computer Science », 2006.
- **Martin Fowler**, « OrmHate », martinfowler.com/bliki, 2012.
- **E. F. Codd**, « A Relational Model of Data for Large Shared Data Banks », *CACM*, 1970 : pour comprendre ce que le modèle relationnel est, et pourquoi il n'est pas un « stockage d'objets ».
- **Martin Kleppmann**, *Designing Data-Intensive Applications*, 2017, ch. 2 : le décalage objet-relationnel comparé aux modèles document et graphe.
- **C. Ireland, D. Bowers, M. Newton, K. Waugh**, « A Classification of Object-Relational Impedance Mismatch », *DBKDA*, 2009.
- **Eric Evans**, *Domain-Driven Design*, 2003 : agrégats et repositories, la raison d'être du Data Mapper.
- **elttam**, « plORMbing your Django ORM » et « plORMbing your Prisma ORM », 2024 : les fuites de données par filtres contrôlés par l'utilisateur.

---

**Dernière mise à jour** : 2026-10-29
**Niveau de confiance** : ⭐⭐⭐⭐☆ (à compléter par ton expérience)
**Prochaine révision** : après le module 02
