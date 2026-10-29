# 🧠 Flashcards : Migrations

## Définitions

### Q: Qu'est-ce qu'une migration ?
<details><summary>R</summary>

Un script qui transforme le schéma (et parfois les données) d'une base, **versionné** avec le code, **ordonné**, **appliqué une seule fois par base** et **rejouable** : la même suite appliquée à une base vide produit le même schéma partout.

</details>

### Q: Pourquoi versionner des transformations plutôt qu'un dump du schéma ?
<details><summary>R</summary>

Parce qu'une base contient des données qu'on ne peut pas jeter. Un dump décrit un état, pas le chemin pour passer d'un état à l'autre en conservant les données. Le schéma actuel est **dérivé** de la suite des migrations.

</details>

### Q: Qu'est-ce qu'un « refactoring de base de données » selon Ambler et Sadalage ?
<details><summary>R</summary>

Une petite modification du schéma qui améliore sa conception en préservant sa sémantique comportementale et informationnelle. Leur idée clé : une **période de transition** où ancien et nouveau schéma coexistent.

</details>

### Q: Que contient la table d'historique d'un moteur de migrations ?
<details><summary>R</summary>

Au minimum la version de chaque migration appliquée. Les bons moteurs ajoutent le nom, la date et un **checksum** du fichier. Exemples : `_prisma_migrations`, `knex_migrations`, `SequelizeMeta`, `schema_migrations`, `flyway_schema_history`, `DATABASECHANGELOG`.

</details>

## Mécanique du moteur

### Q: À quoi sert le checksum d'une migration ?
<details><summary>R</summary>

À détecter qu'un fichier a été **modifié après application**. Sans lui, la production (qui a exécuté l'ancienne version) et une base neuve (qui exécutera la nouvelle) divergent silencieusement.

</details>

### Q: Pourquoi la migration et sa ligne d'historique doivent-elles être dans la même transaction ?
<details><summary>R</summary>

Pour que les deux soient écrites ou qu'aucune ne le soit. Sinon : migration appliquée mais non enregistrée (rejouée, elle échoue), ou enregistrée mais à moitié appliquée (jamais terminée).

</details>

### Q: Pourquoi un moteur de migrations prend-il un verrou ?
<details><summary>R</summary>

Pour que deux processus (par exemple deux instances qui démarrent en même temps) n'appliquent pas la même migration deux fois. Table de verrou (Knex, Liquibase), *advisory lock* PostgreSQL (Prisma), `BEGIN IMMEDIATE` en SQLite. Il faut **revérifier sous le verrou** que la migration est toujours en attente.

</details>

### Q: Séquence (`001`) ou horodatage (`20261029120000`) : quel compromis ?
<details><summary>R</summary>

Séquence : ordre lisible, mais collisions entre branches (deux `004`). Horodatage : pas de collision de nom, mais l'ordre de création n'est plus l'ordre de fusion, donc une migration « ancienne » peut arriver après une plus récente et s'appliquer dans des ordres différents selon l'environnement.

</details>

### Q: Comment Flyway, Rails et Django réagissent-ils à une migration en attente antérieure à la dernière appliquée ?
<details><summary>R</summary>

Flyway refuse par défaut (`outOfOrder=false`). Rails l'applique silencieusement. Django modélise un graphe de dépendances et exige une migration de fusion (`makemigrations --merge`).

</details>

## Philosophies

### Q: Migrations versionnées vs déclaratives ?
<details><summary>R</summary>

**Versionnées** : tu écris les étapes, l'outil les applique (Knex, Flyway, Rails). **Déclaratives** : tu décris l'état voulu, l'outil calcule le diff (Atlas `schema apply`, `prisma db push`, `drizzle-kit push`). **Hybrides** : l'outil génère depuis un diff un fichier versionné que tu relis (`prisma migrate dev`, `drizzle-kit generate`, Django `makemigrations`).

</details>

### Q: Quelle information un diff de schéma ne peut-il pas connaître ?
<details><summary>R</summary>

L'**intention**. Si `title` disparaît et `name` apparaît, renommage (données conservées) et suppression + ajout (données perdues) aboutissent au même état final. D'où l'obligation de relire le SQL généré.

</details>

### Q: Qu'est-ce que la dérive (*drift*) ?
<details><summary>R</summary>

Un écart entre la base réelle et ce que décrit l'historique des migrations, typiquement après un changement fait à la main. Remède : même un hotfix passe par une migration, marquée comme appliquée sur la base concernée.

</details>

## Revenir en arrière

### Q: Quelles sont les trois choses que l'on appelle « rollback » ?
<details><summary>R</summary>

1. Annuler une migration qui **échoue** en cours de route → transaction.
2. Dé-appliquer une migration **réussie** → `down`.
3. Revenir à un état antérieur des **données** → sauvegarde, PITR.

</details>

### Q: Pourquoi un `down` ne remplace-t-il pas une sauvegarde ?
<details><summary>R</summary>

Il restaure une **forme**, pas un **contenu**. Après un `DROP COLUMN`, le `down` recrée la colonne vide.

</details>

### Q: Dans quel ordre écrire les opérations d'un `down` ?
<details><summary>R</summary>

Dans l'ordre **inverse** de l'`up`. Si l'`up` crée une colonne puis un index dessus, le `down` supprime l'index puis la colonne (sinon le `DROP COLUMN` échoue).

</details>

### Q: Donne trois façons pour un `down` de « mentir ».
<details><summary>R</summary>

1. Il détruit ce qui a été écrit depuis l'`up` (`ADD COLUMN` → `DROP COLUMN`).
2. Il recrée une structure vide (l'`up` supprime une colonne, le `down` la recrée avec un défaut).
3. Il inverse une transformation non injective (`draft → archived` ne permet plus de savoir ce qui était archivé avant).

</details>

### Q: Comment déclarer une migration irréversible ?
<details><summary>R</summary>

Rails : `raise ActiveRecord::IrreversibleMigration`. Doctrine : `$this->throwIrreversibleMigrationException()`. Django : `RunPython` sans `reverse_code` lève `IrreversibleError`. Dans le moteur du kata : ne pas exporter de `down`.

</details>

### Q: Knex : différence entre `migrate:rollback` et `migrate:down` ?
<details><summary>R</summary>

`migrate:rollback` annule le dernier **batch** (tout ce qu'un `migrate:latest` a appliqué d'un coup). `migrate:down` annule la **dernière migration** seule.

</details>

### Q: Comment Prisma gère-t-il le retour arrière ?
<details><summary>R</summary>

Pas de `down` natif. Pour une migration réussie : revenir dans `schema.prisma` et générer une **nouvelle** migration. Pour se préparer à un échec : générer un `down.sql` avec `prisma migrate diff … --script`, l'exécuter avec `prisma db execute`, puis `prisma migrate resolve --rolled-back <nom>` (qui ne modifie que l'historique, et seulement pour une migration en échec).

</details>

### Q: Rails : comment annuler les deux dernières migrations ?
<details><summary>R</summary>

`bin/rails db:rollback STEP=2`. Pour une version précise : `bin/rails db:migrate:down VERSION=…`.

</details>

### Q: Django : comment annuler toutes les migrations d'une application ?
<details><summary>R</summary>

`python manage.py migrate nom_app zero`. Pour revenir à une migration précise : `python manage.py migrate nom_app 0003`.

</details>

### Q: Quels SGBD savent annuler du DDL dans une transaction ?
<details><summary>R</summary>

PostgreSQL (presque tout, sauf `CREATE INDEX CONCURRENTLY` et quelques autres), SQLite, SQL Server. **Pas** MySQL/MariaDB ni Oracle : chaque DDL provoque un commit implicite.

</details>

### Q: Quelle règle adopter sous MySQL, et pourquoi ?
<details><summary>R</summary>

**Une instruction DDL par migration.** Comme chaque DDL est validé implicitement, une migration de trois instructions qui échoue à la deuxième laisse un état partiel non enregistré. Avec une instruction par migration, le point d'échec coïncide avec une frontière de migration.

</details>

### Q: Qu'est-ce que le roll-forward, et pourquoi le préfère-t-on en production ?
<details><summary>R</summary>

Corriger par une **nouvelle** migration plutôt qu'exécuter un `down`. Le `down` est rarement testé sur des données réelles, détruit souvent ce qui a été écrit depuis, et une nouvelle migration passe par la même revue et la même CI.

</details>

### Q: Quand un `down` en production est-il raisonnable ?
<details><summary>R</summary>

Quand la migration vient d'être appliquée, qu'elle est purement additive et qu'**aucun code ne l'utilise encore**.

</details>

### Q: Qu'est-ce que la PITR, et comment s'en servir sans tout perdre ?
<details><summary>R</summary>

*Point-in-time recovery* : restaurer la base à un instant précis (en PostgreSQL : sauvegarde de base + archivage du WAL). Restaurer toute la base efface les écritures légitimes postérieures ; on restaure plutôt dans une **instance séparée** pour en extraire les données perdues.

</details>

## Zéro-downtime

### Q: Quelle règle de compatibilité doit respecter chaque migration ?
<details><summary>R</summary>

Rester compatible avec le code **en service** et avec le code **qui va le remplacer** (et idéalement celui vers lequel on pourrait revenir) : pendant un déploiement progressif, les versions N et N+1 tournent sur le même schéma.

</details>

### Q: Pourquoi supprimer une colonne « inutilisée » peut-il casser une application avec ORM ?
<details><summary>R</summary>

Parce que l'ORM liste toutes les colonnes **mappées** dans ses `SELECT`. Si l'entité mappe encore la colonne, toutes les requêtes sur la table échouent. Rails propose `ignored_columns` pour retirer la colonne du mapping avant de la supprimer.

</details>

### Q: Quelles sont les trois phases d'expand/contract ?
<details><summary>R</summary>

1. **Expand** : ajouter la nouvelle structure à côté de l'ancienne (et synchroniser).
2. **Migrate** : copier les données, basculer les lectures puis les écritures.
3. **Contract** : supprimer l'ancienne structure quand plus rien ne l'utilise.

</details>

### Q: Pourquoi `SET lock_timeout` avant une migration PostgreSQL ?
<details><summary>R</summary>

Un `ALTER TABLE` qui attend un verrou exclusif bloque **toutes** les requêtes arrivées après lui sur la table. Mieux vaut une migration qui échoue vite (et qu'on relance) qu'une file d'attente qui rend le site indisponible.

</details>

### Q: Comment ajouter `NOT NULL` sur une grosse table PostgreSQL sans long verrou ?
<details><summary>R</summary>

```sql
ALTER TABLE t ADD CONSTRAINT c CHECK (col IS NOT NULL) NOT VALID;
ALTER TABLE t VALIDATE CONSTRAINT c;        -- n'empêche pas les écritures
ALTER TABLE t ALTER COLUMN col SET NOT NULL; -- PG 12+ : pas de scan
ALTER TABLE t DROP CONSTRAINT c;
```

</details>

### Q: Quelle contrainte impose `CREATE INDEX CONCURRENTLY` au moteur de migrations ?
<details><summary>R</summary>

Il ne peut pas s'exécuter dans une transaction : la migration doit être déclarée **non transactionnelle**. En cas d'échec, il laisse un index `INVALID` à supprimer.

</details>

## Données

### Q: Pourquoi ne pas utiliser les modèles de l'ORM dans une migration de données ?
<details><summary>R</summary>

Le modèle évolue avec le code, la migration est figée dans le temps. Quand le modèle aura perdu le champ utilisé, la migration ne sera plus rejouable. Écrire du SQL, ou utiliser le modèle **historique** fourni par l'outil (Django : `apps.get_model`).

</details>

### Q: Quatre propriétés d'un backfill robuste ?
<details><summary>R</summary>

**Par lots** (transactions courtes), **à curseur sur la clé primaire** (pas d'`OFFSET`), **idempotent** (ne touche que les lignes non traitées), **reprenable** (repart du dernier curseur).

</details>

### Q: Seeds, fixtures, données de référence : où va quoi ?
<details><summary>R</summary>

**Seeds** : données pour rendre un environnement utilisable (démo), idempotentes. **Fixtures** : données de test, jetables. **Données de référence** dont le code a besoin (rôles, pays) : dans les **migrations**.

</details>

## SQLite

### Q: Quelles opérations `ALTER TABLE` SQLite sait-il faire ?
<details><summary>R</summary>

`RENAME TO`, `RENAME COLUMN` (3.25+), `ADD COLUMN` (sans `UNIQUE`/`PRIMARY KEY`, défaut constant), `DROP COLUMN` (3.35+, colonne non indexée, non `UNIQUE`, hors FK, vues et triggers). Tout le reste passe par une reconstruction de table.

</details>

### Q: Quel est le piège de la reconstruction d'une table SQLite ?
<details><summary>R</summary>

Avec les clés étrangères actives, `DROP TABLE` exécute un `DELETE` implicite qui déclenche les `ON DELETE CASCADE` : les tables filles sont vidées sans erreur. Il faut `PRAGMA foreign_keys = OFF` **hors transaction** (à l'intérieur, il est sans effet), puis `PRAGMA foreign_key_check` avant le commit.

</details>

### Q: Que faut-il recréer après `DROP TABLE` + `RENAME` lors d'une reconstruction ?
<details><summary>R</summary>

Les **index**, **triggers** et **vues** de la table : `DROP TABLE` les emporte. On les lit dans `sqlite_schema` avant de commencer.

</details>

---

**Cartes** : 38 · **Dernière mise à jour** : 2026-10-29 · **Niveau** : Intermédiaire → Avancé
