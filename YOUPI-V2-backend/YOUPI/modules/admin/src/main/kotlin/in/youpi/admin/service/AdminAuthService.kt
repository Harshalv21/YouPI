package `in`.youpi.admin.service

import `in`.youpi.admin.domain.*
import `in`.youpi.admin.repository.AdminRepository
import `in`.youpi.core.Result
import at.favre.lib.crypto.bcrypt.BCrypt
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service

/**
 * Uses at.favre.lib:bcrypt (already a project dependency, version pinned in
 * gradle/libs.versions.toml as `bcrypt`) -- NOT Spring Security's
 * BCryptPasswordEncoder, which is a different library with a different API
 * and was not already present in this project.
 *
 * SEEDING THE FIRST ADMIN: generate a bcrypt hash for your chosen password
 * once, then INSERT it directly (see the migration file's bottom comment).
 */
@Service
class AdminAuthService(
    private val adminRepo: AdminRepository,
    private val jwtService: AdminJwtService
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val bcryptCost = 12

    suspend fun login(req: AdminLoginRequest): Result<AdminLoginResponse, AdminException> {
        val admin = adminRepo.findByEmail(req.email.trim().lowercase())
            ?: run {
                log.warn("Admin login attempt for unknown email: {}", req.email)
                return Result.failure(AdminInvalidCredentialsException())
            }

        val verifyResult = BCrypt.verifyer().verify(req.password.toCharArray(), admin.passwordHash)
        if (!verifyResult.verified) {
            log.warn("Admin login failed (bad password): {}", req.email)
            return Result.failure(AdminInvalidCredentialsException())
        }

        val token = jwtService.issueToken(admin.id, admin.email, admin.role)
        log.info("Admin login success: {}", admin.email)

        return Result.success(
            AdminLoginResponse(token = token, adminName = admin.name, role = admin.role)
        )
    }
}