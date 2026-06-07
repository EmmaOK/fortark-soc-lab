#!/usr/bin/env python3
import asyncio
import os
import time
from typing import List, Optional

import httpx
from fastapi import FastAPI, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

app = FastAPI(title="Fortark SOC Tools", docs_url=None, redoc_url=None)

OS_URL  = os.environ.get("OPENSEARCH_URL",           "https://soc-opensearch:9200")
OS_USER = os.environ.get("OPENSEARCH_USER",           "admin")
OS_PASS = os.environ.get("OPENSEARCH_ADMIN_PASSWORD", "")
TH_URL  = os.environ.get("THEHIVE_URL",               "http://soc-thehive:9000")
TH_KEY  = os.environ.get("THEHIVE_API_KEY",           "")
CX_URL  = os.environ.get("CORTEX_URL",                "http://soc-cortex:9001")
CX_KEY  = os.environ.get("CORTEX_API_KEY",            "")

HTML = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fortark SOC Tools</title>
<style>
:root{--bg:#0d1117;--bg2:#161b22;--bg3:#21262d;--accent:#1f6feb;--ah:#388bfd;--border:#30363d;--text:#c9d1d9;--muted:#8b949e;--ok:#3fb950;--warn:#d29922;--err:#f85149}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:"Segoe UI",system-ui,sans-serif;font-size:14px}
header{background:var(--bg2);border-bottom:1px solid var(--border);padding:12px 24px;display:flex;align-items:center}
.logo{font-size:16px;font-weight:700;color:#fff;letter-spacing:.5px}.logo span{color:var(--accent)}
.tabs{background:var(--bg2);border-bottom:1px solid var(--border);padding:0 24px;display:flex;gap:4px}
.tab{padding:12px 16px;cursor:pointer;border-bottom:2px solid transparent;color:var(--muted);font-size:13px;transition:.15s;user-select:none}
.tab:hover{color:var(--text)}.tab.on{color:var(--accent);border-bottom-color:var(--accent)}
.content{padding:24px;max-width:1200px;margin:0 auto}
.panel{display:none}.panel.on{display:block}
.row{display:flex;gap:8px;align-items:flex-end;margin-bottom:16px;flex-wrap:wrap}
.f{display:flex;flex-direction:column;gap:4px}.f label{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.5px}
input[type=text],select,textarea{background:var(--bg2);border:1px solid var(--border);color:var(--text);padding:7px 11px;border-radius:6px;font-size:13px;outline:none;font-family:inherit}
input[type=text]:focus,select:focus,textarea:focus{border-color:var(--accent)}
input.w{width:360px}textarea{resize:vertical;width:100%}
.btn{padding:8px 16px;border:none;border-radius:6px;cursor:pointer;font-size:13px;font-weight:500;transition:.15s}
.btn-p{background:var(--accent);color:#fff}.btn-p:hover{background:var(--ah)}
.btn-s{background:var(--bg3);color:var(--text);border:1px solid var(--border)}.btn-s:hover{border-color:var(--accent);color:var(--accent)}
.btn:disabled{opacity:.4;cursor:not-allowed}
.st{font-size:12px;color:var(--muted);margin-bottom:12px;min-height:18px}
.st.load{color:var(--accent)}.st.ok{color:var(--ok)}.st.err{color:var(--err)}
.wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:12px}
th{background:var(--bg3);color:var(--muted);text-align:left;padding:8px 12px;border-bottom:1px solid var(--border);font-weight:500;white-space:nowrap}
td{padding:8px 12px;border-bottom:1px solid var(--border);vertical-align:top;max-width:420px;word-break:break-word}
tr:hover td{background:var(--bg2)}
.lv{display:inline-block;padding:1px 6px;border-radius:4px;font-weight:700;font-size:11px}
.lv0{background:#1c2c1c;color:var(--ok)}.lv1{background:#2c240e;color:var(--warn)}
.lv2{background:#2c1a1a;color:var(--err)}.lv3{background:#3a0000;color:#ff4444}
.card{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:16px;margin-top:12px}
.card h3{font-size:13px;color:var(--muted);margin-bottom:12px}
.crow{display:flex;gap:24px;flex-wrap:wrap;margin-bottom:12px}
.cf{display:flex;flex-direction:column;gap:3px}.cf .k{font-size:11px;color:var(--muted)}.cf .v{font-size:13px;font-weight:600}
.bad{display:inline-block;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:600;margin-right:4px}
.mal{background:#3a0000;color:#ff4444}.sus{background:#2c240e;color:var(--warn)}.safe{background:#1c2c1c;color:var(--ok)}
.form-box{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:16px;margin-top:16px}
.form-box h3{margin-bottom:12px;font-size:14px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.span2{grid-column:1/-1}
.empty{text-align:center;padding:48px 24px;color:var(--muted)}
pre{font-size:11px;overflow-x:auto;color:var(--muted);max-height:300px;overflow-y:auto;background:var(--bg);padding:10px;border-radius:6px;border:1px solid var(--border)}
summary{cursor:pointer;color:var(--muted);font-size:12px;margin-top:10px;user-select:none}
</style>
</head>
<body>
<header>
  <div class="logo">FORTARK <span>SOC</span> TOOLS</div>
</header>

<div class="tabs">
  <div class="tab on"  onclick="tab(event,\'events\')">Events</div>
  <div class="tab"     onclick="tab(event,\'alerts\')">Alerts</div>
  <div class="tab"     onclick="tab(event,\'ioc\')">IOC Lookup</div>
  <div class="tab"     onclick="tab(event,\'cases\')">Cases</div>
</div>

<div class="content">

  <!-- EVENTS -->
  <div class="panel on" id="p-events">
    <div class="row">
      <div class="f"><label>Filter query</label>
        <input type="text" class="w" id="ev-q" placeholder="rule.groups: suricata   or   rule.id: 5763">
      </div>
      <div class="f"><label>Time range</label>
        <select id="ev-t">
          <option value="15m">Last 15 min</option>
          <option value="1h" selected>Last 1 hour</option>
          <option value="4h">Last 4 hours</option>
          <option value="24h">Last 24 hours</option>
          <option value="7d">Last 7 days</option>
        </select>
      </div>
      <div class="f"><label>Index</label>
        <select id="ev-idx">
          <option value="wazuh-alerts-*">Wazuh alerts</option>
          <option value="suricata-*">Suricata</option>
          <option value="*">All indices</option>
        </select>
      </div>
      <div class="f"><label>&nbsp;</label>
        <button class="btn btn-p" onclick="searchEvents()">Search</button>
      </div>
    </div>
    <div class="st" id="ev-st"></div>
    <div class="wrap" id="ev-res"></div>
  </div>

  <!-- ALERTS -->
  <div class="panel" id="p-alerts">
    <div class="row">
      <div class="f"><label>Minimum level</label>
        <select id="al-lv">
          <option value="3">3+ (Low)</option>
          <option value="5">5+ (Medium)</option>
          <option value="7" selected>7+ (High)</option>
          <option value="10">10+ (Critical)</option>
          <option value="12">12+ (Very critical)</option>
        </select>
      </div>
      <div class="f"><label>Max results</label>
        <select id="al-lim">
          <option value="20" selected>20</option>
          <option value="50">50</option>
          <option value="100">100</option>
        </select>
      </div>
      <div class="f"><label>&nbsp;</label>
        <button class="btn btn-p" onclick="fetchAlerts()">Fetch Alerts</button>
      </div>
    </div>
    <div class="st" id="al-st"></div>
    <div class="wrap" id="al-res"></div>
  </div>

  <!-- IOC -->
  <div class="panel" id="p-ioc">
    <div class="row">
      <div class="f"><label>Observable value</label>
        <input type="text" class="w" id="ioc-v" placeholder="IP address, domain, hash...">
      </div>
      <div class="f"><label>Type</label>
        <select id="ioc-t">
          <option value="ip">IP address</option>
          <option value="domain">Domain / FQDN</option>
          <option value="hash">File hash</option>
          <option value="url">URL</option>
        </select>
      </div>
      <div class="f"><label>Analyser</label>
        <select id="ioc-a">
          <option value="AbuseIPDB_2_0">AbuseIPDB</option>
          <option value="VirusTotal_GetReport_3_1">VirusTotal</option>
          <option value="Shodan_Host_1_0">Shodan</option>
        </select>
      </div>
      <div class="f"><label>&nbsp;</label>
        <button class="btn btn-p" onclick="runIOC()">Analyse</button>
      </div>
    </div>
    <div class="st" id="ioc-st"></div>
    <div id="ioc-res"></div>
  </div>

  <!-- CASES -->
  <div class="panel" id="p-cases">
    <div class="row">
      <div class="f"><label>Status filter</label>
        <select id="cs-st">
          <option value="Open">Open</option>
          <option value="Resolved">Resolved</option>
        </select>
      </div>
      <div class="f"><label>&nbsp;</label>
        <button class="btn btn-p" onclick="fetchCases()">Fetch Cases</button>
        <button class="btn btn-s" onclick="toggleForm()" style="margin-left:8px">+ New Alert</button>
      </div>
    </div>
    <div class="st" id="cs-msg"></div>
    <div class="wrap" id="cs-res"></div>

    <div class="form-box" id="new-form" style="display:none">
      <h3>Create Alert in TheHive</h3>
      <div class="grid2">
        <div class="f span2"><label>Title *</label>
          <input type="text" id="nw-title" placeholder="e.g. SSH brute force from 10.0.0.5" style="width:100%">
        </div>
        <div class="f span2"><label>Description *</label>
          <textarea id="nw-desc" rows="3" placeholder="Describe the incident, what you observed, and when it started..."></textarea>
        </div>
        <div class="f"><label>Severity</label>
          <select id="nw-sev">
            <option value="1">Low</option>
            <option value="2" selected>Medium</option>
            <option value="3">High</option>
            <option value="4">Critical</option>
          </select>
        </div>
        <div class="f"><label>Tags (comma-separated)</label>
          <input type="text" id="nw-tags" placeholder="T1110.001, ssh, brute-force">
        </div>
      </div>
      <div style="margin-top:12px;display:flex;gap:8px">
        <button class="btn btn-p" onclick="createAlert()">Create Alert</button>
        <button class="btn btn-s" onclick="toggleForm()">Cancel</button>
      </div>
    </div>
  </div>

</div>

<script>
function tab(ev, name) {
  document.querySelectorAll(\'.tab\').forEach(function(t){ t.classList.remove(\'on\'); });
  document.querySelectorAll(\'.panel\').forEach(function(p){ p.classList.remove(\'on\'); });
  ev.target.classList.add(\'on\');
  document.getElementById(\'p-\'+name).classList.add(\'on\');
}

function lvClass(l) {
  l = parseInt(l);
  if (l >= 12) return \'lv lv3\';
  if (l >= 7)  return \'lv lv2\';
  if (l >= 5)  return \'lv lv1\';
  return \'lv lv0\';
}

function fmt(ts) {
  if (!ts) return \'-\';
  return new Date(ts).toLocaleString(\'en-GB\', {month:\'short\',day:\'numeric\',hour:\'2-digit\',minute:\'2-digit\',second:\'2-digit\'});
}

function st(id, msg, cls) {
  var el = document.getElementById(id);
  el.textContent = msg;
  el.className = \'st\' + (cls ? \' \'+cls : \'\');
}

async function searchEvents() {
  var q = document.getElementById(\'ev-q\').value.trim();
  var t = document.getElementById(\'ev-t\').value;
  var idx = document.getElementById(\'ev-idx\').value;
  var res = document.getElementById(\'ev-res\');
  if (!q) { st(\'ev-st\',\'Enter a query.\',\'err\'); return; }
  st(\'ev-st\',\'Searching...\',\'load\'); res.innerHTML = \'\';
  try {
    var r = await fetch(\'/api/events\', {method:\'POST\',headers:{\'Content-Type\':\'application/json\'},
      body: JSON.stringify({query:q, time_range:t, size:30, index:idx})});
    var d = await r.json();
    if (d.error) { st(\'ev-st\', d.error, \'err\'); return; }
    st(\'ev-st\', d.total + \' total — showing \' + d.count, \'ok\');
    if (!d.events.length) { res.innerHTML = \'<div class="empty">No events in this time window.</div>\'; return; }
    var rows = d.events.map(function(e) {
      var lv = e.rule && e.rule.level != null ? e.rule.level : \'-\';
      var rid = (e.rule && e.rule.id) || \'-\';
      var desc = (e.rule && e.rule.description) || (e.event && e.event.module) || \'-\';
      var src = (e.data && e.data.srcip) || (e.network && e.network.src_ip) || \'\';
      var ag = (e.agent && e.agent.name) || \'-\';
      return \'<tr><td>\'+fmt(e[\'@timestamp\'])+\'</td><td><span class="\'+lvClass(lv)+\'">\'+lv+\'</span></td><td>\'+rid+\'</td><td>\'+ag+\'</td><td>\'+esc(desc)+(src?\' &mdash; \'+src:\'\')+\'</td></tr>\';
    }).join(\'\');
    res.innerHTML = \'<table><thead><tr><th>Time</th><th>Lvl</th><th>Rule ID</th><th>Agent</th><th>Description</th></tr></thead><tbody>\'+rows+\'</tbody></table>\';
  } catch(e) { st(\'ev-st\',\'Request failed: \'+e.message,\'err\'); }
}

async function fetchAlerts() {
  var lv = document.getElementById(\'al-lv\').value;
  var lim = document.getElementById(\'al-lim\').value;
  var res = document.getElementById(\'al-res\');
  st(\'al-st\',\'Loading...\',\'load\'); res.innerHTML = \'\';
  try {
    var r = await fetch(\'/api/alerts?min_level=\'+lv+\'&limit=\'+lim);
    var d = await r.json();
    if (d.error) { st(\'al-st\', d.error, \'err\'); return; }
    st(\'al-st\', d.count + \' alerts  |  last 24h\', \'ok\');
    if (!d.alerts.length) { res.innerHTML = \'<div class="empty">No alerts at this level in the last 24 hours.</div>\'; return; }
    var rows = d.alerts.map(function(a) {
      var lv = a.rule && a.rule.level != null ? a.rule.level : \'-\';
      var desc = (a.rule && a.rule.description) || \'-\';
      var src = (a.data && a.data.srcip) || \'\';
      return \'<tr><td><span class="\'+lvClass(lv)+\'">\'+lv+\'</span></td><td>\'+fmt(a[\'@timestamp\'])+\'</td><td>\'+esc(desc)+(src?\' &mdash; src: \'+src:\'\')+\'</td></tr>\';
    }).join(\'\');
    res.innerHTML = \'<table><thead><tr><th>Level</th><th>Time</th><th>Alert</th></tr></thead><tbody>\'+rows+\'</tbody></table>\';
  } catch(e) { st(\'al-st\',\'Request failed: \'+e.message,\'err\'); }
}

async function runIOC() {
  var val = document.getElementById(\'ioc-v\').value.trim();
  var type = document.getElementById(\'ioc-t\').value;
  var anl = document.getElementById(\'ioc-a\').value;
  var res = document.getElementById(\'ioc-res\');
  if (!val) { st(\'ioc-st\',\'Enter an observable value.\',\'err\'); return; }
  st(\'ioc-st\',\'Submitting job — may take 15-30s...\',\'load\'); res.innerHTML = \'\';
  try {
    var r = await fetch(\'/api/cortex\', {method:\'POST\',headers:{\'Content-Type\':\'application/json\'},
      body: JSON.stringify({analyzer_id:anl, data:val, data_type:type})});
    var d = await r.json();
    if (d.error) { st(\'ioc-st\', d.error, \'err\'); return; }
    st(\'ioc-st\', \'Analysis complete  |  \' + anl, \'ok\');
    renderIOC(d, val, anl);
  } catch(e) { st(\'ioc-st\',\'Request failed: \'+e.message,\'err\'); }
}

function renderIOC(d, val, anl) {
  var res = document.getElementById(\'ioc-res\');
  var report = d.report || {};
  var summary = (report.summary) || {};
  var taxa = summary.taxonomies || [];
  var badges = taxa.map(function(t) {
    var cls = t.level === \'malicious\' ? \'mal\' : t.level === \'suspicious\' ? \'sus\' : \'safe\';
    return \'<span class="bad \'+cls+\'">\'+esc(t.namespace)+\': \'+esc(String(t.value))+\'</span>\';
  }).join(\'\');
  var full = JSON.stringify(report, null, 2);
  res.innerHTML = \'<div class="card"><h3>\'+esc(anl)+\' &mdash; \'+esc(val)+\'</h3>\'
    +\'<div class="crow">\'
    +\'<div class="cf"><div class="k">Status</div><div class="v">\''+(d.status||\'-\')+\'</div></div>\'
    +\'<div class="cf"><div class="k">Verdicts</div><div class="v">\''+(badges||\'&mdash;\')+\'</div></div>\'
    +\'</div>\'
    +\'<details><summary>Full report</summary><pre>\'+esc(full)+\'</pre></details>\'
    +\'</div>\';
}

async function fetchCases() {
  var s = document.getElementById(\'cs-st\').value;
  var res = document.getElementById(\'cs-res\');
  st(\'cs-msg\',\'Loading...\',\'load\'); res.innerHTML = \'\';
  try {
    var r = await fetch(\'/api/cases?status=\'+s);
    var d = await r.json();
    if (d.error) { st(\'cs-msg\', d.error, \'err\'); return; }
    st(\'cs-msg\', d.count + \' cases\', \'ok\');
    if (!d.cases.length) { res.innerHTML = \'<div class="empty">No cases.</div>\'; return; }
    var sm = {1:\'Low\',2:\'Medium\',3:\'High\',4:\'Critical\'};
    var sc = {1:\'lv lv0\',2:\'lv lv1\',3:\'lv lv2\',4:\'lv lv3\'};
    var rows = d.cases.map(function(c) {
      var sev = c.severity || 2;
      var tags = (c.tags||[]).slice(0,4).map(function(t){ return \'<span style="background:var(--bg3);padding:1px 6px;border-radius:4px;font-size:11px;margin-right:3px">\'+esc(t)+\'</span>\'; }).join(\'\');
      return \'<tr><td>#\'+(c.caseId||c._id||\'?\')+\'</td><td>\'+esc(c.title||\'\')+\'</td>\'
        +\'<td><span class="\'+sc[sev]+\'">\'+sm[sev]+\'</span></td>\'
        +\'<td>\'+esc(c.status||\'\')+\'</td>\'
        +\'<td>\'+fmt(c._createdAt)+\'</td>\'
        +\'<td>\'+tags+\'</td></tr>\';
    }).join(\'\');
    res.innerHTML = \'<table><thead><tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th><th>Created</th><th>Tags</th></tr></thead><tbody>\'+rows+\'</tbody></table>\';
  } catch(e) { st(\'cs-msg\',\'Request failed: \'+e.message,\'err\'); }
}

function toggleForm() {
  var f = document.getElementById(\'new-form\');
  f.style.display = f.style.display === \'none\' ? \'block\' : \'none\';
}

async function createAlert() {
  var title = document.getElementById(\'nw-title\').value.trim();
  var desc = document.getElementById(\'nw-desc\').value.trim();
  var sev = parseInt(document.getElementById(\'nw-sev\').value);
  var tags = document.getElementById(\'nw-tags\').value.split(\',\').map(function(t){ return t.trim(); }).filter(Boolean);
  if (!title || !desc) { st(\'cs-msg\',\'Title and description are required.\',\'err\'); return; }
  st(\'cs-msg\',\'Creating...\',\'load\');
  try {
    var r = await fetch(\'/api/alerts/create\', {method:\'POST\',headers:{\'Content-Type\':\'application/json\'},
      body: JSON.stringify({title:title, description:desc, severity:sev, tags:tags, source:\'Student\'})});
    var d = await r.json();
    if (d.error) { st(\'cs-msg\', d.error, \'err\'); return; }
    st(\'cs-msg\',\'Alert created! ID: \'+(d._id||d.id||\'?\'), \'ok\');
    toggleForm();
    document.getElementById(\'nw-title\').value = \'\';
    document.getElementById(\'nw-desc\').value = \'\';
    document.getElementById(\'nw-tags\').value = \'\';
  } catch(e) { st(\'cs-msg\',\'Request failed: \'+e.message,\'err\'); }
}

function esc(s) {
  return String(s).replace(/&/g,\'&amp;\').replace(/</g,\'&lt;\').replace(/>/g,\'&gt;\').replace(/"/g,\'&quot;\');
}
</script>
</body>
</html>'''


class EventSearch(BaseModel):
    query: str
    time_range: str = "1h"
    size: int = 20
    index: str = "wazuh-alerts-*"

class CortexReq(BaseModel):
    analyzer_id: str
    data: str
    data_type: str
    tlp: int = 2

class AlertCreate(BaseModel):
    title: str
    description: str
    severity: int = 2
    tags: List[str] = []
    source: str = "Manual"


@app.get("/", response_class=HTMLResponse)
async def index():
    return HTML


@app.post("/api/events")
async def search_events(req: EventSearch):
    body = {
        "query": {
            "bool": {
                "must": [{"query_string": {"query": req.query, "default_operator": "AND"}}],
                "filter": [{"range": {"@timestamp": {"gte": f"now-{req.time_range}"}}}],
            }
        },
        "size": req.size,
        "sort": [{"@timestamp": {"order": "desc"}}],
    }

    async with httpx.AsyncClient(verify=False, timeout=15) as c:
        r = await c.post(
            f"{OS_URL}/{req.index}/_search",
            auth=(OS_USER, OS_PASS),
            json=body,
        )
        if r.status_code not in (200, 201):
            return {"error": f"OpenSearch {r.status_code}: {r.text[:300]}"}
        data = r.json()

    hits = data.get("hits", {}).get("hits", [])
    total = data.get("hits", {}).get("total", {})
    if isinstance(total, dict):
        total = total.get("value", 0)
    return {"count": len(hits), "total": total, "events": [h["_source"] for h in hits]}


@app.get("/api/alerts")
async def get_alerts(
    min_level: int = Query(7),
    limit: int = Query(20),
):
    body = {
        "query": {
            "bool": {
                "must": [{"range": {"rule.level": {"gte": min_level}}}],
                "filter": [{"range": {"@timestamp": {"gte": "now-24h"}}}],
            }
        },
        "size": limit,
        "sort": [{"@timestamp": {"order": "desc"}}],
    }

    async with httpx.AsyncClient(verify=False, timeout=15) as c:
        r = await c.post(
            f"{OS_URL}/wazuh-alerts-*/_search",
            auth=(OS_USER, OS_PASS),
            json=body,
        )
        if r.status_code not in (200, 201):
            return {"error": f"OpenSearch {r.status_code}: {r.text[:300]}"}
        data = r.json()

    hits = data.get("hits", {}).get("hits", [])
    return {"count": len(hits), "alerts": [h["_source"] for h in hits]}


@app.post("/api/cortex")
async def run_cortex(req: CortexReq):
    headers = {"Authorization": f"Bearer {CX_KEY}"}
    payload = {"data": req.data, "dataType": req.data_type, "tlp": req.tlp}

    async with httpx.AsyncClient(verify=False, timeout=90) as c:
        r = await c.post(
            f"{CX_URL}/api/v1/analyzer/{req.analyzer_id}/run",
            headers=headers,
            json=payload,
        )
        if r.status_code not in (200, 201):
            return {"error": f"Cortex {r.status_code}: {r.text[:300]}"}

        job = r.json()
        job_id = job.get("id")
        if not job_id:
            return {"error": "No job ID returned", "raw": job}

        for _ in range(20):
            await asyncio.sleep(3)
            jr = await c.get(f"{CX_URL}/api/v1/job/{job_id}", headers=headers)
            if jr.status_code != 200:
                return {"error": f"Job poll error {jr.status_code}"}
            jdata = jr.json()
            if jdata.get("status") in ("Success", "Failure"):
                return jdata

    return {"error": "Job timed out (60s)", "job_id": job_id}


@app.get("/api/cases")
async def get_cases(status: str = Query("Open")):
    headers = {"Authorization": f"Bearer {TH_KEY}", "Content-Type": "application/json"}
    query = {
        "query": [
            {"_name": "listCase"},
            {"_name": "filter", "_eq": {"_field": "status", "_value": status}},
            {"_name": "sort", "_fields": [{"_createdAt": "desc"}]},
            {"_name": "page", "from": 0, "to": 50},
        ]
    }
    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.post(
            f"{TH_URL}/api/v1/query",
            headers=headers,
            json=query,
            params={"name": "get-cases"},
        )
        if r.status_code not in (200, 201):
            return {"error": f"TheHive {r.status_code}: {r.text[:300]}"}
        data = r.json()
    return {"count": len(data), "cases": data}


@app.post("/api/alerts/create")
async def create_alert(req: AlertCreate):
    headers = {"Authorization": f"Bearer {TH_KEY}", "Content-Type": "application/json"}
    body = {
        "title": req.title,
        "description": req.description,
        "severity": req.severity,
        "type": "External",
        "source": req.source,
        "sourceRef": f"manual-{int(time.time())}",
        "tags": req.tags,
    }
    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.post(f"{TH_URL}/api/v1/alert", headers=headers, json=body)
        if r.status_code not in (200, 201):
            return {"error": f"TheHive {r.status_code}: {r.text[:300]}"}
        return r.json()
