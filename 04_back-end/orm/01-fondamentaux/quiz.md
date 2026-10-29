# 📝 Quiz : Fondamentaux des ORMs

> 12 questions à choix unique, puis 3 questions ouvertes. Réponds sans relire les notes, puis vérifie. Une bonne réponse sans la bonne justification compte pour moitié.

---

### Q1 : Qu'est-ce qui distingue un ORM d'un query builder ?
A) L'ORM génère du SQL, le query builder non
B) L'ORM mappe les résultats vers un modèle objet (types, relations, identité), le query builder s'arrête au SQL
C) Le query builder est toujours plus rapide
D) L'ORM ne fonctionne qu'avec PostgreSQL

<details><summary>Réponse</summary>

**B**. Les deux génèrent du SQL (A est faux). La différence est le mapping vers un modèle objet : hydratation, relations, souvent suivi des changements. C et D sont sans fondement : la vitesse dépend du SQL produit, pas de la catégorie d'outil.

</details>

---

### Q2 : On exécute deux fois `SELECT * FROM members WHERE id = 1` et on hydrate chaque résultat sans Identity Map. Que vaut `a === b` ?
A) `true`, car c'est la même ligne
B) `false`, car ce sont deux objets distincts en mémoire
C) `true` seulement si aucune colonne n'a changé entre-temps
D) Une erreur est levée

<details><summary>Réponse</summary>

**B**. Même clé primaire ne veut pas dire même objet. Sans Identity Map, chaque lecture crée un nouvel objet ; modifier l'un ne modifie pas l'autre, et des sauvegardes concurrentes s'écrasent en silence.

</details>

---

### Q3 : Dans l'Atelier, pourquoi `contributions` doit-elle devenir une entité dans le modèle objet alors que `project_tags` peut rester cachée ?
A) Parce que `contributions` a une clé primaire composite
B) Parce que `contributions` porte des attributs propres au couple (`role`, `since`)
C) Parce que `project_tags` n'a pas de clé étrangère
D) Parce que `contributions` est plus volumineuse

<details><summary>Réponse</summary>

**B**. Les deux tables ont une clé primaire composite (A ne discrimine pas) et des clés étrangères (C est faux). `project_tags` ne porte que les deux clés : une collection `project.tags` suffit. `contributions` porte un rôle et une date qui n'appartiennent qu'au couple : sans entité `Contribution`, ces données disparaissent du modèle.

</details>

---

### Q4 : Selon Fowler, quelle est la différence entre Row Data Gateway et Active Record ?
A) Le Row Data Gateway gère une table entière, l'Active Record une ligne
B) L'Active Record ajoute de la logique métier ; le Row Data Gateway n'en contient pas
C) Le Row Data Gateway utilise une Unit of Work
D) Il n'y en a aucune, ce sont deux noms du même pattern

<details><summary>Réponse</summary>

**B**. Les deux représentent une ligne par objet et savent se persister. L'Active Record y ajoute le comportement métier. A décrit le Table Data Gateway ; C est faux (aucun des deux n'implique de Unit of Work).

</details>

---

### Q5 : Quel extrait relève du pattern Data Mapper avec Unit of Work ?
A) `member.save()`
B) `prisma.member.update({ where: { id: 2 }, data: { email } })`
C) `$member->changeEmail($email); $entityManager->flush();`
D) `memberGateway.updateEmail(2, email)`

<details><summary>Réponse</summary>

**C**. L'entité n'a pas de méthode de persistance ; un gestionnaire (`EntityManager`) a suivi ses changements et les écrit au `flush`. A est un Active Record, B un client généré (appel de requête explicite, objets simples), D un Table Data Gateway.

</details>

---

### Q6 : Quel critère est le plus discriminant pour choisir un Data Mapper plutôt qu'un Active Record ?
A) La taille de la base de données
B) Le SGBD utilisé
C) Le besoin de tester des règles métier nombreuses sans base, avec un modèle qui diverge du schéma
D) Le nombre de développeurs dans l'équipe

<details><summary>Réponse</summary>

**C**. Le Data Mapper paie son coût (plus de code, plus de concepts) par l'indépendance du domaine. Ce gain n'a de valeur que si le domaine est riche et diffère du schéma. A, B et D n'ont pas d'influence directe sur le choix de pattern.

</details>

---

### Q7 : Quelle affirmation sur Prisma est la plus juste ?
A) C'est un Active Record : chaque modèle a une méthode `save()`
B) C'est un Data Mapper complet avec Identity Map et Unit of Work
C) C'est un client typé généré depuis un schéma, qui renvoie des objets simples ; il n'entre exactement dans aucune des deux familles
D) Ce n'est qu'un driver PostgreSQL

<details><summary>Réponse</summary>

**C**. Pas de `save()` sur des instances (A faux), pas d'Identity Map ni de Unit of Work (B faux), et il gère bien plus que la connexion (D faux). Structurellement, c'est une passerelle de table typée et générée, avec gestion des relations.

</details>

---

### Q8 : Un filtre SQL `WHERE status <> 'banned'` s'applique à une table où certains `status` sont `NULL`. Que se passe-t-il ?
A) Les lignes `NULL` sont incluses, comme en JavaScript
B) Les lignes `NULL` sont exclues, car `NULL <> 'banned'` vaut `NULL` (inconnu)
C) Une erreur est levée
D) Le résultat dépend de l'ORM

<details><summary>Réponse</summary>

**B**. SQL utilise une logique à trois valeurs : toute comparaison avec `NULL` donne `NULL`, et `WHERE` ne garde que les lignes où la condition est vraie. Pour inclure les `NULL` : `status IS DISTINCT FROM 'banned'` (PostgreSQL, SQLite ≥ 3.39) ou `status <> 'banned' OR status IS NULL`. D est un piège : l'ORM génère le SQL, mais la sémantique est celle du SGBD.

</details>

---

### Q9 : Dans un Active Record générique, pourquoi ne peut-on pas écrire `SELECT * FROM members WHERE ? = ?` avec le nom de colonne en premier paramètre ?
A) Parce que SQLite ne supporte pas deux paramètres
B) Parce que les paramètres liés ne remplacent que des valeurs, jamais des identifiants : la requête comparerait une chaîne constante à une valeur
C) Parce que c'est plus lent
D) On peut, c'est la méthode recommandée

<details><summary>Réponse</summary>

**B**. `? = ?` compare deux valeurs liées (par exemple la chaîne `'handle'` à `'ada'`), pas une colonne. Les identifiants doivent être insérés dans le texte SQL, donc **validés contre une liste blanche** (les métadonnées de mapping). Sinon, l'injection passe par le nom de colonne, là où aucun paramètre ne protège.

</details>

---

### Q10 : Que dit en substance Ted Neward dans « The Vietnam of Computer Science » ?
A) Les ORMs sont inutiles et doivent être interdits
B) L'ORM est un bourbier : succès rapides, puis coûts croissants pour chaque cas limite, sans solution complète ni sortie claire
C) Les bases objet ont définitivement remplacé le relationnel
D) Le SQL est obsolète

<details><summary>Réponse</summary>

**B**. Neward ne prône pas l'interdiction (A) : il décrit une dynamique d'engagement croissant et énumère plusieurs issues possibles (renoncer aux objets, au relationnel, mapper à la main, accepter les limites, intégrer le relationnel au langage ou aux frameworks). C et D sont contraires à son propos.

</details>

---

### Q11 : Pourquoi la portabilité d'un ORM entre SGBD est-elle limitée ?
A) Parce que les ORMs ne supportent qu'un SGBD
B) Parce que l'ORM abstrait la syntaxe mais pas la sémantique (isolation, collations, `NULL` dans les tris, JSON…)
C) Parce que le SQL n'est pas standardisé du tout
D) Elle ne l'est pas : un ORM garantit un comportement identique partout

<details><summary>Réponse</summary>

**B**. La plupart des ORMs supportent plusieurs SGBD (A faux). Le SQL a un standard, mais chaque moteur s'en écarte et le complète (C exagère). L'application dépend des comportements fins du moteur sur lequel elle a été développée, que l'ORM ne normalise pas (D faux).

</details>

---

### Q12 : Laquelle de ces situations justifie le plus clairement de **ne pas** passer par l'ORM ?
A) Un formulaire d'édition du profil d'un membre
B) Un tableau de bord qui agrège le nombre de contributions par rôle et par mois, avec un cumul glissant
C) La création d'un projet avec ses étiquettes
D) L'archivage d'un projet après vérification de son statut

<details><summary>Réponse</summary>

**B**. Agrégats, regroupement temporel et fonction de fenêtre : c'est de la pensée ensembliste, que l'ORM exprime mal, et l'hydratation en objets n'apporte rien. A, C et D sont des écritures sur des entités avec des règles : le terrain naturel d'un ORM.

</details>

---

## ✍️ Questions ouvertes

### Q13 : Explique trois dimensions de l'*impedance mismatch* avec un exemple tiré de l'Atelier pour chacune.

<details><summary>Réponse modèle</summary>

- **Identité** : charger deux fois le membre 1 donne deux objets ; si deux parties du code modifient chacune leur copie de `theo` puis l'enregistrent, la seconde écriture écrase la première sans erreur. La base, elle, n'a qu'une ligne d'identifiant 1.
- **Associations** : `project.owner` est une référence portée par le projet ; `member.projects` est une seconde référence à maintenir. En base, une seule clé étrangère `projects.owner_id` sert les deux sens. Pour les étiquettes, le modèle objet n'a qu'un tableau `project.tags`, la base a besoin d'une table `project_tags`.
- **Types** : `created_at` revient en texte UTC sans fuseau ; mal converti par `new Date()`, il est décalé à Paris. Côté écriture, `node:sqlite` refuse de lier `true`, un `Date` ou `undefined`.

Autres réponses valables : granularité (objet valeur `Email` contre colonne texte), héritage (pas d'équivalent relationnel), navigation (boucle sur `project.owner()` contre jointure unique), encapsulation (statut modifiable seulement via `archive()` contre colonne `status` en écriture libre), fraîcheur (objet chargé périmé si un autre processus modifie la ligne).

**Critères** : trois dimensions distinctes, chacune avec le côté objet **et** le côté relationnel, et une conséquence concrète.

</details>

---

### Q14 : Ton équipe démarre un back-office interne (gestion des membres, projets, étiquettes ; peu de règles). Un collègue propose Doctrine avec entités pures, repositories et services. Argumente pour ou contre.

<details><summary>Réponse modèle</summary>

Plutôt **contre**, pour ce contexte précis. Le Data Mapper paie son surcoût (entité, mapping, repository, service ; concepts de *flush*, d'entités gérées ou détachées) par l'indépendance du domaine. Ici, le domaine est peu fourni en règles et calqué sur le schéma : l'indépendance n'a presque rien à protéger. Un Active Record (Eloquent, ou un ORM du même style) ou même un query builder avec quelques fonctions d'hydratation livre plus vite, avec moins de concepts à maîtriser.

Les conditions qui renverseraient l'argument : des règles métier nombreuses à tester isolément, un modèle qui diverge du schéma (objets valeurs, agrégats), une durée de vie longue avec une équipe qui change, un cadre imposé (Symfony utilise Doctrine par défaut : lutter contre le framework a aussi un coût).

**Critères** : relier le choix à la nature du domaine (Fowler), nommer le coût du Data Mapper, donner au moins une condition qui inverserait la décision.

</details>

---

### Q15 : Neward et Fowler ont-ils des positions incompatibles ? Explique ce qui les rapproche, ce qui les sépare, et la pratique qui en découle.

<details><summary>Réponse modèle</summary>

**Ce qui les rapproche** : tous deux tiennent le décalage objet-relationnel pour irréductible. Aucun ne pense qu'une bibliothèque le fera disparaître.

**Ce qui les sépare** : la valeur d'une solution partielle. Neward insiste sur le coût caché et croissant des cas que l'ORM couvre mal, et sur l'absence de sortie une fois engagé. Fowler insiste sur la valeur des cas bien couverts, et attribue la frustration à des attentes irréalistes ; selon lui, un mapping maison finit généralement plus mauvais.

**Pratique qui en découle** : utiliser l'ORM là où le modèle objet apporte quelque chose (écritures sur le domaine, invariants) et du SQL là où la pensée ensembliste est naturelle (rapports, agrégats, opérations en masse), en gardant la compétence SQL à jour dans l'équipe. Les positions ne sont donc pas incompatibles : elles délimitent le domaine de validité de l'outil.

**Critères** : un point d'accord, un point de désaccord formulé précisément, une conséquence pratique argumentée.

</details>

---

**Score** : /12 pour le QCM, plus les questions ouvertes évaluées sur leurs critères.
**Objectif** : 9/12 au QCM et les trois questions ouvertes argumentées.
