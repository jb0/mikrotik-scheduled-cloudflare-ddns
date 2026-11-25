# CF-DDNS - Cloudflare Scheduled Dynamic DNS Updater for Mikrotik RouterOS  
# (Requires RouterOS v7.10+)
# (IPV4 only)

# --- CONFIGURATION ---------------------
:local cfToken "YOUR_SCOPED_CLOUDFLARE_API_TOKEN"
:local zoneId  "YOUR_CLOUDFLARE_ZONE_ID"

# Array of FQDNs (A records) to update
:local records {
    "host1.example.com";
    "host2.example.com";
    "host3.example.com"
}

# --- END CONFIG --------------------------


# --- Get current public IPv4 ---
:local currentIp ""
:do {
    :local res [/tool fetch url="https://api.ipify.org" mode=https output=user as-value]
    :set currentIp ($res->"data")
} on-error={
    :log error "CF-DDNS: Failed to fetch public IP from ipify.org"
    :error "Fetch failed"
}

# Strip trailing CR/LF if present
:local crPos [:find $currentIp "\r"]
:if ([:typeof $crPos] = "num") do={ :set currentIp [:pick $currentIp 0 $crPos] }
:local lfPos [:find $currentIp "\n"]
:if ([:typeof $lfPos] = "num") do={ :set currentIp [:pick $currentIp 0 $lfPos] }

# Validate IPv4
:local validIp [:toip $currentIp]
:if ([:typeof $validIp] != "ip") do={
    :log warning ("CF-DDNS: Invalid IP response: " . $currentIp)
    :error "Invalid IP"
}


# --- Update all records only when IP changes ---
:global cfLastIp
:if ($currentIp != $cfLastIp) do={
    :local prevIp $cfLastIp
    :if ([:len $prevIp] = 0) do={ :set prevIp "none" }
    :log info ("CF-DDNS: IP changed (" . $prevIp . " -> " . $currentIp . "), updating " . [:len $records] . " records(s)")

    :local successCount 0
    :local failCount 0
    :local headers ("Authorization: Bearer " . $cfToken . ",Content-Type: application/json")

    :foreach recName in=$records do={
        :local lookupUrl ("https://api.cloudflare.com/client/v4/zones/" . $zoneId . "/dns_records?type=A&name=" . $recName)
        :local rawJson ""
        :local lookupOk false

        :do {
            :local getRes [/tool fetch url=$lookupUrl mode=https http-method=get http-header-field=$headers output=user as-value]
            :set rawJson ($getRes->"data")
            :set lookupOk true
        } on-error={
            :log error ("CF-DDNS: Lookup failed for " . $recName)
            :set failCount ($failCount + 1)
        }

        :if ($lookupOk) do={
            :local parsed ""
            :local resultList ""
            :do {
                :set parsed [:deserialize from=json value=$rawJson]
                :set resultList ($parsed->"result")
            } on-error={
                :log warning ("CF-DDNS: Could not parse Cloudflare response for " . $recName)
                :set failCount ($failCount + 1)
                :set resultList ""
            }

            :if ([:typeof $resultList] = "array") do={
                :if ([:len $resultList] > 0) do={
                    :local recObj   ($resultList->0)
                    :local recId    ($recObj->"id")
                    :local recTtl   ($recObj->"ttl")
                    :local recProx  ($recObj->"proxied")
                    :local proxStr  "false"
                    :if ($recProx = true) do={ :set proxStr "true" }

                    :local patchUrl ("https://api.cloudflare.com/client/v4/zones/" . $zoneId . "/dns_records/" . $recId)
                    :local payload  ("{\"type\":\"A\",\"name\":\"" . $recName . "\",\"content\":\"" . $currentIp . "\",\"ttl\":" . $recTtl . ",\"proxied\":" . $proxStr . "}")

                    :do {
                        /tool fetch url=$patchUrl mode=https http-method=patch http-header-field=$headers http-data=$payload output=none
                        :log info ("CF-DDNS: Updated " . $recName . " -> " . $currentIp . " (proxied=" . $proxStr . ", ttl=" . $recTtl . ")")
                        :set successCount ($successCount + 1)
                    } on-error={
                        :log error ("CF-DDNS: Failed updating " . $recName)
                        :set failCount ($failCount + 1)
                    }
                } else={
                    :log warning ("CF-DDNS: No A record found for " . $recName . ", skipping (not created)")
                }
            }
        }
    }

    :if ($successCount > 0) do={
        :set cfLastIp $currentIp
        :if ($failCount > 0) do={
            :log warning ("CF-DDNS: " . $failCount . " record(s) failed to update; cfLastIp still updated to " . $currentIp)
        }
    } else={
        :log error "CF-DDNS: All records failed to update; leaving cfLastIp unchanged to retry next run"
    }
} else={
    :log debug ("CF-DDNS: IP unchanged (" . $currentIp . "), skipping updates")
}