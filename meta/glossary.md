# 📖 Programming Glossary

A comprehensive reference of programming terms and concepts used throughout this knowledge base.

## A

**Algorithm**  
A step-by-step procedure for solving a problem or completing a task.

**Array**  
A data structure that stores multiple values in a single variable, accessible by index.

**API (Application Programming Interface)**  
A set of rules and protocols that allows different software applications to communicate.

**Abstraction**  
The concept of hiding complex implementation details while showing only essential features.

**ACID**
Atomicité, Cohérence, Isolation, Durabilité : les garanties d'une transaction. L'isolation est la plus nuancée : elle dépend du niveau choisi (voir *Niveau d'isolation*).

**Active Record (pattern)**
Objet qui représente une ligne de table et porte à la fois ses données, sa logique et sa propre persistance (`save()`, `delete()`). Rails ActiveRecord, Eloquent, Sequelize. Nommé par Martin Fowler (PoEAA, 2002).

## B

**Big O Notation**  
A mathematical notation used to describe the time or space complexity of algorithms.

**Binary Search**  
An efficient algorithm for finding an item in a sorted array by repeatedly dividing the search interval in half.

**Boolean**  
A data type that can only have two values: true or false.

**Bug**  
An error or flaw in a program that causes incorrect or unexpected behavior.

## C

**Closure**  
A function that has access to variables in its outer (enclosing) scope even after the outer function has returned.

**Complexity**  
A measure of how the runtime or space requirements of an algorithm grow with input size.

**Constructor**  
A special method used to create and initialize objects in object-oriented programming.

**CRUD**
Create, Read, Update, Delete - the four basic operations of persistent storage.

**CRDT (Conflict-free Replicated Data Type)**
Une structure de données qui permet la fusion automatique de modifications concurrentes sans conflits. Essentiel pour les applications local-first.

## D

**Data Structure**  
A way of organizing and storing data to enable efficient access and modification.

**Debugging**  
The process of finding and fixing bugs in computer programs.

**Declaration**  
A statement that introduces a variable, function, or other identifier to the program.

**DRY (Don't Repeat Yourself)**  
A principle aimed at reducing repetition of code patterns.

**Data Mapper (pattern)**
Couche qui transfère les données entre des objets métier ignorants de la base et les tables, en gardant les deux indépendants. Doctrine, Hibernate, MikroORM. Opposé à l'Active Record.

**DDL (Data Definition Language)**
Partie de SQL qui définit la structure : `CREATE`, `ALTER`, `DROP`. Selon le SGBD, le DDL est transactionnel (PostgreSQL, SQLite) ou provoque un commit implicite (MySQL).

## E

**Encapsulation**  
The bundling of data and methods that operate on that data within a single unit.

**Expression**  
A combination of values, variables, and operators that evaluates to a single value.

**Edge Case**  
A problem or situation that occurs only at an extreme (maximum or minimum) operating parameter.

**ERD (Entity-Relationship Diagram)**
Diagramme entité-association issu de Peter Chen (1976). La notation *crow's foot* (pattes de corbeau) est la plus répandue dans les outils actuels.

**Expand/Contract**
Stratégie de migration sans interruption : on ajoute la nouvelle structure (*expand*), on fait cohabiter ancien et nouveau, puis on retire l'ancien (*contract*). Aussi appelée *parallel change*.

## F

**Function**  
A reusable block of code that performs a specific task.

**Framework**  
A pre-written code library that provides a foundation for developing applications.

**Functional Programming**  
A programming paradigm that treats computation as the evaluation of mathematical functions.

## G

**Global Variable**  
A variable that can be accessed from anywhere in the program.

**Git**  
A distributed version control system for tracking changes in source code.

**Garbage Collection**  
Automatic memory management that frees up memory occupied by objects no longer in use.

## H

**Hash Table**  
A data structure that implements an associative array abstract data type.

**HTTP**  
HyperText Transfer Protocol - the foundation of data communication on the web.

**Hoisting**  
A JavaScript mechanism where variable and function declarations are moved to the top of their scope.

**Hydratation**
Transformation des lignes renvoyées par la base en objets du langage, avec conversion des types (texte → `Date`, entier → booléen…).

## I

**IndexedDB**
API de base de données NoSQL asynchrone côté client pour stocker de grandes quantités de données structurées dans le navigateur.

**Inheritance**
A mechanism where a new class inherits properties and methods from an existing class.

**Interface**
A contract that defines what methods a class must implement.

**Iteration**
The repetition of a process or set of instructions in a program.

**Identity Map**
Registre qui garantit qu'une ligne donnée n'est chargée qu'une fois par contexte : deux lectures du même `id` renvoient le même objet.

**Impedance mismatch (objet-relationnel)**
Décalage entre le modèle objet (identité, références, héritage, graphe) et le modèle relationnel (clés, ensembles, jointures). Le problème que tout ORM tente de combler.

## J

**JSON (JavaScript Object Notation)**  
A lightweight data interchange format that's easy for humans to read and write.

**JIT (Just-In-Time)**  
A compilation technique where code is compiled during execution rather than beforehand.

## K

**Kata**  
A coding exercise designed to practice programming skills through repetition.

**Keyword**  
A reserved word in a programming language that has special meaning.

## L

**Library**
A collection of pre-written code that can be used in programs.

**Local-First**
Paradigme de développement où l'application fonctionne d'abord localement, avec synchronisation en arrière-plan. Priorité aux données locales.

**Loop**
A programming construct that repeats a block of code.

**Linked List**
A data structure where elements are stored in nodes, each containing data and a reference to the next node.

**LWW-Register (Last-Write-Wins Register)**
CRDT simple où la valeur avec le timestamp le plus récent gagne lors de la fusion. Base des systèmes de synchronisation.

## M

**Method**  
A function that is associated with an object or class.

**Module**  
A separate file containing code that can be imported and used in other files.

**Memoization**  
An optimization technique that stores the results of expensive function calls.

**MCD / MLD / MPD**
Modèles Conceptuel, Logique et Physique des Données de la méthode Merise : du sens métier (entités, associations, cardinalités) aux tables, puis au SQL d'un SGBD précis.

**Merise**
Méthode française de conception de systèmes d'information (Tardieu, Rochfeld, Colletti, fin des années 1970). Toujours enseignée dans les titres professionnels du numérique.

**Migration**
Changement de schéma (ou de données) versionné, ordonné et rejouable, généralement avec une opération inverse (`down`) pour revenir en arrière.

## N

**Null**  
A special value that represents "no value" or "empty value".

**Node**  
A basic unit of a data structure, such as a linked list or tree.

**Nested**  
Code structures placed inside other similar structures.

**N+1 (problème)**
Une requête pour charger N lignes, puis une requête supplémentaire par ligne pour charger une relation : N+1 requêtes au lieu de 1 ou 2. Défaut de performance n°1 des ORMs.

**Niveau d'isolation**
Degré auquel une transaction voit les modifications concurrentes : *read uncommitted*, *read committed*, *repeatable read*, *serializable*. Chaque niveau autorise ou interdit certaines anomalies.

**Normalisation**
Décomposition d'un schéma pour éliminer les redondances et les anomalies de mise à jour, guidée par les dépendances fonctionnelles (1FN, 2FN, 3FN, BCNF).

## O

**Object**
A collection of related data and methods.

**Object-Oriented Programming (OOP)**
A programming paradigm based on the concept of "objects".

**Offline-First**
Approche de développement web où les applications fonctionnent sans connexion permanente, avec synchronisation automatique en arrière-plan.

**Operator**
A symbol that performs an operation on one or more operands.

**OPFS (Origin Private File System)**
API moderne permettant de manipuler des fichiers directement dans le navigateur avec performances optimales. Privé à l'origine.

**Optimistic UI**
Pattern d'interface où les changements sont affichés immédiatement avant confirmation serveur, pour une interaction instantanée.

**ORM (Object-Relational Mapper)**
Bibliothèque qui fait correspondre des objets du langage et des tables relationnelles : génération du SQL, hydratation, gestion des relations, souvent migrations. Prisma, Doctrine, Hibernate, SQLAlchemy.

## P

**P2P (Peer-to-Peer)**
Architecture réseau où les clients communiquent directement entre eux sans serveur central. Utilisé pour la synchronisation offline-first.

**Parameter**
A variable used in a function to refer to one of the pieces of data provided as input.

**Polymorphism**
The ability of different types to be treated as instances of the same type through a common interface.

**Promise**
An object representing the eventual completion or failure of an asynchronous operation.

## Q

**Query**  
A request for data or information from a database.

**Queue**  
A data structure that follows the First-In-First-Out (FIFO) principle.

**Query Builder**
API qui construit du SQL par composition de méthodes (`select().where().orderBy()`) sans mapper vers des objets métier. Knex, Kysely, SQLAlchemy Core.

## R

**Recursion**  
A programming technique where a function calls itself to solve a problem.

**Refactoring**  
The process of restructuring existing code without changing its external behavior.

**REST (Representational State Transfer)**  
An architectural style for designing networked applications.

**Rollback**
Annulation : d'une transaction en cours (`ROLLBACK`), ou d'une migration déjà appliquée (exécution de son `down`). Un rollback de migration ne restaure pas les données supprimées.

## S

**Scope**  
The region of a program where a variable can be accessed.

**Stack**  
A data structure that follows the Last-In-First-Out (LIFO) principle.

**String**  
A sequence of characters used to represent text.

**Syntax**  
The set of rules that defines valid constructs in a programming language.

## T

**Type**  
A classification of data that determines what operations can be performed on it.

**Tree**  
A hierarchical data structure with a root node and child nodes.

**Testing**  
The process of evaluating a program to ensure it works correctly.

## U

**Undefined**  
A value assigned to variables that have been declared but not initialized.

**URL (Uniform Resource Locator)**  
A reference to a web resource that specifies its location.

**Unit Test**  
A test that verifies the behavior of a small, isolated piece of code.

**UML (Unified Modeling Language)**
Langage de modélisation standardisé par l'OMG. Son diagramme de classes décrit le modèle objet, qu'un ORM fait correspondre au schéma relationnel.

**Unit of Work**
Objet qui enregistre les créations, modifications et suppressions d'une opération métier et les écrit en une seule fois, dans une transaction, au moment du `flush`/`commit`.

## V

**Variable**  
A named storage location that can hold a value.

**Version Control**  
A system that tracks changes to files over time.

**Virtual Machine**  
A software implementation of a computer that executes programs like a physical machine.

**Verrouillage optimiste**
Détection des écritures concurrentes par une colonne `version` vérifiée au moment de l'`UPDATE`, plutôt que par un verrou posé à la lecture (verrouillage pessimiste).

## W

**Web API**
An application programming interface for a web application or web server.

**WebRTC (Web Real-Time Communication)**
API permettant la communication temps réel entre navigateurs (vidéo, audio, données) sans serveur central. Base du P2P web.

**Wrapper**
A function or class that provides a simplified interface to another function or class.

## X

**XML (eXtensible Markup Language)**  
A markup language that defines rules for encoding documents.

## Y

**YAML (YAML Ain't Markup Language)**  
A human-readable data serialization standard.

## Z

**Zero-based indexing**  
A numbering scheme where the first element of a sequence is assigned the index 0.

---

**Note**: This glossary is continuously updated as new concepts are introduced in the knowledge base. Suggest additions by creating an issue or pull request.