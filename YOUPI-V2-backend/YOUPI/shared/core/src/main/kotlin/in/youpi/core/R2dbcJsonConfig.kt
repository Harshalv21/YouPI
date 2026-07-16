package `in`.youpi.config

import io.r2dbc.postgresql.codec.Json
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.convert.converter.Converter
import org.springframework.data.convert.ReadingConverter
import org.springframework.data.convert.WritingConverter
import org.springframework.data.r2dbc.convert.R2dbcCustomConversions
import org.springframework.data.r2dbc.dialect.PostgresDialect

@WritingConverter
class StringToJsonConverter : Converter<String, Json> {
    override fun convert(source: String): Json = Json.of(source)
}

@ReadingConverter
class JsonToStringConverter : Converter<Json, String> {
    override fun convert(source: Json): String = source.asString()
}

@Configuration
class R2dbcJsonConfig {
    @Bean
    fun r2dbcCustomConversions(): R2dbcCustomConversions =
        R2dbcCustomConversions.of(
            PostgresDialect.INSTANCE,
            listOf(StringToJsonConverter(), JsonToStringConverter())
        )
}