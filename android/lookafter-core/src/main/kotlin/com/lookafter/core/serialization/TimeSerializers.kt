package com.lookafter.core.serialization

import java.time.Instant
import java.time.LocalDate
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.modules.SerializersModule
import kotlinx.serialization.modules.contextual

/** ISO-8601 Instant serializer (e.g. 2026-03-11T14:00:00Z). */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("java.time.Instant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) {
        encoder.encodeString(value.toString())
    }

    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}

/** ISO local date serializer (yyyy-MM-dd). */
object LocalDateSerializer : KSerializer<LocalDate> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("java.time.LocalDate", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: LocalDate) {
        encoder.encodeString(value.toString())
    }

    override fun deserialize(decoder: Decoder): LocalDate = LocalDate.parse(decoder.decodeString())
}

/**
 * Shared JSON codec for LifeState snapshots.
 * Tolerant of unknown keys so schema can grow without wiping user data.
 */
object LookAfterJson {
    val module: SerializersModule = SerializersModule {
        contextual(InstantSerializer)
        contextual(LocalDateSerializer)
    }

    val codec: Json = Json {
        serializersModule = module
        ignoreUnknownKeys = true
        encodeDefaults = true
        prettyPrint = false
        isLenient = false
    }
}
