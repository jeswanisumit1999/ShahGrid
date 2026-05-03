import { Router } from 'express';
import * as controller from './products.controller';
import { authenticate } from '../../middleware/auth.middleware';
import { requirePermission } from '../../middleware/rbac.middleware';
import { validate } from '../../middleware/validate.middleware';
import { createProductSchema, updateProductSchema, adjustStockSchema, listProductsQuerySchema } from './products.validators';

const router = Router();

router.use(authenticate);

/**
 * @openapi
 * /products:
 *   get:
 *     tags: [Products]
 *     summary: List products (paginated)
 *     parameters:
 *       - $ref: '#/components/parameters/cursor'
 *       - $ref: '#/components/parameters/limit'
 *       - name: search
 *         in: query
 *         schema: { type: string }
 *         description: Filter by name or SKU
 *       - name: companyId
 *         in: query
 *         schema: { type: string, format: uuid }
 *       - name: categoryId
 *         in: query
 *         schema: { type: string, format: uuid }
 *     responses:
 *       200:
 *         description: Paginated list of products
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: array
 *                   items: { $ref: '#/components/schemas/Product' }
 *                 pagination: { $ref: '#/components/schemas/PaginationMeta' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       403:
 *         $ref: '#/components/responses/Forbidden'
 */
router.get('/', requirePermission('products', 'read'), validate(listProductsQuerySchema, 'query'), controller.listProducts);

// Static sub-paths must come before /:id
router.get('/meta/brands', requirePermission('products', 'read'), controller.listBrands);
router.get('/meta/companies', requirePermission('products', 'manage'), controller.listCompanies);
router.post('/meta/companies', requirePermission('products', 'manage'), controller.createCompany);
router.get('/meta/categories', requirePermission('products', 'manage'), controller.listCategories);
router.post('/meta/categories', requirePermission('products', 'manage'), controller.createCategory);

/**
 * @openapi
 * /products/{id}:
 *   get:
 *     tags: [Products]
 *     summary: Get a single product
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     responses:
 *       200:
 *         description: Product detail
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Product' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.get('/:id', requirePermission('products', 'read'), controller.getProduct);

/**
 * @openapi
 * /products:
 *   post:
 *     tags: [Products]
 *     summary: Create a new product
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateProductRequest' }
 *     responses:
 *       201:
 *         description: Product created
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Product' }
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       409:
 *         description: A product with this SKU already exists
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
 */
router.post('/', requirePermission('products', 'manage'), validate(createProductSchema), controller.createProduct);

/**
 * @openapi
 * /products/{id}:
 *   patch:
 *     tags: [Products]
 *     summary: Update a product (partial update, SKU cannot be changed)
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/CreateProductRequest' }
 *     responses:
 *       200:
 *         description: Product updated
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Product' }
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.patch('/:id', requirePermission('products', 'manage'), validate(updateProductSchema), controller.updateProduct);

/**
 * @openapi
 * /products/{id}/stock-adjust:
 *   post:
 *     tags: [Products]
 *     summary: Manually adjust a product's stock level
 *     description: >
 *       Use a positive delta to add stock, negative to deduct.
 *       The adjustment is rejected if it would make stock go below zero.
 *       Every adjustment is recorded in the StockAdjustment audit table.
 *     parameters:
 *       - $ref: '#/components/parameters/resourceId'
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema: { $ref: '#/components/schemas/AdjustStockRequest' }
 *           example:
 *             delta: 100
 *             reason: "Received new stock from warehouse — Invoice #INV-2024-042"
 *     responses:
 *       200:
 *         description: Stock adjusted, returns updated product
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/Product' }
 *       400:
 *         description: Adjustment would result in negative stock
 *         content:
 *           application/json:
 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
 *             example:
 *               success: false
 *               error:
 *                 code: INSUFFICIENT_STOCK
 *                 message: "Adjustment would result in negative stock (current: 5, delta: -10)"
 *       404:
 *         $ref: '#/components/responses/NotFound'
 */
router.post('/:id/stock-adjust', requirePermission('stock', 'update'), validate(adjustStockSchema), controller.adjustStock);

export default router;
