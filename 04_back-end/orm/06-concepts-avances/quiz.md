# 📝 Quiz : Concepts avancés

16 questions : 13 à choix multiple, 3 ouvertes. Réponds sans les notes, puis vérifie. Pour les questions ouvertes, compare ta réponse aux éléments attendus plutôt qu'à la formulation.

---

### Q1 : Une page liste 50 projets avec le pseudo de leur propriétaire et leurs étiquettes, chargés relation par relation dans une boucle. Combien de requêtes ?
A) 1
B) 3
C) 51
D) 101

<details><summary>Réponse</summary>

**D** — 1 requête pour la liste, puis 50 pour les propriétaires et 50 pour les étiquettes : 2N + 1. Le nom « N+1 » désigne toute la famille où le nombre de requêtes croît avec N. Avec un préchargement par lots, ce serait **B** (1 + une par relation).

</details>

---

### Q2 : Tu charges des projets avec un `JOIN` sur `contributions` **et** un `JOIN` sur `project_tags`. Un projet a 4 contributeurs et 3 étiquettes. Combien de lignes pour ce projet ?
A) 1
B) 7
C) 12
D) 4

<details><summary>Réponse</summary>

**C** — Deux relations 1-n indépendantes jointes dans la même requête donnent un **produit cartésien** : 4 × 3 = 12. C'est l'« explosion cartésienne » contre laquelle EF Core propose `AsSplitQuery()`, et la raison pour laquelle on préfère souvent une requête par relation.

</details>

---

### Q3 : Pourquoi `LIMIT 10` sur une requête `projects JOIN project_tags` ne renvoie-t-il pas forcément 10 projets ?
A) Parce que SQLite ignore `LIMIT` avec une jointure
B) Parce que `LIMIT` compte des lignes, et qu'un projet occupe une ligne par étiquette
C) Parce que l'ordre n'est pas garanti
D) Parce qu'il faut `DISTINCT`

<details><summary>Réponse</summary>

**B** — Un projet à 3 étiquettes consomme 3 lignes de la limite. `DISTINCT` (D) ne résout rien tant qu'on sélectionne les étiquettes. Solutions : paginer d'abord les identifiants de projets, puis charger leurs relations (c'est ce que fait le `Paginator` de Doctrine), ou précharger les relations par une seconde requête.

</details>

---

### Q4 : Quelle affirmation sur l'Identity Map est **fausse** ?
A) Deux `find(1)` dans la même unité de travail renvoient le même objet
B) Elle évite que deux copies d'une même ligne divergent en mémoire
C) C'est un cache partagé entre toutes les requêtes HTTP pour réduire la charge de la base
D) Une requête `WHERE status = 'active'` part quand même en base

<details><summary>Réponse</summary>

**C** — L'Identity Map a la portée d'**une** unité de travail (typiquement une requête HTTP). Partagée, elle servirait des données périmées et mélangerait les utilisateurs. Le cache « de second niveau » de certains ORMs est un mécanisme distinct, avec ses propres problèmes d'invalidation.

</details>

---

### Q5 : Avec une Unit of Work, tu enregistres un nouveau projet, **puis** le nouveau membre qui en est propriétaire. Que se passe-t-il au `commit` ?
A) Erreur de clé étrangère : le projet est inséré avant son propriétaire
B) Le membre est inséré d'abord, son id est propagé au projet, puis le projet est inséré
C) Les deux sont insérés avec `owner_id = NULL`, puis mis à jour
D) Rien : il faut appeler `registerDirty`

<details><summary>Réponse</summary>

**B** — L'Unit of Work ordonne les écritures selon le graphe des clés étrangères (parents d'abord), pas selon l'ordre du code. **C** est ce qu'un ORM fait seulement en cas de **cycle** de clés étrangères. Revers : les requêtes envoyées ne suivent plus le fil du code, ce qui complique le débogage.

</details>

---

### Q6 : Lequel de ces outils implémente une Unit of Work ?
A) Prisma
B) Sequelize
C) Drizzle
D) MikroORM

<details><summary>Réponse</summary>

**D** — MikroORM (comme Doctrine, Hibernate, SQLAlchemy, EF Core) suit les entités et écrit au `flush()`. Prisma, Sequelize et Drizzle envoient chaque opération au moment de l'appel. Ce n'est pas un défaut : ce qu'on écrit est ce qui part en base, ce qui est plus prévisible.

</details>

---

### Q7 : Niveau d'isolation par défaut de PostgreSQL ?
A) READ UNCOMMITTED
B) READ COMMITTED
C) REPEATABLE READ
D) SERIALIZABLE

<details><summary>Réponse</summary>

**B** — PostgreSQL : READ COMMITTED. MySQL/InnoDB : REPEATABLE READ. SQLite : SERIALIZABLE. Si l'ORM ne précise rien, c'est le défaut du SGBD qui s'applique ; le même code n'a donc pas les mêmes garanties d'un moteur à l'autre.

</details>

---

### Q8 : Deux auteurs d'un projet vérifient chacun « nous sommes deux auteurs », puis chacun retire **sa propre** contribution. Il ne reste aucun auteur. Quelle anomalie ?
A) Dirty read
B) Lost update
C) Phantom read
D) Write skew

<details><summary>Réponse</summary>

**D** — Write skew : la condition porte sur un **ensemble**, et chaque transaction écrit une ligne **différente**. Aucune ligne n'est écrite deux fois, donc ni verrou de ligne ni verrou optimiste ne le détectent. Il faut SERIALIZABLE (avec retry), ou verrouiller une ligne qui matérialise le conflit (par exemple `SELECT … FROM projects WHERE id = ? FOR UPDATE` avant de vérifier).

</details>

---

### Q9 : Que montre la critique de Berenson et al. (1995) ?
A) Que SERIALIZABLE est trop lent pour être utilisé
B) Que les définitions ANSI des niveaux d'isolation sont ambiguës et oublient des anomalies, dont celles de l'isolation par instantané
C) Que les ORMs gèrent mal les transactions
D) Que READ UNCOMMITTED devrait être supprimé de la norme

<details><summary>Réponse</summary>

**B** — Les phénomènes ANSI admettent une lecture stricte et une lecture large ; la norme ignore dirty write, lost update, read skew et write skew ; la *snapshot isolation* ne rentre dans aucun des quatre niveaux. Conséquence : un nom de niveau ne garantit pas la même chose d'un SGBD à l'autre.

</details>

---

### Q10 : Un formulaire d'édition est affiché (requête HTTP 1), puis soumis 3 minutes plus tard (requête HTTP 2). Qu'est-ce qui empêche d'écraser une modification faite entre-temps par quelqu'un d'autre ?
A) Passer la base en SERIALIZABLE
B) Un `SELECT … FOR UPDATE` dans la requête 1
C) Une colonne `version` vérifiée dans le `WHERE` de l'`UPDATE` de la requête 2
D) Une transaction autour de l'`UPDATE` de la requête 2

<details><summary>Réponse</summary>

**C** — Lecture et écriture sont dans deux transactions séparées : aucun niveau d'isolation (A, D) ne les relie. Un verrou pessimiste (B) devrait rester posé pendant 3 minutes, connexion comprise : impraticable. Le verrou **optimiste** (Fowler : *Optimistic Offline Lock*) détecte le conflit à l'écriture (`changes === 0`).

</details>

---

### Q11 : Dans une transaction interactive Prisma, tu écris `await prisma.project.update(...)` au lieu de `await tx.project.update(...)`. Que se passe-t-il ?
A) Prisma lève une erreur
B) La requête s'exécute hors de la transaction, sur une autre connexion, sans erreur
C) La requête est mise en attente jusqu'au commit
D) Rien de différent : Prisma détecte la transaction en cours

<details><summary>Réponse</summary>

**B** — Le client global n'a aucun lien avec la transaction. La requête est validée immédiatement, et ne sera **pas** annulée si la transaction échoue. Même piège avec `knex` au lieu de `trx`, ou en oubliant `{ transaction: t }` en Sequelize.

</details>

---

### Q12 : `EXPLAIN QUERY PLAN` affiche `SCAN projects` puis `USE TEMP B-TREE FOR ORDER BY` pour `WHERE status = ? ORDER BY created_at DESC LIMIT 20`. Quel index ?
A) `(created_at)`
B) `(status)`
C) `(status, created_at)`
D) `(created_at, status)`

<details><summary>Réponse</summary>

**C** — Égalité d'abord (`status`), tri ensuite (`created_at`) : la base trouve le bloc `status = ?` puis le lit **déjà trié**, et s'arrête après 20 entrées. Avec B, elle filtre mais doit trier ; avec A ou D, elle ne peut pas exploiter l'égalité sur `status` en tête d'index. Ajouter `id` en dernière colonne permet le départage et le curseur.

</details>

---

### Q13 : Quel est le piège du soft delete avec une contrainte `UNIQUE(email)` ?
A) Les e-mails supprimés sont effacés de l'index
B) Un utilisateur supprimé « en douceur » empêche toute réinscription avec le même e-mail
C) La contrainte est désactivée sur les lignes supprimées
D) Aucun

<details><summary>Réponse</summary>

**B** — La ligne existe toujours, l'unicité la voit. Correctif : index unique **partiel** `CREATE UNIQUE INDEX … ON accounts (email) WHERE deleted_at IS NULL` (PostgreSQL, SQLite). Les autres pièges : filtres oubliés hors ORM, cascades qui ne se déclenchent pas, conformité RGPD.

</details>

---

### Q14 (ouverte) : Explique pourquoi un hook `afterSave` qui envoie un e-mail est fragile, et propose une architecture robuste.

<details><summary>Réponse modèle</summary>

Éléments attendus :

- **Le hook s'exécute pendant la transaction** : si elle est annulée ensuite (contrainte violée plus loin, erreur applicative), l'e-mail est déjà parti pour un changement qui n'a jamais existé.
- **Déplacer l'envoi après le `COMMIT` ne suffit pas** : si le processus s'arrête entre le `COMMIT` et l'envoi, l'e-mail ne part jamais. Il n'y a pas d'atomicité entre la base et le service d'e-mail.
- **Invisibilité** : `project.save()` n'annonce pas qu'il envoie un e-mail ; les opérations en masse (`update_all`, `Model.update()` statique) contournent le hook, et l'e-mail ne part pas.
- **Solution : outbox transactionnelle.** Dans la même transaction que la modification, insérer une ligne dans une table `outbox`. Un relais séparé lit les événements non publiés, les envoie, les marque publiés. Soit le changement et l'événement sont écrits, soit aucun des deux.
- **Garantie « au moins une fois »** : l'envoi peut réussir et le marquage échouer ; le consommateur doit être **idempotent** (mémoriser les identifiants d'événements traités). Avec plusieurs relais sur PostgreSQL : `FOR UPDATE SKIP LOCKED`.

</details>

---

### Q15 (ouverte) : Tu dois paginer un fil de 2 millions de projets triés du plus récent au plus ancien. Compare OFFSET et la pagination par curseur, et décris la requête et l'index.

<details><summary>Réponse modèle</summary>

Éléments attendus :

- **OFFSET** : coût linéaire en profondeur (la base produit puis jette `OFFSET` lignes) ; instable (une insertion entre deux pages provoque doublons ou sauts). Avantage : saut direct à la page N, compatible avec un affichage « page 1, 2, 3… ».
- **Curseur (keyset)** : on repart de la dernière ligne vue. Coût constant en profondeur avec le bon index, résultats stables face aux insertions. Limites : pas de saut direct, total coûteux (`COUNT(*)` séparé).
- **Ordre total** : `created_at` n'est pas unique, on départage par `id` : `ORDER BY created_at DESC, id DESC`.
- **Requête** : `WHERE (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC LIMIT n + 1` (le `+ 1` indique s'il existe une page suivante). Sans comparaison de tuples : `created_at < ? OR (created_at = ? AND id < ?)`.
- **Index** : `(created_at, id)` ; avec un filtre d'égalité (`status = ?`), `(status, created_at, id)`. Vérifier avec `EXPLAIN` : plus de tri temporaire.
- **Curseur opaque et validé** (base64url d'un JSON) : c'est une entrée utilisateur, on la décode et on vérifie ses types.

</details>

---

### Q16 (ouverte) : Un collègue propose d'ajouter un `GenericRepository<T>` (`findById`, `findAll`, `save`, `delete`) au-dessus de Doctrine « pour découpler de l'ORM ». Argumente.

<details><summary>Réponse modèle</summary>

Éléments attendus :

- **L'`EntityManager` de Doctrine est déjà un repository générique** (avec Identity Map et Unit of Work). La couche répète l'ORM sans rien ajouter.
- **Elle fait perdre des fonctionnalités** : chargement explicite des relations, requêtes riches (DQL, critères), pagination ; on finit par ajouter des paramètres génériques qui réimplémentent l'ORM en moins bien, ou par contourner la couche.
- **Le « découplage » est illusoire** : la sémantique (Unit of Work, `flush` différé, lazy loading) fuit à travers l'interface ; changer d'ORM changerait le comportement même avec la même interface.
- **Ce qui serait utile à la place** (Evans) : un repository **par agrégat** (pas par table), avec des méthodes **du domaine** (`activeProjectsOf(member)`), qui peut cacher du SQL brut optimisé et servir de point de substitution pour tester un service sans base.
- Conclusion : refuser le générique, accepter des repositories spécifiques là où ils nomment quelque chose.

</details>

---

**Score : /16 — Objectif : 12/16**
(Questions ouvertes : 1 point si tous les éléments principaux sont présents, ½ si la moitié.)
