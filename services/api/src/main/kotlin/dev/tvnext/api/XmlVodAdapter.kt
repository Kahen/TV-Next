package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.io.StringReader
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.server.ResponseStatusException
import org.w3c.dom.Element
import org.xml.sax.InputSource

/** Matches Result.fromType(0) / Vod XML field mappings; never resolves entities or external DTDs. */
@Component
class XmlVodAdapter(private val mapper: ObjectMapper) {
    fun parse(text: String): JsonNode {
        if (text.toByteArray(Charsets.UTF_8).size > 1_048_576 || Regex("<!DOCTYPE|<!ENTITY", RegexOption.IGNORE_CASE).containsMatchIn(text)) bad()
        val factory = DocumentBuilderFactory.newInstance().apply {
            isXIncludeAware = false; isExpandEntityReferences = false
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setFeature("http://xml.org/sax/features/external-general-entities", false)
            setFeature("http://xml.org/sax/features/external-parameter-entities", false)
            setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, ""); setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        }
        val doc = try { factory.newDocumentBuilder().parse(InputSource(StringReader(text))) } catch (_: Exception) { bad() }
        val root = mapper.createObjectNode()
        fun children(parent: Element, name: String): List<Element> = (0 until parent.childNodes.length).map { parent.childNodes.item(it) }.filterIsInstance<Element>().filter { it.tagName == name }
        val rss = doc.documentElement
        if (rss.tagName != "rss") bad()
        val classes = root.putArray("class")
        children(rss, "class").firstOrNull()?.let { c -> children(c, "ty").take(200).forEach {
            classes.addObject().put("type_id", it.getAttribute("id")).put("type_name", it.textContent.take(200))
        } }
        val list = root.putArray("list")
        children(rss, "list").firstOrNull()?.let { c ->
            listOf("page", "pagecount", "pagesize", "recordcount").forEach { attr ->
                root.put(when(attr) { "recordcount" -> "total"; "pagesize" -> "limit"; else -> attr }, c.getAttribute(attr))
            }
            children(c, "video").take(2000).forEach { v ->
                val item = list.addObject()
                val fields = mapOf("id" to "vod_id", "name" to "vod_name", "type" to "type_name", "tid" to "type_id", "pic" to "vod_pic",
                    "note" to "vod_remarks", "year" to "vod_year", "des" to "vod_content", "director" to "vod_director", "actor" to "vod_actor")
                fields.forEach { (source, target) -> children(v, source).firstOrNull()?.let { item.put(target, it.textContent.take(2000)) } }
                children(v, "dl").firstOrNull()?.let { dl ->
                    val lines = children(dl, "dd").take(30)
                    item.put("vod_play_from", lines.joinToString("$$$") { it.getAttribute("flag") })
                    item.put("vod_play_url", lines.joinToString("$$$") { it.textContent })
                }
            }
        }
        return root
    }
    private fun bad(): Nothing = throw ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid or forbidden provider XML")
}
