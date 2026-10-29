# 🧱 Migrations : versionner le schéma et revenir en arrière

## 📋 Vue d'ensemble

Le code se versionne avec Git : on peut revenir à n'importe quel commit et redéployer. Une base de données ne fonctionne pas comme ça. Elle contient un **état** (le schéma et surtout les données) qu'on ne peut ni jeter ni régénérer. On ne remplace pas une base : on la **transforme**. Une migration est la façon disciplinée d'écrire ces transformations.

Ce module est central pour l'usage d'un ORM : presque tous en fournissent un (Prisma Migrate, Drizzle Kit, Doctrine Migrations, Sequelize CLI, Knex…). Mais ils font des choix très différents, notamment sur le retour en arrière, et ces choix ne sont pas des détails.

### 🎯 Objectifs

- Définir une migration et dire précisément ce qu'elle garantit (et ce qu'elle ne garantit pas)
- Connaître l'anatomie d'un moteur de migrations : fichiers, historique, ordre, checksum, verrou, transaction
- Distinguer migrations versionnées, déclaratives et hybrides
- Savoir **revenir en arrière** avec chaque outil, et savoir quand un `down` est une illusion
- Appliquer le pattern *expand/contract* pour changer un schéma sans interruption de service
- Séparer migrations de schéma, migrations de données, seeds et fixtures
- Contourner les limites d'`ALTER TABLE` dans SQLite sans perdre de données

---

## 🤔 Le problème

Théo ajoute une colonne `bio` à `members` en tapant un `ALTER TABLE` dans son client SQL. Il écrit le code qui l'utilise, ouvre une pull request, elle est fusionnée et déployée.

- En production, la colonne n'existe pas : chaque page de profil renvoie une erreur 500.
- Ada, sur sa machine, avait ajouté la même colonne la veille, mais en `VARCHAR(255)`.
- La CI construit sa base à partir d'un vieux dump : les tests passent sur un schéma qui n'existe nulle part ailleurs.

Le schéma est un **état partagé non versionné** : chaque base a sa propre histoire, et personne ne la connaît. La solution n'est pas de versionner l'état (un dump du schéma), parce qu'un dump ne dit pas comment passer d'une version à l'autre **en conservant les données**. On versionne donc les **transformations**.

---

## 📖 Définition

Une **migration** est un script qui transforme le schéma (et parfois les données) d'une base, et qui est :

- **versionné** : il vit dans le dépôt, dans le même commit que le code qui en dépend ;
- **ordonné** : il suppose l'état laissé par la migration précédente ;
- **appliqué une seule fois par base** : la base mémorise ce qui lui a été appliqué ;
- **rejouable** : la même suite, appliquée à une base vide, produit le même schéma partout.

Formellement, l'état du schéma n'est jamais stocké : il est **dérivé** de la suite des migrations.

```
S₀ (base vide) ──m₁──► S₁ ──m₂──► S₂ ──m₃──► S₃ = schéma actuel
```

C'est exactement la distinction du chapitre `02_offline-first` entre CRDT *state-based* et *operation-based* : une migration versionnée transmet des **opérations**, un outil déclaratif (voir plus bas) compare des **états**.

### Migration et refactoring de base de données

Ambler et Sadalage (*Refactoring Databases*, 2006) définissent un **refactoring de base de données** comme une petite modification du schéma qui améliore sa conception **en préservant sa sémantique comportementale et informationnelle**. Toute migration n'est pas un refactoring (ajouter une fonctionnalité change la sémantique), mais leur idée centrale vaut pour toutes : une base partagée par du code en production ne peut pas changer d'un coup. Il faut une **période de transition** où l'ancien et le nouveau schéma coexistent. C'est l'origine du pattern *expand/contract* (plus bas).

### Pourquoi c'est indispensable

| Besoin | Sans migrations | Avec migrations |
|---|---|---|
| Reproductibilité | chaque base a sa propre histoire | même suite → même schéma partout |
| Revue de code | changements invisibles, faits à la main | le SQL passe en revue comme le reste du code |
| Intégration continue | base de test approximative | base construite depuis zéro à chaque exécution |
| Cohérence code/schéma | « ça marche chez moi » | le commit qui lit la colonne contient la migration qui la crée |
| Traçabilité | qui a changé quoi, quand ? | historique Git + table d'historique en base |

Sadalage et Fowler (« Evolutionary Database Design », 2003, révisé en 2016) en tirent des règles qui restent la référence : **tout** changement de base est une migration, y compris les données de référence ; chaque développeur a sa propre instance ; tout est versionné ; les migrations passent en CI comme le code.

---

## 🔬 Anatomie d'une migration

### Le fichier

Une migration contient au minimum une fonction `up` (appliquer). La plupart des outils ajoutent une fonction `down` (annuler). Voici le format du moteur que tu écriras en kata, en JavaScript natif :

```javascript
// migrations/004_add_members_bio.mjs
export function up(db) {
  db.exec('ALTER TABLE members ADD COLUMN bio TEXT');
}

export function down(db) {
  db.exec('ALTER TABLE members DROP COLUMN bio'); // ⚠️ détruit les bios saisies depuis l'up
}
```

Le même changement avec Knex (illustratif) :

```javascript
// migrations/20261029120000_add_members_bio.js
exports.up = (knex) => knex.schema.alterTable('members', (table) => {
  table.text('bio');
});

exports.down = (knex) => knex.schema.alterTable('members', (table) => {
  table.dropColumn('bio');
});
```

Et avec Prisma (illustratif), où l'on modifie le schéma déclaratif puis où l'outil **génère** le SQL :

```prisma
model Member {
  id     Int     @id @default(autoincrement())
  handle String  @unique
  bio    String? // ajout
}
```

```sql
-- prisma/migrations/20261029120000_add_members_bio/migration.sql (généré)
ALTER TABLE "members" ADD COLUMN "bio" TEXT;
```

Remarque : Prisma ne génère **pas** de `down`. On y revient.

### La table d'historique

Le moteur mémorise dans la base elle-même ce qui a été appliqué. Version minimale :

```sql
CREATE TABLE schema_migrations (
  version    TEXT PRIMARY KEY,                     -- 004
  name       TEXT NOT NULL,                        -- add_members_bio
  checksum   TEXT NOT NULL,                        -- empreinte du fichier au moment de l'application
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

Chaque outil a la sienne. Savoir la reconnaître sert le jour où il faut diagnostiquer une base dans un état étrange.

| Outil | Table(s) d'historique | Particularité |
|---|---|---|
| Prisma Migrate | `_prisma_migrations` | checksum, début/fin, `rolled_back_at`, journal d'erreur |
| Knex | `knex_migrations` + `knex_migrations_lock` | colonne `batch` (voir rollback) |
| Sequelize CLI | `SequelizeMeta` | seulement le nom du fichier |
| Doctrine Migrations | `doctrine_migration_versions` | version, date, durée d'exécution |
| Laravel | `migrations` | colonne `batch` |
| Rails | `schema_migrations` (+ `ar_internal_metadata`) | seulement la version |
| Django | `django_migrations` | application + nom |
| Drizzle Kit | `__drizzle_migrations` (schéma `drizzle` en PostgreSQL) | hash du fichier |
| Flyway | `flyway_schema_history` | checksum, durée, succès/échec |
| Liquibase | `DATABASECHANGELOG` + `DATABASECHANGELOGLOCK` | MD5 par *changeSet* |
| Sqitch | schéma `sqitch` (`changes`, `events`, `tags`…) | journal de tous les déploiements **et** reverts |

### L'ordre : séquence ou horodatage

- **Séquence** (`001`, `002` ; Flyway `V1__`, `V2__` ; Django `0001_initial`) : ordre lisible, mais deux branches créent chacune une `004` et entrent en collision.
- **Horodatage** (`20261029120000_…` : Rails, Knex, Prisma, Laravel ; Doctrine `Version20261029120000`) : plus de collision de nom, mais l'ordre de **création** n'est plus l'ordre de **fusion**. Une migration créée lundi sur une branche fusionnée vendredi arrive *après* une migration de mercredi déjà appliquée en production. Selon l'environnement, les deux seront appliquées dans des ordres différents.

Les outils réagissent différemment : Rails applique silencieusement toute version en attente, même antérieure ; Flyway refuse par défaut (`outOfOrder=false`) ; Django modélise un graphe de dépendances explicite et exige une migration de fusion (`makemigrations --merge`) ; Atlas maintient un fichier d'intégrité `atlas.sum` qui provoque volontairement un conflit Git quand deux branches ajoutent des migrations.

**Ce qu'il faut retenir :** si deux migrations touchent des objets indépendants, leur ordre importe peu. Sinon, c'est un vrai conflit, à résoudre par un humain, exactement comme un conflit de code. Un moteur qui le signale vaut mieux qu'un moteur qui choisit.

### Le checksum

Une migration appliquée est un **fait historique**. Si tu modifies son fichier après coup, la production (qui a exécuté l'ancienne version) et toute base neuve (qui exécutera la nouvelle) divergent **silencieusement**. Le checksum transforme cette divergence silencieuse en erreur bruyante : l'outil recalcule l'empreinte du fichier et la compare à celle enregistrée.

Flyway (`flyway validate`), Liquibase (MD5 par *changeSet*), Prisma, Atlas (`atlas.sum`) le font. Sequelize et Rails ne stockent que le nom ou la version : ils ne voient rien.

> **Règle absolue :** on ne modifie jamais une migration déjà appliquée ailleurs que sur sa propre machine. On en écrit une nouvelle qui corrige.

### Le verrou

Si chaque instance de l'application lance les migrations à son démarrage (pratique courante et discutable), deux instances qui démarrent ensemble appliqueront la même migration deux fois. Les moteurs prennent donc un verrou : table dédiée (Knex, Liquibase), *advisory lock* PostgreSQL (Prisma Migrate), verrou d'écriture (`BEGIN IMMEDIATE` en SQLite, dans le kata).

La meilleure solution reste de lancer les migrations comme **une étape dédiée du déploiement**, une seule fois, avant de démarrer les nouvelles instances.

### La transaction

Le moteur exécute chaque migration **et** l'insertion dans la table d'historique dans la **même transaction**. Soit les deux sont écrits, soit aucun. Sans cela, une migration réussie mais non enregistrée sera rejouée (et échouera), et une migration enregistrée mais à moitié appliquée ne sera jamais terminée.

Cela suppose que le SGBD sache annuler du DDL (`CREATE`, `ALTER`, `DROP`) dans une transaction. Ce n'est pas universel : voir [DDL transactionnel](#-ddl-transactionnel--ça-dépend-du-sgbd).

---

## 🧭 Trois philosophies

### Versionnée (impérative)

Tu écris les étapes. L'outil les applique dans l'ordre. Knex, Sequelize, Rails, Laravel, Flyway, Liquibase, Sqitch.

- ✅ Tu contrôles exactement ce qui s'exécute, y compris les migrations de données
- ✅ L'intention est explicite : un renommage est un renommage
- ❌ Il faut écrire chaque changement, et l'historique s'allonge indéfiniment

### Déclarative (état désiré)

Tu décris le schéma voulu. L'outil compare avec la base réelle et calcule le plan pour y arriver. Atlas (`atlas schema apply`), `prisma db push`, `drizzle-kit push`.

- ✅ Pas d'historique à maintenir, le schéma cible est toujours lisible
- ❌ Un diff ne connaît pas l'**intention**. Si `title` disparaît et `name` apparaît, est-ce un renommage (données conservées) ou une suppression suivie d'un ajout (données perdues) ? Les deux donnent le même état final.
- ❌ Aucune place pour les migrations de données

`prisma db push` et `drizzle-kit push` sont conçus pour le **prototypage**, pas pour la production.

### Hybride : déclaratif en entrée, versionné en sortie

Tu modifies le schéma déclaratif, l'outil **génère** un fichier de migration versionné que tu relis, ajustes et commites. `prisma migrate dev`, `drizzle-kit generate`, Doctrine `doctrine:migrations:diff` (ou `make:migration` avec Symfony), Django `makemigrations`, `atlas migrate diff`.

C'est le meilleur compromis à condition de **relire le SQL généré**. Le problème du renommage ne disparaît pas : `drizzle-kit generate` et Django `makemigrations` posent la question de manière interactive ; Prisma génère par défaut une suppression et un ajout, et prévient de la perte de données. Une migration générée est un brouillon, pas une vérité.

### La dérive (*drift*)

Il y a dérive quand la base réelle ne correspond plus à ce que l'historique décrit : un index ajouté à la main pendant un incident, une colonne modifiée par un script. Prisma la détecte en développement (`migrate dev` compare avec une *shadow database*) et propose de réinitialiser la base, ce qui est acceptable en local et impensable en production. Atlas et Liquibase savent comparer une base à un état attendu.

**Règle :** même le correctif d'urgence passe par une migration. Si tu as dû agir à la main, écris immédiatement la migration qui reproduit ton geste, et marque-la comme appliquée sur la base concernée (Prisma : `migrate resolve --applied`).

---

## ⏪ Revenir en arrière

### Trois choses différentes que l'on appelle « rollback »

1. **Annuler une migration qui échoue en cours de route.** C'est le rôle de la transaction. Automatique si le SGBD sait annuler du DDL.
2. **Dé-appliquer une migration réussie.** C'est le rôle du `down`.
3. **Revenir à un état antérieur des données.** C'est le rôle des sauvegardes et de la restauration à un instant donné.

Confondre les trois est la source de la plupart des mauvaises décisions en incident. Un `down` ne remplace pas une sauvegarde : il restaure une **forme**, pas un **contenu**.

### Le `down`

Le `down` applique l'inverse de l'`up`, **dans l'ordre inverse** : si l'`up` crée une colonne puis un index dessus, le `down` supprime l'index puis la colonne (sinon le `DROP COLUMN` échoue).

| Opération dans `up` | Inverse dans `down` | Sans perte ? |
|---|---|---|
| `CREATE TABLE` | `DROP TABLE` | ⚠️ perd les lignes écrites depuis |
| `ADD COLUMN` | `DROP COLUMN` | ⚠️ perd les valeurs écrites depuis |
| `CREATE INDEX` | `DROP INDEX` | ✅ un index ne contient que des données dérivées |
| `RENAME COLUMN a TO b` | `RENAME COLUMN b TO a` | ✅ |
| `DROP COLUMN` | `ADD COLUMN` | ❌ restaure la colonne, pas son contenu |
| `UPDATE` non injectif (plusieurs valeurs → une seule) | aucun | ❌ l'information d'origine a disparu |

Certains outils dérivent le `down` automatiquement pour les opérations inversibles : Rails avec la méthode `change`, Django pour les opérations de schéma, Liquibase pour certains types de changements (`createTable`, `addColumn`…). Pour le reste, il faut l'écrire, ou déclarer la migration irréversible.

### Les commandes, outil par outil

| Outil | Annuler la dernière | Revenir plus loin | À savoir |
|---|---|---|---|
| Knex | `knex migrate:rollback` (dernier *batch*) ; `knex migrate:down` (dernière migration) | `knex migrate:rollback --all` | un *batch* = tout ce qu'un `migrate:latest` a appliqué d'un coup |
| Sequelize CLI | `npx sequelize-cli db:migrate:undo` | `db:migrate:undo:all --to XXXX-nom.js` | |
| Doctrine | `php bin/console doctrine:migrations:migrate prev` | `doctrine:migrations:migrate 'DoctrineMigrations\Version2026…'` ; `doctrine:migrations:execute '…' --down` | `execute --down` vise une migration précise |
| Laravel | `php artisan migrate:rollback` (dernier *batch*) ; `--step=1` | `php artisan migrate:reset` | `migrate:fresh` supprime toutes les tables **sans** passer par les `down` |
| Rails | `bin/rails db:rollback STEP=1` | `bin/rails db:migrate VERSION=2026…` ; `db:migrate:down VERSION=…` | `db:migrate:redo` = down puis up |
| Django | `python manage.py migrate app 0003` | `python manage.py migrate app zero` | annule tout ce qui suit la migration nommée |
| Prisma | pas de `down` natif | voir ci-dessous | `migrate resolve` ne modifie que l'historique |
| Drizzle Kit | pas de rollback intégré (à revérifier selon ta version) | `down` écrit à la main, ou nouvelle migration inverse | |
| Flyway | `flyway undo` avec des scripts `U2__…sql` | | réservé aux éditions payantes (Teams et au-delà) |
| Liquibase | `liquibase rollback-count --count=1` | `liquibase rollback --tag=v1.2` ; `rollback-to-date` | bloc `<rollback>` à écrire quand l'inverse n'est pas déductible |
| Sqitch | `sqitch revert --to @HEAD^` | `sqitch revert --to <changement>` | chaque changement a trois scripts : *deploy*, *revert*, *verify* |

*Tous ces extraits sont illustratifs : vérifie la syntaxe exacte dans la documentation de ta version.*

#### Le cas Prisma (illustratif)

Prisma assume l'absence de `down` : pour annuler une migration **réussie**, on revient en arrière dans `schema.prisma` et on génère une **nouvelle** migration. Pour se préparer à l'échec d'une migration en production, la documentation propose de générer un script inverse **avant** de créer la migration :

```bash
# 1. Après avoir modifié schema.prisma, AVANT de créer la migration :
#    calculer le SQL qui ramène du nouveau schéma à l'état décrit par les migrations existantes
npx prisma migrate diff --from-schema prisma/schema.prisma --to-migrations prisma/migrations --script > down.sql
# (Prisma 6 : --from-schema-datamodel, et une shadow database via --shadow-database-url)

# 2. Créer la migration sans l'appliquer, la relire
npx prisma migrate dev --create-only --name add_members_bio

# 3. Si elle échoue en production : appliquer le down, puis l'indiquer à l'historique
npx prisma db execute --file ./down.sql
npx prisma migrate resolve --rolled-back 20261029120000_add_members_bio
```

Deux limites documentées : `migrate resolve --rolled-back` ne fonctionne que sur une migration **en échec**, et `migrate diff` ne sait pas inverser le SQL que tu as ajouté à la main (vues, triggers, migrations de données).

### Le `down` qui ment, et les migrations irréversibles

Un `down` peut être syntaxiquement correct et sémantiquement faux :

- **Il détruit ce qui a été écrit depuis l'`up`.** `ADD COLUMN bio` puis, après une semaine d'utilisation, `DROP COLUMN bio` : les bios sont perdues. C'est parfois acceptable, mais ça doit être une décision, pas une surprise.
- **Il restaure une forme vide.** L'`up` supprime `contributions.since`, le `down` la recrée avec une valeur par défaut : toutes les dates valent `1970-01-01`. Le schéma est revenu, l'information non.
- **Il inverse une transformation qui n'est pas inversible.** L'`up` archive les brouillons (`draft → archived`), le `down` repasse tout ce qui est archivé en brouillon… y compris les projets qui étaient archivés avant. C'est une fonction non injective : on ne peut pas l'inverser.

Mieux vaut une migration **honnêtement irréversible** qu'un `down` qui ment. Les outils le permettent : Rails `raise ActiveRecord::IrreversibleMigration`, Doctrine `$this->throwIrreversibleMigrationException()`, Django lève `IrreversibleError` si une opération `RunPython` n'a pas de `reverse_code`. Dans le moteur du kata, une migration sans `down` est refusée au rollback.

Le kata 3 transforme ces intuitions en test automatique : deux propriétés vérifiables (« le `down` restaure l'état d'avant » et « l'information écrite après l'`up` survit à `down` puis `up` »).

### 🔐 DDL transactionnel : ça dépend du SGBD

| SGBD | Le DDL est-il annulable dans une transaction ? | Conséquence pour les migrations |
|---|---|---|
| PostgreSQL | Oui, pour presque tout | Exceptions : `CREATE INDEX CONCURRENTLY`, `DROP INDEX CONCURRENTLY`, `CREATE DATABASE`, `VACUUM`… refusent de tourner dans une transaction |
| SQLite | Oui | Mais `PRAGMA foreign_keys` est sans effet à l'intérieur d'une transaction (important pour les reconstructions de table) |
| SQL Server | Oui pour l'essentiel | |
| MySQL / MariaDB | **Non** : chaque instruction DDL provoque un *commit* implicite | Une migration de trois instructions qui échoue à la deuxième laisse la première appliquée et l'historique non mis à jour |
| Oracle | **Non** : commit implicite | Même conséquence |

Le « DDL atomique » de MySQL 8 garantit qu'**une** instruction est appliquée entièrement ou pas du tout, même en cas de crash. Il ne rend pas une **suite** d'instructions atomique. D'où la règle pour MySQL : **une instruction DDL par migration**, pour que le point d'échec coïncide avec une frontière de migration. Doctrine permet d'ailleurs de déclarer une migration non transactionnelle (`isTransactional()`), Knex aussi (`exports.config = { transaction: false }`), Django (`atomic = False`).

Démonstration avec SQLite, testable telle quelle :

```javascript
// ddl-transactionnel.mjs (dans 03-migrations/)
import { openDb } from '../fil-rouge/open-db.mjs';

const db = openDb();
const columns = () => db.prepare("SELECT name FROM pragma_table_info('members')").all().map((c) => c.name);

try {
  db.exec('BEGIN');
  db.exec('ALTER TABLE members ADD COLUMN bio TEXT');     // 1ʳᵉ instruction : réussit
  db.exec('CREATE INDEX members_bio_idx ON members (bio)');
  db.exec('CREATE INDEX members_bio_idx ON members (bio)'); // 3ᵉ : échoue (index déjà créé)
  db.exec('COMMIT');
} catch (error) {
  db.exec('ROLLBACK');
  console.log('Échec :', error.message);
}
console.log(columns()); // [ 'id', 'handle', 'email', 'created_at' ] : pas de bio, rien n'a été appliqué
```

Sous MySQL, le même script laisserait la colonne `bio` créée.

### Roll-forward plutôt que rollback

En production, la pratique dominante est le **roll-forward** (*fix forward*) : on corrige par une **nouvelle** migration plutôt qu'en exécutant un `down`. Les raisons sont concrètes :

- un `down` est presque toujours moins testé que l'`up`, et jamais sur les données réelles ;
- des données ont été écrites depuis l'`up`, et le `down` va probablement les détruire ;
- une nouvelle migration passe par la même revue et la même CI que le reste ;
- l'historique reste linéaire : la production et une base neuve suivent le même chemin.

Le `down` garde sa place : en développement (itérer sur une migration), en CI (tester l'aller-retour), et en production dans un cas précis : la migration vient d'être appliquée, elle est purement additive et **aucun code ne l'utilise encore**.

Remarque sur une contradiction apparente : Rails et Laravel cultivent l'écriture systématique de `down`, Prisma et Drizzle n'en proposent pas. Les deux positions sont cohérentes avec des hypothèses différentes. Ce qui compte n'est pas l'existence d'un `down`, mais l'existence d'un **plan de retour testé**.

### Le vrai filet : sauvegardes et restauration à un instant donné

Quand des données ont été détruites, aucun `down` ne les rendra. Il faut une **sauvegarde**, et idéalement la **restauration à un instant donné** (PITR, *point-in-time recovery*). En PostgreSQL, elle combine une sauvegarde de base (`pg_basebackup`) et l'archivage continu du journal d'écriture (WAL) ; les services managés la proposent en option.

Deux nuances qui changent tout en incident :

- Restaurer **toute** la base à 9 h 59 efface tout ce qui a été écrit ensuite, pas seulement l'erreur. On restaure plutôt dans une **instance séparée**, on en extrait les données perdues, et on les réinjecte par une migration (roll-forward).
- Une sauvegarde dont la restauration n'a jamais été testée n'est pas une sauvegarde. Deux chiffres à connaître : **RPO** (combien de données peut-on perdre ?) et **RTO** (combien de temps peut-on être indisponible ?).

### Code et schéma ne se déploient pas en même temps

Pendant un déploiement progressif (*rolling deploy*), l'ancienne version du code (N) et la nouvelle (N+1) tournent **en même temps** sur le **même** schéma. Et si tu dois annuler le déploiement du code, c'est la version N qui tournera sur le schéma migré. Sans compter les workers, les tâches planifiées, les caches et les applications mobiles qui ne sont jamais mises à jour.

D'où la vraie règle, plus importante que l'écriture de `down` : **chaque migration doit rester compatible avec le code en cours d'exécution ET avec le code qui va le remplacer.**

| Changement | L'ancien code continue-t-il de fonctionner ? |
|---|---|
| Ajouter une colonne facultative | Oui, sauf `INSERT` sans liste de colonnes |
| Ajouter une colonne `NOT NULL` sans défaut | Non : les `INSERT` de l'ancien code échouent |
| Ajouter une colonne `NOT NULL` avec défaut | Oui |
| Supprimer une colonne | Non, dès que l'ancien code la lit **ou que l'ORM la mappe encore** |
| Renommer une colonne ou une table | Non |
| Changer le type d'une colonne | Souvent non |
| Ajouter une contrainte d'unicité | Dépend des données existantes et des écritures en cours |

Le piège propre aux ORM : un ORM liste toutes les colonnes mappées dans ses `SELECT`. Supprimer une colonne que ton code « n'utilise plus » casse quand même toutes les requêtes sur la table si l'entité la mappe encore. Rails propose `ignored_columns` précisément pour retirer une colonne du mapping **avant** de la supprimer.

Les changements incompatibles ne sont pas interdits : il faut les **découper**.

---

## 🔀 Expand / contract : changer le schéma sans interruption

Le pattern s'appelle aussi *parallel change* (Danilo Sato, bliki de martinfowler.com, 2014) ; c'est la mise en œuvre de la « période de transition » d'Ambler et Sadalage. Trois phases :

1. **Expand** : ajouter la nouvelle structure à côté de l'ancienne, sans rien casser.
2. **Migrate** : copier les données, faire basculer le code, lecture puis écriture.
3. **Contract** : supprimer l'ancienne structure quand plus rien ne l'utilise.

Chaque étape est **compatible avec le code avant et après elle**, et **réversible isolément**.

### Exemple complet : renommer `projects.title` en `name` (PostgreSQL)

Un simple `ALTER TABLE projects RENAME COLUMN title TO name` est instantané en PostgreSQL, et casse immédiatement chaque instance qui exécute encore `SELECT title`. Voici la version sans interruption. Ce script a été exécuté sur PostgreSQL 16 ; il reste illustratif pour ton propre projet.

**Migration 1 (expand)** : nouvelle colonne facultative et synchronisation dans les deux sens.

```sql
ALTER TABLE projects ADD COLUMN name text;   -- facultative : instantané, rien ne casse

CREATE FUNCTION projects_sync_title_name() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.name  := coalesce(NEW.name, NEW.title);
    NEW.title := coalesce(NEW.title, NEW.name);
  ELSIF NEW.title IS DISTINCT FROM OLD.title THEN
    NEW.name := NEW.title;
  ELSIF NEW.name IS DISTINCT FROM OLD.name THEN
    NEW.title := NEW.name;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER projects_sync_title_name
  BEFORE INSERT OR UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION projects_sync_title_name();
```

Le trigger `BEFORE` remplit la colonne manquante **avant** la vérification des contraintes : l'ancien code (qui n'écrit que `title`) et le nouveau (qui n'écrit que `name`) peuvent écrire en même temps.

**Migration 2 (migrate)** : remplir les lignes existantes, par lots, pour ne pas verrouiller la table d'un coup.

```sql
-- à répéter jusqu'à ce qu'aucune ligne ne soit modifiée
UPDATE projects SET name = title
WHERE id IN (SELECT id FROM projects WHERE name IS NULL ORDER BY id LIMIT 5000);
```

**Migration 3 (migrate)** : rendre `name` obligatoire et `title` facultative, sans verrou long.

```sql
SET lock_timeout = '3s';
ALTER TABLE projects ADD CONSTRAINT projects_name_not_null CHECK (name IS NOT NULL) NOT VALID;
ALTER TABLE projects VALIDATE CONSTRAINT projects_name_not_null;  -- n'empêche pas les écritures
ALTER TABLE projects ALTER COLUMN name SET NOT NULL;               -- PG 12+ : pas de scan grâce au CHECK
ALTER TABLE projects DROP CONSTRAINT projects_name_not_null;
ALTER TABLE projects ALTER COLUMN title DROP NOT NULL;
```

**Déploiement du code v2** : lit et écrit `name`. Pendant le déploiement, v1 et v2 cohabitent ; le trigger les réconcilie.

**Migration 4 (contract)**, une fois **plus aucune** instance v1 en service **et** la fenêtre de retour arrière vers v1 passée :

```sql
DROP TRIGGER projects_sync_title_name ON projects;
DROP FUNCTION projects_sync_title_name();
```

**Migration 5 (contract)** :

```sql
ALTER TABLE projects DROP COLUMN title;
```

| Étape | Code en service | Retour arrière de l'étape |
|---|---|---|
| M1 expand | v1 | `DROP TRIGGER`, `DROP FUNCTION`, `DROP COLUMN name` : sans perte, `title` reste la source |
| M2 backfill | v1 | rien à faire : `name` sera supprimée avec M1 |
| M3 contraintes | v1 | rétablir `title NOT NULL`, retirer celle de `name` |
| déploiement v2 | v1 + v2, puis v2 | redéployer v1 : le trigger maintient `title` à jour |
| M4 fin de synchro | v2 | recréer le trigger |
| M5 suppression | v2 | `ADD COLUMN title` puis `UPDATE projects SET title = name` : reconstructible, car `name` contient tout |

Ce que montre ce tableau : le **seul** moment où un retour arrière devient coûteux est le *contract*, et il arrive quand on a cessé d'en avoir besoin. C'est tout l'intérêt du découpage. Le kata 5 déroule la même idée sous SQLite, où les triggers ne peuvent pas modifier `NEW` : il faut alors une version intermédiaire du code qui écrit les deux colonnes.

### Verrous et opérations coûteuses (PostgreSQL)

Le danger d'une migration en production n'est souvent pas l'échec, mais le **verrou**. Un `ALTER TABLE` qui attend un verrou exclusif se met dans la file d'attente… et **toutes** les requêtes suivantes sur la table attendent derrière lui. Une migration bloquée trente secondes derrière une longue requête de reporting suffit à rendre un site indisponible. D'où `SET lock_timeout = '3s'` : mieux vaut une migration qui échoue (et qu'on relance) qu'une file d'attente qui bloque tout.

| Opération | Risque | Alternative sûre |
|---|---|---|
| `ADD COLUMN` facultative | aucun (métadonnées seules) | |
| `ADD COLUMN … DEFAULT constante` | aucun depuis PG 11 | un défaut **volatil** (`random()`, `clock_timestamp()`) réécrit encore la table |
| `SET NOT NULL` | scan complet sous verrou exclusif | `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE`, puis `SET NOT NULL` (PG 12+) |
| `CREATE INDEX` | bloque les écritures pendant la construction | `CREATE INDEX CONCURRENTLY`, hors transaction ; en cas d'échec, supprimer l'index `INVALID` laissé derrière |
| `ADD FOREIGN KEY` | scan des deux tables | `ADD CONSTRAINT … NOT VALID`, puis `VALIDATE CONSTRAINT` |
| `ALTER COLUMN TYPE` | réécriture complète sous verrou exclusif (sauf conversions binaires compatibles) | nouvelle colonne + backfill + bascule (expand/contract) |
| `RENAME COLUMN` | instantané… et casse le code en service | expand/contract |

Côté MySQL : `ALGORITHM=INSTANT` couvre certains ajouts de colonne depuis la 8.0 ; pour le reste, des outils comme **gh-ost** (GitHub) ou **pt-online-schema-change** (Percona) copient la table en arrière-plan et basculent à la fin.

Conséquence pour les moteurs de migrations : une migration contenant `CREATE INDEX CONCURRENTLY` doit être déclarée **non transactionnelle**, sinon PostgreSQL la refuse (`cannot run inside a transaction block`).

---

## 🧪 Données : migrations de données, backfill, seeds, fixtures

### Migration de schéma ≠ migration de données

- Une **migration de schéma** change la structure : rapide (souvent), transactionnelle (selon le SGBD), facile à relire.
- Une **migration de données** transforme le contenu : sa durée dépend du volume, elle peut verrouiller longtemps, et elle est souvent irréversible.

Les séparer en fichiers distincts permet de les déployer, chronométrer et annuler séparément.

Piège classique : utiliser les **modèles de l'ORM** dans une migration de données. Le modèle évolue avec le code ; la migration, elle, est figée dans le temps. Dans six mois, le modèle `Project` n'aura plus de champ `title`, et la migration qui l'utilisait ne pourra plus être rejouée sur une base neuve. Solutions : écrire du SQL, ou utiliser le modèle **historique** que fournit l'outil (Django : `apps.get_model('atelier', 'Project')` dans une `RunPython`).

### Backfill par lots

Un `UPDATE` sur des millions de lignes dans une seule transaction verrouille ces lignes jusqu'au bout, gonfle le journal et, s'il échoue à 95 %, recommence à zéro. Un backfill robuste est :

- **par lots** : une transaction courte par lot (quelques milliers de lignes) ;
- **à curseur sur la clé primaire** (`WHERE id > :dernier ORDER BY id LIMIT :n`) plutôt qu'à `OFFSET`, qui relit tout le début à chaque lot ;
- **idempotent** : il ne touche que les lignes pas encore traitées, donc on peut le relancer sans risque ;
- **reprenable** : il sait repartir du dernier curseur ;
- **temporisé** si besoin, pour laisser respirer la base et la réplication.

Il tourne souvent **hors** du moteur de migrations (tâche dédiée), parce qu'il peut durer des heures et qu'on ne veut pas bloquer le déploiement. Le kata 6 en écrit un.

### Seeds et fixtures

- **Seeds** : données insérées pour qu'un environnement soit utilisable (comptes de démo, jeu d'exemple). Ils doivent être idempotents (`INSERT … ON CONFLICT DO NOTHING`). Exemples : `prisma db seed`, `knex seed:run`, `php artisan db:seed`, `bin/rails db:seed`.
- **Fixtures** : données de test, recréées pour chaque test et jetées ensuite (voir module 06).
- **Données de référence** dont le code a besoin pour fonctionner (liste de pays, rôles autorisés) : elles relèvent des **migrations**, pas des seeds. Sans elles, la base n'est pas dans un état valide, quel que soit l'environnement.

### Compacter l'historique

Après des années, rejouer 800 migrations pour créer une base de test prend du temps et finit par échouer (une vieille migration dépend d'une extension disparue). Options :

- **Charger un instantané du schéma** au lieu de rejouer l'historique : Rails le fait avec `db/schema.rb` ou `structure.sql` (`bin/rails db:schema:load`) ;
- **Fusionner** des migrations : Django `squashmigrations` ;
- **Repartir d'une ligne de base** (*baseline*) : une migration initiale qui décrit l'état actuel, marquée comme appliquée sur les bases existantes (Flyway `baseline`, Prisma `migrate resolve --applied 0_init`).

---

## 🪨 SQLite et ses `ALTER TABLE` limités

Nos exemples tournent sur SQLite (3.50 dans Node 22.22), qui ne sait faire que quatre choses avec `ALTER TABLE` :

| Opération | Depuis | Restrictions principales |
|---|---|---|
| `RENAME TO` (table) | toujours | |
| `RENAME COLUMN` | 3.25 (2018) | |
| `ADD COLUMN` | toujours | pas de `UNIQUE` ni `PRIMARY KEY` ; `NOT NULL` exige un défaut non nul ; défaut constant uniquement |
| `DROP COLUMN` | 3.35 (2021) | impossible si la colonne est indexée, clé primaire, `UNIQUE`, utilisée par une clé étrangère, une vue ou un trigger |

Les messages sont explicites (`Cannot add a UNIQUE column`, `error in index … after drop column`). Pour tout le reste (changer un type, ajouter une contrainte `CHECK`, retirer un `NOT NULL`), la documentation SQLite décrit une **procédure de reconstruction** :

1. désactiver les clés étrangères (`PRAGMA foreign_keys = OFF`) **hors transaction** ;
2. ouvrir une transaction ;
3. mémoriser les index, triggers et vues de la table ;
4. créer `new_X` avec le schéma voulu ;
5. copier : `INSERT INTO new_X SELECT … FROM X` ;
6. `DROP TABLE X` ;
7. `ALTER TABLE new_X RENAME TO X` ;
8. recréer index, triggers et vues ;
9. vérifier l'intégrité : `PRAGMA foreign_key_check` ;
10. valider la transaction ;
11. réactiver les clés étrangères.

L'étape 1 n'est pas une formalité. Avec les clés étrangères actives, `DROP TABLE projects` exécute un `DELETE FROM projects` implicite **qui déclenche les `ON DELETE CASCADE`** : sur le fil rouge, une reconstruction naïve de `projects` vide entièrement `contributions` (10 → 0 lignes) et `project_tags` (9 → 0), sans aucune erreur. Et comme `PRAGMA foreign_keys` est sans effet dans une transaction, le moteur de migrations doit permettre de lancer ce type de migration **hors transaction**. Le kata 4 te le fait constater.

Les ORM le font pour toi sur SQLite (les migrations générées par Prisma contiennent un bloc commenté `-- RedefineTables`, par exemple). Raison de plus pour **lire** ce qu'ils génèrent.

---

## ✅ Checklist d'une bonne migration

- [ ] **Une intention par migration** : un nom qui la dit (`add_members_bio`, pas `update_db`)
- [ ] **Jamais modifiée après application** hors de ta machine : on en écrit une nouvelle
- [ ] **Le SQL généré a été relu**, en particulier les renommages, suppressions et reconstructions
- [ ] **Compatible avec le code en service et le code à venir** ; sinon, découpée en expand/contract
- [ ] **Réversible, ou explicitement irréversible** ; un `down` destructeur est signalé
- [ ] **Testée en aller-retour** en CI : `up` → `down` → `up` produit le même schéma
- [ ] **Répétée sur une copie des données de production** quand elle touche beaucoup de lignes ou prend des verrous
- [ ] **Durée et verrous estimés** ; `lock_timeout` positionné en PostgreSQL
- [ ] **Migration de données séparée** de la migration de schéma, sans les modèles de l'ORM
- [ ] **Sauvegarde récente et restauration testée** avant toute migration destructrice

La documentation de chaque migration (en-tête : intention, réversibilité, risques) et le *runbook* de retour arrière sont traités dans le [module 05](../05-documenter/notes.md).

---

## ⚠️ Pièges fréquents

1. **Modifier une migration déjà appliquée** : la production et les nouvelles bases divergent silencieusement. Le checksum est là pour ça.
2. **Croire que `down` = sauvegarde** : il restaure une forme, pas des données.
3. **Faire confiance au SQL généré** : un renommage peut devenir une suppression suivie d'un ajout.
4. **Lancer les migrations au démarrage de chaque instance** : courses, verrous, déploiements bloqués. Une étape dédiée est plus sûre.
5. **Supprimer une colonne encore mappée par l'ORM** : toutes les requêtes sur la table cassent.
6. **Plusieurs DDL par migration sous MySQL** : un échec laisse un état partiel non enregistré.
7. **Un `UPDATE` géant dans une seule transaction** : verrous, journal saturé, reprise impossible.
8. **Reconstruire une table SQLite avec les FK actives** : les cascades vident les tables filles.
9. **Utiliser les modèles de l'ORM dans une migration de données** : elle ne sera plus rejouable quand le modèle aura changé.
10. **Utiliser `db push` en production** : aucun historique, aucune revue, renommages ambigus.

---

## 🔗 Liens avec les autres modules

- [01 — Fondamentaux](../01-fondamentaux/notes.md) : la table d'historique et le moteur sont un bon exemple de *Table Data Gateway* ; le mapping explique pourquoi supprimer une colonne mappée casse tout.
- [02 — SQL brut, query builder, ORM](../02-sql-query-builder-orm/notes.md) : migrations en SQL brut, via l'API de schéma d'un query builder (Knex) ou générées par un ORM (Prisma) : les mêmes trois niveaux d'abstraction.
- [04 — Modélisation](../04-modelisation-merise-uml-erd/notes.md) : le MPD (modèle physique) est exactement ce que la suite des migrations construit ; chaque évolution du MCD se traduit en migrations.
- [05 — Documenter](../05-documenter/notes.md) : en-têtes de migration, changelog du schéma, *runbook* de retour arrière, ADR pour les changements structurants.
- [06 — Concepts avancés](../06-concepts-avances/notes.md) : transactions et niveaux d'isolation côté application, verrous, tests avec une base réelle construite par les migrations.

---

## 📚 Pour aller plus loin

- **S. Ambler, P. Sadalage**, *Refactoring Databases: Evolutionary Database Design*, 2006. Le catalogue des refactorings de schéma et la notion de période de transition.
- **P. Sadalage, M. Fowler**, « Evolutionary Database Design », martinfowler.com, 2003 (révisé en 2016).
- **D. Sato**, « ParallelChange », bliki de martinfowler.com, 2014. Le pattern expand/contract formulé en général.
- **M. Kleppmann**, *Designing Data-Intensive Applications*, 2017, chapitre 4 (« Encoding and Evolution ») : compatibilité ascendante et descendante entre versions du code et des données.
- **Documentation PostgreSQL** : chapitre « ALTER TABLE », notes sur les niveaux de verrouillage (*Explicit Locking*) et sur l'archivage continu / PITR.
- **Documentation SQLite** : page « ALTER TABLE », section « Making Other Kinds Of Table Schema Changes ».
- **Documentation Prisma** : « Generating down migrations », « Patching & hotfixing », « Baselining ».

---

**Dernière mise à jour** : 2026-10-29
**Niveau** : Intermédiaire → Avancé
**Prérequis** : SQL de base, module 01
