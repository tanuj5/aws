provider "aws"  {
    region = "ap-south-1"
    profile = "tanujm"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits = "4096"
}

resource "aws_key_pair" "task1_key" {
  key_name   = "task-key"
  public_key = tls_private_key.private_key.public_key_openssh
} 

resource "local_file" "private_key" {
    content         =  tls_private_key.private_key.private_key_pem
    filename        =  "C:/Users/Tanuj/Desktop/hybrid cloud/task1/final/task-key.pem"
    file_permission =  0400
}


resource "aws_security_group" "allow_http" {
  name        = "web_sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_instance" "os1" {
  ami           =  "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "task-key"
  security_groups = [ aws_security_group.allow_http.name ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host     = aws_instance.os1.public_ip
    
   }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "task_os"
  }
  depends_on = [
      local_file.private_key,
  ]
}


resource "aws_ebs_volume" "ebs1" {
  availability_zone = aws_instance.os1.availability_zone
  size              = 1
  tags = {
    Name = "task_ebs"
  }
}


resource "aws_volume_attachment" "ebs_attach" {
  device_name = "/dev/sdt"
  volume_id   = "${aws_ebs_volume.ebs1.id}"
  instance_id = "${aws_instance.os1.id}"
  force_detach = true
}


/* output "myos_ip" {
  value = aws_instance.os1.public_ip
} */


resource "null_resource" "local1"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.os1.public_ip} > publicip.txt"
  	}
}

resource "null_resource" "remote1"  {

depends_on = [
    aws_volume_attachment.ebs_attach,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host     = aws_instance.os1.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdt",
      "sudo mount  /dev/xvdt  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/tanuj5/aws.git /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "taskbucket" {
  bucket = "task-bucket-tanujmathur"
  acl    = "public-read"

  tags = {
    Name = "task1-bucket-tanujmathur"
  }
}

resource "aws_s3_bucket_object" "taskobject" {
  depends_on = [ aws_s3_bucket.taskbucket, ]
  bucket = "task-bucket-tanujmathur"
  key    = "welcome.jpg"
  source = "C:/Users/Tanuj/Desktop/hybrid cloud/task1/mytask/welcome.jpg"
  acl    = "public-read"
}

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_origin_access_identity" "taskoai" {
  comment = "OAI"
}

resource "aws_cloudfront_distribution" "task1_cloudfront_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.taskbucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.taskoai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "First task with Terraform"
  default_root_object = "index.php"


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host     = aws_instance.os1.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo su <<EOF",
      "sudo sed  '4i <img src='http://${aws_cloudfront_distribution.task1_cloudfront_distribution.domain_name}/${aws_s3_bucket_object.taskobject.key}' width='800' height='600' />' /var/www/html/index.php",
      "EOF"
    ]
  }
}

output "cloudfront" {
	value = aws_cloudfront_distribution.task1_cloudfront_distribution.domain_name
}

resource "null_resource" "local2"  {

depends_on = [
    null_resource.remote1,
    aws_cloudfront_distribution.task1_cloudfront_distribution,
  ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.os1.public_ip}"
  	}
}




