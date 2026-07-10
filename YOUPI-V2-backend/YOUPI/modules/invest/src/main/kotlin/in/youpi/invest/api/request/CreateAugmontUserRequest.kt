package `in`.youpi.invest.api.request

data class CreateAugmontUserRequest(
    val userName: String,
    val userEmail: String,
    val userMobile: String
)