#
# Cookbook Name:: gitlab
# Recipe:: postgres
#
# Copyright 2012, Seth Vargo
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

# Enable secure password generation
::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
node.set_unless['gitlab']['database']['password'] = secure_password
ruby_block "save node data" do
  block do
    node.save
  end
  not_if { Chef::Config[:solo] }
end

# Helper variables
database = node['gitlab']['database']['database']
database_user = node['gitlab']['database']['username']
database_password = node['gitlab']['database']['password']

# Create the user
pg_user database_user do
  privileges superuser: false, createdb: false, login: true
  password database_password
end

# Create the database
pg_database database do
  owner database_user
  encoding node['gitlab']['database']['encoding']
  locale "en_US.#{node['gitlab']['database']['encoding'].upcase}"
  template "template0"
end

