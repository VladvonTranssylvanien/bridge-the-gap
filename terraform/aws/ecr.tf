resource "aws_ecr_repository" "service_a" {
  name                 = "bridge-the-gap/service-a"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.service_a.repository_url
}
