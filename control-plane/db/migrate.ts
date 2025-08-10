import { Database } from 'bun:sqlite';

const db = new Database('control.db');

// Read and execute schema
const schema = await Bun.file('db/schema.sql').text();
db.exec(schema);

// Read and execute cache tables migration
const cacheMigration = await Bun.file('db/migrations/002_cache_tables.sql').text();
db.exec(cacheMigration);

console.log('✅ Database migrations completed successfully');
db.close();