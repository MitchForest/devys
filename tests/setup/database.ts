import { createDatabase, migrate, start, testDatabase } from "../../scripts/db.ts";
/** Every Workers test run starts from an empty, fully migrated test database. */
export default async function setup() {
  start();
  await createDatabase(testDatabase, true);
  await migrate(testDatabase);
}
