import { OAuth2Client } from 'google-auth-library';
import { prisma } from '../../lib/prisma';
import { env } from '../../config/env';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '../../utils/jwt';
import { AppError } from '../../errors/AppError';

const oauthClient = new OAuth2Client(
  env.GOOGLE_CLIENT_ID,
  env.GOOGLE_CLIENT_SECRET,
  env.GOOGLE_CALLBACK_URL
);

// Emails that are automatically granted the Admin role on first sign-up
const ADMIN_EMAILS: string[] = [
  'manan.s.9999@gmail.com',
  'sumitjeswani.12@gmail.com'
];

async function buildTokenPayload(userId: string) {
  const user = await prisma.user.findUniqueOrThrow({
    where: { id: userId },
    include: {
      userRoles: {
        include: {
          role: { include: { rolePermissions: { include: { permission: true } } } },
        },
      },
    },
  });

  const roles = user.userRoles.map((ur) => ur.role.name);
  const permissions: string[] = [
    ...new Set<string>(
      user.userRoles.flatMap((ur) =>
        ur.role.rolePermissions.map((rp) => `${rp.permission.resource}.${rp.permission.action}`)
      )
    ),
  ];

  return { user, roles, permissions };
}

export async function exchangeGoogleCode(code: string) {
  let tokens;
  try {
    ({ tokens } = await oauthClient.getToken(code));
  } catch (err: any) {
    // invalid_grant = code already used or expired; invalid_client = bad credentials
    const reason = err?.response?.data?.error ?? err?.message ?? 'unknown';
    throw AppError.unauthorized(`Google OAuth failed: ${reason}`);
  }
  oauthClient.setCredentials(tokens);

  const ticket = await oauthClient.verifyIdToken({
    idToken: tokens.id_token!,
    audience: env.GOOGLE_CLIENT_ID,
  });

  const payload = ticket.getPayload();
  if (!payload?.sub || !payload.email) {
    throw AppError.unauthorized('Invalid Google token');
  }

  return upsertAndIssueTokens({ sub: payload.sub, email: payload.email!, name: payload.name, picture: payload.picture });
}

// Shared helper: upsert user from Google profile, issue JWT pair
async function upsertAndIssueTokens(profile: {
  sub: string;
  email: string;
  name?: string | null;
  picture?: string | null;
}) {
  const user = await prisma.$transaction(async (tx) => {
    const existing = await tx.user.findUnique({ where: { googleId: profile.sub } });

    if (existing) {
      return tx.user.update({
        where: { id: existing.id },
        data: {
          name: profile.name ?? existing.name,
          avatarUrl: profile.picture ?? existing.avatarUrl,
        },
      });
    }

    const isAdminEmail = ADMIN_EMAILS.includes(profile.email);
    const roleName = isAdminEmail ? 'Admin' : 'Pending';
    const initialRole = await tx.role.findUnique({ where: { name: roleName } });
    if (!initialRole) throw AppError.internal(`${roleName} role not seeded`);

    const newUser = await tx.user.create({
      data: {
        googleId: profile.sub,
        email: profile.email,
        name: profile.name ?? profile.email,
        avatarUrl: profile.picture,
      },
    });

    await tx.userRole.create({
      data: { userId: newUser.id, roleId: initialRole.id, assignedBy: newUser.id },
    });

    return newUser;
  });

  if (!user.isActive) throw AppError.forbidden('Account is deactivated');

  const { roles, permissions } = await buildTokenPayload(user.id);

  const accessToken = signAccessToken({ sub: user.id, email: user.email, roles, permissions });
  const refreshToken = signRefreshToken(user.id);

  return { accessToken, refreshToken, user: { id: user.id, email: user.email, name: user.name, avatarUrl: user.avatarUrl, roles } };
}

// Used by Flutter mobile/web via google_sign_in (skips code-exchange, verifies idToken directly)
export async function verifyGoogleIdToken(idToken: string) {
  let payload;
  try {
    const ticket = await oauthClient.verifyIdToken({ idToken, audience: env.GOOGLE_CLIENT_ID });
    payload = ticket.getPayload();
  } catch (err: any) {
    throw AppError.unauthorized(`Google token verification failed: ${err?.message ?? 'unknown'}`);
  }

  if (!payload?.sub || !payload.email) throw AppError.unauthorized('Invalid Google token');

  return upsertAndIssueTokens({ sub: payload.sub, email: payload.email, name: payload.name, picture: payload.picture });
}

export async function refreshAccessToken(refreshToken: string) {
  const payload = verifyRefreshToken(refreshToken);

  const user = await prisma.user.findUnique({ where: { id: payload.sub } });
  if (!user || !user.isActive) {
    throw AppError.unauthorized('User not found or deactivated');
  }

  const { roles, permissions } = await buildTokenPayload(user.id);

  const newAccessToken = signAccessToken({
    sub: user.id,
    email: user.email,
    roles,
    permissions,
  });

  return { accessToken: newAccessToken };
}

export function getGoogleAuthUrl() {
  return oauthClient.generateAuthUrl({
    access_type: 'offline',
    scope: ['openid', 'email', 'profile'],
    prompt: 'consent',
  });
}
