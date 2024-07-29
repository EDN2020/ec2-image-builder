
variable "script_names" {
  type = list(string)
  default = [
    "disable_ipv6",
    "install_docker",
  ]
}

locals {
  script_paths = {
    for name in var.script_names : name => "${path.module}/scripts/${name}.yaml"
  }
}

data "local_file" "scripts" {
  for_each = local.script_paths
  filename = each.value
}

resource "aws_imagebuilder_component" "components" {
  for_each = data.local_file.scripts
  name       = each.key
  platform   = "Linux"
  version    = "1.0.0"
  data       = each.value.content
}

resource "aws_imagebuilder_image_recipe" "_" {
  block_device_mapping {
    device_name = "/dev/xvdb"

    ebs {
      delete_on_termination = true
      volume_size           = var.ebs_root_vol_size
      volume_type           = "gp3"
    }
  }

  dynamic "component" {
    for_each = aws_imagebuilder_component.components
    content {
      component_arn = component.value.arn
    }
  }
  name         = "amazon-linux-recipe"
  parent_image = var.parent_image
  version      = var.image_receipe_version

  depends_on = [
    aws_imagebuilder_component.cw_agent
  ]
}

######################################################
#Pipeline configuration
######################################################

resource "aws_imagebuilder_image_pipeline" "_" {
  name                             = var.ami_stem
  status                           = "ENABLED"
  description                      = "Creates an AMI."
  image_recipe_arn                 = aws_imagebuilder_image_recipe._.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration._.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration._.arn

  schedule {
    schedule_expression = "cron(0 0 * * ? *)"
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }

  # Test the image after build
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 60
  }

  tags = {
    "Name" = "${var.ami_stem}-pipeline"
  }

  depends_on = [
    aws_imagebuilder_image_recipe._,
    aws_imagebuilder_infrastructure_configuration._
  ]
}

######################################
# recipe configuration
######################################

data "aws_iam_policy_document" "_" {
  statement {

    actions = [
      "*"
    ]

    resources = [
      "*",
    ]
  }
}

resource "aws_iam_policy" "_" {
  name   = "example_policy"
  path   = "/"
  policy = data.aws_iam_policy_document._.json
}
resource "aws_imagebuilder_image" "_" {
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration._.arn
  image_recipe_arn                 = aws_imagebuilder_image_recipe._.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration._.arn

  depends_on = [
    data.aws_iam_policy_document._,
    aws_imagebuilder_image_recipe._,
    aws_imagebuilder_distribution_configuration._,
    aws_imagebuilder_infrastructure_configuration._
  ]
}

#####################################################
# infrastructure configuration
#####################################################
resource "aws_imagebuilder_infrastructure_configuration" "_" {
  description                   = "imagebuilder infrastructure configuration"
  instance_profile_name         = var.ec2_iam_role_name
  instance_types                = var.instance_types
  #key_pair                      = var.aws_key_pair_name
  name                          = "amazon-linux"
  security_group_ids            = [data.aws_security_group._.id]
  subnet_id                     = data.aws_subnet._.id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket._.id
      s3_key_prefix  = "image-builder"
    }
  }

  tags = {
    Name = "amazon-linux-infr"
  }
}

##################################################
#distribution configuration
#################################################
resource "aws_imagebuilder_distribution_configuration" "_" {
  name = "local-distribution"

  distribution {
    ami_distribution_configuration {

      ami_tags = {
          Name                  = var.ami_stem
          application-group     = "infrastructure"
          application           = "ami-builder"
          application-component = "artifact"
          environment           = "sandbox"
          # source                = var.source_repo
          # version               = local.version
          # in-production         = var.in_production
          # pipeline              = var.pipeline
          purpose               = "general"
          intended-subnet       = "nat"
      }

      name = "${var.ami_stem}-{{ imagebuilder:buildDate }}"

      # launch_permission {
      #   # user_ids = ["123456789012"]
      # }
    }
    region = var.aws_region
  }
}

############################################################
# Component configuration
# We're using CloudWatch agent as an example
############################################################
resource "aws_s3_bucket" "_"{
  bucket = "image-builder"
  force_destroy = true
}

resource "aws_s3_object" "_" {
  for_each = fileset("/files/", "*")

  bucket = aws_s3_bucket._.id
  key    = "/files/${each.value}"
  source = "/files/${each.value}"
  # If the md5 hash is different it will re-upload
  etag = filemd5("/files/${each.value}")
}

data "aws_kms_key" "image_builder" {
  key_id = "fbb6a3ad-XXXXXXXXX"
}

# # Amazon Cloudwatch agent component
resource "aws_imagebuilder_component" "cw_agent" {
  data = yamlencode({
    phases = [{
      name = "build"
      steps = [{
        action = "ExecuteBash"
        inputs = {
          commands = ["echo 'hello world'"]
        }
        name      = "example"
        onFailure = "Continue"
      }]
    }]
    schemaVersion = 1.0
  })
  name     = "example"
  platform = "Linux"
  version  = "1.0.0"
  lifecycle {
    create_before_destroy = true
  }
}