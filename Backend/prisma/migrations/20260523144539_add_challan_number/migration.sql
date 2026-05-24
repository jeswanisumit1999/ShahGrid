-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "challan_number" VARCHAR(16);

-- AlterTable
ALTER TABLE "shipments" ADD COLUMN     "challan_number" VARCHAR(16);
