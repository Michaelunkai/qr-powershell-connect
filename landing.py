"""A static enrollment guide: the capability stays in the browser's URL fragment."""
import hashlib
import base64
import http.server
import json
import time

HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connect to Windows PowerShell</title>
<style>
:root{font-family:system-ui,sans-serif;color:#152332;background:#edf3f7;color-scheme:light}
body{margin:0;padding:28px 18px}main{max-width:560px;margin:auto;background:white;border-radius:20px;padding:28px;box-shadow:0 10px 40px #13263812}
.label{color:#43677b;font-size:13px;font-weight:700;letter-spacing:.1em}h1{font-size:30px;line-height:1.15;margin:14px 0}p,li{line-height:1.65}
ol{padding-left:22px}li{padding-left:6px;margin:12px 0}button{width:100%;font:inherit;font-weight:700;border:0;border-radius:12px;padding:17px;background:#075b75;color:white;cursor:pointer}button:disabled{opacity:.5;cursor:not-allowed}
textarea{box-sizing:border-box;width:100%;font:12px ui-monospace,monospace;border:1px solid #bacbd5;border-radius:8px;padding:12px;resize:vertical;word-break:break-all}code{background:#edf3f7;padding:3px 7px;border-radius:5px}#status{font-weight:600}#expiry{color:#526574;font-size:14px}.muted{color:#526574;font-size:14px}
</style></head><body><main>
<div class="label">QR POWERSHELL CONNECT</div><h1>Connect your phone<br>to Windows.</h1>
<p>Your QR opened correctly. Keep Tailscale connected and the pairing window open on your PC.</p>
<ol><li>Tap <strong>Copy pairing command</strong> below.</li><li>Open <strong>Termux</strong>, long-press the terminal, choose <strong>Paste</strong>, then press <strong>Enter</strong>.</li><li>Wait for <code>QRBRIDGE_ANDROID_OK</code>, then type <code>windows</code> to open PowerShell.</li></ol>
<button id="copy" disabled>Copy pairing command</button><p id="status" role="status" aria-live="polite">Checking this QR…</p>
<p id="expiry"></p><details><summary>Show command / copy manually</summary><p><textarea id="command" aria-label="Pairing command" readonly rows="5"></textarea></p></details>
<p class="muted">Your existing Termux setup works with this page. No reinstall is needed. Keep the QR and command private: they authorize access to your PC.</p>
<noscript>Enable JavaScript to prepare the pairing command, then reload this page.</noscript>
</main><script>
'use strict';
const copy=document.getElementById('copy'), output=document.getElementById('command'), status=document.getElementById('status'), expiry=document.getElementById('expiry');
let deadline=0;
function expire(){copy.disabled=true;output.value='';status.textContent='This QR has expired. Run Start-Pairing.ps1 on your PC and scan the new QR.';expiry.textContent='';}
try{
  const fragment=location.hash.slice(1);
  if(!/^[A-Za-z0-9_-]{40,4000}$/.test(fragment))throw Error('missing link');
  const padded=fragment.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-fragment.length%4)%4);
  const data=JSON.parse(atob(padded));
  const octets=String(data.host).split('.').map(Number);
  if(data.v!==1 || data.host!==location.hostname || octets.length!==4 || octets[0]!==100 || octets[1]<64 || octets[1]>127 || octets.some(x=>!Number.isInteger(x)||x<0||x>255) || !Number.isInteger(data.port) || data.port<1024 || data.port>65535 || !/^[a-f0-9]{64}$/.test(data.pin) || !/^[A-Za-z0-9_-]{43}$/.test(data.token) || !Number.isInteger(data.expires))throw Error('invalid link');
  deadline=data.expires*1000;
  if(deadline<=Date.now()){expire();}else{
    output.value='python "$HOME/.local/lib/qrbridge/client.py" '+"'https://qrbridge.invalid/enroll#"+fragment+"'";
    copy.disabled=false;status.textContent='Ready to pair. Copy the command, then paste it into Termux.';
    const tick=()=>{const remaining=Math.ceil((deadline-Date.now())/1000);if(remaining<=0){expire();return;}expiry.textContent='QR expires in '+Math.floor(remaining/60)+'m '+remaining%60+'s.';};tick();setInterval(tick,1000);
  }
}catch(error){status.textContent='This link is missing valid pairing details. Scan the full QR from Start-Pairing.ps1 again.';}
copy.addEventListener('click',async()=>{
  if(Date.now()>=deadline){expire();return;}
  try{
    if(navigator.clipboard && window.isSecureContext){await navigator.clipboard.writeText(output.value);}else{
      const temporary=document.createElement('textarea');temporary.value=output.value;temporary.style.position='fixed';temporary.style.top='0';temporary.style.left='0';temporary.style.opacity='0';document.body.appendChild(temporary);temporary.focus();temporary.select();temporary.setSelectionRange(0,temporary.value.length);let copied=false;try{copied=document.execCommand('copy');}finally{temporary.remove();}if(!copied)throw Error('manual copy required');
    }
    status.textContent='Copied. Open Termux, paste the command, and press Enter.';
  }catch(error){document.querySelector('details').open=true;output.focus();output.select();output.setSelectionRange(0,output.value.length);status.textContent='Long-press the selected command and choose Copy, then paste it in Termux.';}
});
</script></body></html>'''

SCRIPT = HTML.split('<script>', 1)[1].split('</script>', 1)[0]
SCRIPT_HASH = base64.b64encode(hashlib.sha256(SCRIPT.encode()).digest()).decode()


def make_landing_handler(expires):
    class Handler(http.server.BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *args):
            return

        def do_GET(self):
            if self.path not in ('/', '/enroll', '/health'):
                self.send_error(404)
                return
            if self.path == '/health':
                content = json.dumps({'ready': time.time() < expires, 'version': 2}).encode()
                kind = 'application/json'
            else:
                content, kind = HTML.encode(), 'text/html; charset=utf-8'
            self.send_response(200)
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(content)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('Content-Security-Policy', f"default-src 'none'; script-src 'sha256-{SCRIPT_HASH}'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
            self.end_headers()
            self.wfile.write(content)

        def do_POST(self):
            self.send_error(405, 'Enrollment requires the pinned TLS client')
    return Handler
