package dev.tvnext.api

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode

/** Original gson/FilterAdapter supports either one Filter object or a list per category. */
object SubscriptionFilters {
    fun normalize(raw: JsonNode,mapper: ObjectMapper): ObjectNode {
        val output=mapper.createObjectNode()
        if(!raw.isObject)return output
        raw.fields().asSequence().take(1000).forEach { (category,source) ->
            if(category.length>4096)return@forEach
            val entries=if(source.isObject)listOf(source) else source.takeIf { it.isArray }?.toList().orEmpty()
            val keys=mutableSetOf<String>();val filters=mapper.createArrayNode()
            entries.take(30).forEach filter@ { filter ->
                val key=filter.path("key").takeIf { it.isValueNode && !it.isNull }?.asText().orEmpty()
                if(key.isBlank() || key.length>100 || !keys.add(key))return@filter
                val choices=mapper.createArrayNode();val values=mutableSetOf<String>()
                filter.path("value").takeIf { it.isArray }?.take(200)?.forEach choice@ { value ->
                    if(!value.isObject)return@choice
                    val rawValue=value.path("v")
                    if(!rawValue.isMissingNode && !rawValue.isValueNode)return@choice
                    val v=if(rawValue.isNull || rawValue.isMissingNode)"" else rawValue.asText().trim()
                    if(v.length>1000 || !values.add(v))return@choice
                    choices.addObject().put("n",value.path("n").takeIf { it.isValueNode && !it.isNull }?.asText().orEmpty().take(200)).put("v",v)
                }
                if(choices.isEmpty)return@filter
                val item=filters.addObject().put("key",key).put("name",filter.path("name").takeIf { it.isValueNode && !it.isNull }?.asText().orEmpty().take(200))
                filter.path("init").takeIf { it.isValueNode && !it.isNull }?.asText()?.trim()?.takeIf { it.length<=1000 }?.let { item.put("init",it) }
                item.set<JsonNode>("value",choices)
            }
            if(!filters.isEmpty)output.set<JsonNode>(category,filters)
        }
        return output
    }
}
