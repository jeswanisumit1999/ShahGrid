class ApiConstants {
  ApiConstants._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  // Auth
  static const String googleIdToken = '/auth/google/id-token';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';

  // Users
  static const String users = '/users';
  static const String roles = '/users/roles';
  static String roleById(String id) => '/users/roles/$id';
  static String rolePermissions(String id) => '/users/roles/$id/permissions';
  static const String permissions = '/users/permissions';
  static String userById(String id) => '/users/$id';
  static const String assignRole = '/users/assign-role';
  static String deactivateUser(String id) => '/users/$id/deactivate';
  static const String activityLog = '/users/activity-log';

  // Retailers
  static const String retailers = '/retailers';
  static const String retailersImport = '/retailers/import';
  static String retailerById(String id) => '/retailers/$id';
  static String retailerLedger(String id) => '/retailers/$id/ledger';
  static String retailerLedgerPdf(String id) => '/retailers/$id/ledger/pdf';

  // Products
  static const String products = '/products';
  static String productById(String id) => '/products/$id';
  static String stockAdjust(String id) => '/products/$id/stock-adjust';
  static String stockLedger(String id) => '/products/$id/ledger';
  static const String brands = '/products/meta/brands';
  static const String companies = '/products/meta/companies';
  static const String categories = '/products/meta/categories';
  // aliases used for POST (same URL, different method)
  static const String createCompany = '/products/meta/companies';
  static const String createCategory = '/products/meta/categories';

  // Orders
  static const String orders = '/orders';
  static String orderById(String id) => '/orders/$id';
  static String orderChallan(String id) => '/orders/$id/challan';
  static String orderItems(String orderId) => '/orders/$orderId/items';
  static String orderItemById(String orderId, String itemId) => '/orders/$orderId/items/$itemId';

  // Shipments
  static const String shipments = '/shipments';
  static String shipmentById(String id) => '/shipments/$id';
  static String shipmentStatus(String id) => '/shipments/$id/status';
  static String shipmentSplit(String id) => '/shipments/$id/split';

  // Payments
  static const String payments = '/payments';

  // Returns
  static const String returns = '/returns';

  // Visits
  static const String visits = '/visits';

  // CheckIns
  static const String checkins = '/checkins';

  // Analytics
  static const String dashboard = '/analytics/dashboard';
  static const String myStats = '/analytics/my-stats';
  static const String stockAlerts = '/analytics/stock-alerts';
  static const String godownStats = '/analytics/godown-stats';

  // Direct Sales
  static const String directSales = '/direct-sales';
  static String directSaleById(String id) => '/direct-sales/$id';
  static String directSaleChallan(String id) => '/direct-sales/$id/challan';

  // Settings
  static const String settings = '/settings';
  static String settingByKey(String key) => '/settings/$key';
}
