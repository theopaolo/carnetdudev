# 📝 Quiz : SQL brut, query builder, ORM

### Q1: Quelle affirmation décrit le mieux un query builder ?
A) Il associe chaque table à une classe et suit les modifications des objets
B) Il construit du SQL à partir d'une API du langage hôte et renvoie des lignes
C) Il analyse des fichiers `.sql` contre la base pour générer des types
D) Il implémente le protocole réseau du SGBD

<details><summary>Réponse</summary>

**B** — Un query builder connaît la grammaire SQL, pas ton domaine. A décrit un ORM, C l'approche SQL-first (sqlc, PgTyped), D un driver.

</details>

---

### Q2: Lequel de ces éléments PEUT être passé comme paramètre `?`
A) Le nom de la colonne de tri
B) La direction `DESC`
C) La valeur recherchée dans `WHERE handle = …`
D) Le nom de la table

<details><summary>Réponse</summary>

**C** — Un paramètre remplace une **valeur**. Identifiants (A, D) et mots-clés (B) font partie de la syntaxe : liste blanche obligatoire.

</details>

---

### Q3: Cette requête renvoie `contributor_count = 4` pour un projet qui a 2 contributeurs et 2 étiquettes. Pourquoi ?

```sql
SELECT p.title, count(*) AS contributor_count
  FROM projects p
  JOIN contributions c ON c.project_id = p.id
  JOIN project_tags pt ON pt.project_id = p.id
 GROUP BY p.id;
```

A) `count(*)` compte aussi les valeurs `NULL`
B) Les deux jointures 1-n produisent une ligne par combinaison contribution × étiquette
C) Il manque un index sur `project_tags`
D) `GROUP BY p.id` devrait être `GROUP BY p.title`

<details><summary>Réponse</summary>

**B** — C'est le *fan-out* : 2 × 2 = 4 lignes avant le regroupement. On corrige avec des sous-requêtes séparées (une par collection), pas avec un `count(DISTINCT)` de rattrapage. Effet secondaire : un projet sans étiquette disparaît à cause du `JOIN` interne.

</details>

---

### Q4: `db.prepare('SELECT * FROM projects ORDER BY ?').all('title')` :
A) Trie par titre
B) Lève une erreur de syntaxe
C) Ne trie pas : on trie par une constante
D) Est une injection SQL

<details><summary>Réponse</summary>

**C** — Le paramètre est une valeur (la chaîne `'title'`), identique pour toutes les lignes. Pas d'erreur, pas de tri : un bug silencieux.

</details>

---

### Q5: Ce code Prisma est-il sûr ?

```typescript
const query = `SELECT * FROM projects WHERE status = '${status}'`;
await prisma.$queryRawUnsafe(query);
```

A) Oui, Prisma échappe toujours les valeurs
B) Oui, car `status` est typé `string`
C) Non : la chaîne est construite par JavaScript avant d'atteindre Prisma
D) Non, mais uniquement sur MySQL

<details><summary>Réponse</summary>

**C** — Le template JavaScript (sans tag) est évalué avant l'appel : c'est une concaténation. La version sûre est le tagged template `` prisma.$queryRaw`… ${status}` ``. Un type `string` ne dit rien du contenu.

</details>

---

### Q6: Les types de ton client Prisma ont été générés depuis le schéma. Que ne garantissent-ils PAS ?
A) Qu'une faute de nom de champ soit détectée à la compilation
B) Que la base de production ait réellement ce schéma
C) Que le résultat d'un `select` n'ait que les champs demandés
D) Que les relations déclarées existent dans le schéma Prisma

<details><summary>Réponse</summary>

**B** — Un type statique est une affirmation faite dans le code. Si une migration n'a pas été appliquée, ou si la base a été modifiée à la main (dérive), les types mentent. D'où l'importance des migrations (module 03).

</details>

---

### Q7: Un utilisateur cherche « 100% » avec `WHERE label LIKE ?` et le paramètre `'%100%%'`. Que se passe-t-il ?
A) Erreur de syntaxe
B) Seuls les libellés contenant littéralement « 100% » sont trouvés
C) Les libellés contenant « 100 » suivi de n'importe quoi sont trouvés
D) Injection SQL

<details><summary>Réponse</summary>

**C** — Pas d'injection (la valeur est paramétrée), mais le `%` saisi reste un joker. Il faut échapper `%`, `_` et `\` et ajouter `ESCAPE '\'` (obligatoire en SQLite, qui n'a pas de caractère d'échappement par défaut).

</details>

---

### Q8: Laquelle de ces différences entre SGBD est exacte ?
A) MySQL supporte `INSERT … RETURNING`, PostgreSQL non
B) SQLite accepte `x IN ()` (liste vide), PostgreSQL non
C) PostgreSQL ne supporte pas le DDL transactionnel
D) Les collations par défaut de PostgreSQL sont insensibles à la casse

<details><summary>Réponse</summary>

**B** — A est inversé (MySQL n'a pas `RETURNING`), C est faux (PostgreSQL a un DDL transactionnel, MySQL non), D est faux (c'est MySQL dont les collations par défaut ignorent la casse). Ces détails fuient à travers n'importe quel ORM « portable ».

</details>

---

### Q9: Table `members(city)` avec les valeurs `'Lyon'`, `'Paris'`, `NULL`. Combien de lignes renvoie `WHERE city <> 'Paris'` ?
A) 0
B) 1
C) 2
D) 3

<details><summary>Réponse</summary>

**B** — `NULL <> 'Paris'` vaut `NULL` (inconnu), donc la ligne est exclue. Pour inclure les `NULL` : `city IS DISTINCT FROM 'Paris'` (ou `IS NOT` en SQLite). Logique ternaire de SQL : elle fuit à travers toute API qui génère un `<>`.

</details>

---

### Q10: Dans la plupart des applications, d'où vient le principal coût de performance d'un ORM ?
A) Du temps de construction de la requête en JavaScript
B) De la forme du SQL généré (requêtes et colonnes en trop, jointures inadaptées)
C) De la taille du paquet npm
D) Du typage TypeScript

<details><summary>Réponse</summary>

**B** — Le surcoût de la couche elle-même est généralement faible devant l'aller-retour réseau et l'exécution. Ce qui coûte, c'est le SQL : N+1, `SELECT *`, `JOIN` au lieu d'`EXISTS`, fonctions du SGBD inaccessibles. On le mesure avec le journal de requêtes et `EXPLAIN`.

</details>

---

### Q11: Quelle paire « niveau bas / ORM au-dessus » est correcte ?
A) Prisma / Drizzle
B) Kysely / Knex
C) SQLAlchemy Core / SQLAlchemy ORM
D) Eloquent / Doctrine DBAL

<details><summary>Réponse</summary>

**C** — SQLAlchemy ORM est construit sur Core, et on peut utiliser Core dans la même session et la même transaction. Autres paires valides : Knex / Objection.js, Doctrine DBAL / Doctrine ORM, Query Builder de Laravel / Eloquent.

</details>

---

### Q12: Pourquoi `const SORTS = { recent: 'p.created_at DESC' }` est-il une liste blanche fragile ?
A) Les objets sont plus lents que les `Map`
B) `SORTS['constructor']` existe via le prototype et passerait un test naïf
C) Les objets ne peuvent pas contenir de chaînes SQL
D) Elle n'est pas fragile

<details><summary>Réponse</summary>

**B** — Les clés héritées (`constructor`, `toString`, `__proto__`…) répondent à `SORTS[key]`. Utiliser `Map.has` ou `Object.hasOwn`.

</details>

---

### Q13 (ouverte): Explique pourquoi « ORM ou SQL brut ? » appelle presque toujours la réponse « les deux », et comment tracer la frontière.

<details><summary>Réponse modèle</summary>

Une application typique a deux sortes d'accès aux données. Les **écritures et le CRUD** touchent peu de lignes, doivent respecter des invariants, déclencher des validations et s'inscrire dans des transactions : c'est le terrain où un ORM (ou un query builder) apporte lisibilité, typage et sécurité par défaut. Les **lectures complexes** (tableaux de bord, recherche, exports, rapports) ont besoin de fonctions propres au SGBD, d'agrégations et d'une forme de résultat précise : l'API d'un ORM les exprime mal ou les rend lentes, le SQL écrit à la main (souvent dans des vues) les exprime directement.

La frontière se trace par **cas d'usage**, pas par préférence : ce qui relève du comportement métier passe par l'ORM ; ce qui relève de la lecture analytique ou des chemins critiques mesurés passe par du SQL. Trois règles la rendent tenable : SQL brut regroupé dans un module dédié, testé sur le vrai SGBD, et frontière documentée (ADR).

</details>

---

### Q14 (ouverte): Explique la différence entre une valeur et un identifiant dans une requête SQL, et la technique de protection adaptée à chacun.

<details><summary>Réponse modèle</summary>

Une **valeur** est une donnée comparée ou insérée (`'theo'`, `42`, une date). Elle peut être transmise **à part** du texte SQL, comme paramètre : le SGBD analyse la syntaxe sans la connaître, elle ne peut donc pas devenir du code. Technique : requête paramétrée, toujours.

Un **identifiant** (table, colonne, alias), comme un mot-clé (`ASC`, `AND`) ou un élément de structure (nombre d'éléments d'un `IN`), fait partie de la **syntaxe** : le SGBD doit le connaître pour analyser la requête, il ne peut pas être un paramètre (`ORDER BY ?` trie par une constante). Technique : **liste blanche**, où l'utilisateur choisit une clé publique que le code associe à un fragment SQL écrit par le développeur (`Map` de tris, `Map` de ressources). Si on doit absolument accepter un identifiant libre, on le valide par une expression régulière stricte puis on le cite, mais la liste blanche reste préférable parce qu'elle protège aussi la confidentialité (on choisit les colonnes exposées).

</details>

---

### Q15 (ouverte): Un collègue affirme : « Avec `include`, Prisma fait une seule requête avec des JOIN. » Comment vérifies-tu, et pourquoi la réponse compte-t-elle ?

<details><summary>Réponse modèle</summary>

On ne tranche ni par la documentation de mémoire ni par l'intuition : on **active le journal** (`new PrismaClient({ log: ['query'] })`), on exécute la requête sur des données réalistes et on lit le SQL émis. La stratégie dépend de la version et d'options comme `relationLoadStrategy` (`'join'` ou `'query'`), donc la réponse d'hier n'est pas forcément celle d'aujourd'hui.

La réponse compte parce que les deux stratégies ont des profils opposés. Une requête unique avec jointures évite les allers-retours mais peut provoquer un *fan-out* (si plusieurs collections sont chargées ensemble) et renvoyer beaucoup de données dupliquées. Plusieurs requêtes (`WHERE project_id IN (…)`) multiplient les allers-retours mais restent proportionnelles. Selon la latence réseau, le volume et le nombre de relations, l'une ou l'autre est meilleure : c'est une décision qu'on prend en mesurant, avec `EXPLAIN` sur le SQL obtenu.

</details>

---

**Score : /15 — Objectif : 11/15** (les questions ouvertes comptent si les deux idées principales de la réponse modèle y sont)
