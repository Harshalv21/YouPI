package `in`.youpi.config

import org.springframework.context.annotation.Configuration

// Global String<->Json converters removed — they were converting every
// String property (including plain VARCHAR fields like mobile, operator,
// status) into JSONB, causing "operator does not exist: character varying = jsonb"
// errors across unrelated queries (e.g. MPIN verify).
//
// JSONB fields now use io.r2dbc.postgresql.codec.Json directly as their
// Kotlin type (see RechargeOrderEntity.planDetails, a1topupRawResponse) —
// the r2dbc-postgresql driver handles this natively without needing a
// custom converter.
@Configuration
class R2dbcJsonConfig