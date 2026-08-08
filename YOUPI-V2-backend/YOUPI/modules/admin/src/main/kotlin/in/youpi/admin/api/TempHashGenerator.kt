package `in`.youpi.admin

import at.favre.lib.crypto.bcrypt.BCrypt

fun main() {
    println(BCrypt.withDefaults().hashToString(12, "Rajmata@8853".toCharArray()))
}