"""Publish a small, atomic snapshot from the configured blackbox checks."""

import json
import sys
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen


def snapshot(prometheus, names, now):
    def query(endpoint, expression, **params):
        args = urlencode({"query": expression, **params})
        with urlopen(f"{prometheus}/api/v1/{endpoint}?{args}", timeout=10) as resp:
            result = json.load(resp)
        if result["status"] != "success":
            raise ValueError("Prometheus query failed")
        return {s["metric"]["service"]: s["values"] for s in result["data"]["result"]}

    probe = 'probe_success{job=~"blackbox-.+",service!=""}'
    # Range vectors retain the actual scrape timestamp, including across gaps.
    current = query("query", probe + "[2m]", time=now)
    end = now // 60 * 60
    hours = [end - i * 3600 for i in reversed(range(24))]

    def hourly(function):
        result = query("query_range", f"{function}({probe}[1h])",
                       start=hours[0], end=end, step=3600)
        return {name: {int(t): int(float(v)) for t, v in values}
                for name, values in result.items()}

    passed, checked = hourly("sum_over_time"), hourly("count_over_time")
    services = []
    for name in names:
        t, value = current.get(name, [(None, None)])[-1]
        services.append({
            "name": name, "lastCheck": t, "up": {"0": False, "1": True}.get(value),
            # Bucket = [successful checks, observed checks]. No samples ≠ downtime.
            "hours": [[passed.get(name, {}).get(h, 0), checked.get(name, {}).get(h, 0)]
                      for h in hours],
        })
    return {"asOf": now, "historyEnd": end, "services": services}


if __name__ == "__main__":
    url, output, *names = sys.argv[1:]
    data = snapshot(url, names, int(time.time()))
    path = Path(output)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    tmp.replace(path)
