#!/bin/bash
apt-get update -y
apt-get install -y curl unzip git
#!/bin/bash
USER="anas"
useradd -m $USER
usermod -aG adm $USER
usermod -aG wheel $USER
usermod -aG systemd-journal $USER
mkdir -p /home/$USER/.ssh
cat << "EOF" | tee /home/$USER/.ssh/authorized_keys
# Add your SSH keys here
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKsAdT+kvJ3EVBdNDBxVQBrzlYDzhRAwP9B9vo1FdZfb
EOF
chmod 700 /home/$USER/.ssh
chmod 600 /home/$USER/.ssh/authorized_keys
chown -R $USER:$USER /home/$USER

# Add user to sudoers with NOPASSWD
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER
sudo chmod 440 /etc/sudoers.d/$USER

# Disable password expiration for the user
chage -m 0 -M -1 -I -1 -E -1 $USER

# Install GitLab Runner
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
apt-get install -y gitlab-runner

# Register the runner (replace with your actual values)
gitlab-runner register \
  --non-interactive \
  --url "https://$(curl ifconfig.me)/" \
  --registration-token "glQ.0w02o8eda" \
  --executor "shell" \
  --description "Terraform GitLab Runner" \
  --tag-list "terraform" \
  --run-untagged="true" \
  --locked="false"
