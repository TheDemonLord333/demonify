-- Konten: E-Mail, Startpasswort, Einmal-Tokens; Künstler: Herkunft (manuell/Scan/Altbestand)
-- CreateEnum
CREATE TYPE "EmailTokenKind" AS ENUM ('VERIFY_EMAIL', 'PASSWORD_RESET');

-- CreateEnum
CREATE TYPE "ArtistOrigin" AS ENUM ('MANUAL', 'SCAN', 'LEGACY');

-- AlterTable
-- Bestehende Künstler haben eine unklare Herkunft → LEGACY (wird beim automatischen Aufräumen nie entfernt).
-- Neue Einträge: MANUAL als sicherer Standard; der Scan setzt ausdrücklich SCAN.
ALTER TABLE "Artist" ADD COLUMN     "origin" "ArtistOrigin" NOT NULL DEFAULT 'LEGACY';
ALTER TABLE "Artist" ALTER COLUMN "origin" SET DEFAULT 'MANUAL';

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "email" TEXT,
ADD COLUMN     "emailKey" TEXT,
ADD COLUMN     "emailVerifiedAt" TIMESTAMP(3),
ADD COLUMN     "mustChangePassword" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "EmailToken" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "kind" "EmailTokenKind" NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "email" TEXT,
    "emailKey" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),

    CONSTRAINT "EmailToken_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "EmailToken_tokenHash_key" ON "EmailToken"("tokenHash");

-- CreateIndex
CREATE INDEX "EmailToken_userId_kind_createdAt_idx" ON "EmailToken"("userId", "kind", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "User_emailKey_key" ON "User"("emailKey");

-- AddForeignKey
ALTER TABLE "EmailToken" ADD CONSTRAINT "EmailToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;


