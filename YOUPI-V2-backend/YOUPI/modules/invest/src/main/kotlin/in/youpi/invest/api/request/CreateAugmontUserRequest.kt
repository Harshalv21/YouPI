package `in`.youpi.invest.api.request

import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern

data class CreateAugmontUserRequest(
    @field:NotBlank(message = "userName is required")
    val userName: String,
    @field:Email(message = "Invalid email")
    val userEmail: String,
    @field:Pattern(regexp = "^[6-9]\\d{9}$", message = "Invalid mobile number")
    val userMobile: String
)