# CLAUDE.md — Payment Aggregator

## Project Overview

A payment aggregator built with **Laravel 13** (backend) + **Vue 3 + TypeScript** (frontend).
The system supports multiple payment processors (Stripe, PayPal, etc.) with multiple accounts per processor, one-time payments, subscriptions, webhook processing, and outbound notifications to external services.

The architecture follows **DDD + Clean Architecture** principles with strict Bounded Context boundaries.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.3, Laravel 13 |
| Frontend | Vue 3, TypeScript, Vite, Pinia, Vue Router |
| Database | PostgreSQL 17 |
| Cache / Queue | Redis 7 |
| Message Broker | RabbitMQ 3.13 |
| Web Server | Nginx 1.25 + PHP-FPM |
| Process Manager | Supervisor |
| Containerization | Docker / Docker Compose |
| Payments | Stripe (primary), extensible to PayPal, etc. |
| Mail (dev) | Mailpit |
| Webhook testing | Stripe CLI |

---

## Repository Structure

```
/
├── payment-service-backend/     # Laravel application
├── payment-service-frontend/    # Vue 3 + TypeScript SPA
└── payment-service-docker/      # Docker, Nginx, PHP-FPM configs
```

---

## Backend Architecture

### Namespace Convention

```
app\
├── Domain\
│   ├── Payment\
│   ├── Subscription\
│   ├── Catalog\
│   ├── Processor\
│   ├── Webhook\
│   ├── Notification\
│   └── Customer\
├── Application\
│   ├── Payment\
│   ├── Subscription\
│   └── ... (per bounded context)
├── Infrastructure\
│   ├── Persistence\
│   │   └── Models\       # Eloquent models (infrastructure only)
│   ├── Providers\
│   └── ... (adapters, repositories)
└── Presentation\
    └── Http\
        └── Controllers\
```

> **Rule:** Eloquent models live **only** in `Infrastructure\Persistence\Models\`. Domain objects are plain PHP classes. Never use Eloquent in Domain or Application layers.

### Bounded Contexts

#### Core Domain

**Payment** — one-time payment lifecycle.
- Aggregate root: `Payment`
- Value objects: `Money`, `PaymentStatus`, `PaymentMethod`
- Entity: `PaymentAttempt`
- Use Cases: `CreateOneTimePaymentUseCase`, `RefundPaymentUseCase`, `GetPaymentStatusUseCase`

**Subscription** — recurring billing lifecycle.
- Aggregate root: `Subscription`
- Value objects: `SubscriptionStatus`, `SubscriptionPeriod`, `Trial`
- Entity: `SubscriptionCycle`
- Use Cases: `CreateSubscriptionUseCase`, `CancelSubscriptionUseCase`, `PauseSubscriptionUseCase`, `RenewSubscriptionUseCase`, `UpgradeDowngradeSubscriptionUseCase`

#### Supporting Domain

**Catalog** — products and prices.
- Aggregate root: `Product`
- Entity: `Price`
- Value objects: `PricingModel` (flat / per-seat / usage-based), `Currency`, `BillingInterval`
- Use Cases: `CreateProductUseCase`, `CreatePriceUseCase`, `SyncPriceWithProcessorUseCase`

**Processor** — payment processor accounts and routing.
- Aggregate root: `ProcessorAccount`
- Value objects: `ProcessorType` (Stripe / PayPal / …), `ProcessorCredentials`, `ProcessorCapability`
- Entity: `ProcessorRoutingRule`
- Use Cases: `RegisterProcessorAccountUseCase`, `SelectProcessorForPaymentUseCase`, `RotateProcessorCredentialsUseCase`

**Webhook** — inbound events from processors.
- Aggregate root: `WebhookEvent`
- Value objects: `WebhookEventType`, `WebhookSignature`, `WebhookEventPayload`, `IdempotencyKey`
- Use Cases: `ReceiveWebhookUseCase`, `VerifyWebhookSignatureUseCase`, `RouteWebhookEventUseCase`, `RetryFailedWebhookUseCase`

#### Generic Domain

**Notification** — outbound notifications to external services.
- Aggregate root: `OutboundNotification`
- Value objects: `NotificationStatus`, `NotificationPayload`, `NotificationEndpoint`, `RetryPolicy`
- Entity: `DeliveryAttempt`
- Use Cases: `NotifyExternalServiceUseCase`, `RetryFailedNotificationUseCase`

**Customer** — payer identity and processor references.
- Aggregate root: `Customer`
- Value objects: `CustomerExternalId`, `ProcessorCustomerReference`
- Use Cases: `RegisterCustomerUseCase`, `SyncCustomerWithProcessorUseCase`

### Context Map (event flow)

```
Webhook  ──(events)──▶  Payment
Webhook  ──(events)──▶  Subscription
Payment  ──(events)──▶  Notification
Subscription ─(events)─▶ Notification
Payment  ──────────────▶  Processor   (account selection)
Subscription ──────────▶  Processor   (account selection)
Payment  ──────────────▶  Catalog     (price lookup)
Subscription ──────────▶  Catalog     (price/product lookup)
Payment  ──────────────▶  Customer
Subscription ──────────▶  Customer
```

### Key Architecture Rules

- **Use Cases** are single-public-method classes (`handle()` or `execute()`). One class = one action.
- **Domain Events** are dispatched from aggregate roots. Infrastructure (listeners, jobs) reacts to them — never call use cases from domain objects.
- **Repository interfaces** are defined in `Domain`, implemented in `Infrastructure`.
- **No Eloquent in Domain or Application.** Repositories return domain objects, not Eloquent models.
- **Idempotency** is mandatory for webhook processing. Use `IdempotencyKey` value object.
- **Money** is always represented as integer cents + currency code. Never use floats.
- **ProcessorCredentials** are always encrypted at rest (Laravel `encrypted` cast).
- **Multiple accounts per processor**: routing is handled by `ProcessorRoutingRule` entities, not hardcoded logic.

---

## API Routes Convention

All backend API routes are prefixed with `/api/v1/`.

```
POST   /api/v1/payments                    # CreateOneTimePayment
GET    /api/v1/payments/{id}               # GetPaymentStatus
POST   /api/v1/payments/{id}/refund        # RefundPayment

POST   /api/v1/subscriptions               # CreateSubscription
DELETE /api/v1/subscriptions/{id}          # CancelSubscription
PATCH  /api/v1/subscriptions/{id}/pause    # PauseSubscription
POST   /api/v1/subscriptions/{id}/upgrade  # UpgradeDowngrade

GET    /api/v1/products                    # ListProducts
POST   /api/v1/products                    # CreateProduct
POST   /api/v1/products/{id}/prices        # CreatePrice

POST   /api/v1/webhooks/{processor}        # ReceiveWebhook (e.g. /webhooks/stripe)

POST   /api/v1/processor-accounts          # RegisterProcessorAccount
```

Webhook endpoints must **not** require authentication middleware. They use signature verification instead.

---

## Queue Configuration

Queues (Redis-backed, managed by Supervisor with 3 workers):

| Queue | Purpose |
|---|---|
| `high` | Webhook signature verification, payment status updates |
| `default` | Use case jobs, event dispatching |
| `low` | Outbound notifications, retries, reporting |

Job retry policy: 3 attempts, exponential backoff.
Max job timeout: 90 seconds.

---

## Running the Project

```bash
# Start all services
cd payment-service-docker
cp .env.example .env   # fill in credentials
docker compose up -d

# Backend setup (first run)
docker compose exec app composer install
docker compose exec app php artisan key:generate
docker compose exec app php artisan migrate

# Dev URLs
# Frontend:      http://localhost:5173
# Backend API:   http://localhost:8080/api/v1
# RabbitMQ UI:   http://localhost:15672
# Mailpit:       http://localhost:8025
# PostgreSQL:    localhost:5432
```

---

## Backend Commands

```bash
# Run tests
docker compose exec app php artisan test

# Run a specific test
docker compose exec app php artisan test --filter=PaymentTest

# Static analysis (if PHPStan installed)
docker compose exec app vendor/bin/phpstan analyse

# Code style fix
docker compose exec app vendor/bin/pint

# Queue worker (handled by Supervisor inside container, but manually)
docker compose exec app php artisan queue:work redis --queue=high,default,low
```

## Frontend Commands

```bash
cd payment-service-frontend

npm install
npm run dev          # Dev server on :5173
npm run build        # Production build
npm run type-check   # TypeScript check
npm run lint         # oxlint + eslint
npm run format       # Prettier
npm run test:unit    # Vitest
```

---

## Testing Strategy

- **Unit tests** (`tests/Unit/`): Domain objects, value objects, use cases with mocked repositories. No database, no HTTP.
- **Feature tests** (`tests/Feature/`): HTTP endpoints, database (SQLite in-memory), jobs dispatched synchronously.
- **Webhook tests**: Always test signature verification failure path first.
- Test environment uses `DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:`, `QUEUE_CONNECTION=sync`.

---

## Environment Variables (Backend)

Critical variables that must be set:

```dotenv
APP_KEY=           # required, generate with artisan key:generate
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_DATABASE=...
DB_USERNAME=...
DB_PASSWORD=...

REDIS_HOST=redis
QUEUE_CONNECTION=redis

STRIPE_SECRET_KEY=sk_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

For additional processor accounts, store credentials in the `processor_accounts` table (encrypted), not in `.env`.

---

## Adding a New Payment Processor

1. Create `ProcessorType::NEW_PROCESSOR` value in `Domain\Processor\ValueObjects\ProcessorType`.
2. Implement `ProcessorGatewayInterface` in `Infrastructure\Processors\NewProcessorGateway`.
3. Register the gateway in `AppServiceProvider` bound to the new `ProcessorType`.
4. Add webhook route: `POST /api/v1/webhooks/new-processor`.
5. Implement `WebhookEventType` mappings for the new processor's event names.
6. Write feature tests covering the full payment and webhook flow.

No changes to Domain use cases should be required — the gateway abstraction handles all processor-specific logic.

---

## Security Notes

- Webhook endpoints verify signatures **before** any processing. Reject with `400` on failure.
- `ProcessorCredentials` use Laravel `encrypted` cast — never log or expose raw values.
- All monetary values are validated as positive integers (cents). Reject floats at the API boundary.
- Idempotency keys must be stored and checked before processing any webhook event.
- Rate limiting applies to all public API endpoints (`throttle:api` middleware).

---

## Common Pitfalls

- **Do not** use `Payment::find()` or any Eloquent calls inside Domain or Application classes.
- **Do not** hardcode processor account IDs. Always resolve via `SelectProcessorForPaymentUseCase`.
- **Do not** dispatch `Notification` synchronously inside a webhook handler. Always queue it.
- **Do not** store raw webhook payloads longer than needed (PCI-DSS consideration).
- `Money` addition/subtraction must use the same currency. The domain throws on mismatch.
