const { createDatabase } = require('./database');
const database = createDatabase();
database.migrate().then(() => console.log('Database migrations applied.')).catch(error => {
  console.error(`Migration failed (${error.code || 'unknown'}).`); process.exitCode = 1;
}).finally(() => database.close());
