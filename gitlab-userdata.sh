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

apt-get update -y
apt-get install -y curl openssh-server ca-certificates tzdata perl

curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | bash

RDS_HOST="gitlab-postgres.${AWS_REGION}.rds.amazonaws.com"

cat <<EOF >> /etc/gitlab/gitlab.rb
external_url 'http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)'
postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'utf8'
gitlab_rails['db_database'] = 'gitlabdb'
gitlab_rails['db_username'] = 'gitlabadmin'
gitlab_rails['db_password'] = 'StrongPassword123!'
gitlab_rails['db_host'] = '${RDS_HOST}'
gitlab_rails['db_port'] = 5432
EOF

mkfs.ext4 /dev/sdf
mkdir -p /var/opt/gitlab
mount /dev/sdf /var/opt/gitlab
echo "/dev/sdf /var/opt/gitlab ext4 defaults,nofail 0 2" >> /etc/fstab

gitlab-ctl reconfigure
