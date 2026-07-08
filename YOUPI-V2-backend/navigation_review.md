# YOUPI V2 — Deep Navigation & Button Review

## Router Overview

The app uses **GoRouter v13** with a **ShellRoute** for the bottom nav tabs and flat `GoRoute` entries for all other screens.

---

## 🗺️ Full Route Map

```
/splash
/onboarding/welcome
/onboarding/carousel           ← Never navigated to (orphaned!)
/auth/mobile
/auth/otp
/auth/profile-setup
/auth/mpin-setup
/kyc/intro
/kyc/aadhaar
/kyc/pan
/kyc/success

[ShellRoute — shows BottomNav]
  /dashboard/home
  /dashboard/plans
  /dashboard/invest
  /dashboard/wallet
  /dashboard/settings
  /dashboard/bnpl              ← In ShellRoute but NOT in BottomNav!

/plans/browse
/plans/search
/plans/smartsave
/plans/emi-select
/plans/success
/invest/gold
/invest/fd
/invest/portfolio
/bnpl/apply/step1
/bnpl/apply/step2
/bnpl/apply/step3
/bnpl/not-approved
/bnpl/smart-deposit
/bnpl/approved
/loan/apply/step1
/loan/apply/step2
/loan/apply/step3
/loan/approved
/loan/my-loans
/wallet/add
/wallet/withdraw
/wallet/send
/wallet/history
/settings/edit-profile
/settings/notifications
/settings/change-mpin
```

---

## 🧭 Screen-by-Screen Navigation Audit

### 1. SplashScreen `/splash`
| Condition | Destination | Method |
|-----------|-------------|--------|
| First launch | `/onboarding/welcome` | `context.go()` ✅ |
| Has token | `/dashboard/home` | `context.go()` ✅ |
| No token | `/onboarding/welcome` | `context.go()` ✅ |

> **Note:** 2.5 second hard-coded delay before navigation. When `hasToken`, the app goes to `/dashboard/home` skipping KYC status check — so even unverified users land on dashboard.

---

### 2. WelcomeScreen `/onboarding/welcome`
| Button | Action | Destination | Method |
|--------|--------|-------------|--------|
| Register card (YoupiCard) | Tap | `/auth/mobile` | `context.push()` ✅ |
| Login card (YoupiCard) | Tap | `/auth/mobile` | `context.push()` ✅ |
| "Explore as Guest" (ghost YoupiButton) | Tap | `/dashboard/home` | `context.go()` ✅ |

> **⚠️ Bug:** Register and Login cards both go to the **same route** `/auth/mobile`. There is no distinction between a new registration vs. an existing login. These are functionally identical.
>
> **⚠️ Orphan:** `/onboarding/carousel` is registered in the router but **no button anywhere navigates to it**. The OnboardingCarouselScreen is completely unreachable from the app.

---

### 3. OnboardingCarouselScreen `/onboarding/carousel` — ⚠️ UNREACHABLE
| Button | Action | Destination | Method |
|--------|--------|-------------|--------|
| Skip (TextButton, top-right) | Tap | `/auth/mobile` | `context.go()` |
| Next / Get Started (YoupiButton) | Tap last page | `/auth/mobile` | `context.go()` |
| Next (YoupiButton) | Tap other pages | next slide | `_pageController.nextPage()` |

> This entire screen is dead code — it cannot be reached.

---

### 4. MobileEntryScreen `/auth/mobile`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Send OTP" (YoupiButton) | Tap (valid mobile) | `/auth/otp` | `context.push()` ✅ |
| "Send OTP" (YoupiButton) | Tap (invalid) | disabled | `null` ✅ |
| Terms link (TextButton) | Tap | **nothing** (`() {}`) | ❌ Dead button |

> **⚠️ Bug:** AUT flow — After OTP verification, the app goes to `/auth/profile-setup` **every time** regardless of whether the user is new or returning. Returning users should go to `/dashboard/home` or a MPIN entry screen.

---

### 5. OtpVerifyScreen `/auth/otp`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Change Number" (TextButton) | Tap | Previous screen | `context.pop()` ✅ |
| "Resend OTP" (TextButton) | Tap | sends OTP again | calls `vm.resendOtp()` ✅ |
| "Verify & Continue" (YoupiButton) | Success | `/auth/profile-setup` | `context.go()` |

> **⚠️ Bug:** Local `_otp` string variable is declared inside `build()` — it resets on every rebuild, which means OTP value may be lost if ViewModel notifies. This is a **state management bug**.
>
> **⚠️ Flow:** Always navigates to profile-setup — no check for whether this is a returning user.

---

### 6. UserProfileSetupScreen `/auth/profile-setup`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| DOB picker (GestureDetector) | Tap | Date Picker dialog | `showDatePicker()` ✅ |
| "Continue" (YoupiButton) | Tap (valid step1) | `/auth/mpin-setup` | `context.push()` ✅ |
| "Continue" (YoupiButton) | Tap (invalid) | disabled | `null` ✅ |
| AppBar back | Tap | OTP screen | default back ✅ |

> **⚠️ Issue:** `ChangeNotifierProvider` creates a **new** `AuthViewModel` here, completely disconnected from the one used in MobileEntryScreen. The mobile number passed from Step 1 is **lost**. This means the profile setup has no link to the actual phone number that was verified.
>
> Shows "Step 1 of 3" progress bar, but there's no step progression indicator visible on other auth screens — inconsistent UX.

---

### 7. MpinSetupScreen `/auth/mpin-setup`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| Number keys (GestureDetector) | Tap | increments PIN | setState ✅ |
| Backspace key | Tap | deletes digit | setState ✅ |
| Auto-submit (after 4th confirm digit) | — | `/kyc/intro` | `context.go()` ✅ |
| AppBar back | Tap | profile-setup | default back ✅ |

> **⚠️ Bug:** MPIN mismatch shows a SnackBar but doesn't reset to re-enter the original MPIN — it only clears `_confirmMpin` and sets `_isLoading = true` but never sets it back to false on mismatch.

---

### 8. KycIntroScreen `/kyc/intro`
| Button | Destination | Method |
|--------|-------------|--------|
| "Start KYC" (YoupiButton) | `/kyc/aadhaar` | `context.push()` ✅ |
| "Skip for Now" (ghost YoupiButton) | `/dashboard/home` | `context.go()` ✅ |
| AppBar back | previous screen | default back ✅ |

---

### 9. AadhaarVerifyScreen `/kyc/aadhaar`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Get Aadhaar OTP" (YoupiButton) | Tap | shows OTP field | `vm.sendAadhaarOtp()` ✅ |
| "Resend OTP" (TextButton) | Tap | resends OTP | `vm.sendAadhaarOtp()` ✅ |
| "Verify Aadhaar" (YoupiButton) | Success | `/kyc/pan` | `context.push()` ✅ |
| ExpansionTile "Why Aadhaar?" | Tap | expands info | in-place ✅ |
| AppBar back | Tap | `/kyc/intro` | default back ✅ |

> **⚠️ Bug:** Same `_otp` local variable issue as OtpVerifyScreen — declared inside `build()`, will lose value on ViewModel rebuilds.
>
> **⚠️ Bug:** Creates a **new** `KycViewModel` instance — if user came through the MpinSetupScreen, any Aadhaar state from previous screens is lost (but KYC starts fresh here anyway so less impactful).

---

### 10. PanVerifyScreen `/kyc/pan`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| PAN input | type | validates PAN | `vm.setPan()` ✅ |
| Selfie circle (GestureDetector) | Tap | simulates capture | `vm.captureSelfie()` ✅ |
| "Complete KYC" (YoupiButton) | Success | `/kyc/success` | `context.go()` ✅ |
| "Complete KYC" | PAN not verified or no selfie | disabled | `null` ✅ |
| AppBar back | Tap | `/kyc/aadhaar` | default back ✅ |

> **⚠️ Bug:** Creates yet another new `KycViewModel` — Aadhaar verification state from step 2 is completely lost. `panVerified` depends only on what the user types here; no cross-step validation.

---

### 11. KycSuccessScreen `/kyc/success`
| Button | Destination | Method |
|--------|-------------|--------|
| "Go to Dashboard" (YoupiButton) | `/dashboard/home` | `context.go()` ✅ |

---

## 🏠 Dashboard Shell (Bottom Navigation)

The `MainShell` has 5 tabs: **Home, Plans, Invest, Wallet, Settings**.

> **⚠️ Bug:** `/dashboard/bnpl` is registered **inside the ShellRoute** but is **NOT in the `_routes` list** of `MainShell`. So going to BNPL hub from a `context.go('/dashboard/bnpl')` call will show the BNPL screen inside the shell, but the active BottomNav tab will incorrectly highlight `Home` (index 0 fallback). Users will be confused.

---

### 12. HomeScreen `/dashboard/home`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| Bell icon (notification) | Tap | **nothing** (`() {}`) | ❌ Dead button |
| "View Wallet" chip (GestureDetector) | Tap | `/dashboard/wallet` | `context.go()` ✅ |
| "Recharge" quick action | Tap | `/dashboard/plans` | `context.go()` ✅ |
| "Smart Saver" quick action | Tap | `/plans/smartsave` | `context.push()` ✅ |
| "Wallet" quick action | Tap | `/dashboard/wallet` | `context.go()` ✅ |
| "Gold" quick action | Tap | `/invest/gold` | `context.push()` ✅ |
| "FD Invest" quick action | Tap | `/invest/fd` | `context.push()` ✅ |
| "BNPL Shop" quick action | Tap | `/dashboard/bnpl` | `context.go()` ✅ |
| "View all" (Portfolio) TextButton | Tap | `/invest/portfolio` | `context.push()` ✅ |
| Offer cards | — | **non-tappable** | ❌ No onTap |
| Pull-to-refresh | swipe | `vm.loadHome()` | ✅ |

> **⚠️ Observations:**
> - Bell Icon is a dead button — no notification screen exists.
> - Offer cards have no tap handlers.

---

### 13. RechargeHomeScreen `/dashboard/plans`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| Search icon (AppBar action) | Tap | `/plans/search` | `context.push()` ✅ |
| Edit icon (mobile number) | Tap | **nothing** (`() {}`) | ❌ Dead button |
| "Browse All" TextButton | Tap | `/plans/browse` | `context.push()` ✅ |
| Plan card (YoupiCard) | Tap | `/plans/emi-select` | `context.push()` ✅ |
| EMI chips | Tap | **nothing** (display only) | ❌ Not interactive |

---

### 14. InvestHubScreen `/dashboard/invest`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Buy / Sell Digital Gold" (YoupiButton) | Tap | `/invest/gold` | `context.push()` ✅ |
| "Fixed Deposits" (YoupiCard) | Tap | `/invest/fd` | `context.push()` ✅ |
| "My Portfolio" (YoupiCard) | Tap | `/invest/portfolio` | `context.push()` ✅ |

---

### 15. WalletScreen `/dashboard/wallet`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Add Money" action | Tap | `/wallet/add` | `context.push()` ✅ |
| "Send Money" action | Tap | `/wallet/send` | `context.push()` ✅ |
| "Withdraw" action | Tap | `/wallet/withdraw` | `context.push()` ✅ |
| "View All" (transactions) | Tap | `/wallet/history` | `context.push()` ✅ |

---

### 16. BnplHubScreen `/dashboard/bnpl`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Apply for Limit Increase" action | Tap | `/bnpl/apply/step1` | `context.push()` ✅ |
| "Smart Deposit" action | Tap | `/bnpl/smart-deposit` | `context.push()` ✅ |
| "Enable SmartDeposit" (YoupiButton) | Tap | `/bnpl/smart-deposit` | `context.push()` ✅ |
| "Where to use BNPL" chips | — | **non-tappable** | ❌ Informational only |

---

### 17. SettingsScreen `/dashboard/settings`
| Element | Action | Destination | Method |
|---------|--------|-------------|--------|
| "Edit Profile" tile | Tap | `/settings/edit-profile` | `context.push()` ✅ |
| "Change MPIN" tile | Tap | `/settings/change-mpin` | `context.push()` ✅ |
| "Notifications" tile | Tap | `/settings/notifications` | `context.push()` ✅ |
| "Help & Support" tile | Tap | **nothing** (`() {}`) | ❌ Dead button |
| "Privacy Policy" tile | Tap | **nothing** (`() {}`) | ❌ Dead button |
| "Terms of Service" tile | Tap | **nothing** (`() {}`) | ❌ Dead button |
| "Sign Out" (YoupiCard) | Tap | `/onboarding/welcome` | `context.go()` ✅ |

---

### 18. BNPL Apply Flow (Step 1 → 2 → 3 → Approved / Not Approved)
| Screen | Button | Destination | Method |
|--------|--------|-------------|--------|
| Step 1 `/bnpl/apply/step1` | "Next" | `/bnpl/apply/step2` | `context.push()` ✅ |
| Step 1 | "Next" (empty income) | disabled | `null` ✅ |
| Step 2 `/bnpl/apply/step2` | "Next" | `/bnpl/apply/step3` | `context.push()` ✅ |
| Step 3 `/bnpl/apply/step3` | "Submit Application" | `/bnpl/approved` | `context.go()` ✅ |
| Approved `/bnpl/approved` | "Start Shopping" | `/dashboard/home` | `context.go()` ✅ |
| Approved | "Enable SmartDeposit" | `/bnpl/smart-deposit` | `context.push()` ✅ |
| Not Approved `/bnpl/not-approved` | "Try SmartDeposit" | `/bnpl/smart-deposit` | `context.push()` ✅ |
| Not Approved | "Back to Home" | `/dashboard/home` | `context.go()` ✅ |

> **⚠️ Bug:** Step 3 "Submit Application" always goes to `/bnpl/approved`. There is no path to `/bnpl/not-approved` — that screen is **unreachable** from the normal BNPL flow.

---

### 19. Loan Apply Flow (Step 1 → 2 → 3 → Approved)
| Screen | Button | Destination | Method |
|--------|--------|-------------|--------|
| Step 1 `/loan/apply/step1` | "Next" | `/loan/apply/step2` | `context.push()` ✅ |
| Step 2 `/loan/apply/step2` | "Next" | `/loan/apply/step3` | `context.push()` ✅ |
| Step 3 `/loan/apply/step3` | "Submit Application" | `/loan/approved` | `context.go()` ✅ |
| Approved `/loan/approved` | "View My Loans" | `/loan/my-loans` | `context.go()` ✅ |
| Approved | "Go to Home" | `/dashboard/home` | `context.go()` ✅ |

> **⚠️ Missing:** There is no entry point to the loan flow anywhere visible in the app (no button on HomeScreen, InvestHub, or BnplHub navigates to `/loan/apply/step1`). The loan screens exist but are **unreachable** from the app UI.

---

### 20. Sub-screens

| Screen | Button | Destination | Method |
|--------|--------|-------------|--------|
| AddMoneyScreen | Quick amounts (₹500…) | **nothing** (`() {}`) | ❌ Dead buttons |
| AddMoneyScreen | "Add Money" | pops screen (SnackBar) | `context.pop()` ✅ |
| WithdrawScreen | "Withdraw" | pops screen (SnackBar) | `context.pop()` ✅ |
| SendMoneyScreen | — | — | (not read) |
| SmartSaveScreen | "Activate SmartSave" | `/plans/success` | `context.push()` ✅ |
| RechargeSuccessScreen | — | — | (not read) |
| EditProfileScreen | "Save Changes" | pops (SnackBar) | `context.pop()` ✅ |
| ChangeMpinScreen | after confirm MPIN | pops | `context.pop()` ✅ |

---

## 🚨 Critical Bugs & Issues Summary

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | 🔴 High | `WelcomeScreen` | Register & Login cards go to **same screen**—no user distinction |
| 2 | 🔴 High | `OtpVerifyScreen` | `_otp` declared in `build()` — **state bug**, OTP lost on rebuild |
| 3 | 🔴 High | `AadhaarVerifyScreen` | Same `_otp` in-build bug — Aadhaar OTP lost on rebuild |
| 4 | 🔴 High | Auth flow | Returning users go through **full profile setup again** — no "returning user" branch |
| 5 | 🔴 High | KYC flow | Each KYC screen creates **new KycViewModel** — no shared state across steps |
| 6 | 🟠 Medium | `app_router.dart` | `/dashboard/bnpl` in ShellRoute but **not in BottomNav `_routes`** — wrong tab active |
| 7 | 🟠 Medium | `app_router.dart` | `/onboarding/carousel` registered but **completely unreachable** |
| 8 | 🟠 Medium | BNPL flow | `/bnpl/not-approved` is **unreachable** — Step 3 always goes to approved |
| 9 | 🟠 Medium | Loan flow | No UI entry point to loan screens — `/loan/apply/step1` is **unreachable** |
| 10 | 🟡 Low | `HomeScreen` | Bell icon, offer cards — **dead/non-interactive** |
| 11 | 🟡 Low | `MobileEntryScreen` | Terms link — **dead button** (`() {}`) |
| 12 | 🟡 Low | `RechargeHomeScreen` | Mobile edit icon — **dead button** (`() {}`) |
| 13 | 🟡 Low | `SettingsScreen` | Help, Privacy Policy, Terms — **3 dead buttons** |
| 14 | 🟡 Low | `AddMoneyScreen` | Quick amount chips — **dead buttons** (`() {}`) |
| 15 | 🟡 Low | `MpinSetupScreen` | `_isLoading = true` on mismatch but never reset to `false` |
| 16 | 🟡 Low | `SplashScreen` | Skips KYC check on re-login — unverified users reach dashboard |
| 17 | 🟡 Low | `UserProfileSetupScreen` | New `AuthViewModel` loses mobile number from sign-in step |

---

## ✅ What Works Well

- GoRouter redirect guard correctly blocks unauthenticated access
- Sign Out properly clears storage and goes to welcome screen
- BNPL apply step 1–3 flow is correctly chained with `context.push()`
- KYC intro to Aadhaar to PAN chain works correctly
- MPIN setup auto-submits on 4th digit — good UX
- Wallet actions (Add, Send, Withdraw, History) all wired correctly
- Invest Hub correctly links to Gold, FD, and Portfolio screens
- Pull-to-refresh on HomeScreen works
- Bottom nav tab switching using `context.go()` is correct (no stack bloat)
