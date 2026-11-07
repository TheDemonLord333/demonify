import 'dotenv/config';
import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    // Für "prisma generate" (Build) nicht nötig; Migrationen brechen ohne DATABASE_URL mit klarer Meldung ab.
    url: process.env.DATABASE_URL ?? '',
  },
});
