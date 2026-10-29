# 🔬 Concepts avancés : ce qui casse en production

## 📋 Vue d'ensemble

Un ORM tient très bien un CRUD sur une table. Il casse ailleurs, et presque toujours sur les mêmes axes :

1. **Le nombre de requêtes** : le code a l'air de faire une opération, la base en reçoit cent (N+1, lazy loading).
2. **Les frontières transactionnelles** : ce qui devait être « tout ou rien » s'exécute en morceaux.
3. **La concurrence** : deux utilisateurs modifient la même ligne et l'un des deux perd son travail sans que personne ne le voie.
4. **Les comportements implicites** : hooks, filtres globaux, sérialisation, affectation de masse… ce que l'ORM fait sans qu'on l'ait écrit.

Ce module traite ces quatre axes, puis l'architecture (repository, CQRS léger, multi-tenant, pool de connexions), les tests et le typage. Le fil conducteur : **chaque problème est d'abord montré en SQL brut sur le fil rouge**, mesuré (nombre de requêtes, plan d'exécution, temps), puis relié à la façon dont les ORMs l'exposent ou le cachent.

### 🎯 Objectifs

- Repérer un N+1 dans un journal de requêtes et choisir entre jointure, préchargement par lots, agrégation JSON et regroupement façon DataLoader
- Expliquer Identity Map et Unit of Work, et savoir quel ORM les implémente
- Nommer les anomalies de concurrence, dire lesquelles chaque niveau d'isolation empêche, et connaître les défauts réels des SGBD
- Empêcher une mise à jour perdue de trois façons (mise à jour atomique, verrou optimiste, verrou pessimiste)
- Lire un `EXPLAIN QUERY PLAN`, paginer par curseur, insérer en lot
- Identifier les comportements cachés dangereux : hooks, *mass assignment*, fuite par sérialisation, soft delete
- Tester la couche d'accès aux données sur une vraie base, en bornant le nombre de requêtes

### ▶️ Faire tourner les exemples

Les blocs marqués **exécutable** se placent dans un fichier `.mjs` de ce dossier (`06-concepts-avances/`) et importent la base du fil rouge :

```bash
node --disable-warning=ExperimentalWarning exemple.mjs
```

Les extraits PostgreSQL, Prisma, Doctrine, Sequelize, Rails, etc. sont **illustratifs** : ils montrent la forme, pas une API à copier sans vérifier la doc de ta version.

> ⚠️ **Limite de SQLite pour ce module.** SQLite n'a qu'un seul écrivain à la fois et ses transactions sont sérialisables. On peut donc y démontrer le N+1, les plans d'exécution, la pagination, les transactions et les savepoints, la mise à jour perdue *entre* transactions et le verrouillage optimiste. On ne peut **pas** y montrer les anomalies propres à `READ COMMITTED` ou `REPEATABLE READ` : pour celles-là, les exemples passent en PostgreSQL illustratif.

---

## 1. 🐌 Le problème N+1

### Mécanisme

On charge une liste (**1** requête), puis, pour chacun des **N** éléments, on charge une relation (**N** requêtes). Le coût n'est pas le volume de données, c'est le **nombre d'allers-retours** : chaque requête paie la latence réseau, l'analyse SQL, la planification et l'exécution. Avec une base distante à 1 ms d'aller-retour, 200 éléments × 2 relations = 400 ms rien qu'en attente, pour des données qu'une seule requête aurait ramenées en quelques millisecondes.

### Démonstration (exécutable)

Besoin : « les projets actifs, avec le pseudo du propriétaire et leurs étiquettes ».

```javascript
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

const db = withQueryLog(openDb(), { print: false });

function listActiveProjectsNaive(db) {
  const projects = db
    .prepare("SELECT id, title, owner_id FROM projects WHERE status = 'active' ORDER BY id")
    .all();

  return projects.map((p) => ({
    title: p.title,
    owner: db.prepare('SELECT handle FROM members WHERE id = ?').get(p.owner_id).handle,
    tags: db
      .prepare(
        `SELECT t.label FROM tags t
         JOIN project_tags pt ON pt.tag_id = t.id
         WHERE pt.project_id = ? ORDER BY t.label`
      )
      .all(p.id)
      .map((t) => t.label),
  }));
}

console.log(listActiveProjectsNaive(db));
console.log(`${db.queries.length} requêtes`); // 7 = 1 + 3 propriétaires + 3 listes d'étiquettes
```

Avec 3 projets actifs : 7 requêtes. Avec 300 : 601. C'est un « 2N+1 », mais le nom N+1 désigne toute la famille : **le nombre de requêtes croît avec la taille des données au lieu d'être constant**.

### Pourquoi les ORMs le rendent invisible

En SQL brut, le N+1 se voit : il y a un `prepare` dans une boucle. Avec un ORM, la boucle et la requête sont séparées :

```javascript
// Illustratif (Sequelize) : aucune requête n'apparaît dans ce code…
const projects = await Project.findAll({ where: { status: 'active' } });
for (const project of projects) {
  const owner = await project.getOwner(); // …mais chaque tour en envoie une
}
```

Les cachettes habituelles : une relation chargée paresseusement (section 2), un template qui affiche `project.owner.handle`, un sérialiseur qui parcourt les relations, un *resolver* GraphQL par champ. Le code est correct, lisible, testé… et lent.

### Détecter

| Moyen | Ce qu'il donne |
|---|---|
| Journal des requêtes (option `logging` de l'ORM, `withQueryLog` ici) | La même requête répétée avec des paramètres différents : la signature du N+1 |
| Compteur de requêtes dans les tests | Un test qui échoue au-delà de K requêtes (voir section 9) |
| Mode strict de l'ORM | Rails (`strict_loading`, depuis 6.1) et Laravel (`Model::preventLazyLoading()`) lèvent une erreur au lieu de charger paresseusement |
| Côté base | `pg_stat_statements` (PostgreSQL) : une requête simple avec un nombre d'appels anormalement élevé |

### Solution A — Une jointure (exécutable)

```javascript
function listActiveProjectsJoin(db) {
  const rows = db
    .prepare(
      `SELECT p.id, p.title, m.handle AS owner, t.label AS tag
       FROM projects p
       JOIN members m            ON m.id = p.owner_id
       LEFT JOIN project_tags pt ON pt.project_id = p.id
       LEFT JOIN tags t          ON t.id = pt.tag_id
       WHERE p.status = 'active'
       ORDER BY p.id, t.label`
    )
    .all();

  // Une ligne par (projet, étiquette) : il faut regrouper côté application.
  const byId = new Map();
  for (const row of rows) {
    if (!byId.has(row.id)) byId.set(row.id, { title: row.title, owner: row.owner, tags: [] });
    if (row.tag !== null) byId.get(row.id).tags.push(row.tag);
  }
  return [...byId.values()];
}
```

**1 requête**, mais 6 lignes pour 3 projets : le titre et le propriétaire sont répétés pour chaque étiquette. Trois compromis à connaître :

1. **Duplication** : les colonnes du parent sont transférées autant de fois qu'il a d'enfants.
2. **Produit cartésien** : joindre *deux* relations 1-n indépendantes multiplie les lignes. Le projet 2 a 3 contributeurs et 2 étiquettes :

   ```sql
   SELECT p.title, c.member_id, pt.tag_id
   FROM projects p
   JOIN contributions c ON c.project_id = p.id
   JOIN project_tags pt ON pt.project_id = p.id
   WHERE p.id = 2;   -- 6 lignes (3 × 2), et ça croît en produit, pas en somme
   ```

   EF Core appelle ça *cartesian explosion* et propose `AsSplitQuery()` précisément pour l'éviter. Le même gonflement fausse aussi les agrégats (`COUNT`, `SUM`) calculés sur ces jointures : c'est démontré dans le [module 02](../02-sql-query-builder-orm/notes.md).
3. **Pagination cassée** : `LIMIT` compte des **lignes**, pas des projets.

   ```sql
   SELECT p.id, p.title, t.label
   FROM projects p
   JOIN project_tags pt ON pt.project_id = p.id
   JOIN tags t ON t.id = pt.tag_id
   ORDER BY p.id
   LIMIT 2;          -- 2 lignes… qui sont les 2 étiquettes du projet 1 : une « page » d'un seul projet
   ```

   C'est pour cela que Doctrine fournit un `Paginator` dédié aux *fetch joins* (il pagine d'abord les identifiants, puis charge).

### Solution B — Préchargement par lots (exécutable)

Une requête pour la liste, puis **une requête par relation** avec `IN (...)`. Le nombre de requêtes dépend du nombre de relations, plus du nombre de lignes.

```javascript
const placeholders = (values) => values.map(() => '?').join(', ');

function listActiveProjectsPreload(db) {
  const projects = db
    .prepare("SELECT id, title, owner_id FROM projects WHERE status = 'active' ORDER BY id")
    .all();
  if (projects.length === 0) return [];

  const ownerIds = [...new Set(projects.map((p) => p.owner_id))];
  const owners = new Map(
    db
      .prepare(`SELECT id, handle FROM members WHERE id IN (${placeholders(ownerIds)})`)
      .all(...ownerIds)
      .map((m) => [m.id, m.handle])
  );

  const projectIds = projects.map((p) => p.id);
  const tagsByProject = Map.groupBy(
    db
      .prepare(
        `SELECT pt.project_id, t.label FROM project_tags pt
         JOIN tags t ON t.id = pt.tag_id
         WHERE pt.project_id IN (${placeholders(projectIds)})
         ORDER BY t.label`
      )
      .all(...projectIds),
    (row) => row.project_id
  );

  return projects.map((p) => ({
    title: p.title,
    owner: owners.get(p.owner_id),
    tags: (tagsByProject.get(p.id) ?? []).map((row) => row.label),
  }));
}
// 3 requêtes, que la liste contienne 3 projets ou 3 000.
```

- ✅ Pas de duplication, pas de produit cartésien, la pagination s'applique à la première requête et reste juste.
- ⚠️ Plus d'allers-retours que la jointure (1 + nombre de relations).
- ⚠️ La liste `IN (...)` a des limites : nombre maximal de paramètres par requête (65 535 dans le protocole PostgreSQL ; 32 766 par défaut dans SQLite récent) et plans moins bons sur des listes immenses. En PostgreSQL on passe plutôt **un seul paramètre tableau** : `WHERE id = ANY($1)`.

### Solution C — Agrégation JSON en base (exécutable)

Une seule requête, une ligne par projet, les enfants agrégés en JSON par la base :

```javascript
function listActiveProjectsJson(db) {
  return db
    .prepare(
      `SELECT p.title, m.handle AS owner,
              (SELECT json_group_array(t.label)
                 FROM (SELECT t.label FROM project_tags pt
                       JOIN tags t ON t.id = pt.tag_id
                       WHERE pt.project_id = p.id ORDER BY t.label) AS t) AS tags
       FROM projects p
       JOIN members m ON m.id = p.owner_id
       WHERE p.status = 'active'
       ORDER BY p.id`
    )
    .all()
    .map((row) => ({ title: row.title, owner: row.owner, tags: JSON.parse(row.tags) }));
}
```

En PostgreSQL : `jsonb_agg` dans une sous-requête `LATERAL`. C'est la stratégie qu'utilisent des outils récents : Drizzle annonce que ses *relational queries* produisent une seule requête SQL, et Prisma propose `relationLoadStrategy: 'join'` (LATERAL JOIN sur PostgreSQL ; option encore en *preview* derrière le flag `relationJoins` au moment où ces notes sont écrites). Compromis : SQL plus complexe à lire, et types JSON à re-convertir (dates, décimaux) côté application.

### Ce que proposent les ORMs

| ORM | Jointure | Requêtes séparées | Remarque |
|---|---|---|---|
| Rails (Active Record) | `eager_load` | `preload` | `includes` choisit tout seul, ce qui est pratique et opaque |
| Doctrine | `JOIN FETCH` en DQL | `fetch: EAGER` / requêtes dédiées | `Paginator` pour paginer un fetch join |
| EF Core | `AsSingleQuery()` | `AsSplitQuery()` | avertit en cas d'explosion cartésienne |
| Sequelize | `include` | `include` + `separate: true` (relations hasMany) | |
| Prisma | `relationLoadStrategy: 'join'` (preview) | `include` par défaut historiquement | |
| Laravel (Eloquent) | `join` manuel | `with()` | |

Les noms changent, le choix est toujours le même : **une requête avec duplication ou plusieurs requêtes sans duplication**. Il n'y a pas de bonne réponse universelle ; il y a une réponse par cas d'usage, mesurée.

### Solution D — Regrouper les chargements (DataLoader)

Quand le code est structuré en fonctions indépendantes (un *resolver* GraphQL par champ, un composant par carte), on ne peut pas toujours écrire « charge tous les propriétaires d'un coup ». Le pattern **DataLoader** (bibliothèque publiée par Facebook) inverse le problème : chaque fonction demande *sa* clé, le loader **collecte les clés demandées pendant le même tour de boucle d'événements**, puis envoie une seule requête.

```javascript
// Exécutable (version minimale ; la vraie bibliothèque gère plus de cas)
class DataLoader {
  #batchFn;
  #queue = [];
  #cache = new Map();

  constructor(batchFn) {
    this.#batchFn = batchFn;
  }

  load(key) {
    if (this.#cache.has(key)) return this.#cache.get(key);
    const promise = new Promise((resolve, reject) => {
      this.#queue.push({ key, resolve, reject });
      // Premier élément du lot : on programme l'envoi après le code synchrone en cours.
      if (this.#queue.length === 1) queueMicrotask(() => this.#dispatch());
    });
    this.#cache.set(key, promise);
    return promise;
  }

  async #dispatch() {
    const batch = this.#queue;
    this.#queue = [];
    try {
      const values = await this.#batchFn(batch.map((item) => item.key));
      batch.forEach((item, i) => item.resolve(values[i]));
    } catch (error) {
      batch.forEach((item) => item.reject(error));
    }
  }
}

const memberLoader = new DataLoader(async (ids) => {
  const rows = db
    .prepare(`SELECT id, handle FROM members WHERE id IN (${ids.map(() => '?').join(', ')})`)
    .all(...ids);
  const byId = new Map(rows.map((row) => [row.id, row]));
  return ids.map((id) => byId.get(id) ?? null); // contrat : une valeur par clé, dans le même ordre
});

const projects = db.prepare('SELECT id, title, owner_id FROM projects').all();
await Promise.all(projects.map((p) => memberLoader.load(p.owner_id))); // 1 requête, pas 5
```

Trois points de rigueur :

- **Le contrat de `batchFn`** : renvoyer exactement une valeur par clé, dans l'ordre des clés. La base ne garantit aucun ordre pour `IN (...)`, d'où la `Map`.
- **La fenêtre de regroupement** : ici une microtâche. Un `load()` émis *après* un `await` part dans un autre lot. La vraie bibliothèque attend un peu plus longtemps (elle laisse se vider la file des promesses déjà résolues), mais le principe et la limite sont les mêmes.
- **Le cache est par requête HTTP**, jamais global : sinon il sert des données périmées et mélange les droits d'accès entre utilisateurs.

Prisma applique ce principe en interne : sa documentation indique que des `findUnique()` émis dans le même tick sont regroupés en une requête (sous conditions sur `where` et `include` : voir sa page sur le N+1).

### Sélectionner seulement ce qui sert

Charger `SELECT *` pour afficher un pseudo, c'est le petit frère du N+1 : on ne multiplie pas les requêtes, on multiplie les octets. Les ORMs le proposent tous (`select` Prisma, `attributes` Sequelize, `columns` Drizzle) ; on y revient en section 6.

---

## 2. 💤 Lazy loading vs eager loading

### Définitions

- **Eager loading** (chargement anticipé) : on charge les relations **en même temps** que l'objet, parce qu'on sait qu'on va s'en servir. Les solutions A, B, C ci-dessus.
- **Lazy loading** (chargement paresseux) : on charge une relation **au premier accès**. Fowler (*PoEAA*, « Lazy Load ») en décrit quatre implémentations : *lazy initialization*, *virtual proxy*, *value holder*, *ghost*.

Le lazy loading n'est pas un défaut en soi : il évite de charger ce qui ne sert pas. Le problème est qu'il **décide du nombre de requêtes à un endroit du code qui ne le voit pas**.

### En JavaScript, « lazy » est forcément asynchrone (exécutable)

Un accès à la base ne peut pas bloquer le fil d'exécution JS. Une relation paresseuse est donc une **promesse** :

```javascript
function hydrateProject(db, row) {
  let owner; // cache local de la relation
  return {
    ...row,
    get owner() {
      owner ??= Promise.resolve(
        db.prepare('SELECT id, handle FROM members WHERE id = ?').get(row.owner_id)
      );
      return owner;
    },
  };
}

const projects = db.prepare('SELECT id, title, owner_id FROM projects').all()
  .map((row) => hydrateProject(db, row));

for (const p of projects) console.log(p.title, (await p.owner).handle); // N+1, version masquée
```

C'est exactement la forme des ORMs JS :

- **TypeORM** : une relation déclarée avec le type `Promise<Member>` est paresseuse (`await project.owner`).
- **Sequelize** : les associations génèrent des méthodes `project.getOwner()` qui renvoient une promesse.
- **Prisma** : pas de lazy loading implicite ; on écrit `include` ou une requête explicite (y compris l'API « fluent » `findUnique(...).owner()`, qui reste une requête visible).

### Le piège de la sérialisation

```javascript
const fresh = hydrateProject(db, db.prepare('SELECT * FROM projects WHERE id = 1').get());
console.log(JSON.stringify(fresh));
// {"id":1,...,"owner":{}}
```

`JSON.stringify` appelle le getter (donc **lance une requête**) et sérialise la promesse… en `{}`. Double peine : une requête inutile et une donnée fausse. Selon l'ORM, la sérialisation d'une entité peut aussi bien **déclencher** des chargements en cascade que **rater** des relations non chargées ; dans les deux cas, ce que reçoit le client dépend de l'historique de l'objet, pas d'un contrat.

En Java, Hibernate charge paresseusement de façon synchrone via des proxies ; l'accès après fermeture de la session lève la fameuse `LazyInitializationException`. Le contournement « Open Session in View » (garder la session ouverte jusqu'au rendu) supprime l'erreur et rétablit… le N+1 dans les templates.

### Règle pratique

> **Chaque cas d'usage déclare ce qu'il charge.** Le lazy loading implicite est interdit par défaut (mode strict quand l'ORM le propose), et ce qui sort de l'application passe par un objet de sortie explicite (DTO), jamais par la sérialisation d'une entité.

---

## 3. 🪞 Identity Map et Unit of Work

Ces deux patterns de Fowler sont ce qui distingue un ORM de type **Data Mapper « complet »** (Hibernate, Doctrine, MikroORM, SQLAlchemy, EF Core) d'un générateur de requêtes typé (Prisma, Drizzle) ou d'un Active Record (Sequelize). Rappel des familles : [module 01](../01-fondamentaux/notes.md).

### Identity Map

> « Ensures that each object gets loaded only once by keeping every loaded object in a map. » — Fowler, *PoEAA*

Sans Identity Map, charger deux fois la ligne `projects#1` donne **deux objets**. Modifier l'un ne modifie pas l'autre ; à l'enregistrement, le dernier écrit écrase le premier, à l'intérieur même d'une seule requête HTTP.

```javascript
// Exécutable
class IdentityMap {
  #maps = new Map(); // table -> Map<id, entity>

  get(table, id) {
    return this.#maps.get(table)?.get(id);
  }

  add(table, entity) {
    if (!this.#maps.has(table)) this.#maps.set(table, new Map());
    this.#maps.get(table).set(entity.id, entity);
  }
}

function findProject(db, identityMap, id) {
  const cached = identityMap.get('projects', id);
  if (cached) return cached;                       // aucune requête
  const row = db.prepare('SELECT * FROM projects WHERE id = ?').get(id);
  if (row) identityMap.add('projects', row);
  return row ?? null;
}

const map = new IdentityMap();
console.log(findProject(db, map, 1) === findProject(db, map, 1)); // true, et une seule requête
```

Deux précisions qui évitent des contresens :

- **Le but premier est la cohérence** (un objet par ligne et par session), le cache n'est qu'un effet secondaire. Une requête par critère (`WHERE status = 'active'`) part quand même en base ; l'Identity Map sert à **réutiliser** les objets déjà chargés pour les lignes renvoyées.
- **Ce n'est pas un cache partagé.** Sa portée est une unité de travail, typiquement une requête HTTP. Le cache « de second niveau » d'Hibernate ou de Doctrine est un autre mécanisme, avec ses propres problèmes d'invalidation.

### Unit of Work

> « Maintains a list of objects affected by a business transaction and coordinates the writing out of changes and the resolution of concurrency problems. » — Fowler, *PoEAA*

Au lieu d'écrire en base à chaque modification, on **enregistre** ce qui change, puis on écrit tout d'un coup (`flush`/`commit`) :

```
registerNew(entity)       → sera INSERT
registerDirty(entity)     → sera UPDATE     (ou détecté automatiquement, voir ci-dessous)
registerRemoved(entity)   → sera DELETE
commit()                  → BEGIN ; INSERT… ; UPDATE… ; DELETE… ; COMMIT
```

Ce que l'Unit of Work règle, et qu'on doit sinon faire à la main :

1. **L'ordre des écritures.** Insérer un membre et son projet : le membre d'abord (le projet a besoin de son id). Supprimer : les enfants d'abord. L'ORM trie les opérations selon le graphe des clés étrangères ; en cas de cycle, il doit insérer avec une FK nulle puis la mettre à jour.
2. **Les identifiants générés.** Un nouveau projet référence un *objet* membre qui n'a pas encore d'id ; au `commit`, l'Unit of Work insère le membre, récupère son id et le propage.
3. **Le *dirty checking*.** Trois façons de savoir qu'un objet a changé : l'appelant le signale (`registerDirty`, la version de Fowler) ; l'ORM compare l'état courant à un **instantané** pris au chargement (Doctrine, Hibernate, MikroORM) ; ou il intercepte les affectations (proxies). L'instantané coûte de la mémoire et un parcours de toutes les entités suivies à chaque `flush`.
4. **L'atomicité.** Tout dans une transaction : un échec au milieu annule tout.
5. **La minimalité.** Seules les colonnes modifiées sont écrites ; une entité chargée et inchangée ne génère aucune requête.

Le [kata 4](katas.md) en construit une version complète (avec instantanés et résolution des références). Le cœur de `commit()` ressemble à ceci :

```javascript
commit() {
  this.db.exec('BEGIN');
  try {
    for (const entity of sortParentsFirst(this.newEntities)) this.insert(entity); // récupère et propage l'id
    for (const change of this.computeDirty()) this.update(change);                // colonnes modifiées seulement
    for (const entity of sortChildrenFirst(this.removedEntities)) this.delete(entity);
    this.db.exec('COMMIT');
  } catch (error) {
    this.db.exec('ROLLBACK');
    throw error;
  }
}
```

### Portée et cycle de vie

- **Une Unit of Work par requête HTTP** (ou par tâche de fond). MikroORM l'impose : il refuse par défaut d'utiliser l'`EntityManager` global et demande un contexte par requête (`RequestContext`, `em.fork()`). Symfony crée un `EntityManager` par requête.
- **Une Unit of Work globale** grossit indéfiniment (toutes les entités jamais chargées restent suivies), sert des données périmées, et mélange les requêtes de différents utilisateurs.
- **Après un échec de `flush`, l'état mémoire ne correspond plus à la base.** Doctrine ferme alors l'`EntityManager` (« The EntityManager is closed ») : il faut en recréer un, pas continuer.
- **Les opérations en masse contournent l'Unit of Work.** Un `UPDATE` DQL ou un `updateMany` modifie la base sans toucher les objets déjà en mémoire, qui deviennent faux (voir section 6).

### Qui implémente quoi

| Outil | Identity Map | Unit of Work |
|---|---|---|
| Hibernate / JPA | ✅ (contexte de persistance) | ✅ |
| Doctrine ORM | ✅ | ✅ (`flush()`) |
| MikroORM | ✅ | ✅ (`em.flush()`) |
| SQLAlchemy (Session) | ✅ | ✅ |
| EF Core (DbContext) | ✅ (résolution d'identité des entités suivies) | ✅ (`SaveChanges()`) |
| Sequelize | ❌ | ❌ (chaque `save()` écrit tout de suite) |
| TypeORM | ❌ | ❌ (`save()` immédiat) |
| Prisma | ❌ (objets simples, nouveaux à chaque requête) | ❌ (chaque appel est une requête ; regroupement possible via `$transaction`) |
| Drizzle, Kysely, Knex | ❌ | ❌ (ce n'est pas leur rôle) |

Ce n'est pas un classement. Sans Unit of Work, **ce que tu écris est ce qui part en base**, au moment où tu l'écris : c'est plus prévisible. Avec, tu gagnes la cohérence d'un graphe d'objets, au prix d'écritures différées dont l'ordre et le contenu sont décidés par l'ORM.

---

## 4. 🔒 Transactions

### ACID, sans folklore

- **A — Atomicité** : en cas d'échec, tout est annulé. Kleppmann suggère de penser « *abortability* » : la capacité à abandonner proprement.
- **C — Cohérence** : c'est une propriété **de l'application** (ses invariants), que la base aide à tenir avec des contraintes. La base ne sait pas qu'« un projet actif doit avoir un auteur ».
- **I — Isolation** : comment les transactions concurrentes se voient. C'est la lettre qui pose le plus de problèmes, et elle est **négociable** : chaque niveau d'isolation est un compromis performance / anomalies.
- **D — Durabilité** : une fois validé, ça survit à une panne (écriture sur disque, `fsync`, réplication). Jamais absolu : un disque qui ment sur ses `fsync` casse la promesse.

### Une transaction, et des transactions imbriquées (exécutable)

```javascript
const depths = new WeakMap(); // profondeur d'imbrication, par connexion

function transaction(db, fn) {
  const depth = depths.get(db) ?? 0;
  const savepoint = `sp_${depth}`;
  db.exec(depth === 0 ? 'BEGIN' : `SAVEPOINT ${savepoint}`);
  depths.set(db, depth + 1);
  try {
    const result = fn();
    db.exec(depth === 0 ? 'COMMIT' : `RELEASE ${savepoint}`);
    return result;
  } catch (error) {
    db.exec(depth === 0 ? 'ROLLBACK' : `ROLLBACK TO ${savepoint}; RELEASE ${savepoint}`);
    throw error;
  } finally {
    depths.set(db, depth);
  }
}

// Transférer un projet ET garder l'ancien propriétaire comme contributeur : tout ou rien.
function transferProject(db, projectId, newOwnerId) {
  return transaction(db, () => {
    const { owner_id: previousOwnerId } = db
      .prepare('SELECT owner_id FROM projects WHERE id = ?')
      .get(projectId);
    db.prepare('UPDATE projects SET owner_id = ? WHERE id = ?').run(newOwnerId, projectId);
    db.prepare(
      `INSERT INTO contributions (member_id, project_id, role) VALUES (?, ?, 'ancien auteur')
       ON CONFLICT (member_id, project_id) DO UPDATE SET role = excluded.role`
    ).run(previousOwnerId, projectId);
  });
}

const db = openDb();
transferProject(db, 3, 2);       // ok
try {
  transferProject(db, 3, 999);   // membre inexistant : la clé étrangère échoue
} catch (error) {
  console.log('annulé :', error.message); // FOREIGN KEY constraint failed, rien n'a changé
}
```

Les **savepoints** permettent d'annuler une partie d'une transaction sans annuler le reste. C'est ainsi que Knex et Doctrine DBAL traduisent les « transactions imbriquées » : il n'existe pas de vraie transaction dans une transaction en SQL standard, seulement des savepoints.

### Les anomalies de concurrence

Exemples dans le domaine de l'Atelier. T1 et T2 sont deux transactions concurrentes.

| Anomalie | Ce qui se passe | Exemple |
|---|---|---|
| **Dirty write** (P0) | T2 écrase une écriture non validée de T1 | Tous les SGBD l'empêchent, à tous les niveaux |
| **Dirty read** (P1) | T2 lit une écriture que T1 va annuler | T2 affiche un titre qui n'a jamais existé |
| **Non-repeatable read** (P2) | T1 relit une ligne et obtient une autre valeur, validée entre-temps par T2 | Le statut d'un projet change entre deux lectures du même rapport |
| **Phantom** (P3) | T1 relit un *ensemble* (`WHERE`) et y trouve des lignes nouvelles | Le nombre de projets actifs change pendant le calcul d'une statistique |
| **Read skew** (A5A) | T1 lit deux objets liés à deux instants différents | Un projet et sa liste de contributeurs incohérents entre eux |
| **Lost update** (P4) | T1 et T2 lisent, calculent, écrivent : une écriture écrase l'autre | Deux « étoiles » ajoutées, une seule comptée |
| **Write skew** (A5B) | T1 et T2 vérifient une condition sur un ensemble, puis écrivent des lignes **différentes** qui, ensemble, la violent | Règle : « un projet actif garde au moins un auteur ». Deux auteurs vérifient qu'ils sont deux, puis chacun se retire. Résultat : zéro auteur |

Le *write skew* est le plus traître : aucune ligne n'est écrite deux fois, donc ni le verrou de ligne ni le verrou optimiste ne le voient. Il faut l'isolation `SERIALIZABLE`, ou matérialiser le conflit (verrouiller la ligne du projet pendant la vérification).

### Niveaux d'isolation : la norme et la réalité

La norme SQL définit quatre niveaux par les anomalies P1, P2, P3 qu'ils interdisent :

| Niveau ANSI | Dirty read | Non-repeatable read | Phantom |
|---|---|---|---|
| READ UNCOMMITTED | possible | possible | possible |
| READ COMMITTED | ✅ empêché | possible | possible |
| REPEATABLE READ | ✅ | ✅ | possible |
| SERIALIZABLE | ✅ | ✅ | ✅ |

**Ce tableau ne suffit pas.** Berenson et al. (« A Critique of ANSI SQL Isolation Levels », 1995) ont montré que les définitions de la norme sont ambiguës (lecture « stricte » ou « large » de chaque phénomène), qu'elles oublient des anomalies (dirty write, lost update, read skew, write skew), et que l'**isolation par instantané** (*snapshot isolation*), utilisée par la plupart des SGBD modernes, ne rentre dans aucune case : elle empêche les phantoms au sens strict mais autorise le write skew.

Conséquence pratique : **un nom de niveau ne dit pas la même chose d'un SGBD à l'autre**.

| SGBD | Niveau par défaut | Ce qu'il faut savoir |
|---|---|---|
| PostgreSQL | READ COMMITTED | `REPEATABLE READ` = snapshot isolation (détecte les lost updates en levant une erreur, autorise le write skew) ; `SERIALIZABLE` = SSI, sérialisable pour de vrai, au prix d'erreurs `40001` à rejouer |
| MySQL / InnoDB | REPEATABLE READ | Lectures cohérentes par instantané, mais un `UPDATE` lit la dernière version validée : le schéma lire-calculer-écrire peut perdre des mises à jour |
| SQL Server | READ COMMITTED (par verrous) | Option `READ_COMMITTED_SNAPSHOT` pour passer en versions |
| Oracle | READ COMMITTED | Pas de READ UNCOMMITTED ni de REPEATABLE READ |
| SQLite | SERIALIZABLE | Un seul écrivain à la fois ; les conflits deviennent des erreurs `SQLITE_BUSY` |

> Ce sont aussi les défauts listés par la documentation de Prisma pour `$transaction` (PostgreSQL ReadCommitted, MySQL RepeatableRead, SQLite Serializable). Quand l'ORM ne précise rien, **c'est le défaut du SGBD qui s'applique**.

### PostgreSQL : la mise à jour perdue en READ COMMITTED (illustratif)

```sql
-- T1                                         -- T2
BEGIN;                                        BEGIN;
SELECT stars FROM projects WHERE id = 1;      
-- → 10                                       SELECT stars FROM projects WHERE id = 1;
                                              -- → 10
UPDATE projects SET stars = 11 WHERE id = 1;
COMMIT;
                                              UPDATE projects SET stars = 11 WHERE id = 1;
                                              COMMIT;   -- ✅ accepté : une étoile perdue
```

Même scénario en `REPEATABLE READ` : l'`UPDATE` de T2 échoue avec `ERROR: could not serialize access due to concurrent update` (SQLSTATE `40001`). L'anomalie est **détectée**, pas évitée : l'application doit rejouer la transaction.

### Rejouer une transaction (illustratif)

```javascript
const RETRYABLE = new Set(['40001', '40P01']); // serialization_failure, deadlock_detected

async function withRetry(pool, fn, { attempts = 3 } = {}) {
  for (let attempt = 1; ; attempt++) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      if (!RETRYABLE.has(error.code) || attempt === attempts) throw error;
      await new Promise((r) => setTimeout(r, 2 ** attempt * 10 + Math.random() * 10)); // backoff + jitter
    } finally {
      client.release();
    }
  }
}
```

On rejoue **toute la transaction, lectures comprises** (les décisions prises sur d'anciennes lectures sont fausses), et `fn` ne doit avoir aucun effet hors base (pas d'e-mail, pas d'appel HTTP) : il pourrait s'exécuter trois fois.

### Les transactions dans les ORMs

```javascript
// Illustratif (Prisma)
// 1. Séquentielle : un tableau d'opérations indépendantes, exécutées dans une transaction.
await prisma.$transaction([
  prisma.project.update({ where: { id: 4 }, data: { status: 'archived' } }),
  prisma.projectTag.deleteMany({ where: { projectId: 4 } }),
]);

// 2. Interactive : du code arbitraire entre les requêtes, avec le client transactionnel `tx`.
await prisma.$transaction(
  async (tx) => {
    const project = await tx.project.findUniqueOrThrow({ where: { id: 3 } });
    await tx.project.update({ where: { id: 3 }, data: { ownerId: 2 } });
    await tx.contribution.upsert({
      where: { memberId_projectId: { memberId: project.ownerId, projectId: 3 } }, // clé @@id([memberId, projectId])
      create: { memberId: project.ownerId, projectId: 3, role: 'ancien auteur' },
      update: { role: 'ancien auteur' },
    });
  },
  { isolationLevel: 'Serializable', maxWait: 2000, timeout: 5000 } // valeurs par défaut documentées : 2000 / 5000 ms
);
```

Pièges récurrents, quel que soit l'ORM :

- **Utiliser le mauvais client.** Dans le callback, une requête faite avec `prisma` (au lieu de `tx`), `knex` (au lieu de `trx`) ou sans l'option `{ transaction: t }` de Sequelize part **sur une autre connexion, hors transaction**. Le code a l'air transactionnel ; il ne l'est pas.
- **Les transactions longues.** Une transaction interactive garde une connexion du pool et ses verrous pendant toute sa durée. Pas d'appel réseau externe à l'intérieur.
- **Les effets de bord.** Un e-mail envoyé dans la transaction part même si elle est annulée ensuite (section 7, *outbox*).

---

## 5. ⚔️ Concurrence : la mise à jour perdue

### Démonstration (exécutable)

Deux connexions sur le **même fichier** (mode WAL), une colonne `stars` ajoutée pour l'exemple :

```javascript
import { openDb } from '../fil-rouge/open-db.mjs';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dir = mkdtempSync(join(tmpdir(), 'atelier-'));
const file = join(dir, 'atelier.db');
const setup = openDb({ path: file });
setup.exec('PRAGMA journal_mode = WAL');
setup.exec('ALTER TABLE projects ADD COLUMN stars INTEGER NOT NULL DEFAULT 0');
setup.close();

const alice = new DatabaseSync(file);
const bob = new DatabaseSync(file);
const read = (conn) => conn.prepare('SELECT stars FROM projects WHERE id = 1').get().stars;
const write = (conn, value) => conn.prepare('UPDATE projects SET stars = ? WHERE id = 1').run(value);

// Cas 1 : lecture et écriture dans des transactions séparées (le cas d'une appli web)
const a = read(alice);
const b = read(bob);
write(alice, a + 1);
write(bob, b + 1);
console.log(read(alice)); // 1 : une étoile perdue, aucune erreur

// Cas 2 : lecture et écriture dans UNE transaction chacune
write(alice, 0);
alice.exec('BEGIN');
bob.exec('BEGIN');
const a2 = read(alice);
const b2 = read(bob);
write(alice, a2 + 1);
alice.exec('COMMIT');
try {
  write(bob, b2 + 1); // l'instantané de Bob est périmé
  bob.exec('COMMIT');
} catch (error) {
  console.log(error.message, error.errcode); // database is locked 517 (SQLITE_BUSY_SNAPSHOT)
  bob.exec('ROLLBACK');
}

// Cas 3 : mise à jour atomique, aucune lecture côté application
write(alice, 0);
alice.prepare('UPDATE projects SET stars = stars + 1 WHERE id = 1').run();
bob.prepare('UPDATE projects SET stars = stars + 1 WHERE id = 1').run();
console.log(read(alice)); // 2

alice.close();
bob.close();
rmSync(dir, { recursive: true });
```

Ce que montre l'expérience :

- **Cas 1 : aucun niveau d'isolation ne te protège** quand la lecture et l'écriture sont dans deux transactions différentes. C'est pourtant le cas normal sur le web : on lit pour afficher un formulaire (requête 1), on écrit quand il est soumis (requête 2), parfois des minutes plus tard. Fowler appelle ça une **transaction métier** qui s'étend sur plusieurs transactions système.
- **Cas 2 : SQLite, sérialisable, refuse la seconde écriture** (`SQLITE_BUSY_SNAPSHOT`, code étendu 517). PostgreSQL en `REPEATABLE READ` ferait la même chose ; en `READ COMMITTED`, il accepterait et perdrait l'étoile.
- **Cas 3 : la voie la plus simple** quand l'écriture peut s'exprimer à partir de l'état courant. Pas de lecture, donc rien à perdre.

### Remède 1 — L'écriture atomique ou conditionnelle

```sql
UPDATE projects SET stars = stars + 1 WHERE id = ?;                          -- incrément
UPDATE projects SET status = 'active' WHERE id = ? AND status = 'draft';     -- transition d'état
```

La seconde forme est un *compare-and-set* : on vérifie `changes` pour savoir si la transition a eu lieu. Les ORMs exposent l'incrément (avec la colonne `stars` de l'exemple : `prisma.project.update({ where: { id }, data: { stars: { increment: 1 } } })` en Prisma, `project.increment('stars')` en Sequelize) ; l'utiliser au lieu de `project.stars += 1; save()` est souvent tout le correctif.

### Remède 2 — Le verrouillage optimiste (exécutable)

Fowler : *Optimistic Offline Lock*. On ne verrouille rien ; on **détecte** le conflit au moment d'écrire grâce à une colonne `version`.

```javascript
const db = openDb();
db.exec('ALTER TABLE projects ADD COLUMN version INTEGER NOT NULL DEFAULT 1');

class ConflictError extends Error {}
class NotFoundError extends Error {}

function renameProject(db, { id, title, version }) {
  const { changes } = db
    .prepare('UPDATE projects SET title = ?, version = version + 1 WHERE id = ? AND version = ?')
    .run(title, id, version);
  if (changes === 1) return version + 1;

  // 0 ligne touchée : le projet n'existe pas, ou quelqu'un est passé avant.
  const current = db.prepare('SELECT version FROM projects WHERE id = ?').get(id);
  if (!current) throw new NotFoundError(`projet ${id} introuvable`);
  throw new ConflictError(`projet ${id} modifié entre-temps (version ${version} → ${current.version})`);
}

const formA = db.prepare('SELECT id, title, version FROM projects WHERE id = 1').get();
const formB = { ...formA }; // deux onglets ouverts sur la même version

renameProject(db, { ...formA, title: 'Carnet du dev — A' }); // ok, version 2
renameProject(db, { ...formB, title: 'Carnet du dev — B' }); // ConflictError
```

- La version voyage avec le formulaire (champ caché, ou en-tête HTTP : `ETag` en lecture, `If-Match` en écriture, `412 Precondition Failed` en cas de conflit ; ou `409 Conflict`).
- Que faire du conflit ? Recharger et réafficher, fusionner automatiquement les champs non concurrents, ou laisser l'utilisateur choisir. C'est une décision **produit**, pas technique.
- Support dans les ORMs : `@Version` (JPA/Hibernate), `#[Version]` (Doctrine), jeton de concurrence (EF Core), option `version: true` (Sequelize, `OptimisticLockError`), `version: true` sur une propriété (MikroORM). Vérifie que l'ORM **vérifie** la version dans le `WHERE` et ne se contente pas de l'incrémenter.

### Remède 3 — Le verrouillage pessimiste (illustratif)

On **empêche** le conflit en verrouillant avant de lire.

```sql
-- PostgreSQL
BEGIN;
SELECT stars FROM projects WHERE id = 1 FOR UPDATE;   -- les autres FOR UPDATE / UPDATE attendent
UPDATE projects SET stars = 11 WHERE id = 1;
COMMIT;

SELECT … FOR UPDATE NOWAIT;        -- échoue tout de suite au lieu d'attendre
SELECT … FOR UPDATE SKIP LOCKED;   -- ignore les lignes verrouillées : idéal pour une file de tâches
```

SQLite n'a pas de verrou de ligne ; son équivalent est `BEGIN IMMEDIATE`, qui prend le verrou d'écriture **de toute la base** dès le début de la transaction (testé : une seconde connexion attend jusqu'à son `timeout`, puis échoue avec `database is locked`).

Coûts : attente, risque d'interblocage (*deadlock*, que PostgreSQL détecte et résout en tuant une des transactions, code `40P01`), et impossibilité de verrouiller pendant qu'un humain remplit un formulaire. Le verrou pessimiste couvre une transaction **système** courte ; pour une transaction métier longue, on revient à l'optimiste.

### Choisir

| Situation | Remède |
|---|---|
| Compteur, incrément, transition d'état simple | Écriture atomique / conditionnelle |
| Formulaire d'édition, conflits rares, humain dans la boucle | Verrou optimiste |
| Conflits fréquents, section critique courte, file de tâches | Verrou pessimiste (`FOR UPDATE`, `SKIP LOCKED`) |
| Invariant sur un ensemble de lignes (write skew) | `SERIALIZABLE` + retry, ou verrou sur une ligne qui matérialise le conflit |

---

## 6. ⚡ Performance

### Index : ce que l'ORM ne fait pas pour toi

Ni PostgreSQL ni SQLite ne créent d'index sur une colonne de clé étrangère (MySQL/InnoDB, si). Le schéma du fil rouge les crée explicitement (`projects_owner_id_idx`…). Sans eux :

- les jointures `projects → members` lisent toute la table enfant ;
- supprimer un membre impose de **parcourir toute la table `projects`** pour vérifier le `RESTRICT` ou appliquer le `CASCADE`.

Certains ORMs ajoutent ces index dans les migrations qu'ils génèrent, d'autres non : lis le SQL généré ([module 03](../03-migrations/notes.md)).

### Lire un plan d'exécution (exécutable)

```javascript
const db = openDb({ seed: false });
db.exec("INSERT INTO members (id, handle, email) VALUES (1, 'theo', 'theo@atelier.test')");

// 100 000 projets, insérés dans UNE transaction
const insert = db.prepare('INSERT INTO projects (owner_id, title, status, created_at) VALUES (1, ?, ?, ?)');
const statuses = ['draft', 'active', 'archived'];
db.exec('BEGIN');
for (let i = 0; i < 100_000; i++) {
  const at = new Date(Date.UTC(2020, 0, 1) + i * 3_600_000).toISOString().replace('T', ' ').slice(0, 19);
  insert.run(`Projet ${i}`, statuses[i % 3], at);
}
db.exec('COMMIT');

const plan = (sql) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all().map((row) => row.detail);
const latest = `SELECT id, title, created_at FROM projects
                WHERE status = 'active' ORDER BY created_at DESC, id DESC LIMIT 20`;

console.log(plan(latest));
// [ 'SCAN projects', 'USE TEMP B-TREE FOR ORDER BY' ]   → lit tout, trie tout, garde 20 lignes

db.exec('CREATE INDEX projects_status_created_idx ON projects (status, created_at, id)');
console.log(plan(latest));
// [ 'SEARCH projects USING INDEX projects_status_created_idx (status=?)' ]   → lit 20 entrées dans l'ordre
```

- `SCAN` = lecture de toute la table ; `SEARCH … USING INDEX` = accès par l'index ; `USE TEMP B-TREE FOR ORDER BY` = tri en mémoire ; `COVERING INDEX` = toutes les colonnes utiles sont dans l'index, la table n'est pas lue.
- **L'ordre des colonnes d'un index composite compte** : d'abord les colonnes filtrées par égalité (`status`), puis celles du tri (`created_at, id`). C'est le cœur de l'enseignement de Winand.
- En PostgreSQL : `EXPLAIN (ANALYZE, BUFFERS) …`. Attention, `ANALYZE` **exécute** la requête : sur un `DELETE`, enveloppe-le dans une transaction que tu annules.

### Pagination : OFFSET contre curseur (exécutable)

`OFFSET 30000` oblige la base à produire 30 020 lignes et à en jeter 30 000. La **pagination par curseur** (*keyset*, « no offset » chez Winand) repart de la dernière ligne vue :

```javascript
const offsetPage = db.prepare(
  `SELECT id, title, created_at FROM projects WHERE status = 'active'
   ORDER BY created_at DESC, id DESC LIMIT 20 OFFSET ?`
);
const keysetPage = db.prepare(
  `SELECT id, title, created_at FROM projects
   WHERE status = 'active' AND (created_at, id) < (?, ?)
   ORDER BY created_at DESC, id DESC LIMIT 20`
);

const deep = 30_000;
const lastSeen = offsetPage.all(deep - 1)[0]; // la ligne juste avant la page voulue
console.log(
  JSON.stringify(offsetPage.all(deep)) === JSON.stringify(keysetPage.all(lastSeen.created_at, lastSeen.id))
); // true : mêmes résultats
```

Mesuré sur la machine de test (100 000 lignes en mémoire) : environ **1 ms** par page en OFFSET à cette profondeur, contre **0,02 ms** en keyset, et l'écart croît avec la profondeur. Les chiffres absolus dépendent de ta machine ; la forme de la courbe, non : OFFSET est linéaire en profondeur, keyset constant.

Le keyset est aussi **plus juste** : si une ligne est insérée en tête entre deux pages, OFFSET décale tout et **affiche deux fois** la dernière ligne de la page précédente (testé), alors que le curseur reprend exactement après la dernière ligne vue.

Conditions et limites :

- L'ordre doit être **total** : `created_at` seul a des égalités, d'où le départage par `id`.
- La comparaison de tuples `(a, b) < (?, ?)` existe en PostgreSQL et en SQLite ; ailleurs, on écrit `a < ? OR (a = ? AND b < ?)`.
- Pas de « saut direct à la page 37 », et le nombre total de pages coûte un `COUNT(*)` séparé. Pour un flux ou un défilement infini, ce n'est pas un manque.
- Prisma propose une pagination par curseur (`cursor` + `skip: 1`) ; vérifie le SQL généré.

### `SELECT *`

- Transfère des colonnes inutiles (les gros `TEXT`, les JSON).
- Empêche les **index couvrants** (le plan keyset ci-dessus est `COVERING` parce que la requête testée ne lit que des colonnes indexées).
- Fuit des champs sensibles dès qu'on sérialise la ligne (section 7).
- Rend le code fragile aux changements de schéma.

### Écrire en lot (mesuré)

Sur un **fichier** SQLite (machine de test) : 2 000 `INSERT` en mode autocommit ≈ **2,2 s** ; les mêmes dans une transaction ≈ **7 ms**. Chaque transaction validée attend la confirmation d'écriture disque ; en grouper 2 000 en une seule supprime 1 999 attentes. À retenir :

- Grouper les écritures dans une transaction.
- Utiliser l'insertion multi-lignes (`INSERT … VALUES (…), (…), (…)`), `COPY` en PostgreSQL pour les gros volumes, ou les méthodes de lot des ORMs (`createMany`, `bulkCreate`, `insert([...])`).

### Les opérations en masse contournent l'ORM

C'est le revers des écritures en lot : ce qui va vite passe **à côté** des mécanismes de l'ORM.

| ORM | Opération en masse | Ce qui est contourné |
|---|---|---|
| Rails | `update_all`, `delete_all` | callbacks et validations |
| Laravel | `Project::where(...)->update([...])` | événements de modèle |
| Sequelize | `Model.update()` statique, `bulkCreate` | hooks individuels (sauf `individualHooks: true`), validation (sauf `validate: true` pour `bulkCreate`) |
| Doctrine | `UPDATE` / `DELETE` en DQL | Unit of Work et événements de cycle de vie ; les entités déjà chargées deviennent obsolètes |

Si un invariant vit dans un hook, il n'est pas garanti. Les invariants qui doivent tenir **toujours** vont dans la base (contraintes `CHECK`, `UNIQUE`, FK, triggers).

---

## 7. 🕳️ Comportements cachés et sécurité

### Hooks et effets de bord

Un hook `afterSave` qui envoie un e-mail paraît naturel. Deux problèmes :

1. **Il s'exécute dans la transaction.** Si elle est annulée ensuite, l'e-mail est déjà parti. Rails distingue d'ailleurs `after_save` (dans la transaction) et `after_commit` (après validation).
2. **Il est invisible au point d'appel.** `project.save()` n'annonce pas qu'il envoie un e-mail, déclenche un webhook et recalcule un cache.

La solution robuste est l'**outbox transactionnelle** : dans la même transaction que la modification, on insère une ligne « événement à publier » dans une table `outbox` ; un processus séparé lit cette table et envoie. Soit les deux sont écrits, soit aucun ; l'envoi peut être rejoué (il doit donc être idempotent).

### Mass assignment / over-posting (exécutable)

```javascript
db.exec('ALTER TABLE members ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0');

// ❌ Toutes les clés reçues deviennent des colonnes
function updateMemberUnsafe(db, id, body) {
  const columns = Object.keys(body);
  db.prepare(`UPDATE members SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`)
    .run(...columns.map((c) => body[c]), id);
}
updateMemberUnsafe(db, 2, { email: 'ada@new.test', is_admin: 1 }); // Ada vient de se promouvoir

// ✅ Liste blanche explicite, par cas d'usage
const EDITABLE_BY_SELF = ['handle', 'email'];
const pick = (object, keys) =>
  Object.fromEntries(keys.filter((k) => Object.hasOwn(object, k)).map((k) => [k, object[k]]));

function updateOwnProfile(db, id, body) {
  const changes = pick(body, EDITABLE_BY_SELF);
  const columns = Object.keys(changes);
  if (columns.length === 0) return 0;
  return db
    .prepare(`UPDATE members SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`)
    .run(...columns.map((c) => changes[c]), id).changes;
}
```

La version non sûre est doublement fautive : affectation de masse, **et** injection par les noms de colonnes, qui ne peuvent pas être paramétrés ([module 02](../02-sql-query-builder-orm/notes.md)).

Le cas d'école date de mars 2012 : Egor Homakov a exploité une affectation de masse sur GitHub (application Rails) pour ajouter sa clé publique à l'organisation `rails` et pousser un commit sur le dépôt de Rails lui-même. Rails 4 a ensuite rendu obligatoires les *strong parameters*. Laravel a `$fillable` / `$guarded`. Le principe, quel que soit l'outil : **la liste des champs modifiables dépend de qui modifie et pourquoi**, elle n'est pas une propriété du modèle.

### La sérialisation qui fuit

```javascript
db.exec('ALTER TABLE members ADD COLUMN password_hash TEXT');
res.json(db.prepare('SELECT * FROM members WHERE id = ?').get(id)); // ❌ envoie password_hash

const toPublicMember = ({ id, handle }) => ({ id, handle });           // ✅ contrat de sortie explicite
```

Les ORMs proposent des garde-fous (`omit` Prisma, stable depuis la 6.2 ; `defaultScope` avec exclusion d'attributs en Sequelize ; `$hidden` en Eloquent). Ce sont des filets ; le contrat de sortie explicite (DTO) reste la règle, parce qu'il échoue **fermé** : un champ ajouté au schéma n'est pas exposé tant qu'on ne l'ajoute pas au DTO.

### Le soft delete et ses pièges (exécutable)

On ne supprime pas, on marque : `deleted_at = now()`, et l'ORM filtre automatiquement (`paranoid: true` Sequelize, `SoftDeletes` Eloquent, `@DeleteDateColumn` TypeORM, filtre Doctrine). Les pièges :

1. **L'unicité.** Un membre supprimé « en douceur » bloque son e-mail : `UNIQUE(email)` le voit toujours. Correctif : un index unique **partiel**.

   ```sql
   CREATE UNIQUE INDEX accounts_email_alive_uq ON accounts (email) WHERE deleted_at IS NULL;
   -- testé : une ligne supprimée + une ligne vivante avec le même e-mail = ok ; deux vivantes = refusé
   ```

2. **Les filtres oubliés.** Le filtre global ne s'applique qu'aux requêtes qui passent par l'ORM : le SQL brut, les rapports, les jointures manuelles, les vues, les exports voient les lignes « supprimées ».
3. **Les cascades.** `ON DELETE CASCADE` ne se déclenche pas : il n'y a pas eu de `DELETE`. Les contributions d'un projet « supprimé » restent actives.
4. **Le droit.** Un soft delete n'est pas une suppression. Le RGPD prévoit un droit à l'effacement (article 17) et un principe de minimisation (article 5) : garder indéfiniment des données personnelles marquées `deleted_at` est difficile à justifier. Il faut une vraie suppression ou une anonymisation, éventuellement différée.
5. **Le volume.** Tables et index grossissent de lignes que personne ne lit.

Alternatives, selon le besoin réel :

| Besoin | Mécanisme |
|---|---|
| Pouvoir annuler une suppression pendant quelques jours | Soft delete **avec purge programmée** |
| Garder une trace pour l'audit | Table d'archive (déplacer la ligne dans une transaction) ou journal d'événements |
| Retrouver l'état à une date passée | Tables temporelles SQL:2011 (MariaDB, SQL Server, Db2) ; en PostgreSQL, triggers ou extensions |
| Historique complet des changements | *Event sourcing* : un modèle de persistance différent (voir le module CRDT du chapitre offline-first) |

---

## 8. 🏛️ Architecture

### Repository et agrégats, sans sur-ingénierie

Evans (*Domain-Driven Design*, 2003) définit le **Repository** comme une interface de type collection qui donne accès aux **racines d'agrégat**. Un **agrégat** est un groupe d'objets modifiés ensemble sous un même invariant : par exemple un `Project` avec ses `Contribution`s, si la règle « au moins un auteur » appartient au projet.

Ce que ça implique :

- **Un repository par agrégat, pas par table.** Pas de `ContributionRepository` si les contributions ne se modifient qu'à travers leur projet.
- **Des méthodes du domaine, pas un CRUD générique.** `projects.activeOwnedBy(member)` dit quelque chose ; `findAll(where)` répète l'ORM.

L'anti-pattern courant : un `GenericRepository<T>` avec `findById`, `findAll`, `save`, `delete` posé sur un ORM Data Mapper… dont l'`EntityManager` est **déjà** un repository générique. On ajoute une couche, on perd les fonctionnalités de l'ORM (chargement des relations, requêtes riches), on ne gagne rien.

Un repository se justifie quand il **nomme** des requêtes du domaine, isole un SQL brut derrière une interface stable, ou sert de point de substitution pour tester un service sans base. S'il ne fait rien de cela, il ne sert à rien.

### CQRS léger (exécutable)

Les écritures et les lectures n'ont pas les mêmes besoins. Les écritures protègent des invariants : passer par des entités et l'ORM a du sens. Les lectures veulent des données à plat, adaptées à un écran, vite : une vue SQL fait mieux.

```javascript
db.exec(`
  CREATE VIEW project_cards AS
  SELECT p.id, p.title, p.status, m.handle AS owner,
         (SELECT count(*) FROM contributions c WHERE c.project_id = p.id) AS contributors,
         (SELECT group_concat(t.label, ', ') FROM project_tags pt
            JOIN tags t ON t.id = pt.tag_id WHERE pt.project_id = p.id) AS tags
  FROM projects p
  JOIN members m ON m.id = p.owner_id;
`);
db.prepare("SELECT * FROM project_cards WHERE status = 'active'").all();
// [{ id: 1, title: 'Carnet du dev', owner: 'theo', contributors: 2, tags: 'pedagogie, web' }, …]
```

C'est le **CQRS léger** : même base, deux chemins. Le CQRS « complet » (Greg Young) sépare les modèles jusque dans le stockage, avec des projections alimentées par événements. C'est une autre échelle de complexité, qu'on ne prend pas « au cas où ».

### Multi-tenant

Plusieurs clients (*tenants*) partagent l'application. Trois modèles :

| Modèle | Isolation | Coût opérationnel | Risque principal |
|---|---|---|---|
| Une colonne `tenant_id` dans chaque table | faible (logique) | faible | **une requête qui oublie le filtre** expose les données d'un autre client |
| Un schéma PostgreSQL par tenant | moyenne | migrations × N schémas | dérive entre schémas, nombre d'objets |
| Une base par tenant | forte | élevé (connexions, sauvegardes, migrations × N) | coût, agrégations transverses difficiles |

Avec une colonne `tenant_id`, PostgreSQL permet de mettre le filtre **dans la base** avec la *Row-Level Security* :

```sql
-- Illustratif (PostgreSQL)
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects FORCE ROW LEVEL SECURITY;  -- sinon le propriétaire de la table n'est pas filtré
CREATE POLICY tenant_isolation ON projects
  USING (tenant_id = current_setting('app.tenant_id')::int);

-- À chaque transaction de l'application :
BEGIN;
SET LOCAL app.tenant_id = '42';   -- LOCAL : la valeur meurt avec la transaction
SELECT * FROM projects;           -- ne voit que le tenant 42, même si le code oublie le WHERE
COMMIT;
```

Pourquoi `SET LOCAL` et pas `SET` : avec un pool de connexions, la connexion est réutilisée par la requête suivante, peut-être pour un autre tenant. Les superutilisateurs et les rôles `BYPASSRLS` ignorent les politiques : l'application ne doit pas se connecter avec eux.

### Pool de connexions et serverless

Une connexion PostgreSQL est un processus serveur : l'ouvrir coûte cher (authentification, TLS, mémoire). Un **pool** garde quelques connexions ouvertes et les prête. Deux erreurs classiques :

- **Un pool trop grand.** Au-delà du nombre de requêtes que le serveur exécute vraiment en parallèle (de l'ordre du nombre de cœurs), ajouter des connexions ajoute de la contention, pas du débit.
- **Le serverless.** Chaque instance de fonction a son propre pool ; cent instances × dix connexions dépassent vite le `max_connections` de PostgreSQL (100 par défaut). On intercale un *pooler* externe, typiquement **PgBouncer**.

PgBouncer a trois modes : `session` (une connexion serveur par client, peu de gain), `transaction` (connexion rendue à chaque fin de transaction, le mode utile), `statement`. En mode `transaction`, tout ce qui vit **au niveau de la session** casse : `SET` (d'où `SET LOCAL` plus haut), verrous consultatifs de session, `LISTEN`, tables temporaires… et, historiquement, les **requêtes préparées** du protocole. Depuis PgBouncer 1.21, l'option `max_prepared_statements` les prend en charge en mode transaction (désactivée par défaut à l'origine ; plusieurs sources indiquent un défaut à 200 depuis la 1.24 — vérifie ta version et ton hébergeur, certains services managés gardent 0). C'est pour ce problème que Prisma a longtemps documenté un paramètre de connexion `pgbouncer=true`.

---

## 9. 🧪 Tester la couche d'accès aux données

### Une vraie base, pas un mock de l'ORM

Un mock de l'ORM vérifie que tu as appelé l'ORM, pas que ta requête est juste. Les contraintes, les collations, le comportement transactionnel, le SQL généré n'existent que dans la vraie base. Et **le même moteur qu'en production** : SQLite et PostgreSQL divergent sur les types, la sensibilité à la casse de `LIKE`, les contraintes différées, les niveaux d'isolation. Pour PostgreSQL en test, Testcontainers démarre un conteneur jetable par suite.

### Transaction annulée par test + borne sur le nombre de requêtes (exécutable)

```javascript
// queries.test.mjs — lancer avec : node --disable-warning=ExperimentalWarning --test queries.test.mjs
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { openDb, withQueryLog } from '../fil-rouge/open-db.mjs';

const db = withQueryLog(openDb(), { print: false });
beforeEach(() => db.exec('BEGIN'));
afterEach(() => db.exec('ROLLBACK')); // chaque test repart des mêmes données

function assertMaxQueries(db, max, fn) {
  const before = db.queries.length;
  const result = fn();
  const used = db.queries.length - before;
  assert.ok(
    used <= max,
    `${used} requêtes exécutées, ${max} au plus autorisées :\n` +
      db.queries.slice(before).map((q) => `  ${q.sql.replace(/\s+/g, ' ').trim()}`).join('\n')
  );
  return result;
}

function ownerHandles(db) {
  return db
    .prepare('SELECT m.handle FROM projects p JOIN members m ON m.id = p.owner_id ORDER BY p.id')
    .all()
    .map((row) => row.handle);
}

test('la liste des propriétaires tient en 3 requêtes au plus', () => {
  const handles = assertMaxQueries(db, 3, () => ownerHandles(db));
  assert.deepEqual(handles, ['theo', 'ada', 'theo', 'chloe', 'bruno']);
});

test('les écritures d’un test ne fuient pas dans le suivant', () => {
  db.prepare("INSERT INTO tags (label) VALUES ('temporaire')").run();
  assert.equal(db.prepare("SELECT count(*) AS n FROM tags WHERE label = 'temporaire'").get().n, 1);
});
```

Limites de la transaction par test : si le code testé ouvre **lui-même** une transaction, il faut qu'il utilise des savepoints (le helper de la section 4 le fait) ; et une autre connexion ne voit pas les données non validées du test (tests de concurrence, workers).

### Fabriques plutôt que fixtures partagées

- **Fixtures** : un jeu de données fixe chargé pour tous (`seed.sql`). Pratique pour lire, mais chaque test dépend de données qu'il ne déclare pas ; modifier la fixture casse des tests sans rapport.
- **Fabriques** : une fonction qui crée une entité minimale valide, avec des surcharges explicites : `makeProject(db, { status: 'archived' })`. Chaque test montre les données qui comptent pour lui.

---

## 10. 🏷️ Typage depuis la base

Deux directions, deux philosophies ([module 02](../02-sql-query-builder-orm/notes.md) pour le détail) :

- **Schéma → types** : on décrit le schéma (fichier Prisma, schéma Drizzle en TypeScript) ou on introspecte la base (`kysely-codegen`, `kanel`), et l'outil génère les types des tables. Les requêtes sont construites par une API typée.
- **SQL → types** (*SQL-first*) : on écrit du SQL dans des fichiers ; l'outil demande à la base de décrire paramètres et résultats, et génère des fonctions typées (`sqlc`, né en Go ; `PgTyped` pour TypeScript). Le SQL reste du SQL, vérifié contre le vrai schéma.

Dans les deux cas, le typage garantit que la requête est **cohérente avec le schéma**, pas qu'elle est **performante** ni **correcte** sous concurrence. Rien dans ce module n'est rattrapé par un compilateur.

---

## ⚠️ Checklist de revue de code

Avant de valider une modification de la couche d'accès aux données :

- [ ] Combien de requêtes ce code exécute-t-il pour N éléments ? Est-ce constant ?
- [ ] Les relations utilisées sont-elles chargées explicitement ?
- [ ] Ce qui doit être « tout ou rien » est-il dans **une** transaction, et toutes les requêtes utilisent-elles le client transactionnel ?
- [ ] Y a-t-il une lecture suivie d'une écriture ? Qu'arrive-t-il si deux utilisateurs le font en même temps ?
- [ ] Les nouvelles colonnes filtrées ou triées sont-elles indexées ? Le plan d'exécution a-t-il été lu ?
- [ ] La pagination est-elle stable et efficace en profondeur ?
- [ ] Les champs modifiables sont-ils une liste blanche ? La sortie est-elle un DTO explicite ?
- [ ] Un hook envoie-t-il quelque chose hors de la base ?
- [ ] Une opération en masse contourne-t-elle un invariant porté par un hook ?

---

## 🧠 Modèles mentaux

- **L'ORM est un compilateur dont tu ne lis pas la sortie.** Lis-la : le journal des requêtes est la sortie du compilateur.
- **Le coût d'une requête, c'est d'abord l'aller-retour.** Compte les requêtes avant de compter les millisecondes.
- **Une transaction système dure des millisecondes ; une transaction métier dure des minutes.** Les verrous et l'isolation protègent la première ; la seconde a besoin d'un verrou optimiste.
- **Ce qui doit être vrai toujours va dans la base** (contraintes). Ce qui est vrai « quand on passe par l'ORM » est une convention.
- **Implicite = invisible au point d'appel.** Hooks, filtres globaux, lazy loading, sérialisation automatique : chacun est pratique jusqu'au jour où il faut savoir ce qu'a fait une ligne de code.

---

## 🔗 Liens avec les autres modules

- [01 — Fondamentaux](../01-fondamentaux/notes.md) → Active Record et Data Mapper : c'est la famille de l'ORM qui dit s'il a une Identity Map et une Unit of Work.
- [02 — SQL brut, query builder, ORM](../02-sql-query-builder-orm/notes.md) → injection SQL, requêtes paramétrées, approche SQL-first et typage.
- [03 — Migrations](../03-migrations/notes.md) → créer les index et contraintes de ce module sans bloquer la production (`CREATE INDEX CONCURRENTLY`, *expand/contract*).
- [04 — Modélisation](../04-modelisation-merise-uml-erd/notes.md) → agrégats et associations ; l'héritage et ses stratégies de mapping.
- [05 — Documenter](../05-documenter/notes.md) → documenter les comportements cachés (hooks, filtres globaux, soft delete, cascades) et les décisions d'isolation.
- [Offline-first — CRDT](../../../02_offline-first/03-crdt-basics/notes.md) → un autre modèle de concurrence : fusionner plutôt que verrouiller ou rejeter.

---

## 📚 Pour aller plus loin

- **Martin Fowler**, *Patterns of Enterprise Application Architecture* (2002) : Identity Map, Unit of Work, Lazy Load, Optimistic Offline Lock, Pessimistic Offline Lock.
- **H. Berenson, P. Bernstein, J. Gray, J. Melton, E. O'Neil, P. O'Neil**, « A Critique of ANSI SQL Isolation Levels », SIGMOD 1995.
- **Martin Kleppmann**, *Designing Data-Intensive Applications* (2017), chapitre 7 « Transactions » : la meilleure présentation pédagogique des anomalies et du write skew.
- **Documentation PostgreSQL**, chapitre « Concurrency Control » (13.2, *Transaction Isolation*) et « Explicit Locking ».
- **Markus Winand**, *SQL Performance Explained* (2012) et [use-the-index-luke.com](https://use-the-index-luke.com/), en particulier la page [« No Offset »](https://use-the-index-luke.com/no-offset).
- **Eric Evans**, *Domain-Driven Design* (2003), chapitre 6 : agrégats, fabriques, repositories.
- **Chris Richardson**, pattern « Transactional outbox » ([microservices.io](https://microservices.io/patterns/data/transactional-outbox.html)).

---

**Dernière mise à jour** : 2026-10-29
**Niveau** : Avancé
**Prérequis** : modules 01 à 03
