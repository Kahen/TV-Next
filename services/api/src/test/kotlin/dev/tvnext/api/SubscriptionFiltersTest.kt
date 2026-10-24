package dev.tvnext.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.nio.file.Path
import java.util.Base64
import kotlin.test.*

class SubscriptionFiltersTest {
    private val mapper=jacksonObjectMapper()
    @Test fun originalSingleObjectListsNullChoicesAndTrimmedValuesMatchTheClientGolden() {
        val fixture=mapper.readTree(Path.of("../../fixtures/fongmi-filters-golden.json").toFile())
        assertEquals(fixture.path("expected"),SubscriptionFilters.normalize(fixture.path("input"),mapper))
        val provider=SubscribedProvider(Subscriptions(mapper,ProviderTransport()),mapper,StaticFongMiProvider(mapper),ProviderTransport(),XmlVodAdapter(mapper))
        val values=fixture.path("initial").fields().asSequence().associate { it.key to it.value.asText() }
        val request=SiteRequest(categoryId="movie",filters=values,page=2)
        val type4=provider.params(4,"category",request,"")
        assertEquals(fixture.path("initial"),mapper.readTree(Base64.getUrlDecoder().decode(type4.getValue("ext"))))
        val type1=provider.params(1,"category",request,"")
        assertEquals(fixture.path("initial"),mapper.readTree(type1.getValue("f")))
        assertEquals("2",type4["pg"])
    }
    @Test fun malformedAndOversizedChoicesDoNotBreakTheWholeCatalog() {
        val root=mapper.createObjectNode();val category=root.putArray("movie")
        category.addNull();category.addObject().put("key","x").putArray("value").addObject().put("v","a".repeat(1001))
        repeat(40) { index -> category.addObject().put("key","key$index").putArray("value").addObject().put("v",index) }
        val filters=SubscriptionFilters.normalize(root,mapper).path("movie")
        assertTrue(filters.size()<=30);assertTrue(filters.all { it.path("key").asText().startsWith("key") })
        assertTrue(SubscriptionFilters.normalize(mapper.nullNode(),mapper).isEmpty)
    }
}
