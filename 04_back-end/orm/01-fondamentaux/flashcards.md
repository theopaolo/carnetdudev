# 🧠 Flashcards : Fondamentaux des ORMs

> Réponds à voix haute ou par écrit **avant** d'ouvrir la réponse. Marque les cartes ratées et revois-les en priorité.

## 📖 Définitions

### Q: Définis un ORM en une phrase précise.
<details><summary>R</summary>Une bibliothèque qui maintient une correspondance déclarée (métadonnées de mapping) entre des types du langage et un schéma relationnel, et qui s'en sert pour traduire dans les deux sens : opérations sur objets → SQL, lignes de résultat → objets.</details>

### Q: Quelle différence entre un driver, un query builder et un ORM ?
<details><summary>R</summary>Le driver transporte le SQL vers le SGBD et rapporte les lignes. Le query builder construit du SQL à partir d'appels de fonctions. L'ORM construit le SQL <strong>et</strong> mappe les résultats vers un modèle objet (relations, types, suivi des changements). La plupart des ORMs contiennent un query builder.</details>

### Q: Qu'est-ce que l'*object-relational impedance mismatch* ?
<details><summary>R</summary>Le décalage entre deux modèles bâtis sur des fondations différentes : le relationnel (ensembles de tuples, valeurs, logique déclarative, Codd 1970) et l'objet (identité, état encapsulé, références navigables, comportement). Il se manifeste sur l'identité, la granularité, l'héritage, les associations, la navigation, les types, l'encapsulation et la fraîcheur des données.</details>

### Q: Qu'est-ce que l'hydratation ?
<details><summary>R</summary>La transformation d'une ligne de résultat en objet du domaine, avec conversion de représentation : noms (<code>created_at</code> → <code>createdAt</code>), types (texte → <code>Date</code>, <code>0/1</code> → booléen), valeurs dérivées, assemblage des objets liés. L'inverse s'appelle la déshydratation.</details>

### Q: Qu'appelle-t-on « métadonnées de mapping » ? Cite trois façons de les fournir.
<details><summary>R</summary>La description de la correspondance classe ↔ table, propriété ↔ colonne, types et relations. On les fournit par conventions (Rails, Eloquent), par annotations dans le code (décorateurs TypeORM, attributs PHP Doctrine) ou par un fichier de schéma séparé (<code>schema.prisma</code>, schéma Drizzle).</details>

## 🤔 Impedance mismatch

### Q: Quelles sont les trois notions d'identité en jeu, et pourquoi posent-elles problème ?
<details><summary>R</summary>Identité objet (même référence, <code>a === b</code>), égalité de valeurs, identité en base (clé primaire). Charger deux fois la même ligne donne deux objets distincts : des modifications concurrentes en mémoire s'écrasent sans erreur. L'Identity Map impose « un objet par ligne et par session ».</details>

### Q: Pourquoi une association n-n porteuse d'attributs force-t-elle une entité dans le modèle objet ?
<details><summary>R</summary>L'attribut (ici <code>role</code>, <code>since</code>) n'appartient ni au membre ni au projet, mais au couple. Une simple collection <code>member.projects</code> le perdrait. Il faut une entité <code>Contribution</code> qui référence les deux côtés et porte l'attribut.</details>

### Q: Où vit une association 1-n côté objet, et côté relationnel ?
<details><summary>R</summary>Côté objet : une ou deux références (<code>project.owner</code>, <code>member.projects</code>), à synchroniser si on veut les deux sens. Côté relationnel : une seule clé étrangère du côté « plusieurs » (<code>projects.owner_id</code>), interrogeable dans les deux sens par jointure, sans rien à synchroniser.</details>

### Q: Que vaut `NULL = NULL` en SQL, et quelle conséquence pour un filtre `status <> 'banned'` ?
<details><summary>R</summary><code>NULL</code> (inconnu), donc pas vrai. Le filtre exclut les lignes dont <code>status</code> est <code>NULL</code>, alors que l'équivalent JavaScript <code>m.status !== 'banned'</code> les garderait. Il faut écrire <code>status IS DISTINCT FROM 'banned'</code> (PostgreSQL, SQLite ≥ 3.39) ou <code>status &lt;&gt; 'banned' OR status IS NULL</code>.</details>

### Q: Pourquoi `new Date('2026-04-03 09:10:00')` est-il un piège avec SQLite ?
<details><summary>R</summary>SQLite écrit <code>datetime('now')</code> en UTC sans indicateur de fuseau, et V8 interprète ce format comme une heure <strong>locale</strong>. Sur une machine à Paris, la date est décalée d'une ou deux heures. Il faut convertir explicitement : <code>new Date(text.replace(' ', 'T') + 'Z')</code>.</details>

### Q: Une relation SQL est-elle ordonnée ?
<details><summary>R</summary>Non : c'est un ensemble. Sans <code>ORDER BY</code>, l'ordre du résultat n'est pas garanti, même s'il paraît stable. Un tableau ordonné côté objet exige une colonne de position explicite côté base.</details>

### Q: Comment Doctrine hydrate-t-il une entité, et quelle conséquence pour les invariants ?
<details><summary>R</summary>Il n'appelle jamais le constructeur : il instancie par réflexion et écrit directement dans les propriétés, même privées. Les vérifications placées dans le constructeur ne sont pas rejouées au chargement. D'où l'intérêt de doubler les invariants simples par des contraintes en base.</details>

### Q: Qu'est-ce que la dimension « fraîcheur » du décalage objet-relationnel ?
<details><summary>R</summary>Un objet chargé est une copie de la ligne à un instant donné. Un autre processus peut modifier la ligne entre-temps, sans que l'objet le sache. Tout ORM est un cache d'objets devant une base partagée, et doit gérer les écritures concurrentes (verrouillage, transactions).</details>

## 🏛️ Patterns de Fowler

### Q: Table Data Gateway : définition et cas d'usage.
<details><summary>R</summary>Un objet par table, qui encapsule son SQL et renvoie des données brutes. Pas de logique métier. Va avec une logique organisée en <em>Transaction Script</em> ou <em>Table Module</em> : applications CRUD simples, back-ends où le SQL doit rester visible.</details>

### Q: Row Data Gateway : en quoi diffère-t-il de l'Active Record ?
<details><summary>R</summary>Les deux ont un objet par ligne qui sait s'insérer, se mettre à jour, se supprimer. Le Row Data Gateway ne contient <strong>aucune</strong> logique métier ; l'Active Record ajoute la logique métier sur ces données.</details>

### Q: Définition de l'Active Record selon Fowler.
<details><summary>R</summary>« Un objet qui enveloppe une ligne d'une table ou d'une vue, encapsule l'accès à la base, et ajoute de la logique métier sur ces données. » L'objet est la ligne.</details>

### Q: Définition du Data Mapper selon Fowler.
<details><summary>R</summary>« Une couche de mappers qui déplace les données entre les objets et la base en les gardant indépendants l'un de l'autre et du mapper lui-même. » Le domaine ne connaît pas la base.</details>

### Q: Selon Fowler, de quoi dépend le choix du pattern d'accès aux données ?
<details><summary>R</summary>De l'organisation de la logique métier : Transaction Script → gateways ; Table Module → Table Data Gateway ; Domain Model simple et calqué sur le schéma → Active Record ; Domain Model riche → Data Mapper.</details>

### Q: Metadata Mapping, en une phrase.
<details><summary>R</summary>Décrire le mapping par des données (décorateurs, fichier de schéma) qu'un code générique exploite pour produire le SQL et hydrater, au lieu d'écrire un mapper à la main par classe. C'est le cœur de tout ORM.</details>

### Q: Identity Map, Unit of Work, Lazy Load : une ligne chacun.
<details><summary>R</summary>

- <strong>Identity Map</strong> : un objet par ligne et par session (table clé → objet).
- <strong>Unit of Work</strong> : liste les objets créés, modifiés, supprimés, et écrit tout au <code>flush</code>, dans le bon ordre.
- <strong>Lazy Load</strong> : un objet qui va chercher ses données manquantes au premier accès (cause du N+1).

</details>

### Q: Repository : d'où vient le terme et quelle est son interface typique ?
<details><summary>R</summary>Fowler (PoEAA) et surtout Evans (<em>Domain-Driven Design</em>, 2003). Une interface de type collection entre le domaine et le mapping : <code>findById</code>, <code>save</code>, <code>remove</code>, recherches par spécification. Chez Evans, un repository par agrégat.</details>

## ⚖️ Active Record vs Data Mapper

### Q: Dans quel sens vont les dépendances avec Active Record, et avec Data Mapper ?
<details><summary>R</summary>Active Record : le domaine dépend de la base (la classe contient le SQL ou hérite d'une classe qui le contient). Data Mapper : le mapper dépend du domaine et de la base ; le domaine ne dépend de rien.</details>

### Q: Quel est « le test qui tranche » entre les deux ?
<details><summary>R</summary>Puis-je instancier mon objet métier et tester sa règle la plus importante <strong>sans base de données</strong> ? Si c'est nécessaire, il faut un Data Mapper, ou au minimum sortir la règle de l'Active Record.</details>

### Q: Qu'est-ce que la *persistence ignorance*, et pourquoi est-elle toujours partielle ?
<details><summary>R</summary>Un domaine qui ne sait pas comment ni s'il sera stocké. Partielle parce que les annotations de mapping (<code>@Column</code>, <code>#[ORM\Column]</code>) recouplent l'entité à la bibliothèque, et parce que le domaine doit tolérer des <code>id</code> absents, des collections chargées à la demande, des objets périmés.</details>

### Q: Dans quelles situations l'Active Record est-il le meilleur choix ?
<details><summary>R</summary>Domaine essentiellement fait de données avec peu de règles, schéma et modèle proches, priorité à la vitesse de développement, équipe qui suit les conventions d'un framework (Rails, Laravel, Django) : back-offices, CRUD, prototypes.</details>

### Q: Quel risque typique guette chaque pattern ?
<details><summary>R</summary>Active Record : la classe « fourre-tout » qui mélange règles, SQL, validation, sérialisation, hooks. Data Mapper : la sur-ingénierie (entité + mapping + repository + service) pour un domaine qui n'est qu'un CRUD.</details>

## 🗺️ Cartographie

### Q: Classe ces outils par famille : Eloquent, Doctrine, Prisma, Dapper, SQLAlchemy ORM, Sequelize, EF Core, Drizzle.
<details><summary>R</summary>Active Record : Eloquent, Sequelize. Data Mapper + Unit of Work : Doctrine, SQLAlchemy ORM, EF Core. Client généré depuis un schéma : Prisma. Headless / SQL-like : Drizzle. Micro-ORM : Dapper.</details>

### Q: Pourquoi Prisma n'est-il ni Active Record ni Data Mapper au sens strict ?
<details><summary>R</summary>Pas d'Active Record : aucune classe d'entité, pas de <code>save()</code> sur un objet. Pas de vrai Data Mapper : pas d'objets métier mappés, pas d'Identity Map, pas de Unit of Work, pas de lazy loading ; les requêtes renvoient des objets JavaScript simples. Structurellement, une passerelle de table typée et générée.</details>

### Q: Knex, Kysely, jOOQ, SQLAlchemy Core sont-ils des ORMs ?
<details><summary>R</summary>Non, ce sont des query builders : ils construisent du SQL (souvent typé) mais ne mappent pas vers un modèle objet. SQLAlchemy montre la frontière : <em>Core</em> est le query builder, <em>ORM</em> le Data Mapper bâti dessus.</details>

### Q: Quel ORM propose à la fois Active Record et Data Mapper ?
<details><summary>R</summary>TypeORM : <code>BaseEntity</code> pour le style Active Record, <code>Repository</code> pour le style Data Mapper (sans Unit of Work complète).</details>

## ✅❌ Avantages, inconvénients, débat

### Q: L'ORM protège-t-il de toute injection ?
<details><summary>R</summary>Non. Il paramètre les valeurs des requêtes qu'il génère, mais les échappatoires brutes (<code>$queryRawUnsafe</code>, <code>whereRaw</code>, <code>sequelize.literal</code>) avec une entrée utilisateur réintroduisent l'injection. Et si l'utilisateur contrôle la <strong>structure</strong> d'un filtre (objet JSON passé tel quel en <code>where</code>), il peut faire fuiter des données sans injection SQL (« ORM Leak », elttam 2024).</details>

### Q: Pourquoi la portabilité entre SGBD est-elle en partie un mythe ?
<details><summary>R</summary>L'ORM abstrait la syntaxe, pas la sémantique : isolation par défaut, sensibilité à la casse, ordre des <code>NULL</code>, collations, JSON, verrouillage diffèrent. Une application mûre dépend de ces détails. Et changer de SGBD en production est rare.</details>

### Q: Que dit la « loi des abstractions qui fuient » appliquée aux ORMs ?
<details><summary>R</summary>(Spolsky, 2002) Toute abstraction non triviale laisse passer ce qu'elle cache. L'ORM cache le SQL jusqu'au premier problème de performance ; il faut alors redescendre au SQL généré, au plan d'exécution, aux index. L'ORM ne supprime pas le besoin de savoir le SQL, il le diffère.</details>

### Q: Thèse de Neward (« The Vietnam of Computer Science », 2006) ?
<details><summary>R</summary>L'ORM est un bourbier : succès rapides au début, puis coût croissant pour chaque cas limite, sans solution complète ni sortie claire, et un coût d'abandon qui augmente avec l'investissement.</details>

### Q: Thèse de Fowler (« OrmHate », 2012) ?
<details><summary>R</summary>Le problème est intrinsèquement difficile ; les ORMs en règlent une grande partie ; la frustration vient d'attentes gonflées (on ne peut pas ignorer la base). Un ORM maison est souvent pire. Ne pas tout faire passer par l'ORM, en particulier les lectures complexes.</details>

### Q: Quelle position pratique découle de Neward et Fowler ?
<details><summary>R</summary>ORM pour les écritures sur le domaine (où le modèle objet protège des invariants), SQL pour les lectures ensemblistes (rapports, agrégats, traitements en masse). Une forme légère de CQRS.</details>

### Q: Cite quatre situations où un ORM est un mauvais choix.
<details><summary>R</summary>Rapports et statistiques ; traitements en masse (import, purge) ; schéma que tu ne contrôles pas ; logique portée par la base (vues, procédures, RLS) ; usage intensif de fonctionnalités spécifiques du SGBD ; script court ; système event-sourcé.</details>

### Q: Pourquoi les validations de l'ORM ne suffisent-elles pas ?
<details><summary>R</summary>Elles ne protègent que le code qui passe par l'ORM. Un script SQL, un autre service, une opération en masse les contournent. Les contraintes en base (<code>NOT NULL</code>, <code>UNIQUE</code>, <code>CHECK</code>, <code>FOREIGN KEY</code>) protègent tous les clients.</details>

---

**Nombre de cartes** : 38
**Dernière mise à jour** : 2026-10-29
**Niveau** : Intermédiaire
