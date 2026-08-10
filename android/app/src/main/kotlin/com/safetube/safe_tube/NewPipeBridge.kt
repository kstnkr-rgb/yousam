package com.safetube.safe_tube

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.channel.ChannelInfo
import org.schabi.newpipe.extractor.channel.tabs.ChannelTabInfo
import org.schabi.newpipe.extractor.channel.tabs.ChannelTabs
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.linkhandler.ListLinkHandler
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Reads a channel's uploads with NewPipeExtractor.
 *
 * The Dart scraper returns nothing since YouTube reorganised its listing
 * responses, and the fix for it is still an unmerged pull request upstream.
 * This library tracks those changes closely and, unlike the RSS feed we fell
 * back to, gives the full archive with durations already attached — so Shorts
 * no longer need a separate request each to be recognised.
 */
object NewPipeBridge {

    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/120 Mobile Safari/537.36"

    @Volatile
    private var initialised = false

    private fun ensureInitialised() {
        if (initialised) return
        synchronized(this) {
            if (initialised) return
            NewPipe.init(SimpleDownloader())
            initialised = true
        }
    }

    /**
     * @param stopAtIds video ids already stored; collection of a tab stops as
     *   soon as one turns up, which is what makes a refresh cheap.
     */
    fun channelVideos(
        channelId: String,
        limit: Int,
        stopAtIds: Set<String>,
    ): List<Map<String, Any?>> {
        ensureInitialised()

        val service = ServiceList.YouTube
        val info = ChannelInfo.getInfo(service, "https://www.youtube.com/channel/$channelId")
        val collected = ArrayList<Map<String, Any?>>()

        // Shorts live in their own tab, so they can be labelled by where they
        // came from rather than guessed at from a duration.
        for ((tabName, isShort) in listOf(ChannelTabs.VIDEOS to false, ChannelTabs.SHORTS to true)) {
            val handler = info.tabs.firstOrNull { it.contentFilters.contains(tabName) } ?: continue
            collectTab(handler, isShort, limit, stopAtIds, collected, info.name, channelId)
        }

        return collected
    }

    private fun collectTab(
        handler: ListLinkHandler,
        isShort: Boolean,
        limit: Int,
        stopAtIds: Set<String>,
        into: MutableList<Map<String, Any?>>,
        channelName: String,
        channelId: String,
    ) {
        val service = ServiceList.YouTube
        var taken = 0

        var page = ChannelTabInfo.getInfo(service, handler)
        var items = page.relatedItems
        var nextPage = page.nextPage

        while (true) {
            for (item in items) {
                if (item !is StreamInfoItem) continue
                val videoId = videoIdOf(item.url) ?: continue
                if (stopAtIds.contains(videoId)) return
                into.add(
                    mapOf(
                        "id" to videoId,
                        "title" to item.name,
                        "channelName" to (item.uploaderName ?: channelName),
                        "channelId" to channelId,
                        "durationSeconds" to item.duration,
                        "viewCount" to item.viewCount,
                        "uploadedAtMillis" to item.uploadDate?.instant?.toEpochMilli(),
                        "isShort" to isShort,
                    )
                )
                taken++
                if (taken >= limit) return
            }

            val current = nextPage ?: return
            if (!Page.isValid(current)) return
            val more = ChannelTabInfo.getMoreItems(service, handler, current)
            items = more.items
            nextPage = more.nextPage
            if (items.isEmpty()) return
        }
    }

    private fun videoIdOf(url: String?): String? {
        if (url == null) return null
        Regex("[?&]v=([\\w-]{11})").find(url)?.let { return it.groupValues[1] }
        Regex("/shorts/([\\w-]{11})").find(url)?.let { return it.groupValues[1] }
        return null
    }

    /**
     * NewPipeExtractor ships no HTTP client of its own. HttpURLConnection is
     * enough here and keeps OkHttp out of the APK.
     */
    private class SimpleDownloader : Downloader() {
        override fun execute(request: Request): Response {
            val connection = URL(request.url()).openConnection() as HttpURLConnection
            connection.requestMethod = request.httpMethod()
            connection.connectTimeout = 15_000
            connection.readTimeout = 25_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", USER_AGENT)

            for ((name, values) in request.headers()) {
                for (value in values) {
                    connection.addRequestProperty(name, value)
                }
            }

            try {
                request.dataToSend()?.let { payload ->
                    connection.doOutput = true
                    connection.setFixedLengthStreamingMode(payload.size)
                    connection.outputStream.use { it.write(payload) }
                }

                val code = connection.responseCode
                val stream =
                    if (code >= 400) connection.errorStream else connection.inputStream
                val body = stream?.bufferedReader()?.use { it.readText() } ?: ""

                return Response(
                    code,
                    connection.responseMessage,
                    connection.headerFields,
                    body,
                    connection.url.toString(),
                )
            } catch (e: Exception) {
                throw IOException("Request to ${request.url()} failed", e)
            } finally {
                connection.disconnect()
            }
        }
    }
}
