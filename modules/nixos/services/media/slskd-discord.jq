# Turns a slskd event (the JSON slskd puts in $SLSKD_SCRIPT_DATA) into a
# Discord webhook payload. Names and messages come from the Soulseek network,
# so they only ever pass through here as data.

def clip($n): if length > $n then .[0:$n - 1] + "…" else . end;
# Soulseek paths use backslashes; local ones forward slashes.
def leaf: split("\\") | map(split("/")) | flatten | map(select(. != "")) | last // .;

env.SLSKD_SCRIPT_DATA | fromjson
| (if .type == "DownloadDirectoryComplete" then
     {
       title: ("Downloaded " + (.remoteDirectoryName | leaf) | clip(256)),
       color: 3066993,
       fields: [
         { name: "From", value: (.username // "unknown" | clip(1024)), inline: true },
         { name: "Folder", value: (.localDirectoryName | leaf | clip(1024)), inline: true }
       ]
     }
   elif .type == "PrivateMessageReceived" then
     {
       title: ("Message from " + (.message.username // "unknown") | clip(256)),
       description: (.message.message // "" | clip(4000)),
       color: 3447003
     }
   else
     { title: (.type // "event" | tostring), color: 9807270 }
   end) as $embed
| {
    username: "slskd",
    allowed_mentions: { parse: [] },
    embeds: [ $embed + { timestamp: .timestamp } ]
  }
