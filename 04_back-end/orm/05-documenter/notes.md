# 📝 Documenter un ORM : rendre le modèle lisible et durable

## 📋 Vue d'ensemble

Documenter une couche ORM ne consiste pas à recopier le schéma. Le schéma dit déjà qu'une colonne `status` est un `TEXT NOT NULL`. Il ne dit pas ce que signifie `archived`, qui a le droit de passer un projet de `draft` à `active`, pourquoi la date est stockée en texte, ni qu'un `DELETE` écrit en SQL brut ne déclenchera pas le hook que l'ORM aurait exécuté.

La thèse de ce module tient en une phrase : **la structure se génère, le sens et les raisons s'écrivent, et les comportements cachés se rendent visibles.** Tout le reste est de l'outillage pour que ces trois choses restent vraies dans le temps.

### 🎯 Objectifs

- Repérer où vit chaque vérité dans un projet avec ORM, et ce que chaque endroit tait
- Documenter en cinq couches : modèle, mapping, évolution, usage, exploitation
- Appliquer le principe « une source de vérité par information, le reste est généré »
- Utiliser les mécanismes natifs : `COMMENT ON`, commentaires `///` de Prisma, `Note` DBML, `comments:` de tbls
- Rédiger un dictionnaire de données, une fiche d'entité, un ADR, un en-tête de migration, un runbook
- Mettre la documentation sous contrôle de la CI pour qu'elle ne pourrisse pas

---

## 🤔 Le problème : une vérité éclatée, des comportements invisibles

### Où vit la vérité ?

Dans un projet qui utilise un ORM, le modèle de données n'est écrit nulle part en entier. Il est réparti entre cinq endroits, et chacun en dit une partie différente.

| Endroit | Ce qu'il dit | Ce qu'il tait |
|---|---|---|
| **La base** (schéma réellement appliqué) | types, contraintes effectivement vérifiées, index | le sens métier, les règles applicatives, le pourquoi |
| **Le schéma ORM / les entités** | noms côté code, relations navigables, valeurs générées par l'ORM | les `CHECK` et triggers écrits à la main, ce que font les autres clients de la base |
| **Les migrations** | l'historique et l'ordre des changements | l'état courant (il faut tout rejouer pour le connaître), les raisons, si personne ne les a écrites |
| **Le code applicatif** (services, hooks, repositories) | les règles métier et les effets de bord | rien de tout cela n'est visible depuis la base |
| **Les seeds / fixtures** | des exemples de données « normales » | la différence entre ce qui est garanti et ce qui est seulement habituel |

### Exercice de pensée : que se passe-t-il quand on supprime un membre ?

Sur le fil rouge, la réponse demande de lire trois endroits :

1. **La base** : `projects.owner_id` est en `ON DELETE RESTRICT`, donc la suppression est refusée si le membre possède encore un projet. `contributions.member_id` est en `ON DELETE CASCADE`, donc ses contributions disparaissent avec lui.
2. **L'ORM** : si le projet utilisait Prisma avec `relationMode = "prisma"`, il n'y aurait pas de clé étrangère en base. Prisma *émulerait* les actions référentielles dans le client. Le même `DELETE` lancé en SQL brut ne bloquerait ni ne propagerait rien.
3. **L'application** : si `deleteMember()` fait en réalité un *soft delete* (`UPDATE members SET deleted_at = …`), aucune ligne n'est supprimée, et c'est un filtre global de l'ORM qui cache le membre.

Quelqu'un qui ne lit qu'un de ces endroits donnera une réponse fausse, avec assurance. Le rôle de la documentation est d'empêcher cette erreur.

### Le catalogue des comportements cachés

Ce sont eux qui justifient l'effort de documentation. Tous existent dans des ORMs courants.

| Comportement | Exemples | Pourquoi il est invisible |
|---|---|---|
| Valeur générée par l'ORM, pas par la base | Prisma `@default(uuid())`, `@default(cuid())`, `@updatedAt` | absent du DDL : un `INSERT` ou un `UPDATE` en SQL brut ne l'applique pas |
| Action référentielle émulée | Prisma `relationMode = "prisma"` | aucune clé étrangère en base |
| Filtre global | Sequelize `paranoid: true`, Eloquent `SoftDeletes` et *global scopes*, filtres Doctrine | la ligne existe en base, mais l'ORM ne la renvoie jamais |
| Hooks / callbacks | Sequelize `beforeCreate`, Doctrine `#[ORM\PrePersist]`, Rails `before_save` | n'existent que dans le processus applicatif. Les opérations groupées peuvent les sauter : Sequelize n'exécute les hooks par instance d'un `update` ou `destroy` groupé qu'avec `individualHooks: true` |
| Validation applicative | longueur, format, unicité « insensible à la casse » | contournée par tout autre client : script, migration de données, autre service |
| Sérialisation | champ exclu du JSON (hash de mot de passe) | rien dans le schéma ne dit qu'il ne doit jamais sortir |
| Chargement par défaut | relation chargée systématiquement (*eager*) | coût invisible jusqu'à la production (voir [module 06](../06-concepts-avances/notes.md)) |

> 💡 **Une règle appliquée par l'ORM est contournée par tout ce qui n'est pas l'ORM.** C'est le fait le plus important à documenter, parce que c'est celui que personne ne devine.

---

## 🧅 Cinq couches à documenter

| Couche | Question à laquelle elle répond | Source de vérité | Forme | Généré ou écrit ? |
|---|---|---|---|---|
| 1. **Modèle** | Que signifie cette donnée ? | la base + ses commentaires | dictionnaire de données, ERD | structure générée, sens écrit |
| 2. **Mapping** | Comment le code voit-il cette table, et quelles règles ajoute-t-il ? | schéma ORM, entités, repositories | fiche d'entité | écrit, à côté des entités |
| 3. **Évolution** | Pourquoi c'est comme ça ? | migrations, ADR | en-têtes de migration, ADR | écrit |
| 4. **Usage** | Comment je requête correctement ? | le code d'accès aux données | guide pratique | écrit |
| 5. **Exploitation** | Comment je migre, j'annule, je restaure ? | scripts | runbook | écrit, et exécuté pour de vrai |

### 1. Le modèle : le dictionnaire de données

Le dictionnaire de données est une **référence** : une entrée par table et par colonne. La structure (type, nullabilité, défaut, clés) se génère depuis la base (voir le [kata 2](katas.md)). Ce qui s'écrit, c'est la description, et une bonne description répond à ces questions :

- **Sens métier** : qu'est-ce que la valeur représente dans le monde réel ?
- **Format, unité, fuseau** : `YYYY-MM-DD HH:MM:SS` en UTC ? des centimes ? des millisecondes ?
- **Domaine** : valeurs possibles, et lesquelles sont garanties par une contrainte
- **Qui l'écrit** : la base (défaut, trigger), l'ORM, l'application, un import ?
- **Invariants non contraints** : ce qui « doit » être vrai sans que rien ne le vérifie
- **Sensibilité** : donnée personnelle (RGPD), secret, donnée à ne jamais exposer
- **Écarts connus** : ce que le schéma fait et qu'on n'a pas voulu, mais qu'on n'a pas encore corrigé

#### ❌ Paraphrase vs ✅ description

| Colonne | ❌ Paraphrase | ✅ Description utile |
|---|---|---|
| `members.email` | « L'email du membre. » | « Adresse de contact et de connexion. Donnée personnelle : à effacer à la suppression du compte. Unique mais **sensible à la casse** : `Theo@…` et `theo@…` peuvent coexister (écart connu, non tranché). » |
| `projects.status` | « Le statut du projet. » | « Cycle de vie : `draft`, `active`, `archived` (CHECK en base). Les transitions draft → active → archived ne sont vérifiées **nulle part**. » |
| `projects.created_at` | « Date de création. » | « Horodatage UTC de création, texte ISO 8601 `YYYY-MM-DD HH:MM:SS`. Écrit par la base (`DEFAULT (datetime('now'))`). » |
| `contributions.role` | « Le rôle. » | « Rôle libre, **sans contrainte** en base. Valeurs observées : `auteur`, `dev`, `design`, `relecture`, `son`. Le propriétaire reçoit `auteur` à la création du projet (`ProjectRepository.create`). » |

La description utile est plus longue, mais chaque phrase apporte une information que le nom et le type ne donnent pas. C'est le seul critère : **si la phrase se déduit du nom de la colonne, supprime-la.**

#### Une description fausse est pire que pas de description

Une description tentante pour `members.id` : « Identifiant unique, jamais réutilisé. » En SQLite, c'est faux. Sans le mot-clé `AUTOINCREMENT`, un `INTEGER PRIMARY KEY` peut récupérer l'identifiant de la dernière ligne supprimée :

```javascript
// rowid-reuse.mjs (dans 05-documenter/)
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();
db.prepare("INSERT INTO tags (label) VALUES ('temporaire')").run();   // reçoit l'id 6
db.prepare("DELETE FROM tags WHERE label = 'temporaire'").run();
const { lastInsertRowid } = db.prepare("INSERT INTO tags (label) VALUES ('autre')").run();
console.log(lastInsertRowid); // 6 : le même identifiant, pour une autre étiquette
```

Si un service externe a gardé l'id 6 en référence, il pointe maintenant vers une autre étiquette. La documentation qui affirmait le contraire a transformé une intention en fait, et quelqu'un s'est fié à elle. **Ce qu'on peut vérifier, on le vérifie avant de l'écrire. Ce qu'on ne peut pas vérifier, on l'écrit comme une intention (« doit », « convention »), pas comme un fait.**

### 2. Le mapping : la fiche d'entité

La fiche d'entité décrit ce que la couche ORM *ajoute* au schéma. Elle vit à côté des entités (même dossier, ou en tête de fichier), pas dans un wiki. Elle contient :

- la correspondance entité ↔ table, et les conventions de nommage (`ownerId` ↔ `owner_id`, `@map` / `@@map` en Prisma, `underscored: true` en Sequelize)
- les relations : cardinalité, sens de navigation, chargement par défaut
- les actions référentielles : **qui les applique**, la base ou l'ORM ?
- les valeurs par défaut : **qui les génère**, la base ou l'ORM ?
- les hooks, filtres globaux, règles de sérialisation
- les validations, avec leur lieu d'application

La colonne décisive est **« Qui l'applique ? »**, avec trois réponses possibles : la base, l'ORM, l'application. Sa conséquence directe, **« Contourné par »**, dit ce qui passe à travers la règle. Le [kata 4](katas.md) construit cette fiche pour `projects` à partir d'un vrai repository.

#### Ce que le schéma ORM peut dire, et ce qu'il ne peut pas dire

Voici le modèle `projects` du fil rouge écrit en Prisma (*illustratif*, non exécuté dans ce carnet). Les commentaires `///` y portent la documentation :

```prisma
/// Projet porté par un membre. Un projet archivé est exclu des listes par défaut (ProjectRepository.findAll).
model Project {
  id            Int            @id @default(autoincrement())
  /// Propriétaire. Suppression du membre refusée tant qu'il possède des projets.
  ownerId       Int            @map("owner_id")
  owner         Member         @relation(fields: [ownerId], references: [id], onDelete: Restrict)
  /// Non vide, sans espaces de bord : vérifié par l'application, pas par la base.
  title         String
  /// draft | active | archived. Le CHECK n'existe que dans la migration SQL : Prisma ne sait pas l'exprimer.
  status        String         @default("draft")
  createdAt     DateTime       @default(now()) @map("created_at")
  contributions Contribution[]
  tags          ProjectTag[]

  @@index([ownerId])
  @@map("projects")
}
```

Remarque la contradiction signalée dans le commentaire de `status` : on présente souvent `schema.prisma` comme « la source de vérité », mais un `CHECK` ajouté à la main dans une migration SQL n'y apparaît pas. Le schéma ORM décrit **l'intention du code**, la base décrit **ce qui est appliqué**. Les deux sont nécessaires, et ils peuvent diverger.

### 3. L'évolution : migrations et ADR

La mécanique des migrations est traitée dans le [module 03](../03-migrations/notes.md). Ici, il s'agit de ce qu'on écrit autour, pour qu'un lecteur comprenne un changement dans six mois.

#### L'en-tête de migration

Un nom explicite (`20261029_1200_add_projects_archived_at`, pas `migration_42`) et un en-tête qui répond aux questions que se pose la personne qui devra l'appliquer ou l'annuler :

```sql
-- Migration   : 20261029_1200_add_projects_archived_at
-- Intention   : dater l'archivage d'un projet (demande #42), préalable à la purge des projets archivés depuis plus de 2 ans.
-- Réversible  : oui. Le down supprime la colonne : les dates d'archivage saisies entre-temps sont perdues.
-- Risques     : ADD COLUMN nullable sans défaut, opération quasi instantanée en SQLite et PostgreSQL. Aucun verrou long.
-- Séquence    : étape 1/3 d'un expand/contract.
--               2/3 : 20261030_0900_backfill_projects_archived_at (données)
--               3/3 : CHECK (status <> 'archived' OR archived_at IS NOT NULL), quand le code écrit la colonne partout
-- Vérification: SELECT count(*) FROM projects WHERE status = 'archived' AND archived_at IS NULL;  -- 0 attendu après l'étape 2

ALTER TABLE projects ADD COLUMN archived_at TEXT;
```

Le champ **Séquence** reprend une idée d'Ambler et Sadalage (*Refactoring Databases*, 2006) : un changement de schéma qui casse la compatibilité passe par une **période de transition** où l'ancien et le nouveau coexistent. Cette période doit être écrite, avec sa date de fin prévue, sinon elle devient permanente.

#### Les ADR (*Architecture Decision Records*)

Michael Nygard a proposé le format en 2011 : un fichier court par décision structurante, numéroté, versionné avec le code. Son article liste cinq rubriques : **titre, contexte, décision, statut, conséquences**. Beaucoup d'équipes (et l'outil `adr-tools` de Nat Pryce) placent le statut juste sous le titre. L'ordre importe peu ; les règles, si :

- **Un ADR accepté ne se réécrit pas.** Si la décision change, on écrit un nouvel ADR et on passe l'ancien en « remplacé par ADR-00XX ». L'historique des raisons est précisément ce qu'on veut garder.
- **Le contexte décrit les forces en présence**, y compris celles qui ont perdu. Une décision sans alternative écartée n'est pas une décision, c'est un constat.
- **Les conséquences listent aussi le négatif.** Un ADR qui n'a que des ✅ n'a pas été pensé jusqu'au bout.

Les décisions de couche de données qui méritent un ADR : identifiants (entier, UUID, ULID), soft delete ou non, stockage des dates, n-n implicite ou explicite, où vit le SQL brut, multi-tenant, choix de l'ORM lui-même.

Exemple réel sur le fil rouge :

```markdown
# ADR-0002 : `contributions` est une table explicite, pas une relation n-n implicite

- **Statut** : accepté, 2026-10-29

## Contexte

Un membre contribue à plusieurs projets, un projet reçoit plusieurs contributeurs.
Chaque contribution porte un rôle (`auteur`, `design`…) et une date de début.
Prisma propose deux modélisations d'une relation n-n :
- implicite : Prisma crée et gère seul une table de jointure (`_MemberToProject`,
  colonnes `A` et `B`), qui ne peut porter aucune autre colonne ;
- explicite : un modèle `Contribution` mappé sur une table que nous nommons et contrôlons.
D'autres outils lisent la base (SQL brut pour les statistiques, scripts d'import).

## Décision

La relation est une table explicite `contributions (member_id, project_id, role, since)`,
clé primaire composite `(member_id, project_id)`, avec son propre modèle ORM.

## Conséquences

- ✅ Le rôle et la date ont une place : l'association porteuse du MCD est traduite fidèlement.
- ✅ La table a un nom métier et des colonnes lisibles pour le SQL brut et les outils externes.
- ❌ Requêtes plus verbeuses côté ORM : `project.contributions[].member` au lieu de `project.members`.
- ❌ La clé composite interdit qu'un membre ait deux rôles sur un même projet.
  Si le besoin apparaît, il faudra un nouvel ADR (clé élargie à `role`, ou identifiant propre).
```

### 4. L'usage : le guide de la couche d'accès

C'est la documentation la plus souvent absente. Elle répond à « comment je fais X correctement ? » :

- **Où vit le SQL brut, et pourquoi.** Un dossier unique (`src/db/queries/`), et chaque requête brute commence par un commentaire qui dit pourquoi l'ORM ne suffisait pas (« agrégat par mois : l'ORM génère N requêtes, voir ADR-0005 »). Sans cette raison, le prochain développeur la « simplifiera » en la réécrivant avec l'ORM.
- **Les pièges connus**, avec leur correction : « lister les projets avec leurs étiquettes : charger les étiquettes en une requête groupée, sinon N+1 » (voir le [module 06](../06-concepts-avances/notes.md)).
- **Les recettes** : « ajouter une étiquette à un projet », « changer le propriétaire d'un projet ». Cette dernière cache une règle : le nouveau propriétaire doit-il devenir `auteur` dans `contributions` ? Si personne ne l'a écrit, personne ne le fera.

### 5. L'exploitation : le runbook

Un runbook est une procédure qu'on suit sous pression. Il doit être exécutable sans réfléchir, donc concret jusqu'à la commande :

```markdown
# Runbook : annuler la dernière migration en production

**Avant tout** : la migration a-t-elle un down sans perte ? (voir son en-tête, ligne « Réversible »)
Si non → ne pas annuler : écrire une migration corrective (roll-forward), voir module 03.

1. Sauvegarder        : `sqlite3 atelier.db "VACUUM INTO 'backup-$(date +%F-%H%M).db'"`
2. Vérifier l'état    : `node scripts/migrate.mjs status`  → noter la dernière migration appliquée
3. Annuler            : `node scripts/migrate.mjs down`
4. Contrôler          : `node scripts/migrate.mjs status` + requête de vérification de l'en-tête
5. Redéployer le code de la version précédente (le code récent peut dépendre de la colonne supprimée)
6. Consigner l'incident et sa cause dans le ticket lié

**Restaurer** (dernier recours, perte des écritures depuis la sauvegarde) : arrêter l'application, remplacer le fichier, redémarrer.
```

Un runbook qu'on n'a jamais exécuté est une hypothèse. Le bon test, c'est de le dérouler en préproduction, ou au minimum de faire tourner un aller-retour `up → down → up` en CI (voir le [module 03](../03-migrations/notes.md)).

---

## 🧭 Diátaxis appliqué à la couche de données

Daniele Procida distingue quatre types de documentation, selon ce que cherche le lecteur. Les mélanger produit des documents qui ne servent bien personne.

| Type | Le lecteur veut… | Pour l'Atelier | Généré ? |
|---|---|---|---|
| **Tutoriel** | apprendre en faisant | « Créer ta base locale, appliquer les migrations, ajouter ton premier projet » | non |
| **Guide pratique** | accomplir une tâche précise | « Annuler la dernière migration », « Renommer une colonne sans interruption », « Ajouter une étiquette » | non |
| **Référence** | consulter un fait | dictionnaire de données, ERD, fiches d'entité | structure oui, sens non |
| **Explication** | comprendre le pourquoi | ADR, « pourquoi `contributions` a une clé composite » | non |

Correspondance avec les cinq couches : le **modèle** et le **mapping** sont de la référence, l'**évolution** est de l'explication (ADR) adossée à une référence (l'historique des migrations), l'**usage** et l'**exploitation** sont des guides pratiques. Le tutoriel sert à l'arrivée d'une nouvelle personne.

Deux mélanges fréquents :

- **Une référence qui explique.** Le dictionnaire de données se met à raconter l'histoire des décisions. Il devient long, et l'explication vieillit sans que personne ne la relise. Les raisons vont dans un ADR, et la référence pointe vers lui (« convention ADR-0003 »).
- **Un tutoriel qui liste tout.** Le guide de démarrage énumère les quarante colonnes du schéma. Le nouvel arrivant décroche, et cette liste fait doublon avec la référence.

---

## 🔁 Une source de vérité par information

Chaque information a **un seul endroit où elle s'écrit**. Partout ailleurs, elle est générée ou référencée par un lien. Sinon, deux copies finissent toujours par diverger, et le lecteur ne sait pas laquelle croire.

| Information | Source unique | Dérivés générés |
|---|---|---|
| Structure (colonnes, types, clés, index) | la base migrée | dictionnaire (partie structure), ERD, types TypeScript |
| Sens des tables et colonnes | commentaires en base (`COMMENT ON`), ou fichier de descriptions versionné si le SGBD n'en a pas | colonne « Description » du dictionnaire |
| Règles appliquées par l'ORM / l'application | le code, et la fiche d'entité juste à côté | — |
| Raisons des choix | ADR | liens depuis le dictionnaire et les en-têtes de migration |
| Procédures | runbooks | — |

### Qui est la source de la structure : la base ou le schéma ORM ?

Deux façons de travailler coexistent :

- **Schéma ORM d'abord** (Prisma, Drizzle, Doctrine) : on modifie `schema.prisma` ou les entités, l'outil génère la migration, la migration modifie la base.
- **Base d'abord** : on écrit les migrations SQL, on les applique, l'ORM s'aligne (à la main ou par introspection, comme `prisma db pull`).

Dans les deux cas, **la référence doit être générée depuis la base migrée**, pas depuis le schéma ORM. Raison : la base est ce qui est effectivement appliqué. Elle contient les `CHECK`, triggers et index ajoutés à la main que le schéma ORM ignore. Une documentation générée depuis le schéma ORM décrit ce que le code croit ; une documentation générée depuis la base décrit ce qui est vrai.

### Docs as code, vérifiée en CI

La documentation vit dans le dépôt, passe en revue avec le code, et la CI vérifie trois choses :

1. **Elle est à jour** : on régénère la référence et on compare avec la version commitée. Une différence fait échouer le build (`tbls diff`, ou un script maison : [kata 7](katas.md)).
2. **Elle est complète** : un *linter* exige une description pour chaque table et colonne (règle `requireColumnComment` de tbls, ou [kata 6](katas.md)).
3. **Le schéma respecte les conventions documentées** : clé étrangère indexée, horodatages au format convenu…

Condition technique : **la génération doit être déterministe.** Même schéma, même fichier, octet pour octet. Donc tri stable des tables, colonnes et index, et surtout pas de « généré le 29/10/2026 à 14:03 » dans le fichier : sinon il diffère à chaque exécution et le contrôle ne vaut rien.

---

## 🛠️ Techniques par outil

### Commentaires en base

C'est l'emplacement le plus durable pour le sens des colonnes : **la base survit à l'ORM.** Un changement d'ORM, un outil de BI, un client `psql` ou DBeaver : tous lisent les commentaires en base, aucun ne lit tes `///`.

**PostgreSQL** (*illustratif*) :

```sql
COMMENT ON TABLE projects IS 'Projet porté par un membre. Archivé = exclu des listes par défaut.';
COMMENT ON COLUMN projects.status IS 'draft | active | archived. Transitions non vérifiées en base.';

-- Relire : \d+ projects dans psql, ou
SELECT col_description('projects'::regclass, attnum) AS description, attname
FROM pg_attribute
WHERE attrelid = 'projects'::regclass AND attnum > 0 AND NOT attisdropped;
```

Ces `COMMENT ON` s'écrivent **dans des migrations**, comme tout changement de schéma : ils sont versionnés, relus, et `pg_dump` les conserve.

**MySQL** (*illustratif*) : le commentaire fait partie de la définition de colonne, `status VARCHAR(16) NOT NULL COMMENT 'draft | active | archived'`, et `COMMENT = '…'` en option de table. On les relit dans `information_schema.COLUMNS.COLUMN_COMMENT`.

**SQLite** n'a pas de `COMMENT`. Trois options, chacune avec son prix :

1. **Commentaires dans le `CREATE TABLE`.** SQLite conserve le texte d'origine dans `sqlite_schema.sql`, commentaires compris. Mais c'est fragile, comme le montre cet exemple (testé) :

   ```javascript
   // sqlite-comments.mjs
   import { DatabaseSync } from 'node:sqlite';

   const db = new DatabaseSync(':memory:');
   db.exec(`CREATE TABLE notes (
     id   INTEGER PRIMARY KEY,
     body TEXT NOT NULL -- Corps de la note, en Markdown
   )`);

   // SQLite conserve le texte du CREATE, commentaires compris…
   console.log(db.prepare("SELECT sql FROM sqlite_schema WHERE name = 'notes'").get().sql);

   // … mais ALTER TABLE ADD COLUMN insère le nouveau texte juste avant la parenthèse finale.
   // Un commentaire `--` avalerait cette parenthèse : SQLite refuse.
   try {
     db.exec('ALTER TABLE notes ADD COLUMN read_at TEXT -- Horodatage UTC de lecture');
   } catch (error) {
     console.log('Refusé :', error.message); // error in table notes after add column: incomplete input
   }
   db.exec('ALTER TABLE notes ADD COLUMN read_at TEXT /* Horodatage UTC de lecture */');
   console.log(db.prepare("SELECT sql FROM sqlite_schema WHERE name = 'notes'").get().sql);
   ```

   Il faut ensuite *parser* ce texte pour extraire les commentaires. C'est faisable, mais on écrit un mini-parseur SQL pour de la documentation.

2. **Une table de métadonnées** (`_column_docs(table_name, column_name, description)`) remplie par les migrations. Elle est interrogeable en SQL, mais c'est une convention maison que les outils externes ignorent.
3. **Un fichier de descriptions versionné** à côté du schéma : c'est ce que fait la section `comments:` de tbls, et ce que font les [katas](katas.md) de ce module (`descriptions.mjs`). Simple et lisible. En contrepartie, rien ne lie mécaniquement le fichier à la base : c'est le linter qui doit détecter une colonne sans description.

Pour un projet SQLite, l'option 3 est le meilleur compromis : elle ne dépend d'aucun parseur fragile, et le contrôle CI compense l'absence de lien mécanique.

### Prisma : `//` contre `///`

Dans `schema.prisma`, `//` est un commentaire pour le lecteur du fichier, ignoré par l'outillage. `///` est un **commentaire de documentation** : la documentation de Prisma indique qu'il est attaché au nœud suivant de l'arbre syntaxique (modèle, champ, enum) et exposé comme sa description. Les générateurs y ont donc accès. Deux générateurs communautaires l'exploitent :

- `prisma-erd-generator` produit un ERD (SVG par défaut, via Mermaid) à chaque `prisma generate` ;
- `prisma-db-comments-generator` transforme les `///` en migration `COMMENT ON` (PostgreSQL, MySQL en expérimental). À ma connaissance, Prisma ne le fait pas nativement : vérifie dans ta version.

Le client généré reprend une partie de ces commentaires en JSDoc ; l'étendue dépend des versions, vérifie sur la tienne avant de t'y fier.

### JSDoc sur les entités

Avec un ORM à base de classes (TypeORM, MikroORM) ou un Data Mapper maison ([module 01](../01-fondamentaux/notes.md)), la fiche d'entité peut tenir en tête de classe. L'éditeur l'affiche au survol, à l'endroit où le développeur en a besoin :

```javascript
/**
 * Projet porté par un membre. Table `projects`.
 *
 * Règles absentes du schéma :
 * - `title` est nettoyé et non vide (ProjectRepository.create) ;
 * - les projets archivés sont exclus de ProjectRepository.findAll() par défaut ;
 * - archive() supprime les étiquettes du projet (irréversible).
 *
 * @see docs/adr/0002-contributions-table-explicite.md
 */
export class Project {
  /** Identifiant technique (`projects.id`). */
  id;

  /**
   * Cycle de vie. CHECK en base ; transitions non vérifiées.
   * @type {'draft' | 'active' | 'archived'}
   */
  status = 'draft';
}
```

### DBML

DBML (*Database Markup Language*, porté par dbdiagram.io) décrit un schéma en texte, avec des notes de table et de colonne (*illustratif*) :

```text
Table projects {
  id         integer [pk, increment]
  owner_id   integer [not null, note: 'Suppression du membre refusée tant qu’il possède des projets']
  status     text    [not null, default: 'draft', note: 'draft | active | archived, transitions non vérifiées']

  Note: 'Projet porté par un membre'
}

Ref: projects.owner_id > members.id
```

Utile pour **concevoir** et discuter un schéma avant de l'écrire. Pour **documenter** un schéma existant, c'est une copie de plus à maintenir, sauf si on la génère (l'écosystème DBML liste des convertisseurs SQL ↔ DBML et un générateur Prisma → DBML, à vérifier selon ta stack).

### Mermaid

GitHub, GitLab et la plupart des générateurs de sites rendent les blocs ```` ```mermaid ```` directement. Un `erDiagram` en texte se relit en *diff*, se régénère par script ([kata 5](katas.md)), et ne pourrit pas comme un PNG exporté. Limite : au-delà d'une quinzaine de tables, le rendu automatique devient illisible. Il faut alors des vues partielles (un diagramme par domaine).

### tbls

`tbls` (Go) se connecte à la base et génère une documentation Markdown navigable, avec ERD (SVG par défaut, PNG, JPG ou Mermaid). Il est conçu pour la CI :

- `tbls doc` génère la documentation ;
- `tbls diff` compare la base et la documentation commitée ;
- `tbls lint` vérifie des règles, dont `requireTableComment`, `requireColumnComment`, `requireForeignKeyIndex`, `unrelatedTable`, `columnCount` ;
- la section `comments:` du `.tbls.yml` ajoute des descriptions sans `ALTER TABLE`, utile pour SQLite et pour les vues.

Configuration *illustrative* pour le fil rouge :

```yaml
# .tbls.yml
dsn: sqlite:///chemin/vers/atelier.db
docPath: docs/schema
er:
  format: mermaid
comments:
  - table: projects
    tableComment: Projet porté par un membre. Archivé = exclu des listes par défaut.
    columnComments:
      status: "draft | active | archived ; transitions non vérifiées en base"
lint:
  requireColumnComment:
    enabled: true
    exclude:
      - id
  requireForeignKeyIndex:
    enabled: true
```

### SchemaSpy

SchemaSpy (Java, via JDBC) analyse une base existante et produit un rapport HTML navigable avec diagrammes. Il signale aussi des anomalies : index manquants, relations implicites (colonnes qui ressemblent à des clés étrangères non déclarées), tables orphelines. Il ne lit que la structure, donc il fonctionne sur une réplique vide. C'est un bon outil de **découverte** d'une base héritée, moins adapté à un contrôle CI que tbls (sortie HTML, pas de *diff*).

### Récapitulatif

| Outil | Entrée | Sortie | Lint | Contrôle CI |
|---|---|---|---|---|
| `COMMENT ON` | — | métadonnées en base | — | via un outil d'introspection |
| Prisma `///` | `schema.prisma` | descriptions exposées aux générateurs | — | — |
| DBML | fichier `.dbml` | diagramme (dbdiagram.io), SQL | — | — |
| Mermaid | texte | diagramme rendu dans le Markdown | — | si généré par script |
| tbls | base | Markdown + ERD | ✅ | ✅ (`tbls diff`) |
| SchemaSpy | base | HTML + diagrammes | anomalies | ❌ |
| Script maison (katas) | base + descriptions | Markdown + Mermaid | ✅ | ✅ |

---

## 📋 Modèles prêts à copier

### Entrée de dictionnaire

```markdown
## `nom_table`

> Une phrase : ce que représente une ligne de cette table dans le monde réel.

| Colonne | Type | Null | Défaut | Clé | Description |
|---|---|---|---|---|---|
| `colonne` | TEXT | non | — | — | Sens. Format/unité. Domaine. Qui l'écrit. Invariants non contraints. Sensibilité. |
```

### Fiche d'entité

```markdown
# Entité `Project` ↔ table `projects`

**Rôle** : …
**Fichiers** : `src/db/project-repository.mjs`, migration de création `…`

## Relations
| Relation | Cardinalité | Chargée par défaut ? |
|---|---|---|

## Règles
| Règle | Appliquée par (base / ORM / application) | Contournée par |
|---|---|---|

## Comportements cachés
- (hooks, filtres implicites, effets de bord, sérialisation)

## Trous connus
- (règles attendues que personne n'applique)
```

### ADR

```markdown
# ADR-00XX : <décision, formulée comme une affirmation>

- **Statut** : proposé | accepté (date) | déprécié | remplacé par ADR-00YY

## Contexte
Les forces en présence, contraintes, alternatives envisagées.

## Décision
« Nous … » : une décision, au présent, vérifiable.

## Conséquences
Ce qui devient plus facile, ce qui devient plus difficile, ce qu'il faudra surveiller.
```

### En-tête de migration

```sql
-- Migration   : <horodatage>_<verbe>_<objet>
-- Intention   : pourquoi, lien vers le ticket
-- Réversible  : oui / non / avec perte (préciser laquelle)
-- Risques     : verrous, durée estimée, volume concerné
-- Séquence    : étape n/m d'un expand/contract, migrations liées, date de retrait prévue
-- Vérification: requête qui prouve que la migration a produit l'effet voulu
```

---

## ⚠️ Anti-patterns

1. **Le wiki séparé.** La documentation vit hors du dépôt, personne ne la met à jour dans la *pull request* qui change le schéma, elle diverge en quelques semaines. Correctif : docs dans le dépôt, générée et vérifiée en CI.
2. **Le commentaire-paraphrase.** « `email` : l'email ». Il coûte du temps de lecture et donne une fausse impression de couverture : le linter est satisfait, le lecteur n'apprend rien. Correctif : la règle « si ça se déduit du nom, supprime ».
3. **L'ERD exporté une fois en PNG.** Exact le jour de l'export, faux dès la migration suivante, et impossible à relire en *diff*. Correctif : diagramme en texte, régénéré.
4. **Le quoi sans le pourquoi.** Un dictionnaire impeccable, et aucune trace des raisons pour lesquelles `contributions` a une clé composite. Le prochain développeur « corrige » une décision délibérée. Correctif : ADR.
5. **L'intention écrite comme un fait.** « Email unique, insensible à la casse » alors que la contrainte est sensible à la casse. Correctif : générer les faits depuis la base, écrire les intentions au conditionnel ou comme conventions, lister les écarts connus.
6. **Tout documenter au même niveau.** Quarante colonnes décrites avec le même soin, et les trois comportements surprenants noyés dedans. Correctif : documenter d'abord ce qui surprend, c'est-à-dire les règles hors schéma, les effets de bord et les trous connus.
7. **Réécrire un ADR accepté.** On perd la trace de ce qu'on pensait et pourquoi on a changé d'avis. Correctif : un nouvel ADR, l'ancien passe en « remplacé ».

---

## 🧠 Points clés à retenir

1. La vérité est répartie entre base, schéma ORM, migrations, code et seeds. **Aucun ne dit tout.**
2. **La structure se génère, le sens et les raisons s'écrivent.**
3. Pour chaque règle, documenter **qui l'applique** (base, ORM, application) et **ce qui la contourne**.
4. Une règle appliquée seulement par l'ORM est contournée par le SQL brut, les scripts et les autres services.
5. La référence se génère depuis **la base migrée**, pas depuis le schéma ORM.
6. Les commentaires en base survivent à l'ORM. Quand le SGBD n'en a pas, utiliser un fichier de descriptions versionné, contrôlé par un linter.
7. Les ADR gardent le pourquoi. Ils sont **immuables** une fois acceptés.
8. Une doc générée doit être **déterministe** pour pouvoir être vérifiée en CI.
9. **Une description fausse est pire qu'une description absente.**

---

## 🔗 Liens avec les autres modules

- [01 · Fondamentaux](../01-fondamentaux/notes.md) : Active Record et Data Mapper ne cachent pas les règles au même endroit (dans le modèle d'un côté, dans le mapper ou le repository de l'autre). La fiche d'entité doit pointer le bon fichier.
- [02 · SQL, query builder, ORM](../02-sql-query-builder-orm/notes.md) : chaque requête SQL brute est une exception à justifier dans le guide d'usage.
- [03 · Migrations](../03-migrations/notes.md) : la mécanique `up`/`down`, l'expand/contract et l'aller-retour en CI, que l'en-tête de migration et le runbook documentent.
- [04 · Modélisation Merise, UML, ERD](../04-modelisation-merise-uml-erd/notes.md) : les notations. Un ERD généré depuis la base perd une partie du MCD (cardinalités minimales, n-n vue comme deux 1-n) : voir le [kata 5](katas.md).
- [06 · Concepts avancés](../06-concepts-avances/notes.md) : N+1, chargement par défaut, soft delete, hooks, autant de comportements cachés à faire figurer dans les fiches d'entité.

---

## 📚 Pour aller plus loin

- **Michael Nygard**, « Documenting Architecture Decisions », 2011 : l'article fondateur des ADR, deux pages.
- **Daniele Procida**, [Diátaxis](https://diataxis.fr/) : le cadre tutoriel / guide / référence / explication, avec sa justification.
- **Scott Ambler, Pramod Sadalage**, *Refactoring Databases*, 2006 : chaque refactoring de schéma est décrit avec sa période de transition, ce qui en fait un modèle pour les en-têtes de migration.
- **Pramod Sadalage, Martin Fowler**, « Evolutionary Database Design », martinfowler.com : schéma et code versionnés ensemble, conditions pour que la documentation suive.
- [tbls](https://github.com/k1LoW/tbls) et [SchemaSpy](https://github.com/schemaspy/schemaspy) : lire les README pour voir ce qu'un outil d'introspection sait (et ne sait pas) déduire.
- [Documentation DBML](https://dbml.dbdiagram.io/docs/) et [syntaxe `erDiagram` de Mermaid](https://mermaid.js.org/syntax/entityRelationshipDiagram.html).

---

**Dernière mise à jour** : 2026-10-29
**Niveau de confiance** : ⭐⭐⭐⭐☆
**Prochaine révision** : après les katas 5 à 7
