package com.example.dex.network

import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ClientEngineTest {

    @Test
    fun `sendClipboard returns true when response is 200 OK`() = runBlocking {
        // Arrange
        val mockEngine = MockEngine { request ->
            respond(
                content = "",
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        val clientEngine = ClientEngine(mockEngine)

        // Act
        val result = clientEngine.sendClipboard("192.168.1.5", 53317, "Hello World")

        // Assert
        assertTrue(result)
    }

    @Test
    fun `sendClipboard returns false when response is not 200 OK`() = runBlocking {
        // Arrange
        val mockEngine = MockEngine { request ->
            respond(
                content = "Internal Server Error",
                status = HttpStatusCode.InternalServerError,
                headers = headersOf(HttpHeaders.ContentType, "text/plain")
            )
        }
        val clientEngine = ClientEngine(mockEngine)

        // Act
        val result = clientEngine.sendClipboard("192.168.1.5", 53317, "Hello World")

        // Assert
        assertFalse(result)
    }
}
