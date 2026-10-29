# 🧠 Flashcards : SQL brut, query builder, ORM

## 🧭 Définitions

### Q: Qu'est-ce qu'un driver de base de données ?
<details><summary>R</summary>

La bibliothèque qui implémente le protocole du SGBD (`pg`, `mysql2`, `node:sqlite`) : elle envoie `(texte SQL, paramètres)` et renvoie des lignes. Elle ne connaît rien de ton schéma. Tous les autres niveaux reposent sur elle.

</details>

### Q: Qu'est-ce qu'un query builder ?
<details><summary>R</summary>

Une API du langage hôte qui **construit** du SQL (`selectFrom(...).where(...)`). Il connaît la grammaire SQL et le dialecte, pas ton domaine : il renvoie des lignes, sans identité d'objet, sans suivi des modifications, sans relations navigables. Exemples : Knex, Kysely, jOOQ, SQLAlchemy Core, Doctrine DBAL.

</details>

### Q: Qu'est-ce qui distingue un ORM d'un query builder ?
<details><summary>R</summary>

L'ORM connaît le **modèle de domaine** grâce à des métadonnées de mapping (table ↔ classe, colonne ↔ propriété, clé étrangère ↔ relation). Il génère les requêtes à partir d'opérations sur des objets, hydrate des graphes, et souvent suit les modifications pour les réécrire en base.

</details>

### Q: Qu'est-ce qu'un micro-ORM ?
<details><summary>R</summary>

Une bibliothèque où **tu écris le SQL** et où elle se charge seulement de mapper les lignes vers des objets typés et de passer les paramètres. Archétype : Dapper (.NET).

</details>

### Q: Qu'est-ce que l'approche « SQL-first avec génération de types » ?
<details><summary>R</summary>

Tu écris du SQL dans des fichiers ; un outil l'analyse contre le vrai schéma et génère des fonctions typées. Le SQL reste la source de vérité. Exemples : sqlc, PgTyped, TypedSQL (Prisma).

</details>

### Q: Quel compromis général fait-on en montant d'un niveau d'abstraction ?
<details><summary>R</summary>

On échange du **contrôle** (et de la visibilité sur le SQL exécuté) contre de la **connaissance déléguée** (la couche écrit à ta place parce qu'elle connaît ton schéma ou ton domaine).

</details>

## 🎯 Le même besoin, trois fois

### Q: Pourquoi utiliser `EXISTS` plutôt qu'un `JOIN` pour « projets où le membre est contributeur » ?
<details><summary>R</summary>

Un `JOIN` duplique la ligne du projet pour chaque contribution correspondante (il faudrait un `DISTINCT`). `EXISTS` répond exactement à la question « existe-t-il au moins une ligne ? » sans changer la cardinalité du résultat.

</details>

### Q: Qu'est-ce que le *fan-out* (produit cartésien) d'une requête ?
<details><summary>R</summary>

Joindre deux collections 1-n sur la même ligne parente (contributions **et** étiquettes) produit une ligne par **combinaison** : 2 contributeurs × 2 étiquettes = 4 lignes. Les `count(*)` sont multipliés. Solution : sous-requêtes séparées, ou agrégations dans des sous-requêtes, pas un `count(DISTINCT)` de rattrapage.

</details>

### Q: Pourquoi `ORDER BY p.created_at DESC, p.id DESC` et pas seulement `created_at` ?
<details><summary>R</summary>

Une pagination n'est déterministe que si le tri est **total**. Deux lignes de même date peuvent sinon changer d'ordre entre deux pages : une ligne apparaît deux fois, une autre jamais.

</details>

### Q: Comment savoir combien de requêtes un `findMany` d'ORM exécute ?
<details><summary>R</summary>

On ne le devine pas, on **active le journal** : `new PrismaClient({ log: ['query'] })`, `drizzle(client, { logger: true })`, option `log` de Kysely, `debug: true` de Knex, `logging` de Sequelize, `echo=True` de SQLAlchemy.

</details>

### Q: Comment voir le SQL d'une requête Kysely ou Knex sans l'exécuter ?
<details><summary>R</summary>

Kysely : `.compile()` → `{ sql, parameters }`. Knex : `.toSQL()` → `{ sql, bindings }` (et `.toNative()`). Attention : `.toString()` de Knex **interpole** les valeurs, à réserver au débogage.

</details>

### Q: Un ORM supprime-t-il le travail de mapping vers la forme attendue par l'interface ?
<details><summary>R</summary>

Non. Il mappe vers **son** modèle (un graphe : `p._count.contributions`, `pt.tag.label`) ; tu mappes encore vers le tien. Il déplace le décalage objet/relationnel, il ne le supprime pas.

</details>

## ⚖️ Comparaison

### Q: Cite les niveaux du spectre de typage, du plus faible au plus fort.
<details><summary>R</summary>

Aucun (driver) → déclaré à la main (une promesse) → généré depuis le schéma (Prisma, kysely-codegen) → inféré depuis la requête (Kysely, Drizzle) → vérifié contre la base (sqlc, PgTyped) → validé à l'exécution (zod sur les lignes).

</details>

### Q: Que garantit un type généré depuis le schéma, et que ne garantit-il pas ?
<details><summary>R</summary>

Il garantit la cohérence avec le schéma **au moment de la génération**. Il ne garantit pas que la base réelle soit dans cet état : si les migrations n'ont pas été appliquées, ou si quelqu'un a modifié la base à la main (dérive), le type ment.

</details>

### Q: Pourquoi l'argument de la portabilité entre SGBD est-il faible ?
<details><summary>R</summary>

On change rarement de SGBD, et les différences fuient quand même : `RETURNING` (absent de MySQL), syntaxe d'upsert, booléens, dates en SQLite, collations et casse, `IN ()` vide, DDL transactionnel.

</details>

### Q: Pourquoi « tester sur SQLite, déployer sur PostgreSQL » est-il un anti-pattern ?
<details><summary>R</summary>

Parce que les deux SGBD ne se comportent pas pareil (casse du `LIKE`, `IN ()` vide, types, contraintes, verrous). Les tests passent sur un système qui n'est pas celui de production. Teste sur le même SGBD (un conteneur suffit).

</details>

### Q: Où se trouve le vrai coût de performance d'un ORM, la plupart du temps ?
<details><summary>R</summary>

Dans la **forme du SQL généré** (colonnes en trop, requêtes en trop, `JOIN` au lieu d'`EXISTS`, fonctions du SGBD inaccessibles), bien plus que dans le temps de calcul de la couche elle-même. Se mesure avec le journal de requêtes et `EXPLAIN`.

</details>

### Q: Quel est le point fort principal d'un query builder ?
<details><summary>R</summary>

La **composabilité** : chaque méthode renvoie une nouvelle requête, donc un filtre optionnel est un `if` autour d'un `.where()`, sans concaténation ni gestion manuelle de l'ordre des paramètres.

</details>

## 🛡️ Injection SQL

### Q: Pourquoi une requête paramétrée empêche-t-elle l'injection ?
<details><summary>R</summary>

Le texte SQL et les valeurs voyagent **séparément** ; le SGBD analyse la syntaxe avant de connaître les valeurs. Une valeur ne peut donc jamais devenir de la syntaxe.

</details>

### Q: Qu'est-ce qu'on ne peut PAS paramétrer dans une requête ?
<details><summary>R</summary>

Les identifiants (tables, colonnes, alias), les mots-clés (`ASC`/`DESC`, `AND`/`OR`, opérateurs) et la structure (nombre d'éléments d'un `IN`, présence d'une clause). Pour eux : **liste blanche**.

</details>

### Q: Que se passe-t-il avec `ORDER BY ?` et la valeur `'title'` ?
<details><summary>R</summary>

Aucune erreur, mais aucun tri : on trie par une constante (la chaîne `'title'`), pas par la colonne. Bug silencieux.

</details>

### Q: Pourquoi utiliser une `Map` plutôt qu'un objet littéral pour une liste blanche ?
<details><summary>R</summary>

`{ recent: '…' }['constructor']` renvoie la fonction `Object` héritée du prototype : un test naïf « la clé existe » passerait. `Map.has` (ou `Object.hasOwn`) ne regarde que les clés déclarées.

</details>

### Q: `WHERE title LIKE ?` est-il suffisant pour une recherche littérale ?
<details><summary>R</summary>

Sûr contre l'injection, mais `%` et `_` saisis restent des jokers. Il faut les échapper et déclarer le caractère d'échappement :

```javascript
const escapeLike = (t) => t.replace(/[\\%_]/g, (ch) => `\\${ch}`);
db.prepare(String.raw`SELECT … WHERE title LIKE ? ESCAPE '\'`).all(`%${escapeLike(q)}%`);
```

</details>

### Q: Comment construire une clause `IN` sûre ?
<details><summary>R</summary>

Générer les **marqueurs** (`ids.map(() => '?').join(', ')`), passer les valeurs en paramètres, valider le texte de chaque valeur, borner la taille de la liste, et décider explicitement du cas « liste vide » (erreur en PostgreSQL).

</details>

### Q: Pourquoi un *tagged template* `sql` est-il sûr par construction ?
<details><summary>R</summary>

Il reçoit séparément les **littéraux du template** (écrits dans le code source) et les **valeurs interpolées**. Les littéraux deviennent le texte SQL ; chaque valeur devient un `?`. Le texte ne peut donc venir que du code.

</details>

### Q: Comment empêcher qu'un « fragment » SQL soit forgé à partir d'une entrée utilisateur ?
<details><summary>R</summary>

Le marquer avec un `Symbol` (que `JSON.parse` ne peut pas produire), le geler avec `Object.freeze`, et vérifier dans `sql` que le premier argument a bien une propriété `.raw` (vrai appel de tagged template).

</details>

### Q: Prisma : quelle différence entre `$queryRaw` et `$queryRawUnsafe` ?
<details><summary>R</summary>

`` $queryRaw`… ${x}` `` est un tagged template : `x` devient un paramètre. `$queryRawUnsafe(chaîne)` reçoit une chaîne déjà construite : si elle a été assemblée avec `${x}`, c'est une concaténation. Même logique pour `Prisma.raw`, `sql.raw` (Kysely, Drizzle), `` knex.raw(`…${x}`) ``.

</details>

### Q: Pourquoi `prepare("SELECT 1; DROP TABLE members")` qui « échoue » n'est-il pas une protection ?
<details><summary>R</summary>

`node:sqlite` ignore silencieusement la seconde instruction, mais d'autres drivers acceptent les instructions multiples (`multipleStatements` de `mysql2`). Et l'exfiltration par `UNION SELECT` fonctionne avec une seule instruction, partout.

</details>

### Q: Qu'est-ce qu'une injection de second ordre ?
<details><summary>R</summary>

Une valeur stockée proprement (paramétrée) puis **relue et concaténée** dans une autre requête plus tard. « Ça vient de ma base » ne veut pas dire « c'est sûr » : tout ce qui n'est pas un littéral du code source est une donnée.

</details>

## 🕳️ Abstractions et architecture

### Q: Énonce la loi des abstractions qui fuient (Spolsky, 2002).
<details><summary>R</summary>

Toute abstraction non triviale fuit, dans une certaine mesure. Appliquée aux ORMs : on finit toujours par devoir comprendre le SQL généré (performance, `NULL`, verrous, dialecte).

</details>

### Q: Donne trois fuites concrètes de l'abstraction ORM.
<details><summary>R</summary>

- `city <> 'Paris'` exclut les lignes où `city` est `NULL` (logique ternaire) ;
- le fan-out quand on charge deux collections ensemble ;
- la collation : en binaire, « Éthique » est trié après « Typographie » ;
- (aussi) un accès à une relation qui déclenche une requête, `LIKE` sensible ou non à la casse selon le SGBD.

</details>

### Q: Neward contre Fowler sur les ORMs : quelles positions ?
<details><summary>R</summary>

Neward (« The Vietnam of Computer Science », 2006) : on s'enlise en investissant toujours plus pour combler un décalage qu'on ne fermera jamais. Fowler (« OrmHate », 2012) : le problème est intrinsèquement difficile, l'ORM en résout une grande partie ; la frustration vient de l'attente de voir la base relationnelle disparaître.

</details>

### Q: Cite trois écosystèmes où un ORM est construit sur un query builder qu'on peut utiliser directement.
<details><summary>R</summary>

SQLAlchemy ORM sur SQLAlchemy Core ; Objection.js sur Knex ; Doctrine ORM sur Doctrine DBAL ; Eloquent sur le Query Builder de Laravel.

</details>

### Q: Quel découpage hybride est fréquent et défendable ?
<details><summary>R</summary>

Écritures par l'ORM (peu de lignes, invariants, validations, transactions) ; lectures complexes (tableaux de bord, recherche, exports) en SQL écrit à la main, souvent dans des **vues** qui renvoient directement la forme attendue. C'est un CQRS léger.

</details>

### Q: Quelles sont les trois règles de frontière pour du SQL brut dans une application à ORM ?
<details><summary>R</summary>

1. Le SQL écrit à la main vit dans un module dédié ;
2. chaque requête a un test sur le vrai SGBD ;
3. la frontière (quoi passe par l'ORM, quoi non, pourquoi) est documentée, par exemple dans un ADR.

</details>

### Q: Vrai ou faux : « Un ORM dispense de savoir SQL. »
<details><summary>R</summary>

**Faux.** Il le suppose. On utilise bien un ORM quand on sait écrire à la main la requête qu'il devrait générer, et donc juger celle qu'il génère.

</details>

---

**Nombre de cartes** : 36
**Dernière mise à jour** : 2026-10-29
**Niveau** : Intermédiaire
