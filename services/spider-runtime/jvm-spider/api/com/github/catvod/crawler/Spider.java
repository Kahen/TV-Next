package com.github.catvod.crawler;

import android.content.Context;
import java.util.HashMap;
import java.util.List;

/** GPL-3.0 compatibility signatures adapted from FongMi/TV 123cc086.
 * Only the documented pure-JVM media subset is implemented. Android host
 * fields, JS/dialog/net/local helpers, proxy/action and live callbacks are absent.
 */
public abstract class Spider {
    public String siteKey;
    public void init(Context context) throws Exception {}
    public void init(Context context, String extend) throws Exception { init(context); }
    public String homeContent(boolean filter) throws Exception { return ""; }
    public String homeVideoContent() throws Exception { return ""; }
    public String categoryContent(String tid, String pg, boolean filter, HashMap<String, String> extend) throws Exception { return ""; }
    public String detailContent(List<String> ids) throws Exception { return ""; }
    public String searchContent(String key, boolean quick) throws Exception { return ""; }
    public String searchContent(String key, boolean quick, String pg) throws Exception { return ""; }
    public String playerContent(String flag, String id, List<String> vipFlags) throws Exception { return ""; }
    public void destroy() {}
}
