data "aws_vpc" "vpc" {
  id = "vpc-0b87e8f4572a9d420"
}

data "aws_subnet" "_" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    "private" = "proxied"
  }
}

data "aws_security_group" "_" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.vpc.id]
 }
}

# Instance Profile for the EC2
data "aws_iam_instance_profile" "_" {
  name = "EC2InstanceProfileForImageBuilder"
}

data "aws_iam_policy_document" "image_builder" {

}
