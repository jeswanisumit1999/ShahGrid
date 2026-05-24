-- CreateTable
CREATE TABLE "direct_sales" (
    "id" UUID NOT NULL,
    "customer_name" VARCHAR(255) NOT NULL,
    "sales_officer_id" UUID NOT NULL,
    "created_by_id" UUID NOT NULL,
    "total_amount" DECIMAL(12,2) NOT NULL,
    "challan_number" VARCHAR(16),
    "notes" VARCHAR(1024),
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL,

    CONSTRAINT "direct_sales_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "direct_sale_items" (
    "id" UUID NOT NULL,
    "direct_sale_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "unit_price" DECIMAL(10,2) NOT NULL,

    CONSTRAINT "direct_sale_items_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "direct_sales" ADD CONSTRAINT "direct_sales_sales_officer_id_fkey" FOREIGN KEY ("sales_officer_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "direct_sales" ADD CONSTRAINT "direct_sales_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "direct_sale_items" ADD CONSTRAINT "direct_sale_items_direct_sale_id_fkey" FOREIGN KEY ("direct_sale_id") REFERENCES "direct_sales"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "direct_sale_items" ADD CONSTRAINT "direct_sale_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
