#
# Cookbook Name:: gitlab
# Recipe:: default
#
# Copyright 2012, Gerald L. Hevener Jr., M.S.
# Copyright 2012, Eric G. Wolfe
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

case node['platform_family']
when 'debian'
  include_recipe 'apt'
when 'rhel'
  include_recipe 'yum::epel'
end

# Install the required packages via cookbook
node['gitlab']['cookbook_dependencies'].each do |requirement|  
  include_recipe requirement
end

# Install required packages for Gitlab
node['gitlab']['packages'].each do |pkg|
  package pkg
end

# symlink redis-cli into /usr/bin (needed for gitlab hooks to work)
link "/usr/bin/redis-cli" do
  to "/usr/local/bin/redis-cli"
end

# The recommended Ruby is >= 1.9.3 
# We'll use Fletcher Nichol's ruby_build cookbook to compile a Ruby.
if node['gitlab']['install_ruby'] !~ /package/
  # build ruby
  ruby_build_ruby node['gitlab']['install_ruby']

  link "/usr/bin/ruby" do
    to "/usr/local/ruby/#{node['gitlab']['install_ruby']}/bin/ruby"
  end

  # Drop off a profile script.
  template "/etc/profile.d/gitlab.sh" do
    owner "root"
    group "root"
    mode 0755
    variables(
      :fqdn => node['fqdn'],
      :install_ruby => node['gitlab']['install_ruby']
    )
  end

  # Set PATH for remainder of recipe.
  ENV['PATH'] = "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin:/usr/local/ruby/#{node['gitlab']['install_ruby']}/bin"
end

# Install required Ruby Gems for Gitlab
%w[ charlock_holmes bundler ].each do |gempkg|
  gem_package gempkg do
    action :install
    options("--no-ri --no-rdoc")
  end
end

# Add a git user for Gitlab
user node['gitlab']['user'] do
  comment "Gitlab User"
  home node['gitlab']['home']
  shell "/bin/bash"
  supports :manage_home => true
end

# Fix home permissions for nginx
directory node['gitlab']['home'] do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0755
end

# Create a $HOME/.ssh folder
directory "#{node['gitlab']['home']}/.ssh" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0700
end

template "#{node['gitlab']['home']}/.gitconfig" do
  source "gitconfig.erb"
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
end

# Configure gitlab user to auto-accept localhost SSH keys
template "#{node['gitlab']['home']}/.ssh/config" do
  source "ssh_config.erb"
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
  variables(
      :fqdn => node['fqdn'],
      :trust_local_sshkeys => node['gitlab']['trust_local_sshkeys']
  )
end

# setup gitlab-shell
# Clone Gitlab-shell repo
git node['gitlab']['shell']['home'] do
  repository node['gitlab']['shell']['git_url']
  reference node['gitlab']['shell']['git_branch']
  action :checkout
  user node['gitlab']['user']
  group node['gitlab']['group']
end

# render gitlab-shell config
template node['gitlab']['shell']['home'] + "/config.yml" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
  source "shell_config.yml.erb"
  variables(
      :fqdn => node['gitlab']['web_fqdn'] || node['fqdn']
  )
end

# Clone Gitlab repo from github
git node['gitlab']['app_home'] do
  repository node['gitlab']['git_url']
  reference node['gitlab']['git_branch']
  action :checkout
  user node['gitlab']['user']
  group node['gitlab']['group']
end

# Setup the database
case node['gitlab']['database']['type']
  when 'mysql'
    include_recipe 'gitlab::mysql'
  when 'postgres'
    include_recipe 'gitlab::postgres'
  else
    Chef::Log.error "#{node['gitlab']['database']['type']} is not a valid type. Please use 'mysql' or 'postgres'!"
end

# Write the database.yml
template "#{node['gitlab']['app_home']}/config/database.yml" do
  source 'database.yml.erb'
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode '0644'
  variables(
      :adapter  => node['gitlab']['database']['adapter'],
      :encoding => node['gitlab']['database']['encoding'],
      :host     => node['gitlab']['database']['host'],
      :database => node['gitlab']['database']['database'],
      :pool     => node['gitlab']['database']['pool'],
      :username => node['gitlab']['database']['username'],
      :password => node['gitlab']['database']['password']
  )
end

# Render gitlab config file
template "#{node['gitlab']['app_home']}/config/gitlab.yml" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
  variables(
      :fqdn => node['gitlab']['web_fqdn'] || node['fqdn'],
      :https_boolean => node['gitlab']['https'],
      :git_user => node['gitlab']['user'],
      :git_home => node['gitlab']['home'],
      :backup_path => node['gitlab']['backup_path'],
      :backup_keep_time => node['gitlab']['backup_keep_time']
  )
end

# Render gitlab smtp config file
if node['gitlab']['email']['smtp']
  template "#{node['gitlab']['app_home']}/config/initializers/smtp_settings.rb" do
    owner node['gitlab']['user']
    group node['gitlab']['group']
    source "smtp_settings.rb.erb"
    mode 0644
  end
end

# create log, tmp, pids and sockets directory
%w{ log tmp tmp/pids tmp/sockets public/uploads }.each do |dir|
  directory File.join(node['gitlab']['app_home'], dir) do
    user node['gitlab']['user']
    group node['gitlab']['group']
    mode "0755"
    recursive true
    action :create
  end
end

# create gitlab-satellites directory
directory File.join(node['gitlab']['home'], "gitlab-satellites") do
  user node['gitlab']['user']
  group node['gitlab']['group']
  mode "0755"
  recursive true
  action :create
end

# create repositories directory
directory File.join(node['gitlab']['home'], "repositories") do
  user node['gitlab']['user']
  group node['gitlab']['group']
  mode "2770"
  recursive true
  action :create
end

# create backup_path
directory node['gitlab']['backup_path'] do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 00755
  action :create
end

# Render unicorn template
template "#{node['gitlab']['app_home']}/config/unicorn.rb" do
  owner node['gitlab']['user']
  group node['gitlab']['group']
  mode 0644
  variables(
      :fqdn => node['fqdn'],
      :gitlab_app_home => node['gitlab']['app_home']
  )
end

without_group = node['gitlab']['database']['type'] == 'mysql' ? 'postgres' : 'mysql'

# Install Gems with bundle install
execute "gitlab-bundle-install" do
  command "bundle install --deployment --without development test #{without_group} aws"
  cwd node['gitlab']['app_home']
  user node['gitlab']['user']
  group node['gitlab']['group']
  environment({ 'LANG' => "en_US.UTF-8", 'LC_ALL' => "en_US.UTF-8" })
  not_if { File.exists?("#{node['gitlab']['app_home']}/vendor/bundle") }
end

# Initialize database 
execute "gitlab-bundle-rake" do
  command "bundle exec rake gitlab:setup RAILS_ENV=production force=yes && touch .gitlab-setup"
  cwd node['gitlab']['app_home']
  user node['gitlab']['user']
  group node['gitlab']['group']
  not_if { File.exists?("#{node['gitlab']['app_home']}/.gitlab-setup") }
end

# Render gitlab init script
template "/etc/init.d/gitlab" do
  owner "root"
  group "root"
  mode 0755
  source "gitlab.init.erb"
  variables(
      :gitlab_app_home => node['gitlab']['app_home'],
      :gitlab_user => node['gitlab']['user']
  )
end

# Use certificate cookbook for keys
certificate_manage node['gitlab']['certificate_databag_id'] do
  cert_path '/etc/nginx/ssl'
  owner node['gitlab']['user']
  group node['gitlab']['user']
  nginx_cert true
  only_if { node['gitlab']['https'] and not node['gitlab']['certificate_databag_id'].nil? }
end

# Create nginx directories before dropping off templates
include_recipe "nginx::commons_dir"

# Either listen_port has been configured elsewhere or we calculate it depending on the https flag
listen_port = node['gitlab']['listen_port'] || node['gitlab']['https'] ? 443 : 80

# Render and activate nginx default vhost config
template "/etc/nginx/sites-available/gitlab" do
  owner "root"
  group "root"
  mode 0644
  source "nginx.gitlab.erb"
  notifies :restart, "service[nginx]"
  variables(
      :server_name => node['gitlab']['nginx_server_names'].join(' '),
      :hostname => node['hostname'],
      :gitlab_app_home => node['gitlab']['app_home'],
      :https_boolean => node['gitlab']['https'],
      :ssl_certificate => node['gitlab']['ssl_certificate'],
      :ssl_certificate_key => node['gitlab']['ssl_certificate_key'],
      :listen => "#{node['gitlab']['listen_ip']}:#{listen_port}"
  )
end

include_recipe "nginx"

nginx_site 'gitlab' do
  enable true 
end

nginx_site "default" do
  enable false
end

# Enable and start unicorn_rails and nginx service
service "gitlab" do
  action [ :enable, :start ]
end
