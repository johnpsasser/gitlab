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
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/gitlab-bootstrap.log",
            "log_group_name": "/${project_name}/gitlab/bootstrap",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/gitlab/gitlab-rails/production.log",
            "log_group_name": "/${project_name}/gitlab/rails",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/gitlab/nginx/gitlab_access.log",
            "log_group_name": "/${project_name}/gitlab/nginx-access",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/gitlab/nginx/gitlab_error.log",
            "log_group_name": "/${project_name}/gitlab/nginx-error",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
