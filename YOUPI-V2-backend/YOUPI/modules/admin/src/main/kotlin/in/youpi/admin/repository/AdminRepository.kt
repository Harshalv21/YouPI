package `in`.youpi.admin.repository

import org.springframework.data.annotation.Id
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.kotlin.CoroutineCrudRepository
import org.springframework.stereotype.Repository
import java.util.UUID

// FIX: was a plain data class with no @Table/@Id -- Spring Data R2DBC
// couldn't identify it as a real entity ("Could not safely identify store
// assignment"), which meant no AdminRepository bean ever got created and
// crashed app startup (AdminAuthService's constructor needs this bean).
@Table("admins")
data class AdminEntity(
    @Id val id: UUID,
    val email: String,
    val passwordHash: String,
    val name: String,
    val role: String
)

@Repository
interface AdminRepository : CoroutineCrudRepository<AdminEntity, UUID> {
    suspend fun findByEmail(email: String): AdminEntity?
}