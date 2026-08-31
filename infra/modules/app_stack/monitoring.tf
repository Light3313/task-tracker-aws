# Email subscriptions need a manual click -> an unconfirmed one accepts publishes and drops them
# Not encrypted — the key policy on alias/aws/sns can't be edited, so CloudWatch could not
# publish through it
#trivy:ignore:AVD-AWS-0095 payload is a metric name and a state string
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"

  tags = merge(local.tags, { Name = "${local.name}-alerts" })
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Golden signal — availability
# breaching alone never fires here — CloudWatch backfills the evaluation range from before
# the gap and then ignores treat_missing_data. FILL is what turns an empty pool into a real 0.
# breaching is left for the target group disappearing altogether
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name        = "${local.name}-alb-no-healthy-targets"
  alarm_description = "No healthy targets behind the ALB — the app is unreachable"

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "breaching"

  metric_query {
    id          = "e1"
    expression  = "FILL(m1, 0)"
    label       = "healthy targets, gaps as 0"
    return_data = true
  }

  metric_query {
    id = "m1"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HealthyHostCount"
      period      = 60
      stat        = "Minimum"

      dimensions = {
        TargetGroup  = aws_lb_target_group.app_ecs.arn_suffix
        LoadBalancer = aws_lb.app.arn_suffix
      }
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, { Name = "${local.name}-alb-no-healthy-targets" })
}

# Golden signal — errors, infrastructure side
# ELB_5XX means no target could answer -> not the same incident as a target returning 500
# No datapoints at all in steady state, hence notBreaching
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name        = "${local.name}-alb-5xx"
  alarm_description = "ALB generated 5xx itself — no target was able to answer"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic   = "Sum"
  period      = 60

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, { Name = "${local.name}-alb-5xx" })
}

# Golden signal — errors, application side
# A rate, not a count -> five errors mean different things at 10 rps and at 10k rps
# IF() gates on volume: at low traffic the counters land in neighbouring buckets, ratio past 100 %
resource "aws_cloudwatch_metric_alarm" "app_5xx_rate" {
  alarm_name        = "${local.name}-app-5xx-rate"
  alarm_description = "Targets returned 5xx for more than 5 % of requests over 5 minutes"

  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "IF(m2 >= 20, 100 * FILL(m1,0) / m2, 0)"
    label       = "5xx rate %"
    return_data = true
  }

  metric_query {
    id = "m1"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = aws_lb.app.arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = aws_lb.app.arn_suffix
      }
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, { Name = "${local.name}-app-5xx-rate" })
}

# Golden signal — latency
# p99, not Average -> Average hides the tail
# Threshold off the baseline: p99 runs 0.006-0.014 s with a 0.65 s cold-path spike
resource "aws_cloudwatch_metric_alarm" "app_latency_p99" {
  alarm_name        = "${local.name}-app-latency-p99"
  alarm_description = "p99 target response time above 1 s for 10 minutes"

  namespace          = "AWS/ApplicationELB"
  metric_name        = "TargetResponseTime"
  extended_statistic = "p99"
  period             = 300

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, { Name = "${local.name}-app-latency-p99" })
}

# Golden signal — saturation
# CPU already drives target tracking at 70 %, so this watches memory, which nothing scales on
# Baseline is a flat 21 % of 512 MB. Missing data belongs to no_healthy_targets, not here
resource "aws_cloudwatch_metric_alarm" "app_memory" {
  alarm_name        = "${local.name}-app-memory"
  alarm_description = "ECS service memory above 80 % for 10 minutes"

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"
  period      = 300

  dimensions = {
    ClusterName = aws_ecs_cluster.tt_ecs.name
    ServiceName = aws_ecs_service.app.name
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "missing"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, { Name = "${local.name}-app-memory" })
}

# Dashboard — the four signals on one screen
# Statistic is per widget: a counter read with Minimum flattens to 0/1
resource "aws_cloudwatch_dashboard" "golden_signals" {
  dashboard_name = "${local.name}-golden-signals"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Traffic — requests/min"
          region  = data.aws_region.current.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Latency — target response time"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "p50", label = "p50" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
          yAxis = { left = { label = "seconds", showUnits = false } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Errors — ELB-generated vs target-returned"
          region = data.aws_region.current.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "ELB 5xx — no target answered" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "Target 5xx — app answered 500" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Saturation — CPU, memory, healthy targets"
          region = data.aws_region.current.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.tt_ecs.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "CPU %" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.tt_ecs.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "Memory %" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app_ecs.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Minimum", label = "Healthy targets", yAxis = "right" }],
          ]
          yAxis = {
            left  = { label = "percent", min = 0, max = 100, showUnits = false }
            right = { label = "targets", min = 0, showUnits = false }
          }
        }
      },
    ]
  })
}
