# Comprehensive 56 API Test Report

This document logs the automated test results across the 12 core modules. Each endpoint lists the Request payload/parameters and the exact Response body returned by the local backend.

### Auth - Send OTP
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/auth/otp/send`
**Payload:**
```json
{
  "mobile": "9369016664"
}
```
**Status:** 200
**Response:**
```json
{
  "success": true,
  "data": {
    "message": "OTP sent successfully",
    "expiresInSeconds": 300
  },
  "requestId": "c7caf4f1-e8e8-4e06-b9ea-710b093eda49",
  "timestamp": "2026-06-15T14:13:07.523317700Z"
}
```

---

### Auth - Verify OTP
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/auth/otp/verify`
**Payload:**
```json
{
  "mobile": "9369016664",
  "otp": "123456",
  "deviceId": "test1234"
}
```
**Status:** 200
**Response:**
```json
{
  "success": true,
  "data": {
    "accessToken": "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxOWQ2YTBiNS00OWMxLTQwZmItYmY1Yy0xZGUwNDkzOTMwMjUiLCJtb2JpbGUiOiIrOTE5MzY5MDE2NjY0IiwidXNlclR5cGUiOiJOT1JNQUwiLCJzY29wZSI6Ik1QSU5fU0VTU0lPTiIsImlhdCI6MTc4MTUzMjc4NywiZXhwIjoxNzgxNTMzNjg3LCJpc3MiOiJ5b3VwaS1hcGkifQ.Z7TddhUhSIN5DNiev7pcUKsdDXwONr9KtgtzEXS-ehBB2zgdeJs665uDQg733xbPQcECm9mn_nvwjRmHhtjXf6ByF722I-9ltI58fsZGpYB-3jmBEe0SPAQtNIV-zessqz6n-bjDZgweoFPqFODE6Qr_e2ba7_lAsyXqcmbR-m82fT_QqePU-vGILivWW-cBaqcRO5IMubkhdwvPH-OtcVe-88F1TyA5sCoxejOnc2PBLJ9adnJo6zThr0rBGQbAge2ksuHLXFCgHqtJNJayit2kuwNqYUOqWorCm3Gmh4coqTWco3XVAjeOWWLXAKlD3WjKCTckSCCf0dC3ZmixCQ",
    "refreshToken": "ca1fa08e-d84f-4c9b-b14f-993a196a7f59566489415898782647",
    "userId": "19d6a0b5-49c1-40fb-bf5c-1de049393025",
    "isNewUser": false,
    "profileComplete": false,
    "kycStatus": "PENDING",
    "userType": "NORMAL"
  },
  "requestId": "f75fb32c-94ec-4256-90d0-29f118a65717",
  "timestamp": "2026-06-15T14:13:07.667102100Z"
}
```

---

### Auth - Setup MPIN
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/auth/mpin/setup`
**Payload:**
```json
{
  "mpin": "1234"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Auth - Verify MPIN
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/auth/mpin/verify`
**Payload:**
```json
{
  "mobile": "9369016664",
  "mpin": "1234",
  "deviceId": "test1234"
}
```
**Status:** 500
**Response:**
```json
{
  "success": false,
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "An unexpected error occurred: in/youpi/auth/service/AuthService$verifyMpin$1 (java.lang.NoClassDefFoundError)"
  },
  "requestId": "577cf9b3-e15a-4a1d-82af-3a7818ab371d",
  "timestamp": "2026-06-15T14:13:07.685180200Z"
}
```

---

### Auth - Refresh Token
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/auth/token/refresh`
**Payload:**
```json
{
  "refreshToken": "dummy-refresh-token"
}
```
**Status:** 500
**Response:**
```json
{
  "success": false,
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "An unexpected error occurred: in/youpi/auth/service/AuthService$refreshAccessToken$1 (java.lang.NoClassDefFoundError)"
  },
  "requestId": "9c1cfd4a-c958-42fb-aee1-30f018eeb139",
  "timestamp": "2026-06-15T14:13:07.720049900Z"
}
```

---

### Auth - Logout
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/auth/logout`
**Status:** 200
**Response:**
```json
null
```

---

### User - Get Profile
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/user/profile`
**Status:** 200
**Response:**
```json
null
```

---

### User - Update Profile
**Method:** `PUT`  
**URL:** `http://localhost:8082/api/v1/user/profile`
**Payload:**
```json
{
  "fullName": "Test User",
  "email": "test@example.com",
  "dateOfBirth": "1990-01-01"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### User - Get KYC Status
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/user/kyc/status`
**Status:** 200
**Response:**
```json
null
```

---

### User - Aadhaar OTP Send
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/user/kyc/aadhaar/otp`
**Payload:**
```json
{
  "aadhaarNumber": "123456789012"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### User - Aadhaar Verify
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/user/kyc/aadhaar/verify`
**Payload:**
```json
{
  "clientId": "dummy-client",
  "otp": "123456"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### User - PAN Verify
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/user/kyc/pan/verify`
**Payload:**
```json
{
  "pan": "ABCDE1234F"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### User - Selfie Upload
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/user/kyc/selfie`
**Payload:**
```json
{
  "base64Image": "data:image/jpeg;base64,..."
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Wallet - Get Balance
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/wallet/balance`
**Status:** 200
**Response:**
```json
null
```

---

### Wallet - Get Ledger
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/wallet/ledger`
**Status:** 200
**Response:**
```json
null
```

---

### Wallet - Transfer Funds
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/wallet/transfer`
**Payload:**
```json
{
  "receiverMobile": "+919999999999",
  "amount": 100
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Smart Saver - Get Balance
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/smart-saver/balance`
**Status:** 200
**Response:**
```json
null
```

---

### Smart Saver - Deposit
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/smart-saver/deposit`
**Payload:**
```json
{
  "amount": 500
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Get Rates
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/rates`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Buy
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/invest/gold/buy`
**Payload:**
```json
{
  "amount": 100,
  "weightMg": 15
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Sell
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/invest/gold/sell`
**Payload:**
```json
{
  "weightMg": 10,
  "targetBankAccountId": "bank-123"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Get Holdings
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/holdings`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Passbook
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/passbook`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - History
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/history`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Products
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/products`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Transactions
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/transactions`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - KYC Status
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/gold/kyc`
**Status:** 200
**Response:**
```json
null
```

---

### Gold - Create User
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/invest/gold/user`
**Payload:**
```json
{
  "pan": "ABCDE1234F",
  "dob": "1990-01-01"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### FD - Create
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/invest/fd/create`
**Payload:**
```json
{
  "amount": 10000,
  "months": 12
}
```
**Status:** 200
**Response:**
```json
null
```

---

### FD - Schemes
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/fd/schemes`
**Status:** 200
**Response:**
```json
null
```

---

### FD - Preview
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/invest/fd/preview`
**Payload:**
```json
{
  "amount": 10000,
  "months": 12
}
```
**Status:** 200
**Response:**
```json
null
```

---

### FD - List
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/fd/list`
**Status:** 200
**Response:**
```json
null
```

---

### FD - Get Details
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/invest/fd/dummy-fd-123`
**Status:** 200
**Response:**
```json
null
```

---

### FD - Close
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/invest/fd/dummy-fd-123/close`
**Status:** 200
**Response:**
```json
null
```

---

### BNPL - Get Status
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/bnpl/status`
**Status:** 200
**Response:**
```json
null
```

---

### BNPL - Apply Step 1
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/bnpl/apply/step1`
**Payload:**
```json
{
  "income": 50000,
  "employmentType": "SALARIED",
  "pan": "ABCDE1234F"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### BNPL - Apply Step 2
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/bnpl/apply/step2`
**Payload:**
```json
{
  "kycData": "dummy"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### BNPL - Apply Step 3
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/bnpl/apply/step3`
**Payload:**
```json
{
  "eSignId": "doc-123"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### BNPL - Smart Deposit Create
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/bnpl/smart-deposit/create`
**Payload:**
```json
{
  "amount": 5000
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Loan - Get Status
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/loan/status`
**Status:** 200
**Response:**
```json
null
```

---

### Loan - Apply Step 1
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/loan/apply/step1`
**Payload:**
```json
{
  "amount": 50000,
  "tenureMonths": 12,
  "purpose": "PERSONAL"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Loan - Apply Step 2
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/loan/apply/step2`
**Payload:**
```json
{
  "bankAccountId": "bank-123"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Loan - Apply Step 3
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/loan/apply/step3`
**Payload:**
```json
{
  "eMandateId": "mandate-123"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Loan - EMI Schedule
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/loan/emi/schedule`
**Status:** 200
**Response:**
```json
null
```

---

### Loan - Calculate EMI
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/loan/emi/calculate?amount=50000&months=12`
**Status:** 200
**Response:**
```json
null
```

---

### Loan - Pay EMI
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/loan/dummy-loan-123/pay-emi`
**Status:** 200
**Response:**
```json
null
```

---

### Payment - Create Order
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/payment/orders`
**Payload:**
```json
{
  "amount": 1000,
  "currency": "INR",
  "description": "Wallet Load"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Payment - Verify
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/payment/verify`
**Payload:**
```json
{
  "razorpayOrderId": "order_123",
  "razorpayPaymentId": "pay_123",
  "razorpaySignature": "sig_123"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Recharge - Search Plans
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/recharge/plans/search?q=Jio%20DL`
**Status:** 200
**Response:**
```json
null
```

---

### Recharge - Get Operator
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/recharge/operator?mobile=9999999999`
**Status:** 200
**Response:**
```json
null
```

---

### Recharge - Create Order
**Method:** `POST`  
**URL:** `http://localhost:8082/api/v1/recharge/order`
**Payload:**
```json
{
  "mobile": "9999999999",
  "planId": "plan_123",
  "amount": 299
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Recharge - Get Order Details
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/recharge/order/dummy-order-123`
**Status:** 200
**Response:**
```json
null
```

---

### Recharge - History
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/recharge/history`
**Status:** 200
**Response:**
```json
null
```

---

### Admin - Dashboard
**Method:** `GET`  
**URL:** `http://localhost:8082/api/v1/admin/users/19d6a0b5-49c1-40fb-bf5c-1de049393025`
**Status:** 200
**Response:**
```json
null
```

---

### Admin - Update User Type
**Method:** `PUT`  
**URL:** `http://localhost:8082/api/v1/admin/users/19d6a0b5-49c1-40fb-bf5c-1de049393025/type`
**Payload:**
```json
{
  "userType": "MERCHANT"
}
```
**Status:** 200
**Response:**
```json
null
```

---

### Admin - Update User Active Status
**Method:** `PUT`  
**URL:** `http://localhost:8082/api/v1/admin/users/19d6a0b5-49c1-40fb-bf5c-1de049393025/active`
**Payload:**
```json
{
  "isActive": false
}
```
**Status:** 200
**Response:**
```json
null
```

---

