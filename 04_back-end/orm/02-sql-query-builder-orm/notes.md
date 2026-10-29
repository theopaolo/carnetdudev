# 🧱 SQL brut, query builder, ORM : trois niveaux d'abstraction

## 📋 Vue d'ensemble

« ORM ou pas ORM ? » est une mauvaise question. Toute application parle SQL à sa base ; la vraie question est **qui écrit ce SQL, et à quel point tu le vois**. Entre la chaîne de caractères que tu tapes toi-même et la méthode `findMany()` qui génère tout, il existe plusieurs niveaux, et une application sérieuse en combine souvent deux ou trois.

Ce module écrit **le même besoin** à chaque niveau, sur le fil rouge « l'Atelier », pour que les différences soient visibles plutôt qu'affirmées.

### 🎯 Objectifs

- Définir précisément driver, SQL brut, query builder, ORM, micro-ORM et approche SQL-first
- Comparer les niveaux avec des critères explicites, pas avec des préférences
- Savoir ce qu'on peut paramétrer dans une requête, et ce qu'on ne peut **pas** paramétrer
- Écrire un *tagged template* `sql` sûr et composable
- Reconnaître où une abstraction fuit, et concevoir une architecture hybride

---

## 🧭 1. Cinq façons de parler à une base

```
 ton code ─┬─► ORM ───────────────┐   connaît ton DOMAINE (entités, relations)
           ├─► query builder ─────┤   connaît la GRAMMAIRE SQL
           ├─► SQL-first + types ─┤   connaît ton SQL ET le schéma réel
           └─► SQL brut ──────────┤   ne connaît rien : c'est du texte
                                  ▼
                               driver      parle le PROTOCOLE du SGBD
                                  ▼
                           base de données
```

Tous les niveaux finissent au même endroit : un **driver** qui envoie du texte SQL et des paramètres au serveur, puis renvoie des lignes. Ce qui change, c'est ce que la couche au-dessus du driver sait, et donc ce qu'elle peut faire pour toi (ou contre toi).

### Driver
Bibliothèque qui implémente le protocole réseau (ou l'API C) du SGBD : `pg` et `postgres` pour PostgreSQL, `mysql2` pour MySQL, `node:sqlite` pour SQLite. Il ouvre la connexion, envoie `(texte SQL, paramètres)`, renvoie des lignes. **Aucune connaissance de ton schéma.**

### SQL brut
Tu écris le texte SQL, le driver l'exécute, tu transformes toi-même les lignes en objets. Contrôle total, aucune aide : ni typage, ni composition, ni détection d'erreur avant l'exécution.

### Query builder
Une API du langage hôte qui **construit** du SQL : `selectFrom('projects').where('status', '=', 'active')`. Il connaît la grammaire SQL (où va le `WHERE`, comment numéroter les paramètres selon le dialecte) mais pas ton domaine : il renvoie des lignes, pas des objets métier. Pas d'identité, pas de suivi des modifications, pas de relations navigables. Exemples : **Knex** (JS), **Kysely** (TypeScript, typé), **jOOQ** (Java), **SQLAlchemy Core** (Python), **Doctrine DBAL** (PHP).

### ORM
Une couche qui associe des **tables à des classes/entités** grâce à des métadonnées de mapping, génère les requêtes à partir d'opérations sur des objets, **hydrate** des graphes d'objets avec leurs relations, et souvent suit les modifications pour les réécrire en base. Les patterns qui le composent (Active Record, Data Mapper, Unit of Work…) sont l'objet du [module 01](../01-fondamentaux/notes.md). Exemples : Prisma, Drizzle (couche relationnelle), Sequelize, TypeORM, MikroORM, Doctrine ORM, Eloquent, Hibernate, Django ORM, SQLAlchemy ORM.

### Micro-ORM
Tu écris le SQL, la bibliothèque se charge seulement de **mapper les lignes vers des objets typés** (et des paramètres). L'archétype est **Dapper** (.NET, créé pour Stack Overflow). C'est du SQL brut avec la corvée du mapping retirée.

### SQL-first avec génération de types (la quatrième voie)
Tu écris du SQL dans des fichiers `.sql` (ou des templates annotés) ; un outil **analyse ce SQL contre le vrai schéma** et génère des fonctions typées. Le SQL reste la source de vérité, le typage vient en plus. Exemples : **sqlc** (Go en priorité, d'autres langages via plugins), **PgTyped** (TypeScript + PostgreSQL), **TypedSQL** de Prisma (fichiers `.sql` typés dans un projet Prisma, apparu en *preview* en 2024 : vérifie son statut dans ta version).

> 💡 **Modèle mental** : chaque niveau échange du **contrôle** contre de la **connaissance déléguée**. Plus la couche en sait sur ton domaine, plus elle peut écrire à ta place, et plus il devient difficile de savoir ce qu'elle a écrit.

---

## 🎯 2. Un même besoin, écrit trois fois

> **Besoin** : pour un membre donné, lister les projets **actifs** dont il est **propriétaire ou contributeur**, avec leurs **étiquettes** et leur **nombre de contributeurs**, du plus récent au plus ancien, **10 par page**.

Ce besoin est ordinaire, et pourtant il contient quatre difficultés : un `OR` qui traverse une relation n-n, une agrégation (le compte), une collection imbriquée (les étiquettes) et une pagination qui doit rester déterministe.

### 2.1 SQL brut (exécutable)

```javascript
// need-raw.mjs, à placer dans 02-sql-query-builder-orm/ (dossier voisin de fil-rouge/)
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();
const PAGE_SIZE = 10;

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

// La couche de « mapping » qu'on écrit soi-même en SQL brut :
// noms de colonnes → propriétés, JSON → tableau.
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

console.log(findMemberProjects(1));
```

Résultat pour `theo` (id 1) :

```javascript
[
  { id: 5, title: 'Éthique des données',  createdAt: '2026-04-20 13:00:00', contributorCount: 2, tags: ['ethique', 'pedagogie'] },
  { id: 2, title: 'Typographie variable', createdAt: '2026-02-05 16:00:00', contributorCount: 3, tags: ['typographie', 'web'] },
  { id: 1, title: 'Carnet du dev',        createdAt: '2026-01-12 10:00:00', contributorCount: 2, tags: ['pedagogie', 'web'] },
]
```

Trois choix méritent d'être justifiés, parce qu'un ORM les ferait à ta place sans te le dire :

1. **`EXISTS` plutôt que `JOIN contributions`** pour le filtre. Une jointure dupliquerait le projet autant de fois que le membre y a de lignes de contribution (et il faudrait un `DISTINCT`). `EXISTS` exprime exactement la question posée : « existe-t-il au moins une contribution ? ».
2. **Des sous-requêtes scalaires plutôt que deux jointures + `GROUP BY`**. Joindre `contributions` *et* `project_tags` sur la même ligne de projet produit un **produit cartésien** : chaque contribution est répétée pour chaque étiquette. Démonstration sur les mêmes données :

   ```
   Version naïve (deux JOIN + count(*))        Résultat attendu
   Carnet du dev         4  pedagogie,pedagogie,web,web        2  pedagogie,web
   Typographie variable  6  typographie ×3, web ×3             3  typographie,web
   ```

   `count(DISTINCT …)` répare le symptôme, mais la requête reste fausse en esprit (et un projet sans étiquette disparaît à cause du `JOIN` interne). Ce piège s'appelle le *fan-out* ; les ORMs y tombent aussi quand ils chargent plusieurs collections en une seule requête.
3. **`ORDER BY p.created_at DESC, p.id DESC`**. Sans le second critère, deux projets créés à la même seconde peuvent changer d'ordre d'une page à l'autre : une ligne apparaît deux fois, une autre jamais. Une pagination n'est déterministe que si le tri est **total**. (La pagination par curseur, plus robuste que `OFFSET`, est traitée en [module 06](../06-concepts-avances/notes.md).)

> `json_group_array(x ORDER BY y)` nécessite SQLite ≥ 3.44 (Node 22 embarque une version bien plus récente). En PostgreSQL, l'équivalent est `json_agg(t.label ORDER BY t.label)` ou `array_agg(...)`. Ce genre de détail est exactement ce que la « portabilité » d'un ORM prétend masquer.

### 2.2 Query builder (illustratif : Kysely)

```typescript
// Illustratif — Kysely, dialecte SQLite. Les types de `db` sont générés depuis le schéma (kysely-codegen)
import { jsonArrayFrom } from 'kysely/helpers/sqlite'; // il existe aussi /postgres et /mysql

const rows = await db
  .selectFrom('projects as p')
  .select((eb) => [
    'p.id',
    'p.title',
    'p.created_at',
    eb.selectFrom('contributions as c')
      .select(eb.fn.countAll().as('n'))
      .whereRef('c.project_id', '=', 'p.id')
      .as('contributor_count'),
    jsonArrayFrom(
      eb.selectFrom('project_tags as pt')
        .innerJoin('tags as t', 't.id', 'pt.tag_id')
        .select('t.label')
        .whereRef('pt.project_id', '=', 'p.id')
        .orderBy('t.label'),
    ).as('tags'),
  ])
  .where('p.status', '=', 'active')
  .where((eb) => eb.or([
    eb('p.owner_id', '=', memberId),
    eb.exists(
      eb.selectFrom('contributions as c')
        .select(eb.lit(1).as('one'))
        .whereRef('c.project_id', '=', 'p.id')
        .where('c.member_id', '=', memberId),
    ),
  ]))
  .orderBy('p.created_at', 'desc')
  .orderBy('p.id', 'desc')
  .limit(10)
  .offset(page * 10)
  .execute();
```

Ce que tu observes :

- **La structure est celle du SQL** : on retrouve sous-requêtes, `EXISTS`, `ORDER BY`. Le query builder ne pense pas à ta place ; il t'empêche surtout de mal assembler le texte.
- **Le typage suit la requête** : le type de `rows` contient exactement `id`, `title`, `created_at`, `contributor_count`, `tags`. Une faute de frappe sur `'p.titel'` est une erreur de compilation, pas une erreur à l'exécution.
- **Tu peux voir le SQL** sans l'exécuter : `.compile()` renvoie `{ sql, parameters }`.
- **Composabilité** : chaque étape renvoie une nouvelle requête ; ajouter un filtre conditionnel est un `if` autour d'un `.where(...)`, pas une concaténation de chaînes.

Avec **Knex** (JavaScript, plus ancien, non typé par défaut), la logique est la même ; `.toSQL()` renvoie `{ sql, bindings }` et `.toSQL().toNative()` le SQL au format du dialecte. Attention, `.toString()` **interpole** les valeurs dans le texte : à réserver au débogage, jamais à l'exécution.

### 2.3 ORM (illustratif : Prisma, puis Drizzle)

En supposant un schéma Prisma où `Project` a les relations `contributions` et `tags` (table de jointure explicite `ProjectTag`, voir le [module 04](../04-modelisation-merise-uml-erd/notes.md) pour la traduction complète) :

```typescript
// Illustratif — Prisma Client
const projects = await prisma.project.findMany({
  where: {
    status: 'active',
    OR: [
      { ownerId: memberId },
      { contributions: { some: { memberId } } },
    ],
  },
  select: {
    id: true,
    title: true,
    createdAt: true,
    tags: { select: { tag: { select: { label: true } } }, orderBy: { tag: { label: 'asc' } } },
    _count: { select: { contributions: true } },
  },
  orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
  take: 10,
  skip: page * 10,
});

// Le résultat a la forme du graphe, pas celle du besoin : il reste un mapping à faire.
const cards = projects.map((p) => ({
  id: p.id,
  title: p.title,
  createdAt: p.createdAt,
  contributorCount: p._count.contributions,
  tags: p.tags.map((pt) => pt.tag.label),
}));
```

C'est plus court et plus lisible **pour qui connaît l'API Prisma**. `some` traduit l'`EXISTS`, `_count` la sous-requête de comptage. Mais remarque que :

- tu ne sais pas, en lisant ce code, **combien de requêtes** partent vers la base, ni leur forme ;
- la table de jointure `ProjectTag` reste visible (`pt.tag.label`) : l'abstraction « un projet a des étiquettes » fuit dès que la relation n-n est explicite.

**Ce que l'ORM exécute vraiment.** Selon la version de Prisma et la stratégie de chargement des relations (une option `relationLoadStrategy` avec les valeurs `'join'` et `'query'` a été introduite en *preview* ; vérifie son statut et sa valeur par défaut dans ta version), ce `findMany` peut devenir **une** requête avec jointures et agrégation JSON, ou **plusieurs** requêtes (une pour les projets, puis une par relation avec `WHERE project_id IN (…)`). Ne le devine pas, **mesure-le** :

```typescript
// Illustratif
const prisma = new PrismaClient({ log: ['query'] }); // chaque requête SQL est affichée
```

Équivalents : `drizzle(client, { logger: true })`, option `log` de Kysely, `debug: true` de Knex, `logging: console.log` de Sequelize, `echo=True` de SQLAlchemy, le profiler Symfony pour Doctrine. **Règle de travail : on ne met en production aucune requête d'ORM dont on n'a pas lu le SQL au moins une fois.**

**Drizzle** se présente comme un ORM, mais son API principale est un query builder typé :

```typescript
// Illustratif — Drizzle, API « SQL-like »
import { and, desc, eq, exists, or, sql } from 'drizzle-orm';

const rows = await db
  .select({
    id: projects.id,
    title: projects.title,
    createdAt: projects.createdAt,
    contributorCount: sql<number>`(select count(*) from ${contributions}
                                    where ${contributions.projectId} = ${projects.id})`,
  })
  .from(projects)
  .where(and(
    eq(projects.status, 'active'),
    or(
      eq(projects.ownerId, memberId),
      exists(db.select({ one: sql`1` }).from(contributions).where(and(
        eq(contributions.projectId, projects.id),
        eq(contributions.memberId, memberId),
      ))),
    ),
  ))
  .orderBy(desc(projects.createdAt), desc(projects.id))
  .limit(10)
  .offset(page * 10);
// Les étiquettes : soit une seconde requête « WHERE project_id IN (ids) » regroupée en JS,
// soit l'API relationnelle `db.query.projects.findMany({ with: … })`, dont la syntaxe
// a changé entre versions majeures : vérifie la doc de ta version.
```

La seconde requête `IN (ids)` regroupée en mémoire, c'est précisément ce que font beaucoup d'ORMs quand ils « préchargent » une relation. L'écrire une fois à la main est le meilleur moyen de comprendre l'*eager loading* (approfondi en [module 06](../06-concepts-avances/notes.md)).

### 2.4 Ce que la comparaison révèle

| | SQL brut | Query builder | ORM |
|---|---|---|---|
| Le code ressemble à… | la requête | la requête | le graphe d'objets |
| Tu choisis `EXISTS` vs `JOIN` | oui | oui | l'ORM choisit |
| Nombre de requêtes visible dans le code | oui | oui | non |
| Forme du résultat | lignes à plat, à mapper | lignes typées | graphe imbriqué, encore à mapper |
| Une faute de nom de colonne est détectée | à l'exécution | à la compilation | à la compilation |

Aucun niveau ne supprime le travail de mapping vers la forme dont l'interface a besoin (`toProjectCard`). L'ORM le déplace : il mappe vers *son* modèle, et tu mappes encore vers le tien.

---

## ⚖️ 3. Grille de comparaison

| Critère | SQL brut | Query builder | ORM |
|---|---|---|---|
| **Contrôle du SQL** | total | quasi total | partiel, via options et échappatoires |
| **Lisibilité** | excellente pour qui lit le SQL | bonne, plus verbeuse | excellente pour le CRUD, opaque pour le complexe |
| **Composabilité** (filtres dynamiques) | faible (concaténation) sauf avec un `sql` composable | excellente | bonne dans le périmètre de l'API |
| **Sécurité (injection)** | dépend entièrement de toi | sûre par défaut, sauf `raw` | sûre par défaut, sauf `raw`/`Unsafe` |
| **Typage** | aucun (ou SQL-first) | inféré depuis la requête | généré depuis le schéma |
| **Portabilité entre SGBD** | nulle à moyenne | moyenne | élevée en apparence (voir plus bas) |
| **Performance** | celle de ta requête | celle de ta requête | celle de la requête générée |
| **Débogage** | tu lis ce que tu as écrit | `.compile()` / `.toSQL()` | journal de requêtes obligatoire |
| **Couplage fournisseur** | SQL : savoir durable | API à réapprendre | schéma, API et migrations propriétaires |
| **Courbe d'apprentissage** | raide au début, puis stable | SQL + API | douce au début, raide pour la maîtrise |
| **Migrations intégrées** | non (outils dédiés) | parfois (Knex, Kysely `Migrator`) | souvent (Prisma Migrate, Doctrine, Django) |

### Le typage, un spectre plutôt qu'un booléen

| Niveau | Exemple | Ce que le type garantit | Ce qu'il ne garantit pas |
|---|---|---|---|
| Aucun | `node:sqlite`, `pg` | rien | tout |
| Déclaré à la main | `/** @type {ProjectRow[]} */` | rien : c'est une promesse | que la requête renvoie bien ça |
| Généré depuis le schéma | Prisma Client, kysely-codegen | cohérence avec le schéma **au moment de la génération** | que la base réelle soit dans cet état (dérive : [module 03](../03-migrations/notes.md)) |
| Inféré depuis la requête | Kysely, Drizzle | le résultat suit les colonnes sélectionnées | idem |
| Vérifié contre la base | sqlc, PgTyped | le SQL a été analysé par le vrai SGBD | le contenu des colonnes JSON, par exemple |
| Validé à l'exécution | zod, valibot sur les lignes reçues | les données effectivement reçues | gratuit : coût CPU et double déclaration |

Un type statique est une affirmation sur la base **faite dans le code**. Il n'a de valeur que si la base et le code évoluent ensemble, ce qui renvoie aux migrations.

### Le mythe de la portabilité

L'argument « avec un ORM, on peut changer de SGBD » est faible pour deux raisons. D'abord, on change très rarement de SGBD en cours de vie d'un projet, et quand on le fait, la couche d'accès n'est pas le plus gros chantier (données, exploitation, performances). Ensuite, les différences **fuient** quand même :

- `RETURNING` : PostgreSQL et SQLite (≥ 3.35) oui, MariaDB (≥ 10.5) oui, MySQL non.
- Upsert : `ON CONFLICT … DO UPDATE` (PostgreSQL, SQLite) contre `ON DUPLICATE KEY UPDATE` (MySQL).
- Booléens : type natif en PostgreSQL, `TINYINT(1)` en MySQL, simple entier 0/1 en SQLite.
- Dates : SQLite n'a pas de type date (texte, réel ou entier selon la convention).
- Casse : les collations par défaut de MySQL sont insensibles à la casse, celles de PostgreSQL non. Le même `WHERE handle = 'Theo'` ne renvoie pas les mêmes lignes.
- `x IN ()` (liste vide) : accepté par SQLite, erreur de syntaxe en PostgreSQL.
- DDL transactionnel : oui en PostgreSQL et SQLite, non en MySQL ([module 03](../03-migrations/notes.md)).

Conséquence pratique : **tester sur SQLite et déployer sur PostgreSQL est un anti-pattern**, même avec un ORM « portable ». Teste sur le SGBD de production (un conteneur suffit).

### Performance : le coût n'est presque jamais là où on le cherche

Le temps passé dans la couche ORM elle-même (construire la requête, hydrater des objets) est généralement faible devant l'aller-retour réseau et l'exécution en base, sauf sur de très gros volumes de lignes ou avec un suivi des modifications qui conserve une copie de chaque entité chargée. Le vrai coût vient de la **forme du SQL généré** : trop de colonnes (`SELECT *` implicite), trop de requêtes (N+1), un `JOIN` là où un `EXISTS` suffisait, l'impossibilité d'utiliser une fonction propre au SGBD (fenêtres, CTE récursives, `LATERAL`, index partiels). D'où la règle : **mesurer avec le journal de requêtes et `EXPLAIN`**, pas avec des intuitions (Winand, *SQL Performance Explained*).

---

## 🛡️ 4. Injection SQL : la seule règle non négociable

### La démonstration

```javascript
import { openDb } from '../fil-rouge/open-db.mjs';
const db = openDb();

// ❌ Concaténation : l'entrée devient du code SQL
function findByHandleUnsafe(handle) {
  return db.prepare(`SELECT id, handle, email FROM members WHERE handle = '${handle}'`).all();
}

findByHandleUnsafe("theo");                    // 1 ligne, normal
findByHandleUnsafe("x' OR '1'='1");            // les 4 membres
findByHandleUnsafe("x' UNION SELECT id, title, status FROM projects --");
// → les 5 projets, déguisés en membres : { id: 1, handle: 'Carnet du dev', email: 'active' }…

// ✅ Paramètre : l'entrée reste une donnée
const byHandle = db.prepare('SELECT id, handle, email FROM members WHERE handle = ?');
byHandle.all("x' OR '1'='1");                  // [] : aucun membre ne s'appelle ainsi
```

Le `UNION` est la vraie leçon : une injection ne sert pas seulement à contourner un filtre, elle permet de **lire n'importe quelle table** accessible à l'utilisateur de la base. Autre détail : `prepare()` de `node:sqlite` ne compile que la première instruction et ignore silencieusement la suite, donc `'; DROP TABLE members; --` échoue ici. **Ce n'est pas une protection** : d'autres drivers acceptent les instructions multiples (option `multipleStatements` de `mysql2`, par exemple), et l'exfiltration par `UNION` fonctionne partout.

### Pourquoi le paramètre protège

Avec une requête paramétrée, le texte SQL et les valeurs voyagent **séparément** jusqu'au SGBD, qui analyse le texte *avant* de connaître les valeurs. Une valeur ne peut donc jamais devenir de la syntaxe. Nuance : certains drivers simulent les paramètres en échappant les valeurs côté client (c'est le cas de `?` dans l'ancien paquet `mysql`), ce qui est correct s'il est bien implémenté, mais n'est pas la même garantie. Ce qui compte pour toi : **ne jamais construire le texte SQL avec une donnée externe**.

### Ce qu'on ne peut PAS paramétrer

Un paramètre remplace une **valeur**, jamais un morceau de syntaxe. Ne sont pas paramétrables :

- les **identifiants** : nom de table, de colonne, d'alias ;
- les **mots-clés** : `ASC`/`DESC`, `AND`/`OR`, opérateurs ;
- la **structure** : nombre d'éléments d'un `IN (…)`, présence d'une clause.

Pour ceux-là, une seule technique : la **liste blanche**. L'utilisateur choisit une *clé* publique, le code associe cette clé à un fragment SQL écrit par le développeur :

```javascript
const SORTS = new Map([
  ['recent', 'p.created_at DESC, p.id DESC'],
  ['oldest', 'p.created_at ASC, p.id ASC'],
  ['title',  'p.title ASC, p.id ASC'],
]);
const orderBy = SORTS.get(query.sort) ?? SORTS.get('recent');
```

Une `Map` plutôt qu'un objet littéral : `{ recent: '…' }['constructor']` renvoie la fonction `Object`, qui passerait un test « la clé existe » naïf. (`Object.hasOwn` règle aussi le problème.)

### `LIKE` : paramétré mais pas encore littéral

`WHERE label LIKE ?` avec `'%' + saisie + '%'` est sûr contre l'injection, mais `%` et `_` saisis par l'utilisateur restent des **jokers**. Chercher « 100% » trouve aussi « 100 libre ». Il faut échapper les jokers et déclarer le caractère d'échappement :

```javascript
const escapeLike = (text) => text.replace(/[\\%_]/g, (ch) => `\\${ch}`);
const search = db.prepare(String.raw`SELECT label FROM tags WHERE label LIKE ? ESCAPE '\'`);
search.all(`%${escapeLike('100%')}%`); // seulement '100%_libre'
```

SQLite n'a pas de caractère d'échappement par défaut (d'où la clause `ESCAPE`) ; PostgreSQL utilise `\` par défaut. Encore une différence de dialecte.

### Listes `IN` : générer les marqueurs, pas les valeurs

```javascript
const ids = [1, 3, 5];
const placeholders = ids.map(() => '?').join(', ');           // '?, ?, ?' : structure, écrite par le code
db.prepare(`SELECT label FROM tags WHERE id IN (${placeholders})`).all(...ids);
```

Et décide explicitement du cas `ids.length === 0` : erreur en PostgreSQL, et « aucun résultat » n'est pas toujours la bonne sémantique (un filtre vide peut vouloir dire « pas de filtre »).

### Un *tagged template* `sql` composable

Les *tagged templates* JavaScript reçoivent séparément les morceaux de texte écrits par le développeur et les valeurs interpolées. C'est exactement la séparation code/données dont on a besoin :

```javascript
// sql.mjs
const FRAGMENT = Symbol('sql.fragment');
const fragment = (text, params) => Object.freeze({ [FRAGMENT]: true, sql: text, params });
export const isFragment = (value) => value?.[FRAGMENT] === true;

export function sql(strings, ...values) {
  // Un vrai appel sql`…` reçoit un TemplateStringsArray (qui a .raw) : on refuse sql(['…' + input]).
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

sql.join = (fragments, separator = ', ') => {
  const parts = fragments.map((f) => (isFragment(f) ? f : sql`${f}`));
  return fragment(parts.map((f) => f.sql).join(separator), parts.flatMap((f) => f.params));
};
```

```javascript
const isMember = sql`(p.owner_id = ${memberId}
  OR EXISTS (SELECT 1 FROM contributions c WHERE c.project_id = p.id AND c.member_id = ${memberId}))`;
const filters = [sql`p.status = ${'active'}`, isMember];

const query = sql`SELECT p.id, p.title FROM projects p
  WHERE ${sql.join(filters, ' AND ')}
  ORDER BY p.created_at DESC LIMIT ${10}`;

query.sql;    // 'SELECT … WHERE p.status = ? AND (p.owner_id = ? OR EXISTS (… c.member_id = ?)) … LIMIT ?'
query.params; // ['active', 1, 1, 10]
db.prepare(query.sql).all(...query.params);
```

Deux propriétés de sécurité méritent d'être nommées :

- **un fragment ne peut pas être forgé depuis une entrée** : il est marqué par un `Symbol`, que `JSON.parse` ne peut pas produire. Un objet `{ sql: '1=1', params: [] }` reçu d'une requête HTTP est traité comme une simple valeur, donc paramétré ;
- **le texte ne vient que des littéraux du template**, c'est-à-dire du code source. C'est la même idée que `postgres` (le driver), Slonik, `sql` de Kysely et de Drizzle, ou `Prisma.sql`.

La version complète (avec `sql.in`, `sql.id` par liste blanche et une échappatoire `sql.unsafe` volontairement mal nommée) est le kata 2.

### Les échappatoires des outils, et leurs pièges

| Outil | Sûr (paramétré) | Dangereux (texte inséré tel quel) |
|---|---|---|
| Prisma | `` prisma.$queryRaw`… ${x}` ``, `Prisma.sql`, `Prisma.join` | `$queryRawUnsafe(chaîne)` construit avec `${x}`, `Prisma.raw(x)` |
| Kysely | `` sql`… ${x}` ``, `sql.ref`, `sql.table` | `sql.raw(x)`, `sql.lit(x)` (insère la valeur littéralement) |
| Drizzle | `` sql`… ${x}` ``, `sql.identifier` | `sql.raw(x)` |
| Knex | `knex.raw('… ?', [x])`, `??` pour un identifiant | `` knex.raw(`… ${x}`) ``, `whereRaw('… ' + x)` |

Le piège le plus fréquent n'est pas de choisir la fonction « Unsafe » par erreur, c'est de **pré-construire la chaîne** puis de la passer à une fonction qui l'accepte :

```typescript
// Illustratif — le template est évalué par JavaScript AVANT d'atteindre Prisma : c'est une concaténation.
const query = `SELECT * FROM members WHERE handle = '${handle}'`;
await prisma.$queryRawUnsafe(query);          // ❌ injectable
await prisma.$queryRaw`SELECT * FROM members WHERE handle = ${handle}`; // ✅ paramétré
```

Vérifie les noms exacts dans la documentation de ta version : ces API évoluent, le principe non.

### Injection de second ordre

Une valeur peut être stockée proprement (paramétrée), puis **relue et concaténée** plus tard dans une autre requête, par exemple un nom de tri sauvegardé dans les préférences d'un utilisateur. « Ça vient de ma base » ne veut pas dire « c'est sûr ». Toute valeur qui n'est pas un littéral du code source est une donnée.

---

## 🕳️ 5. Les abstractions fuient

Joel Spolsky a formulé en 2002 la « loi des abstractions qui fuient » : *toute abstraction non triviale fuit, dans une certaine mesure*. Un ORM est une abstraction très non triviale : il prétend qu'un ensemble de relations est un graphe d'objets. Ted Neward (« The Vietnam of Computer Science », 2006) en tire une conclusion sévère : on investit toujours plus pour combler le décalage sans jamais le fermer. Martin Fowler (« OrmHate », 2012) répond que le problème est intrinsèquement difficile, qu'un ORM en résout honnêtement une grande partie, et que la frustration vient surtout d'une attente irréaliste : faire *disparaître* la base relationnelle.

Ce module te donne déjà plusieurs fuites concrètes :

| Fuite | Ce que l'abstraction promet | Ce qui remonte |
|---|---|---|
| Logique ternaire (`NULL`) | « différent de Paris » | `city <> 'Paris'` **exclut** les `NULL` ; il faut `IS DISTINCT FROM` (ou `IS NOT` en SQLite) |
| Fan-out | « charger les contributions et les étiquettes » | un produit cartésien si les deux collections sont jointes ensemble |
| Collation | « trier par titre » | en collation binaire, « Éthique » passe après « Typographie » |
| Dialecte | « une requête portable » | `RETURNING`, upsert, booléens, `IN ()`… |
| Coût | « `project.contributions` est une propriété » | chaque accès peut être une requête (N+1, [module 06](../06-concepts-avances/notes.md)) |
| Verrous et transactions | « `save()` » | quelle transaction, quel niveau d'isolation, quels verrous ([module 06](../06-concepts-avances/notes.md)) |

La conséquence n'est pas « n'utilise pas d'ORM ». C'est : **un ORM ne dispense pas de savoir SQL, il le suppose**. On utilise bien un ORM quand on sait écrire à la main la requête qu'il devrait générer.

### Quand le query builder est le bon compromis

Le query builder fuit moins parce qu'il promet moins : il ne prétend pas que la base est un graphe d'objets. Il est souvent le meilleur choix quand :

- les requêtes sont **dynamiques** (écrans de recherche multicritère, filtres combinables) : la composition est son point fort ;
- l'équipe **sait SQL** et veut garder la main sur la forme des requêtes, avec du typage ;
- le domaine est **orienté données** (lectures, agrégations, exports) plutôt qu'orienté comportement (invariants métier riches sur des agrégats) ;
- tu veux limiter la **dépendance** : le savoir acquis reste du SQL.

Il est moins adapté quand le domaine a beaucoup d'entités liées dont il faut charger, modifier et sauvegarder des graphes cohérents : c'est là que l'Unit of Work et l'Identity Map d'un ORM de type Data Mapper rendent service ([module 01](../01-fondamentaux/notes.md)).

---

## 🏗️ 6. Architectures hybrides

Les outils mûrs sont **empilés** : le niveau ORM est construit sur un niveau query builder, et on peut descendre d'un étage sans quitter la connexion ni la transaction.

| Écosystème | Niveau bas (SQL / QB) | Niveau haut (ORM) |
|---|---|---|
| Python | SQLAlchemy **Core** | SQLAlchemy **ORM** (même `Session`, même transaction) |
| Node.js | **Knex** | **Objection.js** (construit sur Knex ; même auteur que Kysely) |
| PHP / Symfony | **Doctrine DBAL** | **Doctrine ORM** (et son langage DQL) |
| PHP / Laravel | **Query Builder** (`DB::table()`) | **Eloquent** |
| Java | JDBC, jOOQ | Hibernate / JPA (et ses *native queries*) |
| Prisma | `$queryRaw`, TypedSQL | Prisma Client |

### Écrire avec l'ORM, lire avec du SQL

Un découpage fréquent et défendable :

- **les écritures** passent par l'ORM : elles touchent peu de lignes, doivent respecter des invariants, déclencher des validations, s'inscrire dans une transaction ;
- **les lectures complexes** (tableaux de bord, recherche, exports, rapports) passent par du SQL écrit à la main, souvent exposé sous forme de **vue** ou de fonction dédiée, qui renvoie directement la forme attendue par l'interface.

```javascript
// Une vue = un « modèle de lecture » maintenu par la base elle-même
db.exec(`
  CREATE VIEW project_cards AS
  SELECT p.id, p.title, p.status, p.created_at,
         m.handle AS owner_handle,
         (SELECT count(*) FROM contributions c WHERE c.project_id = p.id) AS contributor_count,
         (SELECT json_group_array(t.label ORDER BY t.label)
            FROM project_tags pt JOIN tags t ON t.id = pt.tag_id
           WHERE pt.project_id = p.id) AS tags
    FROM projects p
    JOIN members m ON m.id = p.owner_id;
`);
db.prepare('SELECT * FROM project_cards WHERE status = ? ORDER BY created_at DESC').all('active');
```

Beaucoup d'ORMs savent mapper une vue en lecture seule comme une entité, ce qui donne le typage sans renoncer au SQL. C'est une forme légère de séparation lecture/écriture (CQRS), développée en [module 06](../06-concepts-avances/notes.md). La vue elle-même se crée et se modifie par migration ([module 03](../03-migrations/notes.md)).

### La règle de frontière

L'hybride devient un problème quand le SQL brut est **éparpillé** dans tout le code. Trois règles simples :

1. le SQL écrit à la main vit dans un **module dédié** (un fichier par agrégat ou par écran de lecture) ;
2. chaque requête écrite à la main a un **test** qui l'exécute sur le vrai SGBD ;
3. la frontière est **documentée** : qu'est-ce qui passe par l'ORM, qu'est-ce qui n'y passe pas, pourquoi ([module 05](../05-documenter/notes.md), sous forme d'ADR).

---

## 🌳 7. Arbre de décision

```
Quel est le travail principal de la couche d'accès ?
│
├─ Un script, un outil interne, quelques requêtes stables
│     → driver + SQL brut. Une dépendance de moins, rien à apprendre.
│
├─ Des lectures complexes : rapports, agrégations, CTE, fonctions de fenêtre
│     → SQL écrit à la main (vues, ou SQL-first typé si tu veux des types)
│
├─ Des requêtes très dynamiques (filtres combinables, tri, pagination)
│     → query builder typé (Kysely, Drizzle core, Knex)
│
└─ Un domaine riche : beaucoup d'entités liées, des invariants, des graphes à sauvegarder
      │
      ├─ L'équipe maîtrise SQL ?
      │     ├─ oui → ORM, avec journal des requêtes activé en dev et échappatoire SQL assumée
      │     └─ non → ORM + formation SQL. L'ORM ne remplace pas la compétence,
      │              il retarde le moment où son absence coûte cher.
      │
      └─ Contraintes de performance fortes sur certains chemins ?
            → ORM pour le reste, SQL mesuré (EXPLAIN) sur ces chemins-là
```

Deux remarques sur cet arbre :

- **La réponse est presque toujours « plusieurs niveaux »**. Une application typique a 80 % de CRUD (ORM ou query builder) et 20 % de lectures qui méritent du SQL écrit à la main. La décision importante est où passe la frontière, et le fait de l'écrire.
- **En apprentissage, commence par le SQL brut.** Le chapitre suit ce principe pour une raison simple : tu ne peux juger le SQL qu'un ORM génère que si tu sais l'écrire.

---

## ⚠️ Pièges courants

1. **Interpoler dans une fonction « raw »** : `` knex.raw(`… ${x}`) `` ou `$queryRawUnsafe` avec une chaîne pré-construite. Le template JavaScript est évalué avant d'atteindre la bibliothèque.
2. **Paramétrer un identifiant** : `ORDER BY ?` trie par une constante (la valeur du paramètre), pas par la colonne. Ça ne plante pas, ça ne trie juste pas. Liste blanche.
3. **Paginer sur un tri non total** : sans critère départageant (`id`), des lignes se dupliquent ou disparaissent entre deux pages.
4. **Joindre deux collections à la fois** pour compter : produit cartésien, comptes multipliés.
5. **Croire que l'ORM fait une seule requête** (ou plusieurs) sans avoir lu le journal.
6. **Tester sur un autre SGBD que la production** au nom de la portabilité.
7. **Confondre type statique et vérité** : un type généré décrit le schéma au moment de la génération, pas la base de production.

---

## 🧠 Modèles mentaux

- **Le traducteur** : le SQL brut, c'est parler la langue ; le query builder, c'est un correcteur de grammaire ; l'ORM, c'est un interprète qui reformule. L'interprète est précieux, mais tu dois pouvoir vérifier ce qu'il a dit.
- **La frontière qui se déplace** : chaque niveau ne supprime pas le décalage objet/relationnel, il choisit où le placer. En SQL brut il est dans ton `toProjectCard` ; avec un ORM, il est dans ses métadonnées de mapping et dans la forme de ses résultats.
- **Code et données ne se mélangent jamais** : tout texte SQL vient du code source ; tout ce qui vient d'ailleurs (requête HTTP, fichier, base, autre service) est une valeur et voyage comme paramètre.

---

## 🔗 Liens avec les autres modules

- [01 Fondamentaux](../01-fondamentaux/notes.md) → les patterns (Active Record, Data Mapper, Unit of Work) qui distinguent un ORM d'un query builder
- [03 Migrations](../03-migrations/notes.md) → la dérive entre schéma réel et types générés ; la création des vues de lecture
- [04 Modélisation](../04-modelisation-merise-uml-erd/notes.md) → le schéma Prisma complet du fil rouge et la traduction des associations n-n
- [05 Documenter](../05-documenter/notes.md) → documenter la frontière ORM / SQL brut (ADR)
- [06 Concepts avancés](../06-concepts-avances/notes.md) → N+1, stratégies de chargement, pagination par curseur, CQRS

## 📚 Pour aller plus loin

- **Martin Fowler**, *Patterns of Enterprise Application Architecture* (2002) : *Query Object*, *Table Data Gateway*, *Metadata Mapping*. Le vocabulaire pour nommer ce que fait chaque niveau.
- **Ted Neward**, « The Vietnam of Computer Science » (2006) et **Martin Fowler**, « OrmHate » (2012) : à lire l'un après l'autre.
- **Joel Spolsky**, « The Law of Leaky Abstractions » (2002).
- **Markus Winand**, *SQL Performance Explained* (2012) et [use-the-index-luke.com](https://use-the-index-luke.com/) : pour juger la forme d'une requête, générée ou non.
- **OWASP**, *SQL Injection Prevention Cheat Sheet* : la référence pratique sur les requêtes paramétrées et les listes blanches.

---

**Dernière mise à jour** : 2026-10-29
**Niveau de confiance** : ⭐⭐⭐⭐☆
**Prochaine révision** : après le module 06
