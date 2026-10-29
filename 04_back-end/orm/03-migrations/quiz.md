# 📝 Quiz : Migrations

Réponds sans ouvrir les notes. Les trois dernières questions sont ouvertes : rédige ta réponse avant de lire la réponse modèle.

---

### Q1 : Qu'est-ce qui distingue une migration d'un script SQL quelconque ?
A) Elle est écrite dans le langage de l'ORM
B) Elle est versionnée, ordonnée, appliquée une seule fois par base et rejouable
C) Elle ne modifie jamais les données
D) Elle est toujours générée automatiquement

<details><summary>Réponse</summary>

**B**. Le langage importe peu (beaucoup de migrations sont en SQL brut), certaines migrations modifient des données, et la génération automatique n'est qu'une option.

</details>

---

### Q2 : Tu modifies une migration déjà appliquée en production pour corriger une faute de frappe dans un nom d'index. Quelle est la conséquence ?
A) Aucune : la migration ne sera pas rejouée en production
B) Les nouvelles bases auront le nouveau nom, la production garde l'ancien : les environnements divergent
C) La production est mise à jour automatiquement au prochain déploiement
D) La migration est annulée puis réappliquée

<details><summary>Réponse</summary>

**B**. La production ne rejoue pas une migration déjà enregistrée, mais une base neuve (CI, nouveau développeur) exécutera la version modifiée. C'est précisément ce que le checksum détecte. La correction se fait par une **nouvelle** migration.

</details>

---

### Q3 : Avec des noms de migration horodatés, quel problème reste possible ?
A) Deux migrations portent le même nom
B) Une migration créée avant une autre est fusionnée après, et l'ordre d'application diffère selon les environnements
C) Les migrations ne peuvent plus être annulées
D) Le checksum ne peut plus être calculé

<details><summary>Réponse</summary>

**B**. L'horodatage supprime les collisions de nom, pas les conflits d'ordre. Flyway les refuse par défaut, Rails les applique silencieusement.

</details>

---

### Q4 : Un outil déclaratif compare ton schéma cible avec la base et voit que `title` a disparu et que `name` est apparue. Quel est le risque ?
A) Aucun, il détecte toujours les renommages
B) Il peut générer `DROP COLUMN title` + `ADD COLUMN name` et perdre les données
C) Il refuse de générer quoi que ce soit
D) Il renomme toujours la colonne

<details><summary>Réponse</summary>

**B**. Un diff d'états ne connaît pas l'intention. Certains outils posent la question (Drizzle Kit, Django), d'autres préviennent de la perte de données (Prisma). Dans tous les cas : relire le SQL généré.

</details>

---

### Q5 : Une migration `up` exécute `ALTER TABLE contributions DROP COLUMN since`. Son `down` exécute `ALTER TABLE contributions ADD COLUMN since TEXT NOT NULL DEFAULT '1970-01-01'`. Que vaut ce `down` ?
A) Il est correct : le schéma revient à l'identique
B) Il restaure la forme mais pas l'information : la migration est en réalité irréversible
C) Il échoue toujours sous SQLite
D) Il est correct si on l'exécute dans une transaction

<details><summary>Réponse</summary>

**B**. Toutes les dates valent `1970-01-01`. Mieux vaut déclarer la migration irréversible (et faire une sauvegarde) qu'un `down` qui donne l'illusion d'un retour arrière.

</details>

---

### Q6 : Sur MySQL, une migration de trois instructions DDL échoue à la deuxième. Dans quel état est la base ?
A) Rien n'a été appliqué, grâce à la transaction
B) La première instruction est appliquée, la migration n'est pas enregistrée dans l'historique
C) Les trois instructions sont appliquées
D) La base est corrompue

<details><summary>Réponse</summary>

**B**. Sous MySQL, chaque DDL provoque un commit implicite. D'où la règle : une instruction DDL par migration.

</details>

---

### Q7 : Quel énoncé sur `prisma migrate resolve --rolled-back` est exact ?
A) Il exécute le `down` de la migration
B) Il met à jour l'historique pour indiquer qu'une migration **en échec** a été annulée ; il n'exécute aucun SQL
C) Il annule n'importe quelle migration réussie
D) Il supprime le dossier de la migration

<details><summary>Réponse</summary>

**B**. C'est à toi de remettre la base en état (par exemple avec `prisma db execute --file down.sql`). Pour annuler une migration **réussie**, Prisma recommande de revenir dans le schéma et de créer une nouvelle migration.

</details>

---

### Q8 : La version 42 du code, déployée cinq minutes après une migration additive (nouvelle colonne facultative), plante à cause d'un bug sans lien avec la base. Que fais-tu ?
A) Exécuter le `down` puis redéployer la version 41
B) Redéployer la version 41 seule
C) Restaurer la sauvegarde de la nuit
D) Exécuter le `down` seul

<details><summary>Réponse</summary>

**B**. Une migration additive est compatible avec la version précédente du code : c'est tout l'intérêt de la règle de compatibilité N/N+1. Annuler la migration n'apporterait que du risque.

</details>

---

### Q9 : Dans un expand/contract, à quel moment peut-on supprimer l'ancienne colonne ?
A) Juste après avoir ajouté la nouvelle
B) Juste après le backfill
C) Quand plus aucun code en service ne la lit ni ne l'écrit, et qu'on a renoncé à revenir à ce code
D) Jamais

<details><summary>Réponse</summary>

**C**. Y compris les tâches planifiées, exports et outils de BI, et sans oublier que l'ORM peut encore la mapper. Le *contract* est le seul moment où le retour arrière devient coûteux : il doit arriver quand on n'en a plus besoin.

</details>

---

### Q10 : Pourquoi `SET lock_timeout = '3s'` avant un `ALTER TABLE` en PostgreSQL ?
A) Pour accélérer la migration
B) Pour qu'un `ALTER` qui attend un verrou exclusif échoue vite au lieu de bloquer toutes les requêtes suivantes sur la table
C) Pour que la migration soit transactionnelle
D) Pour éviter les interblocages entre deux migrations

<details><summary>Réponse</summary>

**B**. Une requête en attente de verrou exclusif bloque toutes celles qui arrivent après elle. Sans délai maximal, une migration coincée derrière une longue requête rend la table inaccessible.

</details>

---

### Q11 : Tu reconstruis la table `projects` sous SQLite (créer `new_projects`, copier, `DROP TABLE projects`, renommer) dans une transaction, avec `PRAGMA foreign_keys = ON`. Que se passe-t-il ?
A) La transaction échoue à cause des clés étrangères
B) Tout fonctionne et rien n'est perdu
C) `DROP TABLE` déclenche les `ON DELETE CASCADE` : `contributions` et `project_tags` sont vidées, sans erreur
D) Les index sont conservés automatiquement

<details><summary>Réponse</summary>

**C**. Et exécuter `PRAGMA foreign_keys = OFF` **dans** la transaction ne sert à rien : ce PRAGMA y est sans effet. Il faut le faire avant `BEGIN`. Les index sont aussi perdus (D est faux).

</details>

---

### Q12 : Pour remplir une nouvelle colonne sur 50 millions de lignes, quelle approche est la plus sûre ?
A) Un seul `UPDATE` dans la migration de schéma
B) Des lots par `LIMIT … OFFSET …` croissants
C) Des lots avec un curseur sur la clé primaire, une transaction par lot, en ne touchant que les lignes non traitées
D) Exporter la table, la transformer, la réimporter

<details><summary>Réponse</summary>

**C**. Transactions courtes, coût constant par lot (pas d'`OFFSET` qui relit tout le début), idempotent et reprenable.

</details>

---

### Q13 (ouverte) : Explique pourquoi « écrire un `down` pour chaque migration » ne suffit pas à garantir qu'on peut revenir en arrière.

<details><summary>Réponse modèle</summary>

Un `down` répond à une seule des trois questions de retour arrière : dé-appliquer une migration réussie. Il ne gère ni l'échec en cours de route (c'est la transaction, et elle n'existe pas pour le DDL sous MySQL), ni la perte de données (seule une sauvegarde la répare). Même pour ce qu'il couvre, un `down` peut être syntaxiquement correct et sémantiquement faux : il détruit les données écrites depuis l'`up`, recrée des structures vides, ou inverse une transformation non injective. Il est enfin rarement testé sur des données réelles. Ce qui garantit la capacité de retour, c'est un ensemble : migrations compatibles avec la version précédente du code (pour pouvoir annuler le code **seul**), test d'aller-retour en CI, migrations destructrices déclarées comme telles, et sauvegardes dont la restauration a été testée.

</details>

---

### Q14 (ouverte) : Explique pourquoi un renommage de colonne, instantané en PostgreSQL, est pourtant une opération dangereuse, et décris comment le faire sans interruption.

<details><summary>Réponse modèle</summary>

`RENAME COLUMN` ne modifie que des métadonnées, mais pendant un déploiement progressif l'ancien code (qui lit `title`) et le nouveau (qui lit `name`) tournent en même temps : quel que soit le moment du renommage, l'un des deux casse, et un retour arrière du code devient impossible. La solution est l'expand/contract :

1. **Expand** : ajouter `name` facultative et un trigger `BEFORE INSERT OR UPDATE` qui synchronise les deux colonnes dans les deux sens.
2. **Migrate** : remplir `name` par lots, puis rendre `name` obligatoire (`CHECK … NOT VALID`, `VALIDATE`, `SET NOT NULL`) et `title` facultative.
3. Déployer le code qui lit et écrit `name` ; le trigger réconcilie les deux versions pendant la cohabitation.
4. **Contract** : quand plus rien n'utilise `title` (y compris tâches planifiées et mapping de l'ORM), supprimer le trigger, puis la colonne.

Chaque étape est compatible avec le code avant et après elle, et réversible isolément.

</details>

---

### Q15 (ouverte) : Une colonne a été supprimée par erreur il y a six heures ; le site a continué de tourner. Explique pourquoi ni le `down` ni une restauration complète ne sont de bonnes réponses, et ce que tu fais.

<details><summary>Réponse modèle</summary>

Le `down` recréerait une colonne vide : il restaure la forme, pas le contenu. Une restauration complète de la base à l'instant d'avant la suppression effacerait six heures d'écritures légitimes sur toutes les tables. La bonne démarche : restaurer la sauvegarde (ou la PITR à l'instant voulu) dans une **instance séparée**, en extraire la clé primaire et la colonne perdue, recréer la colonne par une **nouvelle** migration (roll-forward) et réinjecter les valeurs par un script. Puis traiter la cause racine : la phase *contract* a été faite sans inventaire complet des lecteurs. À l'avenir, retirer d'abord la colonne du mapping et des droits d'accès, attendre un cycle complet (y compris les tâches nocturnes), puis seulement la supprimer.

</details>

---

**Score : /15 — Objectif : 11/15**
