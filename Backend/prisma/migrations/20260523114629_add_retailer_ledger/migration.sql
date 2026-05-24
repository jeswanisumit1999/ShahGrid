-- CreateTable
CREATE TABLE "retailer_ledger" (
    "id" UUID NOT NULL,
    "retailer_id" UUID NOT NULL,
    "company_id" UUID,
    "delta" DECIMAL(12,2) NOT NULL,
    "balance_after" DECIMAL(12,2) NOT NULL,
    "type" VARCHAR(40) NOT NULL,
    "reference_type" VARCHAR(32),
    "reference_id" VARCHAR(64),
    "notes" VARCHAR(512),
    "actor_id" UUID,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "retailer_ledger_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "retailer_ledger_retailer_id_created_at_idx" ON "retailer_ledger"("retailer_id", "created_at" DESC);

-- AddForeignKey
ALTER TABLE "retailer_ledger" ADD CONSTRAINT "retailer_ledger_retailer_id_fkey" FOREIGN KEY ("retailer_id") REFERENCES "retailers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
