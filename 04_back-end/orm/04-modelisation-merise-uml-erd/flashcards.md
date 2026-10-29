# 🧠 Flashcards : Modélisation — Merise, ERD, UML

## Niveaux et vocabulaire

### Q: Quels sont les trois niveaux de modélisation des données, et la question de chacun ?
<details><summary>R</summary>

- **Conceptuel** (MCD) : *quoi* ? Informations et règles métier, indépendamment de toute technologie.
- **Logique** (MLD) : *comment, dans un modèle de données* ? Tables, clés, clés étrangères.
- **Physique** (MPD) : *comment, dans ce SGBD* ? Types, index, `ON DELETE`, `CHECK`.

</details>

### Q: Le « conceptuel » d'ANSI/SPARC (1975) est-il le MCD de Merise ?
<details><summary>R</summary>Non. ANSI/SPARC distingue externe / conceptuel / interne ; son schéma conceptuel correspond plutôt au niveau **logique** Merise. Le MCD se situe au-dessus, avant même le choix du modèle relationnel.</details>

### Q: Entité, occurrence, propriété, identifiant ?
<details><summary>R</summary>Entité : une classe d'objets du domaine (MEMBRE). Occurrence : un élément (le membre « theo »). Propriété : une information élémentaire (`email`). Identifiant : la ou les propriétés qui distinguent chaque occurrence (souligné).</details>

### Q: Qu'est-ce qu'une association porteuse ?
<details><summary>R</summary>Une association qui a ses propres propriétés, parce qu'elles appartiennent au **couple** et non à une entité seule. CONTRIBUER porte `rôle` et `depuis`. Traduction : une table d'association avec des colonnes ; en UML, une classe d'association ; en ORM, un modèle explicite.</details>

### Q: Pourquoi les associations Merise sont-elles des verbes et les tables des noms ?
<details><summary>R</summary>Parce que le passage au code **réifie** la relation : CONTRIBUER devient la chose `Contribution`. Un ORM fait ce glissement systématiquement.</details>

## Cardinalités

### Q: Comment se lit `MEMBRE (0,n) — POSSÉDER — (1,1) PROJET` ?
<details><summary>R</summary>Un membre possède au minimum 0 et au maximum n projets. Un projet est possédé au minimum 1 et au maximum 1 fois, donc par exactement un membre.</details>

### Q: En Merise, de quel côté est notée la cardinalité ?
<details><summary>R</summary>Du côté de l'entité **qu'elle décrit** : elle compte combien de fois une occurrence de cette entité participe à l'association (*look here*).</details>

### Q: En UML et en crow's foot, de quel côté est notée la multiplicité ?
<details><summary>R</summary>À l'extrémité **opposée** : près de `Project`, `0..*` dit combien de projets pour un membre (*look across*).</details>

### Q: Comment convertir une cardinalité Merise binaire en multiplicité UML ?
<details><summary>R</summary>On **échange les extrémités**, puis on traduit : `(0,1)` → `0..1`, `(1,1)` → `1`, `(0,n)` → `0..*`, `(1,n)` → `1..*`.</details>

### Q: Pourquoi une association `(0,n)–(0,n)` mal convertie reste-t-elle juste ?
<details><summary>R</summary>Parce qu'elle est symétrique : échanger les extrémités ne change rien. C'est ce qui rend l'inversion dangereuse : une partie du diagramme faux est correcte et inspire confiance.</details>

### Q: Les cardinalités d'une ternaire se convertissent-elles en multiplicités UML ?
<details><summary>R</summary>Non. En UML, la multiplicité d'une extrémité n-aire porte sur les combinaisons des n-1 autres ; en Merise, elle compte les participations d'une occurrence. Il faut repartir des dépendances fonctionnelles.</details>

### Q: Dans une patte d'oie, quel symbole est le maximum ?
<details><summary>R</summary>Celui **collé à l'entité**. L'autre, plus loin, est le minimum. `o{` : zéro (min) ou plusieurs (max).</details>

### Q: Que signifient `--` et `..` dans un `erDiagram` Mermaid ?
<details><summary>R</summary>`--` (trait plein) : relation **identifiante**, la FK fait partie de la clé primaire de l'enfant. `..` (pointillé) : relation **non identifiante**.</details>

## Règles de passage

### Q: Où va la clé étrangère d'une association `(x,n)–(x,1)` ?
<details><summary>R</summary>Dans la table **côté `(x,1)`** : là où le maximum vaut 1, parce qu'une colonne ne contient qu'une valeur. `NOT NULL` si `(1,1)`, nullable si `(0,1)`.</details>

### Q: Traduction d'une association `(x,n)–(x,n)` ?
<details><summary>R</summary>Une table d'association dont la clé primaire est composée des deux clés étrangères. Les propriétés de l'association (si porteuse) deviennent ses colonnes.</details>

### Q: Traduction d'une association `(0,1)–(1,1)` ?
<details><summary>R</summary>Clé étrangère `NOT NULL` **et `UNIQUE`** côté `(1,1)`. Sans `UNIQUE`, c'est une relation un-à-plusieurs.</details>

### Q: Comment traduire une association réflexive ?
<details><summary>R</summary>Comme une binaire dont les deux clés étrangères pointent vers la même table, **nommées par rôle** : `sponsor_id`, ou `mentor_id` / `mentee_id` dans une table d'association.</details>

### Q: Quelle cardinalité du MCD le SQL déclaratif ne sait-il pas garantir ?
<details><summary>R</summary>Un minimum de **1 du côté « n »** (`(1,n)`) : rien n'empêche la table enfant d'être vide pour un parent. Il faut un déclencheur, une contrainte différée ou une transaction applicative.</details>

### Q: Un même membre peut emprunter plusieurs fois le même équipement. Quel est le piège ?
<details><summary>R</summary>Le couple (membre, équipement) n'identifie plus l'emprunt. On réifie EMPRUNT en entité (avec son propre identifiant), ou on ajoute la date à l'identifiant (ternaire avec une entité DATE en Merise).</details>

### Q: Clé naturelle ou artificielle : quelle position tenir ?
<details><summary>R</summary>Clé artificielle (`id`) pour l'identité technique, stable et courte ; **et** une contrainte `UNIQUE` sur chaque clé naturelle (`email`, `handle`). Oublier le `UNIQUE` est l'erreur classique.</details>

## Normalisation

### Q: Qu'est-ce qu'une dépendance fonctionnelle `X → Y` ?
<details><summary>R</summary>Deux lignes qui ont la même valeur de `X` ont forcément la même valeur de `Y`. Exemple : `member_handle → member_email`.</details>

### Q: 1FN, 2FN, 3FN en une phrase chacune ?
<details><summary>R</summary>

- **1FN** : une valeur par attribut (pas de liste `'pedagogie,web'`).
- **2FN** : aucun attribut non-clé ne dépend d'une **partie** de la clé.
- **3FN** : aucun attribut non-clé ne dépend d'un autre attribut non-clé (pas de dépendance **transitive**).

</details>

### Q: Quelle condition ajoute la BCNF, et quel est son coût possible ?
<details><summary>R</summary>Tout déterminant d'une DF non triviale doit être une clé candidate. Le coût : une décomposition BCNF peut ne pas **préserver les dépendances** (une DF ne se vérifie plus sur une seule table).</details>

### Q: Les trois anomalies d'une table non normalisée ?
<details><summary>R</summary>Mise à jour (un fait stocké plusieurs fois prend plusieurs valeurs), insertion (impossible d'enregistrer un fait sans un autre), suppression (supprimer une ligne efface un fait indépendant).</details>

### Q: Comment vérifier qu'une décomposition est sans perte ?
<details><summary>R</summary>La jointure des tables obtenues doit redonner **exactement** la table d'origine : `original EXCEPT jointure` et `jointure EXCEPT original` vides.</details>

### Q: Qu'est-ce que le *connection trap* ?
<details><summary>R</summary>Décomposer une vraie ternaire en trois binaires : la recomposition invente des triplets faux (theo a fait du web sur Synthé web, Carnet du dev implique du web, theo travaille sur Carnet du dev ⇒ faux « theo a fait du web sur Carnet du dev »).</details>

### Q: Le prix payé copié dans une commande est-il une redondance ?
<details><summary>R</summary>Non : c'est un **autre fait** (le prix au moment de la commande). Une dénormalisation est une copie d'un même fait ; celle-ci est une historisation.</details>

## UML

### Q: Agrégation ou composition : laquelle se traduit en SQL ?
<details><summary>R</summary>Seulement la composition, approximativement : FK `NOT NULL` + `ON DELETE CASCADE` (+ `orphanRemoval` en Doctrine/JPA). La spécification UML reconnaît elle-même que la sémantique de l'agrégation varie selon le modélisateur.</details>

### Q: Pourquoi `contributions`, supprimée en cascade par deux parents, n'est-elle pas une double composition ?
<details><summary>R</summary>En UML, une partie n'a qu'**un** composite à la fois. Une même clause `CASCADE` peut traduire une composition (côté projet) ou une simple politique de suppression (côté membre).</details>

### Q: Comment traduire `{ordered}` et un attribut dérivé `/total` ?
<details><summary>R</summary>`{ordered}` : une colonne de position explicite, à maintenir (attention à l'unicité pendant les décalages). `/total` : une vue ou une colonne générée, jamais une colonne stockée à la main.</details>

### Q: Qu'est-ce que le côté propriétaire (*owning side*) dans Doctrine ou Hibernate ?
<details><summary>R</summary>Le côté qui porte la clé étrangère ou la table de jointure (`ManyToOne` l'est toujours). Seules ses modifications sont persistées : modifier uniquement la collection du côté inverse (`mappedBy`) ne change rien en base.</details>

## Héritage

### Q: Les contraintes Merise X, T, XT ?
<details><summary>R</summary>X : exclusion (au plus un sous-type). T : totalité (au moins un). XT : partition (exactement un). UML : `{disjoint, incomplete}`, `{overlapping, complete}`, `{disjoint, complete}`.</details>

### Q: Les trois stratégies de mapping de l'héritage (Fowler) ?
<details><summary>R</summary>**Single Table** (une table, un discriminant, beaucoup de `NULL`), **Class Table** (une table par classe, jointures), **Concrete Table** (une table par classe concrète, `UNION ALL` pour les requêtes polymorphes).</details>

### Q: Quel est le défaut d'intégrité de Single Table Inheritance, et son remède ?
<details><summary>R</summary>Les colonnes propres aux sous-types deviennent nullables : une image sans `alt_text` passe. Remède : des `CHECK` par discriminant (`kind <> 'image' OR alt_text IS NOT NULL`), que les ORMs ne génèrent presque jamais.</details>

### Q: Comment garantir l'exclusion des sous-types en Class Table Inheritance ?
<details><summary>R</summary>`UNIQUE (id, kind)` sur la table mère, et dans chaque sous-table une colonne `kind` figée par `CHECK` et une FK composite `(media_id, kind) REFERENCES media (id, kind)`. La totalité, elle, n'est pas garantie déclarativement.</details>

### Q: Pourquoi une association polymorphe (`commentable_type`, `commentable_id`) est-elle un anti-pattern ?
<details><summary>R</summary>Une colonne ne peut pas être clé étrangère vers deux tables : plus d'intégrité référentielle, plus de cascade, des commentaires vers des projets inexistants. Alternatives : arc exclusif (une FK par cible + `CHECK` « exactement une ») ou supertype commun.</details>

## ORM et outils

### Q: Prisma : n-n implicite ou explicite ?
<details><summary>R</summary>

Implicite (`tags Tag[]` des deux côtés) : Prisma crée `_ProjectToTag` avec des colonnes `A` et `B`, sans attribut possible. Explicite (modèle `ProjectTag`) : nom de table et colonnes maîtrisés, attributs ajoutables. **Explicite obligatoire si la jointure porte un attribut**, et bon défaut sinon.

</details>

### Q: Que perd l'introspection (`prisma db pull`, `drizzle-kit pull`) ?
<details><summary>R</summary>L'**intention** : qu'une jointure était une n-n, qu'une 1-1 encodait un héritage, qu'un `CASCADE` traduisait une composition, pourquoi une colonne est dénormalisée. La base ne contient que le niveau physique.</details>

### Q: Pourquoi préférer un outil de modélisation en texte (Mocodo, Mermaid, DBML, PlantUML) ?
<details><summary>R</summary>Le modèle se versionne avec le code et les migrations, se diffe et se relit en revue. Les outils graphiques (Looping, draw.io) restent meilleurs pour explorer au tableau et pour apprendre.</details>

---

**Nombre de cartes** : 38
**Dernière mise à jour** : 2026-10-29
**Niveau** : Intermédiaire
