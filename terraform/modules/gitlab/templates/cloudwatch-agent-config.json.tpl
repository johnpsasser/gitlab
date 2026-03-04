{
  "metrics": {
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/var/opt/gitlab"],
        "metrics_collection_interval": 300
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 300
      },
      "procstat": [
        {
          "pattern": "puma",
          "measurement": ["cpu_usage", "memory_rss", "pid_count"],
          "metrics_collection_interval": 300
        },
        {
          "pattern": "gitaly",
          "measurement": ["cpu_usage", "memory_rss", "pid_count"],
          "metrics_collection_interval": 300
        },
        {
          "pattern": "postgresql",
          "measurement": ["cpu_usage", "memory_rss"],
          "metrics_collection_interval": 300
        }
      ]
    }
  }
}