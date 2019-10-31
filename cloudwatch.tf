resource "aws_cloudwatch_log_group" "demo-app-ecs-log-group" {
  name = "/ecs/demo-app"

  tags = {
    Name         = "demo-app-ecs-log-group"
    Application  = "demo-app"
    OwnerContact = "Avijit Sarkar"
  }
}

resource "aws_cloudwatch_log_stream" "demo-app-ecs-log-stream" {
  name           = "demo-app-ecs-log-stream"
  log_group_name = "${aws_cloudwatch_log_group.demo-app-ecs-log-group.name}"
}
