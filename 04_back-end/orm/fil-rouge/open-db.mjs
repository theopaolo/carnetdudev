// Ouvre une base SQLite en mémoire avec le schéma (et, par défaut, les données) du fil rouge.
// Zéro dépendance : node:sqlite est intégré à Node.js depuis la 22.5 (sans option depuis la 22.13).
//
//   import { openDb } from './open-db.mjs';
//   const db = openDb();                       // schéma + données
//   const db = openDb({ seed: false });        // schéma seul
//   const db = openDb({ log: true });          // affiche et compte chaque requête exécutée
//   db.queries.length                          // nombre de requêtes (avec log: true)
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';

const read = (file) => readFileSync(new URL(file, import.meta.url), 'utf8');

export function openDb({ seed = true, log = false, path = ':memory:' } = {}) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA foreign_keys = ON;'); // désactivé par défaut dans SQLite, connexion par connexion
  db.exec(read('./schema.sql'));
  if (seed) db.exec(read('./seed.sql'));
  return log ? withQueryLog(db) : db;
}

// Intercepte prepare() pour journaliser chaque exécution de requête.
// C'est exactement ce que fait l'option « logging » d'un ORM, et c'est l'outil n°1 pour voir un N+1.
export function withQueryLog(db, { print = true } = {}) {
  const prepare = db.prepare.bind(db);
  db.queries = [];
  db.prepare = (sql) => {
    const stmt = prepare(sql);
    for (const method of ['run', 'get', 'all']) {
      const original = stmt[method].bind(stmt);
      stmt[method] = (...params) => {
        db.queries.push({ sql, params });
        if (print) console.log(`[sql #${db.queries.length}]`, sql.replace(/\s+/g, ' ').trim(), params);
        return original(...params);
      };
    }
    return stmt;
  };
  return db;
}
