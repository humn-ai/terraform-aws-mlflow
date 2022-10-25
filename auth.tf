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
  priority     = 2
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
  priority     = 3
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

resource "aws_security_group_rule" "lb_egress_idp" {
  description       = "Open outbound for all"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lb.id
}


# api endpoint configuration
resource "aws_apigatewayv2_api" "mlflow" {
  name          = "MLflow"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_api_mapping" "mlflow" {
  api_id      = aws_apigatewayv2_api.mlflow.id
  domain_name = aws_apigatewayv2_domain_name.mlflow.id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_apigatewayv2_domain_name" "mlflow" {
  domain_name = join(".", [var.record_name, var.api_zone_name])

  domain_name_configuration {
    certificate_arn = var.api_cert_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.mlflow.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.mlflow.id
  route_key          = "$default"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda.id
  target             = "integrations/${aws_apigatewayv2_integration.mlflow.id}"
}

resource "aws_apigatewayv2_authorizer" "lambda" {
  name                              = "MLflow-lambda-auth"
  api_id                            = aws_apigatewayv2_api.mlflow.id
  authorizer_type                   = "REQUEST"
  authorizer_payload_format_version = "1.0"
  authorizer_uri                    = aws_lambda_function.mlflow.invoke_arn
  identity_sources                  = ["$request.header.Authorization"]
}

resource "aws_apigatewayv2_integration" "mlflow" {
  api_id           = aws_apigatewayv2_api.mlflow.id
  integration_type = "HTTP_PROXY"

  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.mlflow.id
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.http.arn
}

resource "aws_apigatewayv2_vpc_link" "mlflow" {
  name               = "MLflow-vpc-link"
  security_group_ids = [aws_security_group.lb.id]
  subnet_ids         = var.database_subnet_ids

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

#Lambda function for auth via api-gateway
resource "aws_lambda_function" "mlflow" {
  filename      = "${path.module}/src/MLflow-custom-authorizer.zip"
  function_name = "MLflow-custom-authorizer"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
}

resource "aws_iam_role" "lambda" {
  name = "mlflow-custom-authorizer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

