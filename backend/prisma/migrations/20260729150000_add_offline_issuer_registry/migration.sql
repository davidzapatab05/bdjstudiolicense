-- Source of truth for BDJ License Console's offline customer/license ledger.
-- The signed SPP2 token is intentionally not persisted in this database.
CREATE TABLE "customers" (
    "id" TEXT NOT NULL,
    "externalId" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "customers_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "customers_externalId_key" ON "customers"("externalId");
CREATE UNIQUE INDEX "customers_email_deviceId_key" ON "customers"("email", "deviceId");

CREATE TABLE "offline_licenses" (
    "id" TEXT NOT NULL,
    "externalId" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "product" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "plan" TEXT NOT NULL,
    "tokenDigest" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "issuedAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "offline_licenses_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "offline_licenses_externalId_key" ON "offline_licenses"("externalId");
CREATE UNIQUE INDEX "offline_licenses_tokenDigest_key" ON "offline_licenses"("tokenDigest");
CREATE INDEX "offline_licenses_customerId_product_idx" ON "offline_licenses"("customerId", "product");
CREATE INDEX "offline_licenses_deviceId_idx" ON "offline_licenses"("deviceId");
ALTER TABLE "offline_licenses" ADD CONSTRAINT "offline_licenses_customerId_fkey"
  FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "offline_device_blocks" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "blockedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "offline_device_blocks_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "offline_device_blocks_deviceId_key" ON "offline_device_blocks"("deviceId");
