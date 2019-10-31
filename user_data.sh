#!/bin/bash

# ECS config
cat > /etc/ecs/ecs.config <<- EOF
ECS_CLUSTER=${cluster_name}
ECS_AVAILABLE_LOGGING_DRIVERS=${ecs_logging}
EOF

start ecs

echo "Done"
