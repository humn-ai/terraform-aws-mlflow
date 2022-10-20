# cognito auth alb listener rules
resource "aws_lb_listener_rule" "https" {
  listener_arn = aws_lb_listener.https.arn

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  action {
    type = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = var.aws_cognito_user_pool_arn
      user_pool_client_id = var.aws_cognito_user_pool_client_id
      user_pool_domain    = var.aws_cognito_user_pool_domain
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mlflow.arn
  }
}

# api access via api-gateway rules
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  condition {
    host_header {
      values = [aws_route53_record.api.name]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mlflow.arn
  }

}


resource "aws_lb_listener_rule" "http" {
  listener_arn = aws_lb_listener.http.arn

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  condition {
    host_header {
      values = [aws_route53_record.record.name]
    }
  }

  action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }

}

# api endpoint configuration
resource "aws_apigatewayv2_api" "mlflow" {
  name          = "MLflow"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "mlflow" {
  api_id = aws_apigatewayv2_api.mlflow.id
  name   = "$default"
}

resource "aws_apigatewayv2_api_mapping" "mlflow" {
  api_id      = aws_apigatewayv2_api.mlflow.id
  domain_name = aws_apigatewayv2_domain_name.mlflow.id
  stage       = aws_apigatewayv2_stage.mlflow.id
}

resource "aws_apigatewayv2_domain_name" "mlflow" {
  domain_name = join(".", [var.record_name, var.api_zone_name])

  domain_name_configuration {
    certificate_arn = var.api_cert_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_route53_record" "api" {
  name    = aws_apigatewayv2_domain_name.mlflow.domain_name
  type    = "A"
  zone_id = var.api_zone_id

  alias {
    name                   = aws_apigatewayv2_domain_name.mlflow.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.mlflow.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }

}