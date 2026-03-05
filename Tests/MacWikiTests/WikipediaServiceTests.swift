import Foundation
import Testing

@testable import MacWiki

/// Tests for WikipediaService
/// Note: These tests make real network requests to Wikipedia API
struct WikipediaServiceTests {
    
    let service = WikipediaService()
    
    @Test func searchReturnsResults() async throws {
        let results = try await service.search("Swift programming")
        
        #expect(!results.isEmpty, "Search should return results")
        #expect(results.first?.title.contains("Swift") == true, "First result should contain Swift")
    }
    
    @Test func searchEmptyQueryReturnsEmpty() async throws {
        let results = try await service.search("")
        
        #expect(results.isEmpty, "Empty query should return no results")
    }
    
    @Test func fetchArticleReturnsHTML() async throws {
        let content = try await service.fetchArticle("Swift (programming language)")
        
        #expect(!content.html.isEmpty, "Article should have HTML content")
        #expect(content.html.contains("html"), "Content should be valid HTML")
    }
    
    @Test func fetchSummaryReturnsData() async throws {
        let summary = try await service.fetchSummary("Swift (programming language)")
        
        #expect(!summary.title.isEmpty, "Summary should have a title")
        #expect(summary.extract != nil, "Summary should have an extract")
    }

    @Test func fetchPageMetadataReturnsReasonableWordCount() async throws {
        let metadata = try await service.fetchPageMetadata("Swift (programming language)")

        #expect(metadata.wordCount > 3_000, "Word count should reflect full article content")
    }

    @Test func fetchPageMetadataResolvesRedirectTitles() async throws {
        let metadata = try await service.fetchPageMetadata("Nintendo Wii")

        #expect(metadata.wordCount > 5_000, "Redirected titles should still return a full-article word count")
    }
    
    @Test func searchResultsCached() async throws {
        // First search
        let results1 = try await service.search("Apple Inc")
        
        // Second search with same query should use cache
        let results2 = try await service.search("Apple Inc")
        
        #expect(results1.count == results2.count, "Cached results should match")
    }

    @Test func articleCacheMetricsPopulate() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWikiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let isolated = WikipediaService(cacheDirectoryURL: tempRoot)
        _ = try await isolated.fetchArticleFast("Swift (programming language)")

        let metrics = await isolated.cacheMetrics()
        #expect(metrics.fastArticleEntries >= 1, "Fast in-memory cache should contain fetched article")
        #expect(metrics.diskArticleEntries >= 1, "Disk article cache should contain fetched article")
        #expect(metrics.diskArticleBytes > 0, "Disk article cache should report non-zero bytes")
    }

    @Test func pinnedArticlesAreTrackedInCacheMetrics() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWikiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let isolated = WikipediaService(cacheDirectoryURL: tempRoot)
        let title = "Swift (programming language)"
        _ = try await isolated.fetchArticleFast(title)

        await isolated.replacePinnedArticleTitles([title])
        let pinned = await isolated.cacheMetrics()
        #expect(pinned.pinnedArticleEntries >= 1, "Pinned entry count should reflect pinned article")

        await isolated.replacePinnedArticleTitles([])
        let unpinned = await isolated.cacheMetrics()
        #expect(unpinned.pinnedArticleEntries == 0, "Pinned entry count should clear when no titles are pinned")
    }

    @Test func clearTemporaryDiskCachePreservesPinnedArticles() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWikiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let isolated = WikipediaService(cacheDirectoryURL: tempRoot)
        let pinnedTitle = "Swift (programming language)"
        let temporaryTitle = "Apple Inc."

        _ = try await isolated.fetchArticleFast(pinnedTitle)
        _ = try await isolated.fetchArticleFast(temporaryTitle)
        await isolated.replacePinnedArticleTitles([pinnedTitle])
        await isolated.clearDiskArticleCache(includePinned: false)

        let metrics = await isolated.cacheMetrics()
        #expect(metrics.pinnedArticleEntries >= 1, "Pinned entries should remain after temporary disk clear")
        #expect(metrics.diskArticleEntries >= 1, "Disk cache should keep pinned article payloads")
    }

    @Test func clearAllDiskCacheRemovesPinnedArticles() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWikiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let isolated = WikipediaService(cacheDirectoryURL: tempRoot)
        let title = "Swift (programming language)"
        _ = try await isolated.fetchArticleFast(title)
        await isolated.replacePinnedArticleTitles([title])

        await isolated.clearDiskArticleCache(includePinned: true)
        let metrics = await isolated.cacheMetrics()
        #expect(metrics.diskArticleEntries == 0, "Clearing all disk cache should remove all disk entries")
        #expect(metrics.pinnedArticleEntries == 0, "Clearing all disk cache should remove pinned entries")
    }

    @Test func clearInMemoryArticleCacheKeepsDiskEntries() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWikiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let isolated = WikipediaService(cacheDirectoryURL: tempRoot)
        _ = try await isolated.fetchArticleFast("Swift (programming language)")

        await isolated.clearInMemoryArticleCache()
        let metrics = await isolated.cacheMetrics()
        #expect(metrics.fullArticleEntries == 0, "Full in-memory cache should be empty after clear")
        #expect(metrics.fastArticleEntries == 0, "Fast in-memory cache should be empty after clear")
        #expect(metrics.diskArticleEntries >= 1, "Disk entries should remain after memory-only clear")
    }

    @Test func discoverParserExtractsFeaturedImageAndNewsStories() async throws {
        let payload = """
        {
          "tfa": {
            "title": "Ada Lovelace",
            "pageid": 42,
            "description": "English mathematician",
            "thumbnail": { "source": "https://upload.wikimedia.org/ada.jpg" }
          },
          "mostread": {
            "articles": [
              {
                "title": "Swift_(programming_language)",
                "pageid": 100,
                "description": "Programming language",
                "thumbnail": { "source": "https://upload.wikimedia.org/swift.jpg" }
              }
            ]
          },
          "news": [
            {
              "story": "Developers announced a major tooling release.",
              "links": [
                { "title": "Tooling", "pageid": 200, "description": "Software tools" },
                { "title": "Swift_(programming_language)", "pageid": 100, "description": "Programming language" }
              ]
            }
          ],
          "onthisday": [
            {
              "text": "A notable event happened.",
              "year": 1990,
              "pages": [{ "title": "History", "pageid": 300 }]
            }
          ],
          "dyk": [
            {
              "text": "... that Swift was introduced in 2014?",
              "pages": [{ "title": "Swift_(programming_language)", "pageid": 100 }]
            }
          ],
          "image": {
            "title": "File:Test.jpg",
            "description": { "text": "A test image from Commons." },
            "artist": { "text": "Test Artist" },
            "credit": { "text": "Test Credit" },
            "file_page": "https://commons.wikimedia.org/wiki/File:Test.jpg",
            "license": {
              "type": "CC BY-SA 4.0",
              "code": "cc-by-sa-4.0",
              "url": "https://creativecommons.org/licenses/by-sa/4.0/"
            },
            "image": { "source": "https://upload.wikimedia.org/test.jpg" },
            "thumbnail": { "source": "https://upload.wikimedia.org/test-thumb.jpg" },
            "wb_entity_id": "Q123"
          }
        }
        """

        let feed = try await service.parseDiscoverFeedPayload(Data(payload.utf8), dateKey: "2026/02/08")

        #expect(feed.dateKey == "2026/02/08")
        #expect(feed.featuredArticle?.title == "Ada Lovelace")
        #expect(feed.newsStories.count == 1)
        #expect(feed.newsStories.first?.links.count == 2)
        #expect(feed.inTheNews.count == 2)
        #expect(feed.featuredImage?.title == "File:Test.jpg")
        #expect(feed.featuredImage?.artist == "Test Artist")
        #expect(feed.featuredImage?.licenseCode == "cc-by-sa-4.0")
    }

    @Test func discoverOnThisDayPayloadEnrichesFeedCollections() async throws {
        let featuredPayload = """
        {
          "tfa": {
            "title": "Ada Lovelace",
            "pageid": 42
          },
          "onthisday": [
            {
              "text": "Original featured feed event.",
              "year": 1988,
              "pages": [{ "title": "Original Event", "pageid": 10 }]
            }
          ]
        }
        """

        let onThisDayPayload = """
        {
          "selected": [
            {
              "text": "Selected event text.",
              "year": 2001,
              "pages": [{ "title": "Selected Event", "pageid": 20 }]
            }
          ],
          "events": [
            {
              "text": "All-events entry.",
              "year": 2002,
              "pages": [{ "title": "Event Entry", "pageid": 21 }]
            }
          ],
          "births": [
            {
              "text": "Notable person born.",
              "year": 1950,
              "pages": [{ "title": "Birth Entry", "pageid": 22 }]
            }
          ],
          "deaths": [
            {
              "text": "Notable person died.",
              "year": 2010,
              "pages": [{ "title": "Death Entry", "pageid": 23 }]
            }
          ],
          "holidays": [
            {
              "text": "International Test Day",
              "pages": [{ "title": "Test Holiday", "pageid": 24 }]
            }
          ]
        }
        """

        let baseFeed = try await service.parseDiscoverFeedPayload(Data(featuredPayload.utf8), dateKey: "2026/02/08")
        let enrichedFeed = try await service.applyOnThisDayPayload(Data(onThisDayPayload.utf8), to: baseFeed)

        #expect(enrichedFeed.onThisDay.first?.text == "All-events entry.")
        #expect(enrichedFeed.onThisDaySelected.first?.article?.title == "Selected Event")
        #expect(enrichedFeed.onThisDayBirths.first?.article?.title == "Birth Entry")
        #expect(enrichedFeed.onThisDayDeaths.first?.article?.title == "Death Entry")
        #expect(enrichedFeed.holidays.first?.article?.title == "Test Holiday")
    }
}
