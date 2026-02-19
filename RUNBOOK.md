# CI/CD Pipeline with Jenkins — Runbook

> **Stack:** Node.js app · Jenkins in Docker on EC2 · Docker Hub · SSH deploy
>
> ⚠️ **IP addresses change on every EC2 restart.** Check `infrastructure-outputs.txt` (or run `terraform output`) for the current IPs before each session. Replace `<JENKINS_IP>` and `<APP_IP>` throughout this guide with those values.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Structure](#2-repository-structure)
3. [Jenkins Server — First-Time Setup](#3-jenkins-server--first-time-setup)
4. [Configure the App Server](#4-configure-the-app-server)
5. [Get the Initial Admin Password](#5-get-the-initial-admin-password)
6. [Install Jenkins Plugins](#6-install-jenkins-plugins)
7. [Add Jenkins Credentials](#7-add-jenkins-credentials)
8. [Create the Pipeline Job](#8-create-the-pipeline-job)
9. [Run the Pipeline](#9-run-the-pipeline)
10. [Verify Deployment](#10-verify-deployment)
11. [Updating the App Server IP](#11-updating-the-app-server-ip)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Architecture Overview

```
Developer → GitHub → Jenkins container (EC2 <JENKINS_IP>:8080)
                              │
                        Pipeline Stages:
                        1. Checkout
                        2. Install (npm ci)
                        3. Test (npm test)
                        4. Docker Build & Tag
                        5. Push to Docker Hub
                        6. SSH Deploy → App Server (EC2 <APP_IP>)
                                              │
                                         Node App :5000
```

Get your current IPs before starting:

```bash
cat infrastructure-outputs.txt
# or
cd terraform && terraform output
```

---

## 2. Repository Structure

```
.
├── app.js                  # Node.js application
├── app.test.js             # Tests
├── package.json            # Dependencies & scripts
├── Dockerfile              # Container definition
├── Jenkinsfile             # Pipeline definition
└── terraform/              # Infrastructure (Terraform modules)
    ├── modules/jenkins/    # Jenkins EC2 + Docker setup script
    ├── modules/ec2/        # App server EC2
    └── scripts/            # App server bootstrap (user_data)
```

---

## 3. Jenkins Server — First-Time Setup

Jenkins is provisioned automatically by Terraform via `jenkins-setup.sh` (in `terraform/modules/jenkins/`) as EC2 `user_data`. **You do not need to run anything manually** — by the time the instance is reachable, the script has already:

- Installed Docker on the host
- Pulled `jenkins/jenkins:lts` and started it with `--restart unless-stopped`
- Mounted `/var/run/docker.sock` so pipeline stages can build and push images
- Installed the Docker CLI and Node.js 20 inside the container
- Exposed Jenkins on port `8080`

To verify everything came up correctly after `terraform apply`:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<JENKINS_IP>

# Container should show STATUS "Up X minutes"
sudo docker ps

# Review the setup log for any errors
sudo cat /var/log/jenkins-setup.log
```

---

## 4. Configure the App Server

The app server only needs Docker. SSH in and run:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<APP_IP>
```

```bash
sudo yum install -y docker
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker ec2-user
exit   # log out so the group change takes effect
```

---

## 5. Get the Initial Admin Password

Jenkins generates a one-time password on first boot. Because Jenkins runs inside a container, retrieve it with `docker exec` — **not** from the host filesystem:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<JENKINS_IP>

sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

> If the command returns "No such file or directory", Jenkins hasn't finished starting yet. Wait 30 seconds and try again, or check `sudo docker logs jenkins` to see where it is in the boot sequence.

---

## 6. Install Jenkins Plugins

1. Open **`http://<JENKINS_IP>:8080`** in your browser.
2. Paste the initial admin password from the step above.
3. Choose **"Install suggested plugins"** and wait for completion.
4. Create your admin user when prompted.

Then install the additional required plugins via **Manage Jenkins → Plugins → Available plugins**:

| Plugin | Purpose |
|--------|---------|
| `Pipeline` | Declarative pipeline support |
| `Git` | Checkout from GitHub |
| `Credentials Binding` | Inject secrets into the pipeline |
| `Docker Pipeline` | `docker` steps in the Jenkinsfile |
| `SSH Agent` | `sshagent` step for deployment |
| `NodeJS` | Manage Node.js versions in Jenkins |

Tick all checkboxes → **Install** → **"Restart Jenkins when no jobs are running"**.

### Configure the NodeJS tool

**Manage Jenkins → Tools → NodeJS → Add NodeJS**

| Field | Value |
|-------|-------|
| Name | `nodejs-20` |
| Version | `NodeJS 20.x` |

Click **Save**.

---

## 7. Add Jenkins Credentials

Navigate to: **Manage Jenkins → Credentials → System → Global credentials → Add Credential**

### `registry_creds` — Docker Hub

| Field | Value |
|-------|-------|
| Kind | `Username with password` |
| Username | Your Docker Hub username |
| Password | Your Docker Hub access token |
| ID | `registry_creds` |

> Generate a token at: hub.docker.com → Account Settings → Security → New Access Token

### `ec2_ssh` — App Server SSH Key

| Field | Value |
|-------|-------|
| Kind | `SSH Username with private key` |
| Username | `ec2-user` |
| Private Key | Enter directly → paste the full `.pem` file contents |
| ID | `ec2_ssh` |

Get the key content on your local machine:

```bash
cat jenkins-cicd-pipeline-dev-keypair.pem
```

Paste everything including the `-----BEGIN` and `-----END` lines.

---

## 8. Create the Pipeline Job

### Update the app server IP in the Jenkinsfile

Because IPs change, the app server IP is set as an environment variable in `Jenkinsfile`. Update it whenever you reprovision:

```groovy
environment {
    APP_SERVER_IP  = "<APP_IP>"   // ← update this when your IP changes
    IMAGE_NAME     = "YOUR_DOCKERHUB_USERNAME/cicd-app"
    ...
}
```

Commit and push:

```bash
git add Jenkinsfile
git commit -m "Update app server IP"
git push
```

### Create the job in Jenkins

1. **Dashboard → New Item**
2. Name: `cicd-pipeline` → select **Pipeline** → **OK**

**General:**
- ✅ Discard old builds → Max builds to keep: `5`

**Build Triggers (optional):**
- ✅ GitHub hook trigger for GITScm polling

**Pipeline:**
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: `https://github.com/YOUR_USERNAME/YOUR_REPO.git`
- Branch: `*/main`
- Script Path: `Jenkinsfile`

Click **Save**.

---

## 9. Run the Pipeline

1. Click **"Build Now"** on the job page.
2. Click the build number in Build History.
3. Click **"Console Output"** to watch live.

### Expected stages

```
Checkout         ✅
Install          ✅  (npm ci)
Test             ✅  (all tests passed)
Docker Build     ✅  (tagged :N and :latest)
Push Image       ✅  (pushed to Docker Hub)
Deploy           ✅  (container running on app server)
Post: cleanup    ✅
```

A successful run ends with:

```
Finished: SUCCESS
Pipeline SUCCEEDED. App running at http://<APP_IP>:5000
```

---

## 10. Verify Deployment

```bash
curl http://<APP_IP>:5000
curl http://<APP_IP>:5000/health
```

Verify the container on the app server:

```bash
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@<APP_IP>

docker ps                    # confirms cicd-app is running
docker logs cicd-app -f      # live app logs
```

---

## 11. Updating the App Server IP

Every time EC2 instances are stopped and restarted, both IPs change. Checklist:

```
1. cat infrastructure-outputs.txt        (or: cd terraform && terraform output)
2. Update APP_SERVER_IP in Jenkinsfile
3. git add Jenkinsfile && git commit -m "Update app IP" && git push
4. Re-run the pipeline in Jenkins
```

The Jenkins UI URL also changes — always derive it from the current `<JENKINS_IP>:8080`.

---

## 12. Troubleshooting

### Jenkins container is not running

```bash
# Check if it exists but is stopped
sudo docker ps -a

# Check startup logs
sudo docker logs jenkins

# Check the Terraform bootstrap log for errors
sudo cat /var/log/jenkins-setup.log

# Start it manually if needed
sudo docker start jenkins
```

### Jenkins UI not reachable

Confirm the container is up (`sudo docker ps`) and that the EC2 security group allows inbound TCP 8080 from your IP.

### Initial admin password file not found

Jenkins runs inside the container — the password is never on the host filesystem. Always use:

```bash
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### `docker: command not found` in pipeline

The Docker CLI is installed inside the container by `jenkins-setup.sh`. If it's missing, install it manually:

```bash
sudo docker exec -u root jenkins bash -c "apt-get update -qq && apt-get install -y docker.io"
```

### SSH deploy fails: `Permission denied (publickey)`

- Confirm `ec2_ssh` credential contains the correct full `.pem` contents.
- Confirm the username is exactly `ec2-user`.
- Test manually from inside the Jenkins container:

```bash
sudo docker exec -it jenkins ssh -o StrictHostKeyChecking=no ec2-user@<APP_IP> "docker ps"
```

### `npm: command not found` in pipeline

Confirm the **NodeJS plugin** is installed and the `nodejs-20` tool is configured under **Manage Jenkins → Tools**. The Jenkinsfile must reference it:

```groovy
tools { nodejs 'nodejs-20' }
```

### Docker Hub push fails: `unauthorized`

- Confirm the credential ID is exactly `registry_creds`.
- Confirm `IMAGE_NAME` starts with your Docker Hub username.
- Check the access token hasn't expired.

### Tests fail in pipeline but pass locally

```bash
# Check Node version inside the container
sudo docker exec jenkins node --version

# Run tests manually in the workspace
sudo docker exec jenkins bash -c "cd /var/jenkins_home/workspace/cicd-pipeline && npm ci && npm test"
```