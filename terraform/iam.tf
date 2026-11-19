data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  for_each           = local.nodes
  name_prefix        = "${var.project_name}-${each.key}-"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = local.nodes
  role       = aws_iam_role.node[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "gateway_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.snort.arn}:*"]
  }
}

resource "aws_iam_role_policy" "gateway_logs" {
  name   = "snort-alerts-only"
  role   = aws_iam_role.node["gateway"].id
  policy = data.aws_iam_policy_document.gateway_logs.json
}

resource "aws_iam_instance_profile" "node" {
  for_each    = local.nodes
  name_prefix = "${var.project_name}-${each.key}-"
  role        = aws_iam_role.node[each.key].name
}
