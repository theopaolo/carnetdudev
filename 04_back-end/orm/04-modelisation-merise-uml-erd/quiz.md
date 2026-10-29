# 📝 Quiz : Modélisation — Merise, ERD, UML

Réponds sans les notes. Les trois dernières questions sont ouvertes : écris ta réponse avant d'ouvrir la réponse modèle.

---

### Q1: Dans un MCD, `PROJET (1,1)` sur l'association POSSÉDER signifie :
A) Un membre possède exactement un projet
B) Un projet est possédé par exactement un membre
C) Un projet possède exactement un membre
D) Il y a exactement un projet dans la base

<details><summary>Réponse</summary>

**B** — La cardinalité Merise décrit l'entité près de laquelle elle est notée : une occurrence de PROJET participe exactement une fois à POSSÉDER.

</details>

---

### Q2: Le MCD dit `MEMBRE (0,n) — POSSÉDER — (1,1) PROJET`. Quel diagramme de classes UML est correct ?
A) `Member "0..*" —— "1" Project`
B) `Member "1" —— "0..*" Project`
C) `Member "0..1" —— "1..*" Project`
D) `Member "1" —— "1" Project`

<details><summary>Réponse</summary>

**B** — En UML, la multiplicité est à l'extrémité opposée : `0..*` près de Project (un membre a 0 à n projets), `1` près de Member (un projet a 1 membre). A est l'erreur classique d'inversion.

</details>

---

### Q3: Dans la traduction d'une association `(0,n)–(1,1)`, la clé étrangère va :
A) Dans la table côté `(0,n)`
B) Dans la table côté `(1,1)`
C) Dans une table d'association
D) Des deux côtés

<details><summary>Réponse</summary>

**B** — La clé étrangère va là où le maximum vaut 1, puisqu'une colonne ne contient qu'une valeur. Ici elle est `NOT NULL`, car le minimum vaut 1.

</details>

---

### Q4: Quelle association produit une table avec ses propres colonnes en plus des deux clés étrangères ?
A) Une binaire `(0,1)–(1,1)`
B) Une n-n pure
C) Une association porteuse n-n
D) Une réflexive 1-n

<details><summary>Réponse</summary>

**C** — Les propriétés de l'association porteuse (`rôle`, `depuis`) deviennent des colonnes de la table d'association.

</details>

---

### Q5: La table `(member_handle, project_title, member_email, role)` de clé `(member_handle, project_title)` viole d'abord :
A) La 1FN
B) La 2FN
C) La 3FN
D) Aucune forme normale

<details><summary>Réponse</summary>

**B** — `member_email` dépend d'une partie seulement de la clé (`member_handle`) : dépendance partielle, interdite par la 2FN.

</details>

---

### Q6: Une table `projects (title, owner_handle, owner_email)` de clé `title` viole :
A) La 1FN
B) La 2FN
C) La 3FN
D) Aucune

<details><summary>Réponse</summary>

**C** — `title → owner_handle → owner_email` : dépendance transitive. La clé n'est pas composée, donc la 2FN est respectée.

</details>

---

### Q7: Quelle cardinalité du MCD ne peut pas être garantie par une simple clé étrangère ?
A) `(1,1)`
B) `(0,1)`
C) `(1,n)`
D) `(0,n)`

<details><summary>Réponse</summary>

**C** — Un minimum de 1 du côté « n » : rien n'empêche qu'un parent n'ait aucune ligne enfant. Il faut un déclencheur, une contrainte différée ou une transaction applicative.

</details>

---

### Q8: En crow's foot, `MEMBERS ||--o| BADGES` signifie :
A) Un membre a exactement un badge ; un badge a 0 ou 1 membre
B) Un membre a 0 ou 1 badge ; un badge a exactement 1 membre
C) Un membre a 0 à n badges ; un badge a 1 membre
D) Relation un-à-un obligatoire des deux côtés

<details><summary>Réponse</summary>

**B** — Le symbole près de BADGES (`o|`) dit combien de badges pour un membre : 0 ou 1. Celui près de MEMBERS (`||`) dit combien de membres pour un badge : exactement 1.

</details>

---

### Q9: Quelle stratégie d'héritage empêche une table tierce de référencer « un média » par clé étrangère ?
A) Single Table
B) Class Table
C) Concrete Table
D) Aucune

<details><summary>Réponse</summary>

**C** — Avec une table par classe concrète, il n'existe pas de table « media » ; les `id` peuvent même se répéter d'une table à l'autre.

</details>

---

### Q10: Pourquoi l'association polymorphe `(commentable_type, commentable_id)` casse-t-elle l'intégrité référentielle ?
A) Parce que `commentable_type` est un texte
B) Parce qu'une colonne ne peut pas être clé étrangère vers plusieurs tables
C) Parce que SQLite ne gère pas les clés étrangères
D) Elle ne la casse pas si l'ORM vérifie

<details><summary>Réponse</summary>

**B** — Sans clé étrangère possible, la base accepte un commentaire vers un projet inexistant. D est faux : l'ORM ne protège que le code qui passe par lui.

</details>

---

### Q11: Dans Prisma, une relation n-n implicite (`tags Tag[]` / `projects Project[]`) :
A) Permet d'ajouter une date d'étiquetage sur la jointure
B) Crée une table `_ProjectToTag` aux colonnes `A` et `B`
C) N'utilise pas de table de jointure
D) Est obligatoire pour les n-n

<details><summary>Réponse</summary>

**B** — Prisma fixe le nom et les colonnes ; aucun attribut n'est possible. Pour une jointure porteuse (`contributions`), il faut une relation explicite.

</details>

---

### Q12: Dans Doctrine, tu ajoutes un projet à `$member->ownedProjects` sans renseigner `$project->owner`, puis tu appelles `flush()`. Que se passe-t-il ?
A) Le projet est rattaché au membre
B) Rien n'est persisté pour la relation
C) Doctrine lève toujours une exception
D) Doctrine met à jour les deux côtés automatiquement

<details><summary>Réponse</summary>

**B** — Seul le côté propriétaire (le `ManyToOne`, qui porte la clé étrangère) est pris en compte. La collection du côté inverse n'est qu'un reflet en mémoire. (Si `owner` n'est pas nullable et que le projet est nouveau, l'insertion échouera sur la contrainte `NOT NULL` : c'est la base, pas Doctrine, qui le signale.)

</details>

---

### Q13 (ouverte) : Un collègue modélise « un membre mobilise une compétence sur un projet » par trois tables binaires : membre–projet, projet–compétence, membre–compétence. Que réponds-tu ?

<details><summary>Réponse modèle</summary>

Il faut d'abord savoir si la connaissance est dans le **triplet**. Si l'on veut savoir quelle compétence un membre a utilisée **sur quel projet**, les trois binaires ne suffisent pas : leur jointure invente des triplets (le *connection trap*). Exemple : theo a fait du web sur Synthé web, ada a fait du web sur Carnet du dev, theo travaille sur Carnet du dev ; les trois binaires laissent conclure que theo a fait du web sur Carnet du dev, ce qui est faux.

La bonne modélisation est une **ternaire** : une table `(member_id, project_id, tag_id)` avec ces trois colonnes en clé. Inversement, s'il existait une DF (par exemple `(membre, projet) → compétence` : une seule compétence par contribution), ce serait une fausse ternaire, à traduire par une colonne dans `contributions`. Le critère n'est pas le nombre d'entités citées dans la phrase, ce sont les dépendances fonctionnelles.

</details>

---

### Q14 (ouverte) : Pour une hiérarchie `media` (image, vidéo, son), compare Single Table et Class Table et propose un choix argumenté pour l'Atelier.

<details><summary>Réponse modèle</summary>

**Single Table** : une seule table avec un discriminant `kind`. Requêtes polymorphes sans jointure, une seule FK possible vers « un média ». En contrepartie, les colonnes propres aux sous-types sont nullables : sans `CHECK` par discriminant, une image sans texte alternatif passe. Ajouter un sous-type modifie la table partagée.

**Class Table** : une table `media` commune et une table par sous-type, reliées 1-1. `NOT NULL` naturels, pas de colonnes vides, ajout d'un sous-type sans toucher à l'existant. En contrepartie, chaque lecture complète demande des jointures, l'exclusion n'est garantie qu'avec la FK composite `(id, kind)`, et la totalité ne l'est pas.

**Pour l'Atelier** : les sous-types diffèrent de 2 ou 3 colonnes, et la requête dominante est « tous les médias d'un projet ». Single Table, **avec** les `CHECK` par discriminant et une table de référence `media_kinds`, est un choix raisonnable. Si les sous-types s'enrichissent (métadonnées EXIF, chapitres vidéo, transcriptions structurées) ou si l'intégrité de chaque sous-type devient critique, Class Table devient préférable. Le choix doit être écrit dans un ADR, parce qu'il est coûteux à inverser.

</details>

---

### Q15 (ouverte) : Pourquoi peut-on dire que le schéma de l'ORM est un sous-ensemble du schéma de la base, et quelles conséquences en tirer ?

<details><summary>Réponse modèle</summary>

Le schéma d'un ORM décrit ce que l'ORM sait générer et utiliser : tables, colonnes, clés, relations, quelques index. Une base peut contenir bien plus : `CHECK` multi-colonnes, index partiels (en *preview* seulement depuis Prisma 7.4), déclencheurs, vues, contraintes différées, politiques de sécurité par ligne. Plusieurs règles de ce module n'ont pas d'équivalent dans un schéma Prisma : les `CHECK` de Single Table Inheritance, `mentor_id <> mentee_id`, les contraintes de dates des emprunts.

Conséquences :
1. Ces règles s'ajoutent **en SQL dans les migrations**, et il faut vérifier que l'outil de migration ne les supprime pas en croyant corriger une dérive.
2. Le schéma de l'ORM n'est pas la documentation complète du modèle : la base est la référence pour les contraintes, et la conception (MCD, ADR) est la référence pour l'intention.
3. Tout accès qui ne passe pas par l'ORM (script, BI, autre service) n'est protégé que par ce qui est **dans la base**. Une règle qui n'existe que dans l'ORM n'est pas une garantie.

</details>

---

**Score : /12 (QCM) + 3 questions ouvertes — Objectif : 9/12, et des réponses ouvertes qui citent des DF ou des contraintes précises**
