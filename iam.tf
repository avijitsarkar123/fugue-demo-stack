resource "aws_iam_role" "demo-app-role" {
  name = "demo-app-ecs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "ecs.amazonaws.com",
          "ecs-tasks.amazonaws.com",
          "ec2.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name         = "demo-app-ecs-role"
    Application  = "demo-app"
    OwnerContact = "Avijit Sarkar"
  }
}

resource "aws_iam_instance_profile" "demo-app-ec2-profile" {
  name = "demo-app-instance-profile"
  role = "${aws_iam_role.demo-app-role.name}"
}

resource "aws_iam_role_policy" "demo-app-ecs-policy" {
  name = "demo-app-ecs-policy"
  role = "${aws_iam_role.demo-app-role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*",
        "ecs:*",
        "cloudwatch:*",
        "logs:*",
        "sns:*",
        "elasticloadbalancing:*",
        "autoscaling:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
