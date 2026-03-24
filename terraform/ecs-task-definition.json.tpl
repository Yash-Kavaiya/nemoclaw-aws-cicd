[
  {
    "name": "${name}",
    "image": "${image}",
    "essential": true,
    "portMappings": [
      {
        "containerPort": ${container_port},
        "protocol": "tcp"
      }
    ],
    "environment": [
      {
        "name": "NEMOCLAW_ENV",
        "value": "${environment}"
      },
      {
        "name": "PORT",
        "value": "${container_port}"
      },
      {
        "name": "NEMOCLAW_NON_INTERACTIVE",
        "value": "1"
      }
    ],
    "secrets": [
      {
        "name": "NVIDIA_API_KEY",
        "valueFrom": "${nvidia_secret_arn}"
      }
    ],
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "curl -f http://localhost:${container_port}/health || exit 1"
      ],
      "interval": 30,
      "timeout": 10,
      "retries": 3,
      "startPeriod": 60
    },
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group}",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "cpu": ${cpu},
    "memory": ${memory},
    "linuxParameters": {
      "capabilities": {
        "add": [],
        "drop": ["ALL"]
      },
      "readonlyRootFilesystem": false
    }
  }
]
