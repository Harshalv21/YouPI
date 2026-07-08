rootProject.name = "youpi-backend"

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

// ── Main application module ──
include("app")

// ── Shared modules ──
include("shared:core")
include("shared:security")
include("shared:events")
include("shared:testkit")

// ── Feature modules ──
include("modules:auth")
include("modules:user")
include("modules:recharge")
include("modules:payment")
include("modules:wallet")
include("modules:smart-saver")
include("modules:invest")
include("modules:bnpl")
include("modules:loan")
include("modules:admin")


