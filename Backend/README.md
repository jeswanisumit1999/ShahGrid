
# 🚀 SHAH GRID Backend Application

A Node.js backend powered by **Express**, **Prisma**, and **PostgreSQL**, with authentication and fully documented APIs using Swagger.

---

## 📦 Prerequisites

Make sure you have the following installed:

* Node.js (v18 or higher)
* Docker

---

## ⚙️ Setup & Installation

### 1. Install Dependencies

```bash
cd /Users/sumit/Desktop/ShahGrid-claude/Backend
npm install
```

---

### 2. Start PostgreSQL (Docker)

```bash
docker-compose up -d
```

---

### 3. Configure Environment Variables

```bash
cp .env.example .env
```

Update the `.env` file:

* `JWT_ACCESS_SECRET` → Any random string (≥ 32 characters)
* `JWT_REFRESH_SECRET` → Any random string (≥ 32 characters)
* `GOOGLE_CLIENT_ID` → From Google Cloud Console → APIs & Services → Credentials
* `GOOGLE_CLIENT_SECRET` → From Google Cloud Console
* `GOOGLE_CALLBACK_URL` →

  ```
  http://localhost:3000/api/v1/auth/google/callback
  ```

> Leave other values as-is for local development.

---

### 4. Generate Prisma Client

```bash
npx prisma generate
```

---

### 5. Run Database Migrations

```bash
npx prisma migrate dev --name init
```

---

### 6. Seed the Database

```bash
npm run db:seed
```

---

### 7. Start Development Server

```bash
npm run dev
```

Server will start at:

👉 [http://localhost:3000](http://localhost:3000)

Test health endpoint:

```bash
curl http://localhost:3000/health
```

---

## 📘 API Documentation (Swagger)

### Access Swagger UI

| URL                                                                        | Description            |
| -------------------------------------------------------------------------- | ---------------------- |
| [http://localhost:3000/api-docs](http://localhost:3000/api-docs)           | Interactive Swagger UI |
| [http://localhost:3000/api-docs.json](http://localhost:3000/api-docs.json) | Raw OpenAPI JSON       |

---

### 🔐 Authenticate in Swagger

1. Open: [http://localhost:3000/api-docs](http://localhost:3000/api-docs)
2. Click **Authorize** (top-right)
3. Paste your **access token** (from `/auth/google/callback`)
4. Click **Authorize**

> Token persists across refresh (`persistAuthorization: true`)

---

## 🛠️ Project Structure Changes

### ✅ New File

* `src/config/swagger.ts`

  * Contains OpenAPI schemas (19 schemas, 3 parameters, 4 responses)
  * Defines `bearerAuth` security scheme
  * Exports `swaggerSpec`

---

### ✏️ Modified Files

#### `src/app.ts`

* Swagger UI mounted at `/api-docs`
* Raw OpenAPI JSON available at `/api-docs.json`
* Mounted **before Helmet** to avoid CSP issues

---

#### Route Files (11 files updated)

* Added `@openapi` JSDoc documentation
* Includes:

  * Tags
  * Parameters
  * Request schemas
  * Response codes

**Special Endpoints with Full Examples:**

* `POST /orders`
* `POST /products/:id/stock-adjust`

---

## 🧪 Troubleshooting

| Problem                  | Fix                                                          |
| ------------------------ | ------------------------------------------------------------ |
| `DATABASE_URL` error     | Ensure Docker is running → `docker ps`                       |
| JWT secret too short     | Must be ≥ 32 characters                                      |
| Prisma generate fails    | Run `npm install` first                                      |
| Port 5432 already in use | Stop local PostgreSQL or change port in `docker-compose.yml` |

---

## 🧠 Notes

* Uses Prisma ORM for database management
* PostgreSQL runs inside Docker container
* Google OAuth is used for authentication
* Swagger provides full API visibility and testing

---

## 📌 Quick Start Summary

```bash
npm install
docker-compose up -d
cp .env.example .env
npx prisma generate
npx prisma migrate dev --name init
npm run db:seed
npm run dev
```
