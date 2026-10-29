# 📝 Quiz : Documenter un ORM

### Q1: Dans un projet Prisma, un script corrige des titres en SQL brut (`UPDATE projects SET title = …`). Le modèle a un champ `updatedAt DateTime @updatedAt`. Que vaut `updatedAt` après le script ?
A) L'heure du script : la base l'a mis à jour
B) L'heure du script : Prisma a intercepté la requête
C) Son ancienne valeur : le champ est géré par Prisma Client, pas par la base
D) `NULL`

<details><summary>Réponse</summary>

**C** — `@updatedAt` est appliqué par Prisma Client lors des écritures qu'il effectue lui-même. Ce comportement est absent du DDL : la date de modification devient silencieusement fausse. C'est exactement le genre de règle à documenter avec « appliqué par : ORM, contourné par : SQL brut ». (Pour un `INSERT` brut qui omet la colonne, c'est pire : si elle est `NOT NULL` sans défaut en base, la requête échoue.)

</details>

---

### Q2: Quelle description de `projects.status` est la plus utile ?
A) « Le statut du projet. »
B) « Colonne de type TEXT, non nulle, valeur par défaut 'draft'. »
C) « Cycle de vie : draft, active, archived (CHECK en base). Les transitions draft → active → archived ne sont vérifiées nulle part. »
D) « Statut (voir le code). »

<details><summary>Réponse</summary>

**C** — A paraphrase le nom. B recopie la structure, qui est déjà générée dans les autres colonnes du dictionnaire. D renvoie au code, ce qui revient à ne pas documenter. C donne le domaine, ce qui le garantit, et signale un trou (les transitions).

</details>

---

### Q3: Une équipe génère son dictionnaire de données depuis `schema.prisma`. Quel risque principal ?
A) Aucun, le schéma Prisma est la source de vérité
B) La doc ignore ce qui n'existe que dans la base : `CHECK`, triggers, index ajoutés à la main dans les migrations
C) Prisma refuse de générer de la documentation
D) La doc sera en anglais

<details><summary>Réponse</summary>

**B** — Le schéma ORM décrit l'intention du code ; la base décrit ce qui est appliqué. Générer la référence depuis la base migrée couvre les deux, puisque les migrations produites par Prisma y sont aussi appliquées.

</details>

---

### Q4: Dans `schema.prisma`, quel commentaire est exposé aux générateurs ?
A) `// commentaire`
B) `/// commentaire`
C) `# commentaire`
D) `-- commentaire`

<details><summary>Réponse</summary>

**B** — `///` est attaché au nœud suivant (modèle, champ) et exposé comme sa description. `//` est ignoré par l'outillage. C et D ne sont pas des syntaxes de commentaire Prisma.

</details>

---

### Q5: Quel est l'emplacement le plus durable pour le sens des colonnes d'une base PostgreSQL ?
A) Un wiki d'équipe
B) Les commentaires `///` du schéma Prisma
C) `COMMENT ON COLUMN`, écrit dans une migration
D) Un tableur partagé

<details><summary>Réponse</summary>

**C** — La base survit à l'ORM, et tous ses clients (psql, BI, tbls, SchemaSpy) lisent ces commentaires. Écrits dans une migration, ils sont versionnés et relus. B est utile côté code, mais aucun outil externe ne le lit. A et D divergent du schéma.

</details>

---

### Q6: Un ADR accepté il y a un an ne reflète plus la décision actuelle. Que faire ?
A) Le modifier pour refléter la décision actuelle
B) Le supprimer
C) Écrire un nouvel ADR et marquer l'ancien « remplacé par ADR-00XX »
D) Ajouter un commentaire en bas de l'ancien

<details><summary>Réponse</summary>

**C** — L'intérêt des ADR, c'est l'historique des raisons. Modifier ou supprimer l'ancien efface ce qu'on pensait et pourquoi on a changé d'avis.

</details>

---

### Q7: Selon Diátaxis, « Comment annuler la dernière migration en production » est :
A) Un tutoriel
B) Un guide pratique
C) Une référence
D) Une explication

<details><summary>Réponse</summary>

**B** — Le lecteur sait déjà ce qu'est une migration et veut accomplir une tâche précise. Un tutoriel enseigne à un débutant en le guidant, une référence décrit des faits, une explication donne le pourquoi.

</details>

---

### Q8: Un script CI régénère `docs/schema.md` et échoue s'il diffère de la version commitée. Il échoue à chaque exécution, même sans changement de schéma. Cause la plus probable ?
A) La base est corrompue
B) Le fichier généré contient une date de génération, ou un ordre non déterministe
C) Git modifie les fins de ligne
D) Le script est lancé trop souvent

<details><summary>Réponse</summary>

**B** — Une génération vérifiable doit être déterministe : même schéma, même fichier, octet pour octet. Une date dans le fichier, ou un ordre de tables qui dépend d'un `Map` non trié ou d'une requête sans `ORDER BY`, suffit à tout casser. (C peut arriver, mais se règle une fois pour toutes avec `.gitattributes`.)

</details>

---

### Q9: En SQLite, pourquoi `ALTER TABLE notes ADD COLUMN read_at TEXT -- horodatage` échoue-t-il ?
A) SQLite interdit les commentaires
B) SQLite insère le texte avant la parenthèse finale du `CREATE TABLE` stocké, et le `--` commente cette parenthèse
C) `read_at` est un mot réservé
D) `ADD COLUMN` n'existe pas en SQLite

<details><summary>Réponse</summary>

**B** — Erreur « incomplete input ». Un commentaire `/* … */` passe. C'est une raison de ne pas fonder la documentation SQLite sur des commentaires dans le DDL.

</details>

---

### Q10: Un ERD est généré automatiquement depuis les clés étrangères. Quelle information ne peut-il **pas** afficher ?
A) Qu'un projet a exactement un propriétaire
B) Qu'un membre peut posséder zéro ou plusieurs projets
C) Qu'un projet doit avoir au moins un contributeur
D) Que `contributions` est identifiée par ses deux clés étrangères

<details><summary>Réponse</summary>

**C** — « Au moins un » côté enfant n'est imposé par aucune contrainte déclarative (il faudrait un trigger ou une règle applicative). A se déduit de la FK `NOT NULL`, B de l'absence d'unicité, D de l'inclusion des FK dans la clé primaire (relation identifiante).

</details>

---

### Q11: Quelle règle de *linter* de schéma a la meilleure justification technique ?
A) Les noms de tables doivent être au pluriel
B) Chaque clé étrangère doit être couverte par un index dont elle forme le préfixe
C) Aucune table ne doit dépasser 5 colonnes
D) Les colonnes doivent être triées par ordre alphabétique

<details><summary>Réponse</summary>

**B** — Ni SQLite ni PostgreSQL n'indexent automatiquement une FK. Sans index, chaque `DELETE` sur le parent (vérification ou cascade) et chaque jointure parcourt toute la table enfant. A est une convention défendable mais arbitraire, C et D n'ont pas de justification technique.

</details>

---

### Q12: Pourquoi la règle « ON DELETE doit être explicite » ne peut-elle être qu'un avertissement en SQLite ?
A) SQLite ne supporte pas `ON DELETE`
B) L'introspection renvoie `NO ACTION` aussi bien pour un choix explicite que pour un oubli : impossible de les distinguer
C) Les avertissements sont plus rapides
D) `NO ACTION` est toujours un bon choix

<details><summary>Réponse</summary>

**B** — `pragma_foreign_key_list` renvoie `NO ACTION` dans les deux cas. Un linter honnête ne bloque pas sur ce qu'il ne peut pas établir.

</details>

---

### Q13 (ouverte): Une collègue propose de documenter le schéma dans le wiki de l'équipe, « parce que c'est plus joli et que tout le monde y a accès ». Que lui réponds-tu ?

<details><summary>Réponse modèle</summary>

Le problème n'est pas l'esthétique, c'est la **divergence**. Un wiki vit hors du dépôt : la *pull request* qui ajoute une colonne ne le met pas à jour, personne ne le relit en revue de code, et rien ne signale qu'il est faux. En quelques semaines, il décrit un schéma qui n'existe plus, et on ne sait plus quelle source croire.

Proposition : séparer ce qui se génère de ce qui s'écrit.
- La **référence** (tables, colonnes, ERD) est générée depuis la base migrée, en Markdown dans le dépôt, et vérifiée en CI. Elle reste exacte par construction.
- Le **sens** s'écrit au plus près de la source : `COMMENT ON` en migration, ou fichier de descriptions versionné, avec un linter qui exige une description par colonne.
- Les **raisons** vont dans des ADR, dans le dépôt.

Le wiki peut garder une page d'accueil qui *pointe* vers ces fichiers (GitHub rend le Markdown et le Mermaid), mais il ne doit pas en être une copie.

</details>

---

### Q14 (ouverte): Liste les comportements cachés de ce repository, et pour chacun, qui l'applique et ce qui le contourne.

```javascript
findAll({ includeArchived = false } = {}) {
  const where = includeArchived ? '' : "WHERE status <> 'archived'";
  return this.#db.prepare(`SELECT id, title, status FROM projects ${where}`).all();
}

archive(id) {
  this.#db.prepare("UPDATE projects SET status = 'archived' WHERE id = ?").run(id);
  this.#db.prepare('DELETE FROM project_tags WHERE project_id = ?').run(id);
}
```

<details><summary>Réponse modèle</summary>

| Comportement | Appliqué par | Contourné par |
|---|---|---|
| Les projets archivés sont exclus des listes par défaut (équivalent d'un filtre global) | `ProjectRepository.findAll` | toute requête SQL directe, tout autre code qui lit `projects` |
| Archiver un projet **supprime ses étiquettes** : effet de bord irréversible, la réactivation ne les rend pas | `ProjectRepository.archive` | un `UPDATE status = 'archived'` direct, qui garde les étiquettes : deux chemins, deux résultats |
| `archive` exécute deux requêtes **sans transaction** : un échec entre les deux laisse un projet archivé avec ses étiquettes | — | (trou à corriger, ou au minimum à documenter) |
| Aucune vérification de transition : `archive` accepte un projet déjà archivé ou en `draft` | personne | — |

Bonus : `findAll` sans `ORDER BY` renvoie un ordre non garanti, ce qui est à documenter (ou à corriger) si l'interface en dépend.

</details>

---

### Q15 (ouverte): Rédige l'en-tête d'une migration qui ajoute `NOT NULL` à `members.email` dans une base PostgreSQL de production où certaines lignes ont un email `NULL`.

<details><summary>Réponse modèle</summary>

```sql
-- Migration   : 20261105_1000_enforce_members_email_not_null
-- Intention   : l'email devient obligatoire pour la connexion (ticket #57).
-- Prérequis   : 20261104_0900_backfill_members_email doit avoir traité les lignes NULL
--               (emails reconstitués depuis l'outil de facturation, sinon comptes désactivés : voir ADR-0006).
-- Réversible  : oui, sans perte (DROP NOT NULL).
-- Risques     : SET NOT NULL parcourt toute la table sous verrou ACCESS EXCLUSIVE.
--               Pour éviter le verrou long : ajouter d'abord
--               CHECK (email IS NOT NULL) NOT VALID, puis VALIDATE CONSTRAINT
--               (verrou plus faible) ; PostgreSQL ≥ 12 réutilise ce CHECK validé pour SET NOT NULL.
-- Séquence    : étape 3/3 (expand : colonne nullable ; migrate : backfill + code qui écrit l'email ; contract : cette migration).
-- Vérification: SELECT count(*) FROM members WHERE email IS NULL;  -- 0 attendu AVANT d'appliquer
```

Ce qui compte : le **prérequis** (la migration échoue sinon), le **risque de verrou** et la façon de l'éviter, la **séquence** dans laquelle elle s'inscrit, et une **vérification** à lancer avant. Les détails de verrouillage relèvent du [module 03](../03-migrations/notes.md).

</details>

---

**Score : /15 — Objectif : 11/15**
