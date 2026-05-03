/**
 * Cursor-based pagination helpers.
 * Cursor is the base64-encoded UUID of the last item in the previous page.
 */

export interface PaginationParams {
  cursor?: string;
  limit: number;
}

export interface PaginationResult<T> {
  items: T[];
  nextCursor: string | null;
  hasMore: boolean;
}

export function decodeCursor(cursor: string): string {
  return Buffer.from(cursor, 'base64').toString('utf8');
}

export function encodeCursor(id: string): string {
  return Buffer.from(id, 'utf8').toString('base64');
}

export function buildPaginationResult<T extends { id: string }>(
  items: T[],
  limit: number
): PaginationResult<T> {
  const hasMore = items.length > limit;
  const page = hasMore ? items.slice(0, limit) : items;
  const nextCursor =
    hasMore ? encodeCursor(page[page.length - 1].id) : null;

  return { items: page, nextCursor, hasMore };
}

/** Build Prisma cursor/skip args from an incoming cursor string. */
export function buildPrismaPage(params: PaginationParams) {
  const { cursor, limit } = params;
  return {
    take: limit + 1, // fetch one extra to detect hasMore
    ...(cursor && {
      cursor: { id: decodeCursor(cursor) },
      skip: 1,
    }),
  };
}
