package dev.tvnext.api

import java.io.*
import java.net.*
import java.nio.charset.StandardCharsets.ISO_8859_1
import javax.net.ssl.*
import org.springframework.http.HttpStatus
import org.springframework.stereotype.Component
import org.springframework.web.server.ResponseStatusException

internal fun mediaOrigin(uri: URI) = "${uri.scheme.lowercase()}://${uri.host.lowercase()}:${if(uri.port>=0)uri.port else if(uri.scheme=="https")443 else 80}"

class MediaResponse(val uri: URI, val status: Int, val headers: Map<String,String>, val body: InputStream,
    private val connection: Closeable): Closeable { override fun close() = connection.close() }

/** Independent streaming HTTP framing; shares the subscription DNS/SSRF policy. No cookies or proxy are inherited. */
@Component
open class MediaTransport(private val policy: ProviderTransport) {
    open fun fetch(initial: URI, initialHeaders: Map<String,String>, range: String?, head: Boolean=false): MediaResponse {
        ProviderTransport.validateHeaders(initialHeaders)
        var uri=Subscriptions.httpUri(initial.toString());var headers=initialHeaders
        for(hop in 0..3) {
            val response=connect(uri,policy.resolveAddress(uri),headers,range,head)
            if(response.status !in setOf(301,302,303,307,308))return response
            response.use {
                if(hop==3)badGateway()
                val next=runCatching { Subscriptions.httpUri(uri.resolve(it.headers["location"] ?: badGateway()).toString()) }.getOrElse { badGateway() }
                if(uri.scheme=="https" && next.scheme!="https")badGateway()
                if(mediaOrigin(uri)!=mediaOrigin(next))headers=emptyMap()
                uri=next
            }
        }
        badGateway()
    }
    internal fun connect(uri: URI,address: InetAddress,headers: Map<String,String>,range: String?,head: Boolean): MediaResponse {
        val plain=Socket()
        try {
            plain.connect(InetSocketAddress(address,if(uri.port>=0)uri.port else if(uri.scheme=="https")443 else 80),3000)
            plain.soTimeout=5000
            val socket=if(uri.scheme=="https") {
                val ssl=(SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(plain,uri.host,plain.port,true) as SSLSocket
                ssl.sslParameters=SSLParameters().apply {
                    endpointIdentificationAlgorithm="HTTPS"
                    if(!uri.host.contains(':') && !uri.host.matches(Regex("[0-9.]+")))serverNames=listOf(SNIHostName(uri.host))
                }
                ssl.startHandshake();ssl
            } else plain
            val wire=URI(uri.toASCIIString())
            val path=(wire.rawPath?.takeIf { it.isNotEmpty() } ?: "/")+(wire.rawQuery?.let { "?$it" } ?: "")
            val host=if(uri.host.contains(':'))"[${uri.host}]" else uri.host
            val authority=host+(if(uri.port>=0)":${uri.port}" else "")
            val extra=headers.entries.joinToString("") { "${it.key}: ${it.value}\r\n" }
            val request="${if(head)"HEAD" else "GET"} $path HTTP/1.1\r\nHost: $authority\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n"+
                extra+(range?.let { "Range: $it\r\n" } ?: "")+"\r\n"
            socket.getOutputStream().write(request.toByteArray(ISO_8859_1))
            val deadline=System.nanoTime()+60_000_000_000L
            val input=object: FilterInputStream(socket.getInputStream().buffered()) {
                private fun checkDeadline() { if(System.nanoTime()>deadline || Thread.currentThread().isInterrupted)throw SocketTimeoutException("Media response deadline") }
                override fun read(): Int { checkDeadline();return super.read() }
                override fun read(b: ByteArray,off: Int,len: Int): Int { checkDeadline();return `in`.read(b,off,len) }
            }
            val response=readResponse(uri,input,socket,head)
            return response
        } catch(error: Exception) { plain.close();throw error }
    }
    companion object {
        const val MAX_BODY=33_554_432L
        const val MAX_RANGE=8_388_608L
        internal fun boundedRange(value: String?): String? {
            if(value==null)return null
            val m=Regex("bytes=([0-9]{0,16})-([0-9]{0,16})").matchEntire(value)
                ?: throw ResponseStatusException(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE,"A single byte range is required")
            val start=m.groupValues[1].toLongOrNull();val end=m.groupValues[2].toLongOrNull()
            if(start==null && (end==null || end<=0) || start!=null && end!=null && end<start)
                throw ResponseStatusException(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE,"Invalid byte range")
            return if(start==null)"bytes=-${minOf(end!!,MAX_RANGE)}" else "bytes=$start-${minOf(end ?: Long.MAX_VALUE,start+MAX_RANGE-1)}"
        }
        internal fun readResponse(uri: URI,input: InputStream,socket: Closeable,head: Boolean=false): MediaResponse {
            var headerBytes=0
            fun line(limit: Int=8192): String {
                val out=ByteArrayOutputStream()
                while(true) {
                    val c=input.read();if(c<0 || ++headerBytes>32768 || out.size()>limit)throw IOException("Media header limit")
                    if(c==10) {
                        val bytes=out.toByteArray()
                        if(bytes.isEmpty() || bytes.last()!=13.toByte())throw IOException("Expected CRLF")
                        return String(bytes,0,bytes.size-1,ISO_8859_1)
                    }
                    out.write(c)
                }
            }
            val status=Regex("HTTP/1\\.[01] ([0-9]{3})(?: .*)?").matchEntire(line())?.groupValues?.get(1)?.toInt() ?: throw IOException("Invalid media status")
            val headers=mutableMapOf<String,String>()
            while(true) {
                val raw=line();if(raw.isEmpty())break
                val split=raw.indexOf(':');if(split<=0 || raw[0].isWhitespace())throw IOException("Invalid media header")
                val name=raw.substring(0,split).lowercase();val value=raw.substring(split+1).trim()
                if(!name.matches(Regex("[a-z0-9!#$%&'*+.^_`|~-]+")) || value.any { it.code<32 || it.code==127 })throw IOException("Invalid media header")
                if(headers.put(name,value)!=null && name in setOf("content-length","transfer-encoding","content-encoding","content-type","content-range","location"))throw IOException("Ambiguous media header")
            }
            if(status in setOf(301,302,303,307,308))return MediaResponse(uri,status,headers,InputStream.nullInputStream(),socket)
            if(status !in setOf(200,206,416))badGateway()
            if(headers["content-encoding"]?.lowercase() !in listOf(null,"identity"))badGateway()
            val transfer=headers["transfer-encoding"]?.lowercase()
            val length=headers["content-length"]?.let { it.toLongOrNull()?.takeIf { n -> n>=0 } ?: throw IOException("Invalid length") }
            if(transfer!=null && (transfer!="chunked" || length!=null))throw IOException("Ambiguous media body")
            if(status==206) {
                val parts=Regex("bytes ([0-9]{1,16})-([0-9]{1,16})/([0-9]{1,16}|\\*)").matchEntire(headers["content-range"].orEmpty()) ?: throw IOException("Invalid content range")
                val first=parts.groupValues[1].toLong();val last=parts.groupValues[2].toLong();val total=parts.groupValues[3].toLongOrNull()
                if(last<first || total!=null && last>=total || length!=null && length!=last-first+1)throw IOException("Invalid range bounds")
            }
            if(head || status==416)return MediaResponse(uri,status,headers,InputStream.nullInputStream(),socket)
            if(length!=null && length>MAX_BODY)throw IOException("Media request requires a smaller byte range")
            val body=object: InputStream() {
                var remaining=length ?: Long.MAX_VALUE
                var chunk=0L;var finished=false;var count=0L
                private fun nextChunk() {
                    if(chunk!=0L || finished)return
                    val raw=line(100).substringBefore(';').trim()
                    if(!raw.matches(Regex("[0-9a-fA-F]{1,16}")))throw IOException("Invalid media chunk")
                    chunk=raw.toLongOrNull(16) ?: throw IOException("Invalid media chunk")
                    if(chunk>MAX_BODY-count)throw IOException("Media body limit")
                    if(chunk==0L){while(line().isNotEmpty()){};finished=true}
                }
                override fun read(): Int { val b=ByteArray(1);return if(read(b,0,1)<0)-1 else b[0].toInt() and 255 }
                override fun read(b: ByteArray,off: Int,len: Int): Int {
                    if(len==0)return 0
                    if(transfer=="chunked")nextChunk()
                    if(finished || remaining==0L)return -1
                    val allowed=minOf(len.toLong(),remaining,if(transfer=="chunked")chunk else Long.MAX_VALUE,MAX_BODY-count+1).toInt()
                    val n=input.read(b,off,allowed)
                    if(n<0) { if(length!=null || transfer=="chunked")throw EOFException("Truncated media");finished=true;return -1 }
                    count+=n;if(count>MAX_BODY)throw IOException("Media body limit")
                    remaining-=n
                    if(transfer=="chunked") { chunk-=n;if(chunk==0L && (input.read()!=13 || input.read()!=10))throw IOException("Invalid media chunk delimiter") }
                    return n
                }
            }
            return MediaResponse(uri,status,headers,body,socket)
        }
        private fun badGateway(): Nothing = throw ResponseStatusException(HttpStatus.BAD_GATEWAY,"Media upstream rejected")
    }
}
