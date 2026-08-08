package com.example.dex.network

import android.content.ContentResolver
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SafStorageTest {

    private val mockContext = mockk<Context>()
    private val mockPrefs = mockk<SharedPreferences>(relaxed = true)
    private val mockEditor = mockk<SharedPreferences.Editor>(relaxed = true)
    private val mockContentResolver = mockk<ContentResolver>(relaxed = true)

    @Before
    fun setUp() {
        every { mockContext.getSharedPreferences("dex_saf_prefs", Context.MODE_PRIVATE) } returns mockPrefs
        every { mockContext.contentResolver } returns mockContentResolver
        every { mockPrefs.edit() } returns mockEditor
        every { mockEditor.putString(any(), any()) } returns mockEditor
    }

    @Test
    fun `getGrantedFolders returns empty map when preference is empty or null`() {
        every { mockPrefs.getString("granted_folders", null) } returns null

        val result = SafStorage.getGrantedFolders(mockContext)

        assertTrue(result.isEmpty())
    }

    @Test
    fun `getGrantedFolders parses valid JSON preference into map`() {
        val rawJson = """{"Documents":"content://com.android.providers.media.documents/tree/1","Downloads":"content://com.android.providers.downloads.documents/tree/2"}"""

        every { mockPrefs.getString("granted_folders", null) } returns rawJson

        val result = SafStorage.getGrantedFolders(mockContext)

        assertEquals(2, result.size)
        assertEquals("content://com.android.providers.media.documents/tree/1", result["Documents"])
    }

    @Test
    fun `getGrantedFolders returns empty map when preference contains malformed JSON`() {
        every { mockPrefs.getString("granted_folders", null) } returns "{ invalid_json: "

        val result = SafStorage.getGrantedFolders(mockContext)

        assertTrue(result.isEmpty())
    }

    @Test
    fun `addGrantedFolder adds new folder entry and persists JSON string`() {
        every { mockPrefs.getString("granted_folders", null) } returns null

        val mockUri = mockk<Uri>()
        every { mockUri.toString() } returns "content://com.android.providers.media.documents/tree/3"

        SafStorage.addGrantedFolder(mockContext, "Pictures", mockUri)

        val slotJson = slot<String>()
        verify { mockEditor.putString("granted_folders", capture(slotJson)) }
    }

    @Test
    fun `removeGrantedFolder removes specified folder and updates JSON preference`() {
        val initialJson = """{"FolderA":"content://uri/a","FolderB":"content://uri/b"}"""

        every { mockPrefs.getString("granted_folders", null) } returns initialJson

        SafStorage.removeGrantedFolder(mockContext, "FolderA")

        val slotJson = slot<String>()
        verify { mockEditor.putString("granted_folders", capture(slotJson)) }
    }
}
