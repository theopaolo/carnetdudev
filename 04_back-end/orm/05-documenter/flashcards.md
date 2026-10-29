# 🧠 Flashcards : Documenter un ORM

## Le problème

### Q: Pourquoi le schéma ne suffit-il pas à documenter une couche ORM ?
<details><summary>R</summary>

Il donne la **structure** (types, clés, contraintes), mais pas le **sens** (ce que la valeur représente), ni les **règles hors schéma** (hooks, filtres, validations applicatives), ni les **raisons** des choix.

</details>

### Q: Cite les cinq endroits où vit la vérité dans un projet avec ORM.
<details><summary>R</summary>

La base (schéma appliqué), le schéma ORM / les entités, les migrations, le code applicatif (services, hooks, repositories), les seeds / fixtures.

</details>

### Q: Quel est le fait le plus important à documenter dans une couche ORM ?
<details><summary>R</summary>

Une règle appliquée par l'ORM ou l'application est contournée par tout ce qui n'est pas l'ORM : SQL brut, scripts, migrations de données, autres services. Il faut documenter qui applique chaque règle.

</details>

### Q: Pourquoi Prisma `@updatedAt` ou `@default(uuid())` sont-ils des comportements cachés ?
<details><summary>R</summary>

Ces valeurs sont générées par Prisma, pas par la base. Elles n'apparaissent pas dans le DDL, et un INSERT ou UPDATE en SQL brut ne les applique pas.

</details>

### Q: Qu'est-ce qu'une action référentielle émulée ?
<details><summary>R</summary>

Une cascade ou une restriction appliquée par l'ORM au lieu de la base (par exemple Prisma avec `relationMode = "prisma"`). Il n'y a pas de clé étrangère en base, donc le SQL brut ne propage et ne bloque rien.

</details>

### Q: Donne trois exemples de filtres globaux d'ORM.
<details><summary>R</summary>

Sequelize `paranoid: true`, Eloquent `SoftDeletes` et les *global scopes*, les filtres Doctrine. La ligne existe en base mais l'ORM ne la renvoie pas.

</details>

## Les cinq couches

### Q: Quelles sont les cinq couches à documenter ?
<details><summary>R</summary>

1. **Modèle** : que signifie la donnée ? (dictionnaire)
2. **Mapping** : comment le code voit la table, quelles règles il ajoute (fiche d'entité)
3. **Évolution** : pourquoi c'est comme ça (migrations, ADR)
4. **Usage** : comment requêter correctement (guide pratique)
5. **Exploitation** : migrer, annuler, restaurer (runbook)

</details>

### Q: Que doit contenir la description d'une colonne ?
<details><summary>R</summary>

Sens métier, format / unité / fuseau, domaine de valeurs, qui l'écrit, invariants non contraints, sensibilité (RGPD), écarts connus.

</details>

### Q: Quel critère permet de repérer un commentaire-paraphrase ?
<details><summary>R</summary>

S'il se déduit du nom de la colonne, il n'apporte rien : on le supprime ou on le réécrit.

</details>

### Q: Pourquoi « Identifiant unique, jamais réutilisé » est-il faux pour `id INTEGER PRIMARY KEY` en SQLite ?
<details><summary>R</summary>

Sans `AUTOINCREMENT`, SQLite attribue max(rowid) + 1. Si la dernière ligne est supprimée, son identifiant est réattribué à la suivante.

</details>

### Q: Quelle colonne est décisive dans une fiche d'entité ?
<details><summary>R</summary>

« Qui l'applique ? » (base, ORM ou application), et sa conséquence, « Contourné par ».

</details>

### Q: Pourquoi le schéma Prisma n'est-il pas la source de vérité complète ?
<details><summary>R</summary>

Il ne sait pas exprimer certaines choses, comme un `CHECK` : celui-ci n'existe que dans la migration SQL écrite à la main. Le schéma ORM décrit l'intention du code, la base décrit ce qui est appliqué.

</details>

## Évolution : migrations et ADR

### Q: Que contient un en-tête de migration utile ?
<details><summary>R</summary>

Nom explicite, intention (avec ticket), réversibilité (et perte éventuelle), risques (verrous, durée, volume), séquence expand/contract et migrations liées, requête de vérification.

</details>

### Q: Quelle idée d'Ambler et Sadalage le champ « Séquence » reprend-il ?
<details><summary>R</summary>

La **période de transition** : un changement incompatible passe par une phase où l'ancien et le nouveau schéma coexistent. Elle doit être écrite, avec une date de retrait prévue, sinon elle devient permanente.

</details>

### Q: Qu'est-ce qu'un ADR ?
<details><summary>R</summary>

*Architecture Decision Record* (Michael Nygard, 2011) : un fichier court, numéroté et versionné, par décision structurante.

</details>

### Q: Quelles rubriques Nygard propose-t-il ?
<details><summary>R</summary>

Titre, contexte, décision, statut, conséquences. Beaucoup d'équipes placent le statut juste sous le titre.

</details>

### Q: Que fait-on quand une décision documentée par un ADR change ?
<details><summary>R</summary>

On ne réécrit pas l'ADR accepté. On en écrit un nouveau, et l'ancien passe en « remplacé par ADR-00XX ».

</details>

### Q: À quoi reconnaît-on un ADR mal pensé ?
<details><summary>R</summary>

Aucune alternative écartée dans le contexte, aucune conséquence négative. Un ADR qui n'a que des ✅ n'a pas été pensé jusqu'au bout.

</details>

### Q: Cite quatre décisions de couche de données qui méritent un ADR.
<details><summary>R</summary>

Type d'identifiant (entier, UUID, ULID), soft delete ou non, stockage des dates, n-n implicite ou explicite, emplacement du SQL brut, stratégie multi-tenant, choix de l'ORM.

</details>

## Principes

### Q: Énonce le principe de la source unique.
<details><summary>R</summary>

Chaque information s'écrit à un seul endroit. Partout ailleurs, elle est générée ou référencée par un lien.

</details>

### Q: Depuis quoi générer la documentation de référence : la base ou le schéma ORM ?
<details><summary>R</summary>

Depuis la **base migrée** : elle contient ce qui est réellement appliqué, y compris les `CHECK`, triggers et index ajoutés à la main que le schéma ORM ignore.

</details>

### Q: Quelles sont les trois vérifications « docs as code » en CI ?
<details><summary>R</summary>

La doc est **à jour** (régénérer et comparer), **complète** (linter des descriptions), et le schéma **respecte les conventions documentées**.

</details>

### Q: Pourquoi ne jamais mettre « généré le … » dans un fichier de doc généré ?
<details><summary>R</summary>

Le fichier différerait à chaque exécution : le contrôle « la doc est à jour » échouerait toujours, et n'aurait donc plus aucune valeur. La génération doit être déterministe.

</details>

### Q: Quels sont les quatre types de Diátaxis ?
<details><summary>R</summary>

Tutoriel (apprendre en faisant), guide pratique (accomplir une tâche), référence (consulter un fait), explication (comprendre le pourquoi).

</details>

### Q: Où ranger, selon Diátaxis : le dictionnaire de données, un ADR, un runbook ?
<details><summary>R</summary>

Dictionnaire : référence. ADR : explication. Runbook : guide pratique.

</details>

## Outils

### Q: Différence entre `//` et `///` dans `schema.prisma` ?
<details><summary>R</summary>

`//` est un commentaire pour le lecteur, ignoré par l'outillage. `///` est attaché au nœud suivant de l'arbre syntaxique et exposé comme sa description, donc lisible par les générateurs.

</details>

### Q: Comment documenter une colonne en PostgreSQL ?
<details><summary>R</summary>

```sql
COMMENT ON COLUMN projects.status IS 'draft | active | archived';
```

Dans une migration, pour qu'il soit versionné. On le relit avec `\d+ projects` ou `col_description()`.

</details>

### Q: Pourquoi les commentaires en base sont-ils l'emplacement le plus durable ?
<details><summary>R</summary>

La base survit à l'ORM. Tous les clients (psql, DBeaver, BI, tbls, SchemaSpy) lisent les commentaires en base ; aucun ne lit les commentaires d'un schéma ORM.

</details>

### Q: Quelles options pour documenter des colonnes en SQLite ?
<details><summary>R</summary>

Commentaires dans le `CREATE TABLE` (conservés dans `sqlite_schema.sql`, mais fragiles à parser), table de métadonnées maison, fichier de descriptions versionné (comme `comments:` de tbls), contrôlé par un linter.

</details>

### Q: Pourquoi un commentaire `--` casse-t-il un `ALTER TABLE ADD COLUMN` en SQLite ?
<details><summary>R</summary>

SQLite insère le texte de la nouvelle colonne juste avant la parenthèse finale du `CREATE TABLE` stocké. Le `--` commente cette parenthèse : « incomplete input ». Un commentaire `/* … */` passe.

</details>

### Q: Que font `tbls doc`, `tbls diff` et `tbls lint` ?
<details><summary>R</summary>

`doc` génère la documentation Markdown + ERD depuis la base. `diff` compare la base et la doc commitée. `lint` vérifie des règles (`requireColumnComment`, `requireForeignKeyIndex`, etc.).

</details>

### Q: À quoi sert SchemaSpy, et pourquoi convient-il moins à la CI que tbls ?
<details><summary>R</summary>

Il produit un rapport HTML navigable d'une base existante, avec diagrammes et anomalies (index manquants, relations implicites, tables orphelines). Idéal pour découvrir une base héritée, mais sa sortie HTML ne se compare pas facilement en *diff*.

</details>

### Q: Pourquoi un ERD en Mermaid plutôt qu'en PNG ?
<details><summary>R</summary>

Texte : il se relit en *diff*, se régénère par script et se rend directement sur GitHub. Un PNG exporté est faux dès la migration suivante.

</details>

### Q: Que perd un ERD déduit automatiquement des clés étrangères ?
<details><summary>R</summary>

Les cardinalités minimales « au moins un », la distinction n-n conceptuelle (vue comme deux 1-n), le sens métier des relations (le libellé n'est que le nom de colonne), et tout ce qui n'est pas déclaré comme FK.

</details>

## Anti-patterns

### Q: Cite cinq anti-patterns de documentation de couche de données.
<details><summary>R</summary>

Wiki séparé qui diverge, commentaire-paraphrase, ERD PNG figé, le quoi sans le pourquoi, l'intention écrite comme un fait, tout documenter au même niveau, ADR réécrit.

</details>

### Q: Par quoi commencer quand on documente une couche ORM existante ?
<details><summary>R</summary>

Par ce qui surprend : règles hors schéma, effets de bord, filtres implicites, trous connus. La structure, elle, se génère.

</details>

---

**Cartes** : 36
**Niveau** : intermédiaire
**Dernière mise à jour** : 2026-10-29
