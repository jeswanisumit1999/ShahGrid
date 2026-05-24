-- AlterTable
ALTER TABLE "payments" ADD COLUMN     "company_id" UUID;

-- CreateTable
CREATE TABLE "retailer_company_balances" (
    "retailer_id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "pending_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,

    CONSTRAINT "retailer_company_balances_pkey" PRIMARY KEY ("retailer_id","company_id")
);

-- AddForeignKey
ALTER TABLE "retailer_company_balances" ADD CONSTRAINT "retailer_company_balances_retailer_id_fkey" FOREIGN KEY ("retailer_id") REFERENCES "retailers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "retailer_company_balances" ADD CONSTRAINT "retailer_company_balances_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE SET NULL ON UPDATE CASCADE;
