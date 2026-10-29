/**
 * Serves the YouTube IFrame player wrapper from a real https origin (this project's domain).
 *
 * Loading the wrapper with WKWebView.loadHTMLString used a synthetic `https://<bundle id>`
 * origin, and YouTube's embed rules now reject identities it cannot verify (errors 150/152/153).
 * A page served from a real domain, navigated to normally, sends a verifiable referrer — the
 * same fix web embedders use. The video itself is never re-hosted; the player runs on YouTube.
 *
 * Public on purpose (no JWT): the WKWebView loads it as a plain page.
 *   GET /functions/v1/youtube-embed?v=<videoId>[&h=nocookie]
 */

const VIDEO_ID = /^[A-Za-z0-9_-]{6,25}$/;
const HOSTS: Record<string, string> = {
  "": "https://www.youtube.com",
  nocookie: "https://www.youtube-nocookie.com",
};

function playerHtml(videoId: string, host: string, origin: string): string {
  return `<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
</head><body><div id="p"></div>
<script src="${host}/iframe_api"></script>
<script>
var player;
function post(m){window.webkit.messageHandlers.yt.postMessage(m);}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{
    host:'${host}',
    videoId:'${videoId}',
    playerVars:{
      playsinline:1,controls:0,rel:0,modestbranding:1,fs:0,
      iv_load_policy:3,cc_load_policy:0,enablejsapi:1,autoplay:1,mute:1,
      origin:'${origin}',widget_referrer:'${origin}'
    },
    events:{
      onReady:function(){post({e:'ready'});},
      onStateChange:function(ev){post({e:'state',v:ev.data});},
      onError:function(ev){post({e:'error',v:ev.data});}
    }
  });
}
function nTime(){ if(player&&player.getCurrentTime){post({e:'time',v:player.getCurrentTime()});} }
</script></body></html>`;
}

Deno.serve((req) => {
  const url = new URL(req.url);
  const videoId = url.searchParams.get("v") ?? "";
  if (!VIDEO_ID.test(videoId)) {
    return new Response("Bad video id", { status: 400, headers: { "Access-Control-Allow-Origin": "*" } });
  }
  const host = HOSTS[url.searchParams.get("h") ?? ""] ?? HOSTS[""];
  return new Response(playerHtml(videoId, host, url.origin), {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
      "Access-Control-Allow-Origin": "*",
    },
  });
});
