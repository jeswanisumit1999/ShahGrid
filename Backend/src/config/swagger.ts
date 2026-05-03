import swaggerJsdoc from 'swagger-jsdoc';
import path from 'path';

// ─────────────────────────────────────────────────────────────────────────────
// Reusable component schemas, parameters, and responses.
// Individual endpoint documentation lives in *.routes.ts files via @openapi
// JSDoc comments; swagger-jsdoc merges them with this definition at startup.
// ─────────────────────────────────────────────────────────────────────────────

const definition: swaggerJsdoc.SwaggerDefinition = {
  openapi: '3.0.0',
  info: {
    title: 'ShahGrid API',
    version: '1.0.0',
    description:
      'B2B distribution platform — orders, shipments, payments, retailers, and stock management.',
    contact: { name: 'ShahGrid Team' },
  },
  servers: [
    { url: 'http://localhost:3000/api/v1', description: 'Local development' },
  ],
  // All protected endpoints require a Bearer JWT unless marked otherwise.
  security: [{ bearerAuth: [] }],

  components: {
    // ── Security ──────────────────────────────────────────────────────────────
    securitySchemes: {
      bearerAuth: {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
        description: 'Access token obtained from POST /auth/refresh or GET /auth/google/callback',
      },
    },

    // ── Reusable parameters ───────────────────────────────────────────────────
    parameters: {
      cursor: {
        name: 'cursor',
        in: 'query',
        schema: { type: 'string' },
        description: 'Base64-encoded ID of the last item on the previous page',
      },
      limit: {
        name: 'limit',
        in: 'query',
        schema: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
        description: 'Number of items per page',
      },
      resourceId: {
        name: 'id',
        in: 'path',
        required: true,
        schema: { type: 'string', format: 'uuid' },
      },
    },

    // ── Common responses ──────────────────────────────────────────────────────
    responses: {
      Unauthorized: {
        description: 'Missing or invalid access token',
        content: {
          'application/json': {
            schema: { $ref: '#/components/schemas/ErrorResponse' },
            example: { success: false, error: { code: 'UNAUTHORIZED', message: 'Authentication required' } },
          },
        },
      },
      Forbidden: {
        description: 'Authenticated but insufficient permissions',
        content: {
          'application/json': {
            schema: { $ref: '#/components/schemas/ErrorResponse' },
            example: { success: false, error: { code: 'FORBIDDEN', message: 'Missing permission: orders.create' } },
          },
        },
      },
      NotFound: {
        description: 'Resource not found',
        content: {
          'application/json': {
            schema: { $ref: '#/components/schemas/ErrorResponse' },
            example: { success: false, error: { code: 'NOT_FOUND', message: 'Order not found' } },
          },
        },
      },
      ValidationError: {
        description: 'Request body or query failed Zod validation',
        content: {
          'application/json': {
            schema: { $ref: '#/components/schemas/ErrorResponse' },
            example: { success: false, error: { code: 'VALIDATION_ERROR', message: 'items: Required' } },
          },
        },
      },
    },

    // ── Schemas ───────────────────────────────────────────────────────────────
    schemas: {
      // ── Primitives ──────────────────────────────────────────────────────────
      ErrorResponse: {
        type: 'object',
        properties: {
          success: { type: 'boolean', example: false },
          error: {
            type: 'object',
            properties: {
              code: { type: 'string', example: 'NOT_FOUND' },
              message: { type: 'string', example: 'Order not found' },
            },
          },
        },
      },
      PaginationMeta: {
        type: 'object',
        properties: {
          nextCursor: { type: 'string', nullable: true, example: 'dXVpZC1zdHJpbmc=' },
          hasMore: { type: 'boolean', example: true },
        },
      },

      // ── Identity ─────────────────────────────────────────────────────────────
      Permission: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          resource: { type: 'string', example: 'orders' },
          action: { type: 'string', example: 'create' },
        },
      },
      Role: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'Sales Officer' },
          description: { type: 'string', example: 'Creates orders and records payments' },
          isSystemRole: { type: 'boolean', example: true },
          rolePermissions: {
            type: 'array',
            items: {
              type: 'object',
              properties: { permission: { $ref: '#/components/schemas/Permission' } },
            },
          },
        },
      },
      UserSummary: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          email: { type: 'string', format: 'email', example: 'user@example.com' },
          name: { type: 'string', example: 'Rahul Sharma' },
          avatarUrl: { type: 'string', nullable: true },
          isActive: { type: 'boolean', example: true },
        },
      },
      UserDetail: {
        allOf: [
          { $ref: '#/components/schemas/UserSummary' },
          {
            type: 'object',
            properties: {
              userRoles: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: { role: { $ref: '#/components/schemas/Role' } },
                },
              },
            },
          },
        ],
      },
      AuthResponse: {
        type: 'object',
        properties: {
          accessToken: { type: 'string', example: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' },
          user: {
            type: 'object',
            properties: {
              id: { type: 'string', format: 'uuid' },
              email: { type: 'string', example: 'user@example.com' },
              name: { type: 'string', example: 'Rahul Sharma' },
              avatarUrl: { type: 'string', nullable: true },
              roles: { type: 'array', items: { type: 'string' }, example: ['Sales Officer'] },
            },
          },
        },
      },
      AssignRoleRequest: {
        type: 'object',
        required: ['userId', 'roleId'],
        properties: {
          userId: { type: 'string', format: 'uuid' },
          roleId: { type: 'string', format: 'uuid' },
        },
      },

      // ── Retailer ──────────────────────────────────────────────────────────────
      Retailer: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'Krishna General Store' },
          phone: { type: 'string', example: '+919876543210' },
          address: { type: 'string', nullable: true },
          creditLimit: { type: 'number', example: 50000 },
          pendingCollection: { type: 'number', example: 12500 },
          allowCompanyOverride: { type: 'boolean', example: false },
          isDirectSale: { type: 'boolean', example: false },
          isActive: { type: 'boolean', example: true },
          createdAt: { type: 'string', format: 'date-time' },
        },
      },
      CreateRetailerRequest: {
        type: 'object',
        required: ['name', 'phone'],
        properties: {
          name: { type: 'string', example: 'Krishna General Store' },
          phone: { type: 'string', example: '+919876543210' },
          address: { type: 'string', example: '12 MG Road, Pune' },
          creditLimit: { type: 'number', minimum: 0, default: 0, example: 50000 },
          allowCompanyOverride: { type: 'boolean', default: false },
          isDirectSale: { type: 'boolean', default: false },
          salesOfficerIds: {
            type: 'array',
            items: { type: 'string', format: 'uuid' },
            description: 'UUIDs of sales officers to assign',
          },
        },
      },

      // ── Catalog ───────────────────────────────────────────────────────────────
      Company: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'Hindustan Unilever' },
          isActive: { type: 'boolean' },
        },
      },
      Category: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'Personal Care' },
        },
      },
      Product: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'Dove Soap 100g' },
          sku: { type: 'string', example: 'HUL-DOVE-100' },
          price: { type: 'number', example: 45.0 },
          stockQuantity: { type: 'integer', example: 240 },
          isActive: { type: 'boolean' },
          company: { $ref: '#/components/schemas/Company' },
          category: { $ref: '#/components/schemas/Category', nullable: true },
        },
      },
      CreateProductRequest: {
        type: 'object',
        required: ['companyId', 'name', 'sku', 'price'],
        properties: {
          companyId: { type: 'string', format: 'uuid' },
          categoryId: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'Dove Soap 100g' },
          sku: { type: 'string', example: 'HUL-DOVE-100' },
          price: { type: 'number', minimum: 0.01, example: 45.0 },
          stockQuantity: { type: 'integer', minimum: 0, default: 0 },
        },
      },
      AdjustStockRequest: {
        type: 'object',
        required: ['delta'],
        properties: {
          delta: { type: 'integer', example: 50, description: 'Positive to add, negative to deduct' },
          reason: { type: 'string', example: 'Received new shipment from warehouse' },
        },
      },

      // ── Orders ────────────────────────────────────────────────────────────────
      OrderItem: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          productId: { type: 'string', format: 'uuid' },
          quantity: { type: 'integer', example: 10 },
          unitPrice: { type: 'number', example: 45.0 },
          deliveredQuantity: { type: 'integer', nullable: true, example: 5 },
          product: {
            type: 'object',
            properties: {
              id: { type: 'string', format: 'uuid' },
              name: { type: 'string' },
              sku: { type: 'string' },
            },
          },
        },
      },
      Order: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          retailerId: { type: 'string', format: 'uuid' },
          salesOfficerId: { type: 'string', format: 'uuid' },
          isDirectSale: { type: 'boolean' },
          totalAmount: { type: 'number', example: 4500.0 },
          notes: { type: 'string', nullable: true },
          createdAt: { type: 'string', format: 'date-time' },
          retailer: { $ref: '#/components/schemas/Retailer' },
          orderItems: { type: 'array', items: { $ref: '#/components/schemas/OrderItem' } },
          shipments: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: { type: 'string', format: 'uuid' },
                status: { type: 'string', example: 'Dispatched' },
              },
            },
          },
        },
      },
      CreateOrderRequest: {
        type: 'object',
        required: ['retailerId', 'salesOfficerId', 'items'],
        properties: {
          retailerId: { type: 'string', format: 'uuid' },
          salesOfficerId: { type: 'string', format: 'uuid' },
          overrideCompanyId: { type: 'string', format: 'uuid', description: 'Override fulfilling company (if retailer allows it)' },
          notes: { type: 'string', maxLength: 1024 },
          items: {
            type: 'array',
            minItems: 1,
            items: {
              type: 'object',
              required: ['productId', 'quantity', 'unitPrice'],
              properties: {
                productId: { type: 'string', format: 'uuid' },
                quantity: { type: 'integer', minimum: 1, example: 10 },
                unitPrice: { type: 'number', minimum: 0.01, example: 45.0 },
              },
            },
          },
        },
      },

      // ── Shipments ─────────────────────────────────────────────────────────────
      Shipment: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          orderId: { type: 'string', format: 'uuid' },
          companyId: { type: 'string', format: 'uuid' },
          status: {
            type: 'string',
            enum: [
              'Pending Stock Verification',
              'Pending Stock Availability',
              'Stock Confirmed',
              'Dispatched',
              'Delivered',
              'Cancelled',
            ],
            example: 'Stock Confirmed',
          },
          dispatchedAt: { type: 'string', format: 'date-time', nullable: true },
          deliveredAt: { type: 'string', format: 'date-time', nullable: true },
          createdAt: { type: 'string', format: 'date-time' },
        },
      },
      UpdateShipmentStatusRequest: {
        type: 'object',
        required: ['status'],
        properties: {
          status: {
            type: 'string',
            enum: [
              'Pending Stock Verification',
              'Pending Stock Availability',
              'Stock Confirmed',
              'Dispatched',
              'Delivered',
              'Cancelled',
            ],
          },
          notes: { type: 'string', maxLength: 1024 },
        },
      },

      // ── Payments ──────────────────────────────────────────────────────────────
      Payment: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          orderId: { type: 'string', format: 'uuid' },
          retailerId: { type: 'string', format: 'uuid' },
          amount: { type: 'number', example: 4500.0 },
          paymentDate: { type: 'string', format: 'date', example: '2024-04-25' },
          method: { type: 'string', enum: ['cash', 'upi', 'bank_transfer', 'cheque', 'other'] },
          referenceNo: { type: 'string', nullable: true },
          idempotencyKey: { type: 'string', nullable: true },
          createdAt: { type: 'string', format: 'date-time' },
        },
      },
      RecordPaymentRequest: {
        type: 'object',
        required: ['orderId', 'retailerId', 'amount', 'paymentDate', 'method'],
        properties: {
          orderId: { type: 'string', format: 'uuid' },
          retailerId: { type: 'string', format: 'uuid' },
          amount: { type: 'number', minimum: 0.01, example: 4500.0 },
          paymentDate: { type: 'string', format: 'date', example: '2024-04-25' },
          method: { type: 'string', enum: ['cash', 'upi', 'bank_transfer', 'cheque', 'other'] },
          referenceNo: { type: 'string', example: 'UPI-TXN-20240425001' },
          idempotencyKey: {
            type: 'string',
            description: 'Client-generated unique key to prevent duplicate submissions from mobile clients',
            example: 'mobile-client-uuid-v4',
          },
          notes: { type: 'string' },
        },
      },

      // ── Returns ───────────────────────────────────────────────────────────────
      Return: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          orderId: { type: 'string', format: 'uuid' },
          retailerId: { type: 'string', format: 'uuid' },
          returnValue: { type: 'number', example: 450.0 },
          reason: { type: 'string', nullable: true },
          createdAt: { type: 'string', format: 'date-time' },
        },
      },
      CreateReturnRequest: {
        type: 'object',
        required: ['orderId', 'retailerId', 'items'],
        properties: {
          orderId: { type: 'string', format: 'uuid' },
          retailerId: { type: 'string', format: 'uuid' },
          reason: { type: 'string', maxLength: 512 },
          items: {
            type: 'array',
            minItems: 1,
            items: {
              type: 'object',
              required: ['orderItemId', 'quantity'],
              properties: {
                orderItemId: { type: 'string', format: 'uuid' },
                quantity: { type: 'integer', minimum: 1 },
              },
            },
          },
        },
      },

      // ── Visits ────────────────────────────────────────────────────────────────
      VisitLog: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          userId: { type: 'string', format: 'uuid' },
          retailerId: { type: 'string', format: 'uuid' },
          latitude: { type: 'number', example: 18.5204 },
          longitude: { type: 'number', example: 73.8567 },
          notes: { type: 'string', nullable: true },
          visitedAt: { type: 'string', format: 'date-time' },
        },
      },
      CreateVisitRequest: {
        type: 'object',
        required: ['retailerId', 'latitude', 'longitude'],
        properties: {
          retailerId: { type: 'string', format: 'uuid' },
          latitude: { type: 'number', minimum: -90, maximum: 90, example: 18.5204 },
          longitude: { type: 'number', minimum: -180, maximum: 180, example: 73.8567 },
          notes: { type: 'string', maxLength: 512 },
        },
      },

      // ── Settings ──────────────────────────────────────────────────────────────
      AppSetting: {
        type: 'object',
        properties: {
          key: { type: 'string', example: 'allow_credit_override' },
          value: { type: 'string', example: 'false' },
          description: { type: 'string', nullable: true, example: 'Allow sales officers to override retailer credit limits' },
          updatedAt: { type: 'string', format: 'date-time' },
        },
      },
      UpdateSettingRequest: {
        type: 'object',
        required: ['value'],
        properties: {
          value: { type: 'string', minLength: 1, maxLength: 512, example: 'true' },
        },
      },
    },
  },
};

const options: swaggerJsdoc.Options = {
  definition,
  // swagger-jsdoc reads JSDoc @openapi comments from these files
  apis: [
    path.join(process.cwd(), 'src/modules/**/*.routes.ts'),  // ts-node (dev)
    path.join(process.cwd(), 'dist/modules/**/*.routes.js'), // compiled (prod)
  ],
};

export const swaggerSpec = swaggerJsdoc(options);
