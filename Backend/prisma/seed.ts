import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const SYSTEM_ROLES = [
  { name: 'Admin', description: 'Full access to all features and settings' },
  { name: 'Supply Chain', description: 'Manages shipments, stock, and challans' },
  { name: 'Sales Officer', description: 'Creates orders and records payments on mobile' },
  { name: 'Godown Manager', description: 'Updates stock and marks deliveries' },
  { name: 'Pending', description: 'Default role for new users — zero permissions' },
];

// resource.action pairs
const PERMISSIONS = [
  { resource: 'orders', action: 'create' },
  { resource: 'orders', action: 'read' },
  { resource: 'orders', action: 'manage' },
  { resource: 'shipments', action: 'manage' },
  { resource: 'stock', action: 'update' },
  { resource: 'products', action: 'read' },
  { resource: 'products', action: 'manage' },
  { resource: 'retailers', action: 'read' },
  { resource: 'retailers', action: 'manage' },
  { resource: 'retailers', action: 'credit_limit' },
  { resource: 'payments', action: 'record' },
  { resource: 'payments', action: 'read' },
  { resource: 'analytics', action: 'read' },
  { resource: 'roles', action: 'manage' },
  { resource: 'users', action: 'read' },
  { resource: 'users', action: 'manage' },
  { resource: 'settings', action: 'manage' },
  { resource: 'challans', action: 'generate' },
  { resource: 'returns', action: 'manage' },
  { resource: 'visits', action: 'create' },
  { resource: 'visits', action: 'read' },
  { resource: 'checkins', action: 'create' },
  { resource: 'checkins', action: 'read' },
  { resource: 'orders', action: 'direct_sale' },
];

const ROLE_PERMISSIONS: Record<string, string[]> = {
  Admin: [
    'orders.create', 'orders.read', 'orders.manage', 'orders.direct_sale',
    'shipments.manage', 'stock.update', 'products.read', 'products.manage',
    'retailers.read', 'retailers.manage', 'retailers.credit_limit',
    'payments.record', 'payments.read',
    'analytics.read', 'roles.manage',
    'users.read', 'users.manage', 'settings.manage',
    'challans.generate', 'returns.manage',
    'visits.create', 'visits.read',
    'checkins.create', 'checkins.read',
  ],
  'Supply Chain': [
    'orders.create', 'orders.read', 'orders.manage',
    'shipments.manage', 'stock.update', 'products.read', 'products.manage',
    'retailers.read', 'retailers.manage',
    'payments.record', 'payments.read', 'challans.generate', 'returns.manage',
  ],
  'Sales Officer': [
    'orders.create', 'orders.read',
    'retailers.read', 'retailers.manage',
    'products.read',
    'payments.read',
    'analytics.read',
    'visits.create', 'visits.read',
    'checkins.create', 'checkins.read',
  ],
  'Godown Manager': [
    'orders.read', 'orders.direct_sale', 'shipments.manage', 'stock.update',
    'products.read', 'products.manage', 'retailers.read', 'returns.manage',
  ],
  Pending: [],
};

const DEFAULT_SETTINGS = [
  {
    key: 'allow_credit_override',
    value: 'false',
    description: 'Allow sales officers to override retailer credit limits',
  },
  {
    key: 'sales_officer_view_all_retailers',
    value: 'false',
    description: 'Allow sales officers to view retailers not assigned to them',
  },
  {
    key: 'sales_officer_order_all_retailers',
    value: 'false',
    description: 'Allow sales officers to place orders for any retailer',
  },
  {
    key: 'next_challan_number',
    value: '1',
    description: 'Next challan sequence number',
  },
];

async function main() {
  console.log('Seeding database...');

  // Step 1: Upsert system roles
  console.log('  Creating system roles...');
  const roleRecords = await Promise.all(
    SYSTEM_ROLES.map((role) =>
      prisma.role.upsert({
        where: { name: role.name },
        update: {},
        create: { ...role, isSystemRole: true },
      })
    )
  );
  const roleByName = Object.fromEntries(roleRecords.map((r) => [r.name, r]));

  // Step 2: Upsert permissions
  console.log('  Creating permissions...');
  const permissionRecords = await Promise.all(
    PERMISSIONS.map((p) =>
      prisma.permission.upsert({
        where: { resource_action: { resource: p.resource, action: p.action } },
        update: {},
        create: p,
      })
    )
  );
  const permByKey = Object.fromEntries(
    permissionRecords.map((p) => [`${p.resource}.${p.action}`, p])
  );

  // Step 3: Assign permissions to roles
  console.log('  Assigning permissions to roles...');
  for (const [roleName, permKeys] of Object.entries(ROLE_PERMISSIONS)) {
    const role = roleByName[roleName];
    if (!role) continue;

    const permissionAssignments = permKeys
      .map((key) => {
        const perm = permByKey[key];
        if (!perm) {
          console.warn(`    Warning: permission "${key}" not found — skipping`);
          return null;
        }
        return { roleId: role.id, permissionId: perm.id };
      })
      .filter((x): x is { roleId: string; permissionId: string } => x !== null);

    // Delete then recreate so removed permissions are properly synced
    await prisma.rolePermission.deleteMany({ where: { roleId: role.id } });
    if (permissionAssignments.length > 0) {
      await prisma.rolePermission.createMany({ data: permissionAssignments });
    }

    console.log(`    ${roleName}: ${permissionAssignments.length} permissions`);
  }

  // Step 4: Seed default app settings
  console.log('  Creating app settings...');
  for (const setting of DEFAULT_SETTINGS) {
    await prisma.appSetting.upsert({
      where: { key: setting.key },
      update: {},
      create: { ...setting, updatedBy: null },
    });
  }

  console.log('Seed complete.');
}

main()
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
