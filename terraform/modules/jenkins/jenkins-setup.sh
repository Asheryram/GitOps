#!/bin/bash
set -e
exec > >(tee /var/log/jenkins-setup.log)
exec 2>&1

echo "Starting Jenkins Docker setup at $(date)"

# ────────────────
# 1. Install Docker on host
# ────────────────
sudo yum update -y
sudo yum install -y docker git unzip curl
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# ────────────────
# 2. Create Docker network
# ────────────────
sudo docker network create jenkins || true

# ────────────────
# 3. Run Docker-in-Docker container
# ────────────────
sudo docker run --name jenkins-docker --rm --detach \
  --privileged --network jenkins --network-alias docker \
  --env DOCKER_TLS_CERTDIR=/certs \
  --volume jenkins-docker-certs:/certs/client \
  --volume jenkins-data:/var/jenkins_home \
  --publish 2376:2376 \
  docker:dind --storage-driver overlay2

# ────────────────
# 4. Build custom Jenkins image with Docker CLI, AWS CLI, SonarScanner
# ────────────────
echo "Building custom Jenkins image with Docker CLI, AWS CLI, SonarScanner..."
sudo docker build -t jenkins-with-docker - <<'EOF'
FROM jenkins/jenkins:2.541.2-jdk21
USER root

# Install basic tools + Docker CLI + jq
RUN apt-get update && \
    apt-get install -y docker.io wget unzip curl jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install SonarScanner
RUN wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip && \
    unzip sonar-scanner-cli-5.0.1.3006-linux.zip -d /opt/ && \
    ln -s /opt/sonar-scanner-5.0.1.3006-linux/bin/sonar-scanner /usr/local/bin/sonar-scanner && \
    chmod -R 755 /opt/sonar-scanner-5.0.1.3006-linux

# Install Jenkins plugins
RUN jenkins-plugin-cli --plugins \
    git \
    workflow-aggregator \
    docker-workflow \
    docker-plugin \
    nodejs \
    credentials-binding \
    pipeline-stage-view \
    blueocean \
    configuration-as-code

USER jenkins
EOF

# ────────────────
# 5. Run Jenkins container with custom image
# ────────────────
echo "Starting Jenkins container..."
sudo docker run --name jenkins --restart=on-failure --detach \
  --network jenkins \
  --env DOCKER_HOST=tcp://docker:2376 \
  --env DOCKER_CERT_PATH=/certs/client \
  --env DOCKER_TLS_VERIFY=1 \
  --publish 8080:8080 \
  --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  jenkins-with-docker

# ────────────────
# 6. Wait for Jenkins to start
# ────────────────
echo "Waiting for Jenkins to start..."
for i in $(seq 1 30); do
  if curl -s http://localhost:8080 > /dev/null; then
    echo "Jenkins is up!"
    break
  fi
  echo "Attempt $i/30 - waiting 10s..."
  sleep 10
done

# ────────────────
# 7. Print initial admin password
# ────────────────
echo "Waiting for initial admin password to be generated..."
sleep 30
echo "==================== JENKINS ADMIN PASSWORD ===================="
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword || echo "Password not yet available - check manually later"
echo "================================================================"

# ────────────────
# 8. Setup summary
# ────────────────
echo "==================== SETUP SUMMARY ===================="
echo "Jenkins running in Docker with Docker CLI, AWS CLI, SonarScanner installed"
echo "Docker version: $(docker --version)"
echo "AWS CLI version: $(aws --version)"
echo "SonarScanner version: $(sonar-scanner --version || echo 'Check inside container')"
echo "======================================================="
echo "Jenkins setup completed at $(date)"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Jenkins accessible at: http://$PUBLIC_IP:8080"
echo ""
echo "Get initial admin password:"
echo "  sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"