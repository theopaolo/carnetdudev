# 🧠 Flashcards : Concepts avancés

Réponds à voix haute ou par écrit **avant** d'ouvrir la réponse.

## 🐌 N+1 et chargement des relations

### Q: Qu'est-ce que le problème N+1 ?
<details><summary>R</summary>

Une requête charge une liste de N éléments, puis une requête par élément charge une relation : 1 + N requêtes. Plus généralement : **le nombre de requêtes croît avec la taille des données** au lieu d'être constant. Le coût dominant est le nombre d'allers-retours, pas le volume.

</details>

### Q: Comment repérer un N+1 dans un journal de requêtes ?
<details><summary>R</summary>

La **même requête SQL** répétée avec des paramètres différents (`SELECT … FROM members WHERE id = ?` × 50). Dans les tests : compter les requêtes et échouer au-delà d'un budget ou d'un seuil de répétition.

</details>

### Q: Trois inconvénients d'un chargement par JOIN sur une relation 1-n ?
<details><summary>R</summary>

1. **Duplication** des colonnes du parent sur chaque ligne enfant.
2. **Produit cartésien** si on joint deux relations 1-n indépendantes (3 contributeurs × 2 étiquettes = 6 lignes).
3. **Pagination cassée** : `LIMIT` compte des lignes, pas des parents.

</details>

### Q: Comment fonctionne le préchargement par lots ?
<details><summary>R</summary>

Une requête pour la liste, puis **une requête par relation** avec `WHERE parent_id IN (...)` (ou `= ANY($1)` en PostgreSQL), et on rattache les enfants en mémoire avec une `Map`. Le nombre de requêtes = 1 + nombre de relations, indépendant de N.

</details>

### Q: `preload` et `eager_load` en Rails, `AsSplitQuery` et `AsSingleQuery` en EF Core : quelle est la question commune ?
<details><summary>R</summary>

Une requête avec jointure (et duplication des lignes) **ou** plusieurs requêtes séparées (sans duplication). `eager_load` / `AsSingleQuery` = jointure ; `preload` / `AsSplitQuery` = requêtes séparées.

</details>

### Q: Quel est le contrat de la fonction de lot d'un DataLoader ?
<details><summary>R</summary>

Recevoir un tableau de clés et renvoyer **un tableau de même longueur, dans le même ordre**, avec une valeur (ou `null`, ou une `Error`) par clé. La base ne garantit aucun ordre pour `IN (...)` : il faut réordonner avec une `Map`.

</details>

### Q: Pourquoi le cache d'un DataLoader doit-il être par requête HTTP ?
<details><summary>R</summary>

Un cache global sert des données **périmées** et peut **mélanger les droits d'accès** entre utilisateurs (ce qu'un utilisateur a le droit de voir n'est pas ce qu'un autre a le droit de voir).

</details>

### Q: Pourquoi le lazy loading est-il forcément asynchrone en JavaScript ?
<details><summary>R</summary>

Une requête en base ne peut pas bloquer le fil d'exécution : l'accès à une relation paresseuse renvoie une **promesse** (`await project.owner` en TypeORM, `await project.getOwner()` en Sequelize).

</details>

### Q: Que produit `JSON.stringify` sur une entité dont la relation est un getter paresseux ?
<details><summary>R</summary>

Il **appelle le getter** (donc lance une requête) et sérialise la promesse renvoyée… en `{}`. Une requête inutile et une donnée fausse.

</details>

### Q: Quelle règle simple évite la plupart des problèmes de chargement ?
<details><summary>R</summary>

Chaque cas d'usage **déclare explicitement** ce qu'il charge ; le lazy loading implicite est interdit (mode strict : `strict_loading` Rails, `preventLazyLoading()` Laravel) ; ce qui sort de l'application passe par un DTO.

</details>

## 🪞 Identity Map et Unit of Work

### Q: Définition de l'Identity Map (Fowler) ?
<details><summary>R</summary>

Garantit que chaque objet n'est chargé **qu'une fois** par unité de travail, en gardant les objets chargés dans une table indexée par (type, identifiant). Deux lectures de `projects#1` renvoient le **même** objet.

</details>

### Q: L'Identity Map est-elle un cache ?
<details><summary>R</summary>

Son but premier est la **cohérence** (un objet par ligne et par session). L'économie de requêtes sur `find(id)` est un effet secondaire ; une requête par critère part quand même en base. Ce n'est pas un cache partagé entre requêtes.

</details>

### Q: Définition de l'Unit of Work (Fowler) ?
<details><summary>R</summary>

Maintient la liste des objets **nouveaux, modifiés, supprimés** pendant une transaction métier, puis coordonne leur écriture (ordre, transaction) et la résolution des conflits de concurrence.

</details>

### Q: Trois façons de détecter qu'une entité a été modifiée (*dirty checking*) ?
<details><summary>R</summary>

1. L'appelant le signale (`registerDirty`).
2. Comparaison avec un **instantané** pris au chargement (Doctrine, Hibernate, MikroORM).
3. Interception des affectations (proxies, setters).

</details>

### Q: Dans quel ordre une Unit of Work écrit-elle ?
<details><summary>R</summary>

Insertions **parents d'abord** (l'enfant a besoin de l'id du parent), puis mises à jour, puis suppressions **enfants d'abord**. L'ordre suit le graphe des clés étrangères, pas l'ordre du code.

</details>

### Q: Cite trois ORMs avec Unit of Work et trois sans.
<details><summary>R</summary>

Avec : Hibernate, Doctrine, MikroORM, SQLAlchemy, EF Core. Sans : Prisma, Sequelize, TypeORM, Drizzle (et les query builders Knex, Kysely).

</details>

### Q: Quelle est la bonne portée d'une Unit of Work dans une application web ?
<details><summary>R</summary>

**Une par requête HTTP** (ou par tâche). Globale, elle grossit sans fin, sert des données périmées et mélange les utilisateurs. MikroORM refuse par défaut l'usage de son `EntityManager` global.

</details>

## 🔒 Transactions et isolation

### Q: Que signifie vraiment le « C » d'ACID ?
<details><summary>R</summary>

La cohérence des **invariants de l'application**. La base aide avec des contraintes, mais elle ne connaît pas les règles métier : c'est une propriété de l'application, pas du moteur.

</details>

### Q: Qu'est-ce qu'un savepoint, et à quoi sert-il dans un ORM ?
<details><summary>R</summary>

Un point de reprise **à l'intérieur** d'une transaction (`SAVEPOINT`, `ROLLBACK TO`, `RELEASE`). Les ORMs et query builders (Knex, Doctrine DBAL) s'en servent pour simuler des transactions imbriquées, qui n'existent pas en SQL standard.

</details>

### Q: Définis le *lost update*.
<details><summary>R</summary>

Deux transactions lisent la même valeur, calculent, écrivent : la seconde écriture écrase la première. Exemple : deux étoiles ajoutées, une seule comptée.

</details>

### Q: Définis le *write skew*, avec un exemple.
<details><summary>R</summary>

Deux transactions vérifient une condition sur un **ensemble**, puis écrivent des lignes **différentes** qui, ensemble, violent la condition. Exemple : « au moins un auteur par projet actif » ; deux auteurs vérifient qu'ils sont deux, chacun se retire, il n'en reste aucun. Ni verrou de ligne ni verrou optimiste ne le voient.

</details>

### Q: Quel est l'apport de Berenson et al. (1995) ?
<details><summary>R</summary>

Montrer que les niveaux d'isolation ANSI sont **ambigus** et **incomplets** : ils oublient dirty write, lost update, read skew, write skew, et l'isolation par instantané (*snapshot isolation*) ne rentre dans aucun niveau.

</details>

### Q: Niveaux d'isolation par défaut : PostgreSQL, MySQL/InnoDB, SQLite ?
<details><summary>R</summary>

PostgreSQL : **READ COMMITTED**. MySQL/InnoDB : **REPEATABLE READ**. SQLite : **SERIALIZABLE** (un seul écrivain à la fois).

</details>

### Q: Que fait PostgreSQL en REPEATABLE READ face à une mise à jour perdue ?
<details><summary>R</summary>

Il la **détecte** : l'`UPDATE` de la seconde transaction échoue (`could not serialize access due to concurrent update`, SQLSTATE `40001`). L'application doit rejouer toute la transaction.

</details>

### Q: Quelles erreurs PostgreSQL justifient de rejouer une transaction ?
<details><summary>R</summary>

`40001` (*serialization_failure*) et `40P01` (*deadlock_detected*). On rejoue **toute** la transaction, lectures comprises, avec backoff, et sans effet de bord hors base dans le code rejoué.

</details>

### Q: Piège n°1 des transactions interactives (Prisma, Knex, Sequelize) ?
<details><summary>R</summary>

Faire une requête avec le **mauvais client** (`prisma` au lieu de `tx`, `knex` au lieu de `trx`, oublier `{ transaction: t }`) : elle part sur une autre connexion, **hors transaction**, sans aucune erreur.

</details>

## ⚔️ Concurrence

### Q: Pourquoi aucun niveau d'isolation ne protège un formulaire d'édition web ?
<details><summary>R</summary>

La lecture (affichage du formulaire) et l'écriture (soumission) sont dans **deux transactions différentes**, parfois séparées de plusieurs minutes. C'est une transaction métier : il faut un verrou optimiste (Fowler : *Optimistic Offline Lock*).

</details>

### Q: Écris le `UPDATE` d'un verrouillage optimiste.
<details><summary>R</summary>

```sql
UPDATE projects SET title = ?, version = version + 1
WHERE id = ? AND version = ?;
-- 0 ligne modifiée → la ligne a disparu, ou quelqu'un est passé avant (conflit)
```

</details>

### Q: Quelle est la « troisième voie », souvent oubliée, contre la mise à jour perdue ?
<details><summary>R</summary>

L'**écriture atomique** : `SET stars = stars + 1`, ou conditionnelle : `UPDATE … SET status = 'active' WHERE id = ? AND status = 'draft'`. Pas de lecture côté application, donc rien à perdre.

</details>

### Q: À quoi servent `FOR UPDATE NOWAIT` et `FOR UPDATE SKIP LOCKED` ?
<details><summary>R</summary>

`NOWAIT` : échouer tout de suite au lieu d'attendre un verrou. `SKIP LOCKED` : ignorer les lignes déjà verrouillées, idéal pour que plusieurs workers prennent des tâches différentes dans une file.

</details>

## ⚡ Performance

### Q: PostgreSQL et SQLite indexent-ils automatiquement les clés étrangères ?
<details><summary>R</summary>

**Non** (MySQL/InnoDB, si). Sans index : jointures lentes et suppression du parent qui parcourt toute la table enfant pour vérifier `RESTRICT` / appliquer `CASCADE`.

</details>

### Q: Que signifient `SCAN`, `SEARCH … USING INDEX`, `USE TEMP B-TREE FOR ORDER BY`, `COVERING INDEX` ?
<details><summary>R</summary>

`SCAN` : lecture de toute la table. `SEARCH … USING INDEX` : accès par l'index. `USE TEMP B-TREE FOR ORDER BY` : tri en mémoire. `COVERING INDEX` : toutes les colonnes nécessaires sont dans l'index, la table n'est pas lue.

</details>

### Q: Dans un index composite, dans quel ordre mettre les colonnes ?
<details><summary>R</summary>

D'abord les colonnes filtrées par **égalité**, ensuite celles du **tri** ou des intervalles : `(status, created_at, id)` pour `WHERE status = ? ORDER BY created_at DESC, id DESC`.

</details>

### Q: Deux défauts de la pagination par `OFFSET` ?
<details><summary>R</summary>

1. **Coût linéaire** : `OFFSET 30000` produit puis jette 30 000 lignes.
2. **Instabilité** : une insertion entre deux pages décale tout (doublons ou lignes sautées).

</details>

### Q: Écris la condition d'une pagination par curseur sur `(created_at, id)` décroissants.
<details><summary>R</summary>

```sql
WHERE (created_at, id) < (?, ?)          -- valeurs de la dernière ligne vue
ORDER BY created_at DESC, id DESC
LIMIT 21                                  -- limit + 1 pour savoir s'il y a une suite
```

Sans comparaison de tuples : `created_at < ? OR (created_at = ? AND id < ?)`.

</details>

### Q: Pourquoi 2 000 insertions en autocommit sont-elles beaucoup plus lentes que dans une transaction ?
<details><summary>R</summary>

Chaque validation attend que l'écriture soit **durable sur disque**. En autocommit, 2 000 attentes ; dans une transaction, une seule (mesuré ici : ≈ 2,2 s contre ≈ 7 ms sur un fichier SQLite).

</details>

### Q: Que contournent les opérations en masse (`update_all`, `Model.update()` statique, `UPDATE` DQL) ?
<details><summary>R</summary>

Les **hooks / callbacks / événements**, souvent les **validations**, et l'**Unit of Work** (les entités déjà chargées deviennent fausses). Les invariants qui doivent tenir toujours vont dans la base (contraintes).

</details>

## 🕳️ Comportements cachés, architecture, tests

### Q: Qu'est-ce que l'outbox transactionnelle et quel problème résout-elle ?
<details><summary>R</summary>

Écrire l'événement à publier dans une table `outbox` **dans la même transaction** que la modification ; un relais séparé l'envoie. Résout : l'e-mail envoyé pour une transaction annulée, ou jamais envoyé si le processus meurt après le `COMMIT`. Garantie « au moins une fois » → consommateur idempotent.

</details>

### Q: Qu'est-ce que le *mass assignment*, et quel incident l'a rendu célèbre ?
<details><summary>R</summary>

Copier toutes les clés reçues dans le modèle, y compris des champs non prévus (`is_admin`). En mars 2012, Egor Homakov l'a exploité sur GitHub (application Rails) pour pousser un commit sur le dépôt de Rails. Réponse : *strong parameters* (Rails 4), `$fillable` (Laravel), liste blanche par cas d'usage.

</details>

### Q: Quatre pièges du soft delete ?
<details><summary>R</summary>

1. **Unicité** bloquée par les lignes supprimées (→ index unique partiel `WHERE deleted_at IS NULL`).
2. **Filtres oubliés** dans le SQL brut, les rapports, les jointures.
3. **Cascades** qui ne se déclenchent pas (pas de `DELETE`).
4. **RGPD** : ce n'est pas une suppression (droit à l'effacement, minimisation).

</details>

### Q: Quand un Repository au-dessus d'un ORM Data Mapper est-il inutile ?
<details><summary>R</summary>

Quand il ne fait que répéter `findById` / `findAll` / `save` : l'`EntityManager` est déjà un repository générique. Il se justifie s'il **nomme des requêtes du domaine**, isole du SQL brut, ou sert de point de substitution en test. Un par **agrégat** (Evans), pas par table.

</details>

### Q: Qu'est-ce que le CQRS « léger » ?
<details><summary>R</summary>

Écritures via les entités et l'ORM (protection des invariants), lectures via SQL ou vues adaptées à chaque écran. Même base, deux chemins. À ne pas confondre avec le CQRS complet (modèles et stockages séparés, projections par événements).

</details>

### Q: Pourquoi `SET LOCAL` et pas `SET` pour la Row-Level Security avec un pool ?
<details><summary>R</summary>

La connexion est réutilisée par la requête suivante, peut-être pour un autre tenant. `SET LOCAL` limite la valeur à la transaction en cours ; `SET` la laisse sur la connexion. Même raison pour laquelle l'état de session casse en mode `transaction` de PgBouncer.

</details>

### Q: Pourquoi tester l'accès aux données sur une vraie base plutôt qu'en mockant l'ORM ?
<details><summary>R</summary>

Un mock vérifie qu'on a **appelé** l'ORM, pas que la requête est juste. Contraintes, collations, transactions, SQL généré n'existent que dans la vraie base, et de préférence **le même moteur** qu'en production (Testcontainers pour PostgreSQL).

</details>

### Q: Fixtures ou fabriques ?
<details><summary>R</summary>

**Fixtures** : jeu de données fixe partagé ; chaque test dépend de données qu'il ne déclare pas. **Fabriques** : fonctions qui créent une entité minimale valide avec des surcharges (`makeProject(db, { status: 'archived' })`) ; chaque test montre les données qui comptent pour lui.

</details>

---

**Cartes** : 45
**Dernière mise à jour** : 2026-10-29
**Niveau** : Avancé
